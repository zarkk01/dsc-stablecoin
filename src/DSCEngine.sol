//SPDX-License-Identifier: MIT
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
        // First, we update the user's collateral balance and increase it by the amount he deposited
        s_collateralBalances[msg.sender][tokenCollateralAddress] += amountCollateral;
        // We emit the event of this deposit
        emit CollateralDeposited(msg.sender, tokenCollateralAddress, amountCollateral);

        // Then, we transfer the tokens from the user to this contract using IERC20 interface bounding it to the address he gave
        bool success = IERC20(tokenCollateralAddress).transferFrom(msg.sender, address(this), amountCollateral);
        // If the transfer fails, we revert
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
    }

    /**
    * @notice Allows a user to mint DSC.
    * @dev This function updates the user's DSC minted balance and checks if the health factor is broken after minting.
    * It reverts if the minting operation fails.
    * @param amountDscToMint The amount of DSC to be minted.
    */
    function mintDsc(uint256 amountDscToMint)
        public
        notZero(amountDscToMint)
        nonReentrant
    {
        // First, we update the user's minted DSC balance and increase it by the amount he minted
        s_mintedDsc[msg.sender] += amountDscToMint;
        // If this operation gonna break the health factor, we revert
        _revertIfHealthFactorIsBroken(msg.sender);

        // Then, we mint the DSC to the user using the mint function of the DSC contract
        bool minted = i_dsc.mint(msg.sender, amountDscToMint);
        // If the minting fails, we revert
        if (!minted) {
            revert DSCEngine__NotMinted();
        }
    }

    /**
    * @notice Allows a user to redeem collateral.
    * @dev This function calls the internal function _redeemCollateral with the user's address as both the 'from' and 'to' parameters.
    * It reverts if the amount of collateral to be redeemed is zero.
    * @param tokenCollateralAddress The address of the ERC20 token to be redeemed as collateral.
    * @param amountCollateral The amount of the ERC20 token to be redeemed.
    */
    function redeemCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        public
        notZero(amountCollateral)
        nonReentrant
    {
        // We call the internal function to redeem the collateral, passing the user's address as both the 'from' and 'to' parameters
        _redeemCollateral(tokenCollateralAddress, amountCollateral, msg.sender, msg.sender);
    }

    /**
    * @notice Allows a user to burn DSC.
    * @dev This function reduces the user's DSC minted balance and checks if the health factor is broken after burning.
    * @param amount The amount of DSC to be burned.
    */
    function burnDsc(uint256 amount) public notZero(amount) {
        // First, we burn the DSC from the user's address
        _burnDsc(amount, msg.sender, msg.sender);
        // If this operation gonna break the health factor, we revert
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    ///////////////////////
    // PRIVATE FUNCTIONS //
    ///////////////////////

    /**
    * @notice Redeems a specified amount of a specified ERC20 token as collateral. It can be called either
    * by the user itself who wants to redeem his collaterals or by the liquidate function, meaning by a different user
    * named liquidator who wants to liquidate the user's collaterals. If the user itself calls this function, the 'from'
    * and 'to' parameters will be the same, but if the liquidator calls this function, the 'from' and 'to' parameters
    * will be different.
    * @dev This function reduces the user's collateral balance, emits a CollateralRedeemed event, and transfers the collateral from this contract to a specified address.
    * It reverts if the transfer operation fails.
    * @param tokenCollateralAddress The address of the ERC20 token to be redeemed as collateral.
    * @param amountCollateral The amount of the ERC20 token to be redeemed.
    * @param from The address of the user whose collateral is being redeemed.
    * @param to The address to which the redeemed collateral is being transferred.
    */
    function _redeemCollateral(address tokenCollateralAddress, uint256 amountCollateral, address from, address to)
        private
        notZero(amountCollateral)
    {
        // First, we reduce the user's collateral balance by the amount he redeemed
        s_collateralBalances[from][tokenCollateralAddress] -= amountCollateral;
        // Then we emit the event of this redemption
        emit CollateralRedeemed(from, to, tokenCollateralAddress, amountCollateral);
        // Finally, we transfer the tokens from this contract to the liquidator or the user itself using IERC20 interface
        bool success = IERC20(tokenCollateralAddress).transfer(to, amountCollateral);
        // If the transfer fails, we revert
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
    }

    /**
    * @notice Burns a specified amount of DSC tokens from a user's balance.
    * @dev This function reduces the user's DSC minted balance, transfers the DSC tokens from the user to this contract, and burns them.
    * It reverts if the transfer operation fails.
    * @param amountDscToBurn The amount of DSC tokens to be burned.
    * @param onBehalfOf The address of the user whose DSC tokens are being burned.
    * @param dscFrom The address from which the DSC tokens are being transferred.
    */
    function _burnDsc(uint256 amountDscToBurn, address onBehalfOf, address dscFrom) private {
        // First, we reduce the user's DSC minted balance by the amount he burned
        s_mintedDsc[onBehalfOf] -= amountDscToBurn;
        // Then we send the DSC tokens from the dscFrom to this contract using IERC20 interface
        bool success = i_dsc.transferFrom(dscFrom, address(this), amountDscToBurn);
        // If the transfer fails, we revert
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
        // Finally, we burn the DSC tokens using the burn function of the DSC contract
        i_dsc.burn(amountDscToBurn);
    }

    ////////////////////////////
    // PURE / VIEW FUNCTIONS  //
    ///////////////////////////

    // This function is used to calculate the health factor of a user, taking the totalDscMinted and the totalCollateralValue
    // It gonna be something like this : (totalCollateralValue * 50) / totalDscMinted
    function calculateHealthFactor(uint256 totalDscMinted, uint256 totalCollateralInUSD)
        external
        pure
        returns (uint256)
    {
        // Call the internal function to calculate the health factor
        return _calculateHealthFactor(totalDscMinted, totalCollateralInUSD);
    }

    // This function is used to get the collateral tokens that we have in our system, all of them
    function getCollateralTokens() external view returns (address[] memory) {
        return s_collateralTokens;
    }

    // This function is used to get the price feed of a token, given the address of the token
    function getPriceFeed(address token) external view returns (address) {
        return s_priceFeeds[token];
    }

    // This function is used to get the health factor of a user, given his address
    function getHealthFactor(address user) external view returns (uint256 healthFactor) {
        healthFactor = _healthFactor(user);
    }

    // This function takes a token address and the amount of USD in wei and returns the amount of tokens that
    // can demonstrate this exact amount of USD in the token metrics, alongside with the bonusCollateral if it is needed
    function getTokenAmountFromUsd(address tokenCollateral, uint256 usdAmountInWei)
        public
        view
        returns (uint256 tokenAmountFromDebtCovered, uint256 bonusCollateral)
    {
        // Using AggregatorV3Interface we pass him a priceFeed and it returns the latestRoundData
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[tokenCollateral]);
        // Here, we take the price of the token and we check if it is stale
        (, int256 price,,,) = priceFeed.staleChecksLatestRoundData();
        // Weird math to calculate the amount of tokens that be needed to cover the debt
        tokenAmountFromDebtCovered = (usdAmountInWei * PRECISION) / (uint256(price) * ADDITIONAL_FEED_PRECISION);
        // The bonusCollateral for the liquidator
        bonusCollateral = tokenAmountFromDebtCovered * LIQUIDATION_BONUS / 100;
    }


    // This function is used to get the user's information, given his address, meaning the totalDscMinted and the totalCollateralValue
    function getUserInformation(address userAddress)
        public
        view
        returns (uint256 totalDscMinted, uint256 totalCollateralInUSD)
    {
        return _getUserInformation(userAddress);
    }

    // This function is used to get the collateral value in USD, given the user's address
    // It justs loops through the collateral tokens and calculates the value of each one
    function getCollateralValueInUSD(address userAddress) public view returns (uint256 totalValue) {
        // For each token in the array of collaterals
        uint256 length = s_collateralTokens.length;
        for (uint256 i = 0; i < length; i++) {
            // Take the token
            address token = s_collateralTokens[i];
            // See how much of this token has the user deposited
            uint256 amount = s_collateralBalances[userAddress][token];
            // If it is zero, don't bother get the value, continue
            if (amount == 0) continue;
            // Calculate the USD value of this amount
            totalValue += getUsdValue(token, amount);
        }
        return totalValue;
    }

    // Using AggregatorV3Interface we pass him a priceFeed and the amount of tokens and it returns the amount of USD in wei
    function getUsdValue(address token, uint256 amount) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        // Here we take the price of the token and we check if it is stale
        (, int256 price,,,) = priceFeed.staleChecksLatestRoundData();
        // Return the amount of USD in wei
        return ((uint256(price) * ADDITIONAL_FEED_PRECISION) * amount) / PRECISION;
    }

    // This function is used to check if the health factor of a user is broken, given his address
    // and reverts if it is
    function _revertIfHealthFactorIsBroken(address userAddress) internal view {
        // Take his healthFactor and if it is under the minimum, revert
        uint256 userHealthFactor = _healthFactor(userAddress);
        if (userHealthFactor < MIN_HEALTH_FACTOR) {
            revert DSCEngine__HealthFactorBroken();
        }
    }

    // This function is used to calculate the health factor of a user, given his address
    // It first takes its info and then passes it to the internal function to calculate the health factor
    function _healthFactor(address userAddress) private view returns (uint256) {
        // Take the user's information
        (uint256 totalDscMinted, uint256 totalCollateralValue) = _getUserInformation(userAddress);
        // Call the internal function to calculate the health factor
        return _calculateHealthFactor(totalDscMinted, totalCollateralValue);
    }

    // This function takes an address and returns the totalDscMinted and the collateralValueInUSD
    function _getUserInformation(address userAddress)
        private
        view
        returns (uint256 totalDscMinted, uint256 collateralValueInUSD)
    {
        // Just see from the mapping how much dsc he has minted
        totalDscMinted = s_mintedDsc[userAddress];
        // Pass his address in the internal function to get the value of his collateral
        collateralValueInUSD = getCollateralValueInUSD(userAddress);
    }

    // This function is used to calculate the health factor of a user, given the totalDscMinted and the totalCollateralValue
    function _calculateHealthFactor(uint256 totalDscMinted, uint256 totalCollateralInUSD)
        private
        pure
        returns (uint256)
    {
        // If no DSC minted, then health factor is max, this is how we fixed the bug.
        // We can't devide with zero but we know that if he has not minted dsc
        // he is good since he has not borrowed anything
        if (totalDscMinted == 0) return type(uint256).max;
        // Adjust the collateral for the threshold
        uint256 collateralAdjustedForThreshold = (totalCollateralInUSD * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;
        // Return the healthFactor ratio of the totalCollateralInUSD and the totalDscMinted
        return (collateralAdjustedForThreshold * PRECISION) / totalDscMinted;
    }
}
