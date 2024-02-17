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
    error DSCEngine__BelowMinHealthFactor();
    error DSCEngine__NotMinted();
    error DSCEngine__HealthFactorOK();
    error DSCEngine__HealthFactorNotImproved();

    mapping(address token => address priceFeed) public s_priceFeeds;
    mapping(address userAddress => mapping(address tokenAddress => uint256 amount)) public s_collateralBalances;
    mapping(address userAddress => uint256 mintedDsc) public s_mintedDsc;
    address[] private s_collateralTokens;

    uint256 private PRECISION = 10 ** 18;
    uint256 private ADDITIONAL_FEED_PRECISION = 10 ** 10;
    uint256 private constant LIQUIDATION_THRESHOLD = 50; //meaning 200% over-collateralized
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

    /*
     * @notice backbone function of the system that call deposit and mint functions
     * @param amountDscToMint The amount of Decentralized StableCoin to mint
     * @param tokenCollateralAddress The address of the collateral token
     * @param amountCollateral The amount of collateral to deposit
     * @notice Actually this function will deposit your collateral and mint dsc in
     one transaction
     */
    function depositCollateralAndMintDsc(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        uint256 amountDscToMint
    ) external {
        depositCollateral(tokenCollateralAddress, amountCollateral);
        mintDsc(amountDscToMint);
    }

    /*
     * @notice follows CEI pattern
     * @param tokenCollateralAddress The address of the collateral token
     * @param amountCollateral The amount of collateral to deposit
     */
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

    /*
     * @notice follows CEI pattern
     * @param amountDscToMint The amount of Decentralized StableCoin to mint
     * @notice The collateral must be higher than the value of minted DSC
     */
    function mintDsc(uint256 amountDscToMint) public notZero(amountDscToMint) nonReentrant {
        s_mintedDsc[msg.sender] += amountDscToMint;

        _revertIfHealthFactorIsBroken(msg.sender);

        bool minted = i_dsc.mint(msg.sender, amountDscToMint);
        if (!minted) {
            revert DSCEngine__NotMinted();
        }
    }

    /*
     * @notice follows CEI pattern
     * @param tokenCollateralAddress The address of the collateral token
     * @param amountCollateral The amount of collateral to redeem
     * @param amountToBeBurned The amount of DSC to be burned
     * @notice Actually this function will burn your dsc and redeem your collateral in one transaction
     */
    function redeemCollateralForDsc(address tokenCollateralAddress, uint256 amountCollateral, uint256 amountToBeBurned)
        external
    {
        // First burn then redeem causa otherwise health factor will be considered broken
        burnDsc(amountToBeBurned);
        redeemCollateral(tokenCollateralAddress, amountCollateral);
    }

    function burnDsc(uint256 amount) public notZero(amount) {
        _burnDsc(amount, msg.sender, msg.sender);
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    // In order to successful redeem collateral
    // the user must have a health factor above 1
    // even after the collateral is redeemed
    function redeemCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        public
        notZero(amountCollateral)
        nonReentrant
    {
        _redeemCollateral(tokenCollateralAddress, amountCollateral, msg.sender, msg.sender);
    }

    /*
     * @notice follows CEI pattern
     * @param userAddress The address of the user
     * @param debtToCover The amount of debt to cover
     * @param tokenCollateral The address of the collateral token
     * @notice This function will liquidate the user if the health factor is below MIN_HEALTH_FACTOR
     * @notice You can partially liquidate a user. You will get a liquidation bonus for taking the users funds
     * @notice This working functions assumes that our system is 200% over-collaterized otherwise we can't make
     this incentive.
     */
    function liquidate(address tokenCollateral, address userAddress, uint256 debtToCover)
        external
        notZero(debtToCover)
        nonReentrant
    {
        // Check health factor of user. Meaning, check if the user must be liquidated.
        // Only should liquidate user who are liquidatable
        uint256 startingUserHealthFactor = _healthFactor(userAddress);
        if (startingUserHealthFactor >= MIN_HEALTH_FACTOR) {
            revert DSCEngine__HealthFactorOK();
        }
        uint256 tokenAmountFromDebtCovered = getTokenAmountFromUsd(tokenCollateral, debtToCover);
        _redeemCollateral(tokenCollateral, tokenAmountFromDebtCovered,userAddress, msg.sender);
        _burnDsc(debtToCover, userAddress, msg.sender);

        uint256 endingUserHealthFactor = _healthFactor(userAddress);

        if (endingUserHealthFactor <= startingUserHealthFactor) {
            revert DSCEngine__HealthFactorNotImproved();
        }
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    function getTokenAmountFromUsd(address tokenCollateral, uint256 usdAmountInWei) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[tokenCollateral]);
        (, int256 price,,,) = priceFeed.latestRoundData();
        uint256 tokenAmountFromDebtCovered = (usdAmountInWei * PRECISION) / (uint256(price) * ADDITIONAL_FEED_PRECISION);
        uint256 bonusCollateral = tokenAmountFromDebtCovered * LIQUIDATION_BONUS / 100;
        return bonusCollateral;
    }

    function getHealthFactor() external view {}

    function getUsdValue(address token, uint256 amount) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 price,,,) = priceFeed.latestRoundData();
        return ((uint256(price) * ADDITIONAL_FEED_PRECISION) * amount) / PRECISION;
    }

    function getCollateralValueInUSD(address userAddress) public view returns (uint256 totalValue) {
        for (uint256 i = 0; i < s_collateralTokens.length; i++) {
            address token = s_collateralTokens[i];
            uint256 amount = s_collateralBalances[userAddress][token];
            totalValue += getUsdValue(token, amount);
        }
        return totalValue;
    }

    //////////////////////////////////////////////
    //Internal and private function starting with _//
    ////////////////////////////////////////////////

    /*
    * @dev Low-level internal function to burn DSC, do not call unless you check the health factor
    */
    function _burnDsc(uint256 amountDscToBurn, address onBehalfOf, address dscFrom) private {
        s_mintedDsc[onBehalfOf] -= amountDscToBurn;
        bool success = i_dsc.transferFrom(dscFrom, address(0), amountDscToBurn);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
        i_dsc.burn(amountDscToBurn);
    }

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

    function _getUserInformation(address userAddress)
        private
        view
        returns (uint256 totalDscMinted, uint256 collateralValueInUSD)
    {
        totalDscMinted = s_mintedDsc[userAddress];
        collateralValueInUSD = getCollateralValueInUSD(userAddress);
    }

    /*
     * @notice follows CEI pattern
     * @param userAddress The address of the user
     * @return how close to liquidation the user is
     if user goes below to 1, meaning that the ratio of collateral / mintedDsc is under 1
     then we gotta liquidate the user
     */
    function _healthFactor(address userAddress) private view returns (uint256) {
        (uint256 totalDscMinted, uint256 totalCollateralValue) = _getUserInformation(userAddress);
        uint256 totalCollateralValueAdjustedForThreshold =
            totalCollateralValue * LIQUIDATION_THRESHOLD / LIQUIDATION_PRECISION;
        return totalCollateralValueAdjustedForThreshold * PRECISION / totalDscMinted;
    }
    ///////////////////////// BUG IN HEALTH FACTOR /////////////////////////

    function _revertIfHealthFactorIsBroken(address userAddress) internal view {
        uint256 userHealthFactor = _healthFactor(userAddress);
        if (userHealthFactor < MIN_HEALTH_FACTOR) {
            revert DSCEngine__BelowMinHealthFactor();
        }
    }
}
