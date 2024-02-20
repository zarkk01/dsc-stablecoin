//SPDX-License-Identifier: MIT

// Layout of Contract:
// pragma version
// imports
// interfaces, libraries, contracts
// errors
// Type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// view & pure functions

// For functions :
// Visibility (public, private internal, external)
// Mutability (pure, view, nonpayable, payable)
// Virtual
// Override
// Custom modifier

pragma solidity ^0.8.24;

import {DecentralizedStableCoin} from "./DecentralizedStableCoin.sol";
import {OracleLib} from "./libraries/OracleLib.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

/*
 * @title DSCEngine contract
 * @author Theodoros Zarkalis
 * @notice This contract is the core of the DSC System. It handles all the logic for the mining
 * and redeeming DSC, as well as depositing and withdrawing collateral. It is based on DAI System.
 */
contract DSCEngine is ReentrancyGuard {
    // Custom errors for the DSCEngine contract
    error DSCEngine__NotZero();
    error DSCEngine__NotAllowedCollateral();
    error DSCEngine__NotEqualLength();
    error DSCEngine__TransferFailed();
    error DSCEngine__HealthFactorBroken();
    error DSCEngine__NotMinted();
    error DSCEngine__HealthFactorOK();
    error DSCEngine__HealthFactorNotImproved();

    // Constant variables
    uint256 private constant PRECISION = 10 ** 18;
    uint256 private constant ADDITIONAL_FEED_PRECISION = 10 ** 10;
    uint256 private constant LIQUIDATION_THRESHOLD = 50;
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant MIN_HEALTH_FACTOR = 1;
    uint256 private constant LIQUIDATION_BONUS = 10;

    // State variables
    DecentralizedStableCoin public immutable i_dsc;
    mapping(address token => address priceFeed) public s_priceFeeds;
    mapping(address userAddress => mapping(address tokenAddress => uint256 amount)) public s_collateralBalances;
    mapping(address userAddress => uint256 mintedDsc) public s_mintedDsc;
    address[] private s_collateralTokens;

    // Events
    event CollateralDeposited(address indexed user, address indexed token, uint256 indexed amount);
    event CollateralRedeemed(
        address indexed redeemedFrom, address indexed redeemedTo, address indexed token, uint256 amount
    );

    // Modifiers
    modifier notZero(uint256 _value) {
        // If given value is zero, revert
        if (_value == 0) {
            revert DSCEngine__NotZero();
        }
        // Else, continue
        _;
    }
    modifier isAllowedCollateral(address _tokenCollateralAddress) {
        // If given token address is not in our mapping with collaterals, revert
        // Zero address means we did not find it
        if (s_priceFeeds[_tokenCollateralAddress] == address(0)) {
            revert DSCEngine__NotAllowedCollateral();
        }
        // Else, continue
        _;
    }

    // Instead of using the Chainlink's AggregatorV3Interface, we are using our own OracleLib which is a library
    // and calls the latestRoundData function of the Chainlink's AggregatorV3Interface but with a check for stale data
    using OracleLib for AggregatorV3Interface;

    // Constructor of our DSCEngine contract that takes the tokenAddresses that we will take as collateral
    // and the priceFeedAddresses that we will use to get the price of these tokens, alongside with the address of the DSC contract
    constructor(address[] memory tokenAddresses, address[] memory priceFeedAddresses, address dscAddress) {
        // Token collaterals and priceFeeds should have the same length, else revert
        if (tokenAddresses.length != priceFeedAddresses.length) {
            revert DSCEngine__NotEqualLength();
        }
        // For each token address, we will add the priceFeed address to our mapping and the token address to our array
        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            // Map each token with its priceFeed
            s_priceFeeds[tokenAddresses[i]] = priceFeedAddresses[i];
            // Add the token address to our array of collaterals
            s_collateralTokens.push(tokenAddresses[i]);
        }
        i_dsc = DecentralizedStableCoin(dscAddress);
    }

    /////////////////////////////////
    // EXTERNAL / PUBLIC FUNCTIONS //
    /////////////////////////////////

    /**
    * @notice Allows a user to deposit collateral and mint DSC in a single transaction.
    * @dev This function is a convenience function for users who want to perform both actions at once
    * so various problems and attacks can be avoided.
    * @param tokenCollateralAddress The address of the ERC20 token to be deposited as collateral.
    * @param amountCollateral The amount of the ERC20 token to be deposited as collateral.
    * @param amountDscToMint The amount of DSC to be minted.
    */
    function depositCollateralAndMintDsc(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        uint256 amountDscToMint
    )
        external
    {
        // First, we deposit the collateral
        depositCollateral(tokenCollateralAddress, amountCollateral);
        // Then, we mint the dsc we want, in this way we do not break our health factor
        mintDsc(amountDscToMint);
    }

    /**
    * @notice Allows a user to burn DSC and redeem collateral in a single transaction.
    * @dev This function is a convenience function for users who want to perform both actions at once.
    * @param tokenCollateralAddress The address of the ERC20 token to be redeemed as collateral.
    * @param amountCollateral The amount of the ERC20 token to be redeemed.
    * @param amountToBeBurned The amount of DSC to be burned.
    */
    function redeemCollateralForDsc(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        uint256 amountToBeBurned
    )
        external
    {
        // Burn the DSC first, meaning that they will be reduced from the user's balance and totalSupply
        burnDsc(amountToBeBurned);
        // Then, user takes back the collateral he had deposited
        redeemCollateral(tokenCollateralAddress, amountCollateral);
    }

    /**
    * @notice Allows a user to liquidate another user's collateral if their health factor is below the minimum.
    * @dev This function is used to maintain the stability of the system. It checks the health factor of the user
    * being liquidated before and after the operation, and reverts if it has not improved.
    * @param tokenCollateral The address of the ERC20 token to be liquidated as collateral.
    * @param userAddress The address of the user whose collateral is being liquidated.
    * @param debtToCover The amount of debt to be covered by the liquidation.
    */
    function liquidate(
        address tokenCollateral,
        address userAddress,
        uint256 debtToCover
    )
        external
        notZero(debtToCover)
        nonReentrant
    {
        // First, we take the initial healthFactor of the user who is gonna be liquidated
        uint256 startingUserHealthFactor = _healthFactor(userAddress);
        // Then, we check if he is not under the minimum health factor, if he is not, we revert
        // since there is no reason to liquidate him
        if (startingUserHealthFactor >= MIN_HEALTH_FACTOR) {
            revert DSCEngine__HealthFactorOK();
        }
        // Then, we calculate the amount of collateral we need to cover the debt
        // Example : if the debtToCover is $100 and he has 1 ETH as collateral which goes for $2000,
        // we need to take take 0.05 ETH to cover the debt, and we will take 0.005 ETH as a bonus
        (uint256 tokenAmountFromDebtCovered, uint256 bonusCollateral) =
                        getTokenAmountFromUsd(tokenCollateral, debtToCover);
        // Having this info, we can now redeem the collateral from the user to cover the debt
        _redeemCollateral(tokenCollateral, tokenAmountFromDebtCovered + bonusCollateral, userAddress, msg.sender);
        // Then, we burn the DSC from the user
        _burnDsc(debtToCover, userAddress, msg.sender);

        // The healthFactor of user after the liquidaion
        uint256 endingUserHealthFactor = _healthFactor(userAddress);

        // If this action, did not fix the health factor, we revert since we may need
        // to liquidate more of his collateral
        if (endingUserHealthFactor <= startingUserHealthFactor) {
            revert DSCEngine__HealthFactorNotImproved();
        }
        // Check the health factor of the user, maybe can be removed
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    /**
    * @notice Allows a user to deposit collateral.
    * @dev This function updates the user's collateral balance and emits a CollateralDeposited event.
    * It reverts if the transfer from the user to this contract fails.
    * @param tokenCollateralAddress The address of the ERC20 token to be deposited as collateral.
    * @param amountCollateral The amount of the ERC20 token to be deposited as collateral.
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

    function mintDsc(uint256 amountDscToMint)
        public
        notZero(amountDscToMint)
        nonReentrant
    {
        s_mintedDsc[msg.sender] += amountDscToMint;
        _revertIfHealthFactorIsBroken(msg.sender);

        bool minted = i_dsc.mint(msg.sender, amountDscToMint);
        if (!minted) {
            revert DSCEngine__NotMinted();
        }
    }

    function redeemCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        public
        notZero(amountCollateral)
        nonReentrant
    {
        _redeemCollateral(tokenCollateralAddress, amountCollateral, msg.sender, msg.sender);
    }

    function burnDsc(uint256 amount) public notZero(amount) {
        _burnDsc(amount, msg.sender, msg.sender);
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    ///////////////////////
    // PRIVATE FUNCTIONS //
    ///////////////////////

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

    ////////////////////////////
    // PURE / VIEW FUNCTIONS  //
    ///////////////////////////

    function calculateHealthFactor(uint256 totalDscMinted, uint256 totalCollateralInUSD)
        external
        view
        returns (uint256)
    {
        return _calculateHealthFactor(totalDscMinted, totalCollateralInUSD);
    }

    function getCollateralTokens() external view returns (address[] memory) {
        return s_collateralTokens;
    }

    function getPriceFeed(address token) external view returns (address) {
        return s_priceFeeds[token];
    }

    function getHealthFactor(address user) external view returns (uint256 healthFactor) {
        healthFactor = _healthFactor(user);
    }

    function getTokenAmountFromUsd(address tokenCollateral, uint256 usdAmountInWei)
        public
        view
        returns (uint256 tokenAmountFromDebtCovered, uint256 bonusCollateral)
    {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[tokenCollateral]);
        (, int256 price,,,) = priceFeed.staleChecksLatestRoundData();
        tokenAmountFromDebtCovered = (usdAmountInWei * PRECISION) / (uint256(price) * ADDITIONAL_FEED_PRECISION);
        bonusCollateral = tokenAmountFromDebtCovered * LIQUIDATION_BONUS / 100;
    }

    function getUserInformation(address userAddress)
        public
        view
        returns (uint256 totalDscMinted, uint256 totalCollateralInUSD)
    {
        return _getUserInformation(userAddress);
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
        (, int256 price,,,) = priceFeed.staleChecksLatestRoundData();
        return ((uint256(price) * ADDITIONAL_FEED_PRECISION) * amount) / PRECISION;
    }

    function _revertIfHealthFactorIsBroken(address userAddress) internal view {
        uint256 userHealthFactor = _healthFactor(userAddress);
        if (userHealthFactor < MIN_HEALTH_FACTOR) {
            revert DSCEngine__HealthFactorBroken();
        }
    }

    function _healthFactor(address userAddress) private view returns (uint256) {
        (uint256 totalDscMinted, uint256 totalCollateralValue) = _getUserInformation(userAddress);
        return _calculateHealthFactor(totalDscMinted, totalCollateralValue);
    }

    function _getUserInformation(address userAddress)
        private
        view
        returns (uint256 totalDscMinted, uint256 collateralValueInUSD)
    {
        totalDscMinted = s_mintedDsc[userAddress];
        collateralValueInUSD = getCollateralValueInUSD(userAddress);
    }

    function _calculateHealthFactor(uint256 totalDscMinted, uint256 totalCollateralInUSD)
        private
        view
        returns (uint256)
    {
        // If no DSC minted, then health factor is max, this is how we fixed the bug.
        if (totalDscMinted == 0) return type(uint256).max;
        uint256 collateralAdjustedForThreshold = (totalCollateralInUSD * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;
        return (collateralAdjustedForThreshold * PRECISION) / totalDscMinted;
    }
}
