//SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {DecentralizedStableCoin} from "./DecentralizedStableCoin.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { AggregatorV3Interface } from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

/*
 * @title DSCEngine
 * @author Zark
 * This contract is meant to be as minimal as possible and have
 *  the token to be pegged == $1
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

    mapping(address token => address priceFeed) public s_priceFeeds;
    mapping(address userAddress => mapping(address tokenAddress => uint256 amount)) public s_collateralBalances;
    mapping(address userAddress => uint256 mintedDsc) public s_mintedDsc;
    address[] private s_collateralTokens;

    uint256 private PRECISION = 10**18;
    uint256 private ADDITIONAL_FEED_PRECISION = 10**10;
    uint256 private constant LIQUIDATION_THRESHOLD = 50; //meaning 200% over-collateralized
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant MIN_HEALTH_FACTOR = 1;

    DecentralizedStableCoin public immutable i_dsc;

    event CollateralDeposited(address indexed user, address indexed token, uint256 indexed amount);

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

    function depositCollateralAndMintDsc() external {}

    /*
     * @notice follows CEI pattern
     * @param tokenCollateralAddress The address of the collateral token
     * @param amountCollateral The amount of collateral to deposit
     */
    function depositCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        external
        notZero(amountCollateral)
        isAllowedCollateral(tokenCollateralAddress)
        nonReentrant
    {
        s_collateralBalances[msg.sender][tokenCollateralAddress] += amountCollateral;
        emit CollateralDeposited(msg.sender, tokenCollateralAddress, amountCollateral);

        bool success = IERC20(tokenCollateralAddress).transferFrom(msg.sender, address(this), amountCollateral);
        if(!success) {
            revert DSCEngine__TransferFailed();
        }
    }

    function redeemDSCAForDsc() external {}

    function redeemCollateral() external {}

    /*
     * @notice follows CEI pattern
     * @param amountDscToMint The amount of Decentralized StableCoin to mint
     * @notice The collateral must be higher than the value of minted DSC
     */
    function mindDsc(uint256 amountDscToMint) external notZero(amountDscToMint) nonReentrant {
        s_mintedDsc[msg.sender] += amountDscToMint;

        _revertIfHealthFactorIsBroken(msg.sender);

        bool minted = i_dsc.mint(msg.sender, amountDscToMint);
        if (!minted) {
            revert DSCEngine__NotMinted();
        }
    }

    function burnDsc() external {}

    function liquidate() external {}

    function getHealthFactor() external view {}

    function getUsdValue(address token, uint256 amount) public view returns(uint256){
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (,int price,,,) = priceFeed.latestRoundData();
        return ((uint256(price)* ADDITIONAL_FEED_PRECISION) * amount) / PRECISION;
    }

    function getCollateralValueInUSD(address userAddress) public view returns(uint256 totalValue) {
        for (uint256 i = 0; i < s_collateralTokens.length;i++) {
            address token = s_collateralTokens[i];
            uint256 amount = s_collateralBalances[userAddress][token];
            totalValue += getUsdValue(token, amount);
        }
        return totalValue;
    }



    //////////////////////////////////////////////
    //Internal and private function starting with _
    ////////////////////////////////////////////////

    function _getUserInformation(address userAddress) private view returns (uint256 totalDscMinted, uint256 collateralValueInUSD) {
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
    function _healthFactor(address userAddress) private view returns(uint256) {
        (uint256 totalDscMinted, uint256 totalCollateralValue) = _getUserInformation(userAddress);
        uint256 totalCollateralValueAdjustedForThreshold = totalCollateralValue * LIQUIDATION_THRESHOLD / LIQUIDATION_PRECISION;
        return totalCollateralValueAdjustedForThreshold * PRECISION / totalDscMinted;
    }

    function _revertIfHealthFactorIsBroken(address userAddress) internal view {
        uint256 userHealthFactor = _healthFactor(userAddress);
        if (userHealthFactor < MIN_HEALTH_FACTOR) {
            revert DSCEngine__BelowMinHealthFactor();
        }

    }
}
