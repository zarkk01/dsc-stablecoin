//SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {DecentralizedStableCoin} from "./DecentralizedStableCoin.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

/*
 * @title DSCEngine
 * @author Zark
 * This contract is meant to be as minimal as possible and have
 * the token to be pegged == $1
 * This stablecoin has the properties:
 * 1. Collateral : Exogenous (ETH and BTC)
 * 2. Minting : Algorithmic
 * 3. Relative Stability : Pegged to USD
 *
 * This stablecoin should be always "over-collateralized". At no point should the
 * value of the collateral be less than the value of the stablecoin.
 *
 * @notice This contract is the core of the DSC System. It handles all the logic for the mining
 *  and redeeming DSC, as well as depositing and withdrawing collateral. Also based on DAI System.
 */
contract DSCEngine is ReentrancyGuard {
    error DSCEngine__NotZero();
    error DSCEngine__NotAllowedCollateral();
    error DSCEngine__NotEqualLength();
    error DSCEngine__TransferFailed();
    error DSCEngine__HealthFactorBroken();
    error DSCEngine__NotMinted();
    error DSCEngine__HealthFactorOK();
    error DSCEngine__HealthFactorNotImproved();

    mapping(address token => address priceFeed) public s_priceFeeds;
    mapping(address userAddress => mapping(address tokenAddress => uint256 amount)) public s_collateralBalances;
    mapping(address userAddress => uint256 mintedDsc) public s_mintedDsc;
    address[] private s_collateralTokens;

    uint256 private PRECISION = 10 ** 18;
    uint256 private ADDITIONAL_FEED_PRECISION = 10 ** 10;
    uint256 private constant LIQUIDATION_THRESHOLD = 50;
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant MIN_HEALTH_FACTOR = 1;
    uint256 private constant LIQUIDATION_BONUS = 10;

    DecentralizedStableCoin public immutable i_dsc;

    event CollateralDeposited(address indexed user, address indexed token, uint256 indexed amount);
    event CollateralRedeemed(
        address indexed redeemedFrom, address indexed redeemedTo, address indexed token, uint256 amount
    );

    modifier notZero(uint256 _value) {
        if (_value == 0) {
            revert DSCEngine__NotZero();
        }
        _;
    }

    modifier isAllowedCollateral(address _tokenCollateralAddress) {
        if (s_priceFeeds[_tokenCollateralAddress] == address(0)) {
            revert DSCEngine__NotAllowedCollateral();
        }
        _;
    }

    constructor(address[] memory tokenAddresses, address[] memory priceFeedAddresses, address dscAddress) {
        if (tokenAddresses.length != priceFeedAddresses.length) {
            revert DSCEngine__NotEqualLength();
        }
        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            s_priceFeeds[tokenAddresses[i]] = priceFeedAddresses[i];
            s_collateralTokens.push(tokenAddresses[i]);
        }
        i_dsc = DecentralizedStableCoin(dscAddress);
    }

    function depositCollateralAndMintDsc(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        uint256 amountDscToMint
    ) external {
        depositCollateral(tokenCollateralAddress, amountCollateral);
        mintDsc(amountDscToMint);
    }

    function depositCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        public
        notZero(amountCollateral)
        isAllowedCollateral(tokenCollateralAddress)
        nonReentrant
    {
        s_collateralBalances[msg.sender][tokenCollateralAddress] += amountCollateral;
        emit CollateralDeposited(msg.sender, tokenCollateralAddress, amountCollateral);

        bool success = IERC20(tokenCollateralAddress).transferFrom(msg.sender, address(this), amountCollateral);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
    }

    function mintDsc(uint256 amountDscToMint) public notZero(amountDscToMint) nonReentrant {
        s_mintedDsc[msg.sender] += amountDscToMint;

        _revertIfHealthFactorIsBroken(msg.sender);

        bool minted = i_dsc.mint(msg.sender, amountDscToMint);
        if (!minted) {
            revert DSCEngine__NotMinted();
        }
    }

    function redeemCollateralForDsc(address tokenCollateralAddress, uint256 amountCollateral, uint256 amountToBeBurned)
        external
    {
        burnDsc(amountToBeBurned);
        redeemCollateral(tokenCollateralAddress, amountCollateral);
    }

    function burnDsc(uint256 amount) public notZero(amount) {
        _burnDsc(amount, msg.sender, msg.sender);
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    function redeemCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        public
        notZero(amountCollateral)
        nonReentrant
    {
        _redeemCollateral(tokenCollateralAddress, amountCollateral, msg.sender, msg.sender);
    }

    function liquidate(address tokenCollateral, address userAddress, uint256 debtToCover)
        external
        notZero(debtToCover)
        nonReentrant
    {
        uint256 startingUserHealthFactor = _healthFactor(userAddress);
        if (startingUserHealthFactor >= MIN_HEALTH_FACTOR) {
            revert DSCEngine__HealthFactorOK();
        }
        (uint256 tokenAmountFromDebtCovered, uint256 bonusCollateral) =
            getTokenAmountFromUsd(tokenCollateral, debtToCover);
        _redeemCollateral(tokenCollateral, tokenAmountFromDebtCovered + bonusCollateral, userAddress, msg.sender);
        _burnDsc(debtToCover, userAddress, msg.sender);

        uint256 endingUserHealthFactor = _healthFactor(userAddress);

        if (endingUserHealthFactor <= startingUserHealthFactor) {
            revert DSCEngine__HealthFactorNotImproved();
        }
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    function getTokenAmountFromUsd(address tokenCollateral, uint256 usdAmountInWei)
        public
        view
        returns (uint256 tokenAmountFromDebtCovered, uint256 bonusCollateral)
    {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[tokenCollateral]);
        (, int256 price,,,) = priceFeed.latestRoundData();
        tokenAmountFromDebtCovered = (usdAmountInWei * PRECISION) / (uint256(price) * ADDITIONAL_FEED_PRECISION);
        bonusCollateral = tokenAmountFromDebtCovered * LIQUIDATION_BONUS / 100;
    }

    function getHealthFactor(address user) external view returns (uint256 healthFactor) {
        healthFactor = _healthFactor(user);
    }

    function getCollateralValueInUSD(address userAddress) public view returns (uint256 totalValue) {
        for (uint256 i = 0; i < s_collateralTokens.length; i++) {
            address token = s_collateralTokens[i];
            uint256 amount = s_collateralBalances[userAddress][token];
            totalValue += getUsdValue(token, amount);
        }
        return totalValue;
    }

    function getUsdValue(address token, uint256 amount) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 price,,,) = priceFeed.latestRoundData();
        return ((uint256(price) * ADDITIONAL_FEED_PRECISION) * amount) / PRECISION;
    }

    //////////////////////////////////
    // Internal / Private functions //
    //////////////////////////////////

    function _redeemCollateral(address tokenCollateralAddress, uint256 amountCollateral, address from, address to)
        private
        notZero(amountCollateral)
    {
        s_collateralBalances[from][tokenCollateralAddress] -= amountCollateral;
        emit CollateralRedeemed(from, to, tokenCollateralAddress, amountCollateral);
        bool success = IERC20(tokenCollateralAddress).transfer(to, amountCollateral);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
    }

    function _burnDsc(uint256 amountDscToBurn, address onBehalfOf, address dscFrom) private {
        s_mintedDsc[onBehalfOf] -= amountDscToBurn;
        bool success = i_dsc.transferFrom(dscFrom, address(this), amountDscToBurn);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
        i_dsc.burn(amountDscToBurn);
    }

    function _revertIfHealthFactorIsBroken(address userAddress) internal view {
        uint256 userHealthFactor = _healthFactor(userAddress);
        if (userHealthFactor < MIN_HEALTH_FACTOR) {
            revert DSCEngine__HealthFactorBroken();
        }
    }

    /////// BUG ////////
    function _healthFactor(address userAddress) private view returns (uint256) {
        (uint256 totalDscMinted, uint256 totalCollateralValue) = _getUserInformation(userAddress);
        uint256 totalCollateralValueAdjustedForThreshold =
            totalCollateralValue * LIQUIDATION_THRESHOLD / LIQUIDATION_PRECISION;
        return totalCollateralValueAdjustedForThreshold * PRECISION / totalDscMinted;
    }

    function _getUserInformation(address userAddress)
        private
        view
        returns (uint256 totalDscMinted, uint256 collateralValueInUSD)
    {
        totalDscMinted = s_mintedDsc[userAddress];
        collateralValueInUSD = getCollateralValueInUSD(userAddress);
    }

    function getUserInformation(address userAddress)
        public
        view
        returns (uint256 totalDscMinted, uint256 totalCollateralInUSD)
    {
        return _getUserInformation(userAddress);
    }
}
