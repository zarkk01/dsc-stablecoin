//SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";


contract Handler is Test {
    // Constants
    uint256 constant MAX_DEPOSIT = type(uint96).max;

    // Contracts to be used in the tests
    DSCEngine dsce;
    DecentralizedStableCoin dsc;
    MockV3Aggregator wethAggregator;
    MockV3Aggregator wbtcAggregator;
    ERC20Mock weth;
    ERC20Mock wbtc;

    // Variables
    address[] public users;
    address[] collateralTokens;
    int256 public priceWeth;
    int256 public priceWbtc;

    /**
     * @notice Sets up the initial state for the tests.
     * @param _dsce The DSCEngine contract to be tested.
     * @param _dsc The DecentralizedStableCoin contract to be tested.
     */
    constructor(DSCEngine _dsce, DecentralizedStableCoin _dsc) {
        // Assign given contracts to the state variables
        dsce = _dsce;
        dsc = _dsc;

        // Get the collateral tokens and the price feeds
        collateralTokens = dsce.getCollateralTokens();
        weth = ERC20Mock(collateralTokens[0]);
        wbtc = ERC20Mock(collateralTokens[1]);

        // Get the price feeds
        wethAggregator = MockV3Aggregator(dsce.getPriceFeed(address(weth)));
        wbtcAggregator = MockV3Aggregator(dsce.getPriceFeed(address(wbtc)));

        // Get the prices
        (, priceWeth,,,) = wethAggregator.latestRoundData();
        (, priceWbtc,,,) = wbtcAggregator.latestRoundData();
    }

    // Deposit Collateral
    // Here, we gonna pass random numbers instead of random addresses, because it is easier to predict
    function depositCollateral(uint256 collateralSeed, uint256 collateralAmount) public {
        // Like that we take the address of the collateral token but it is random which one
        ERC20Mock collateralToken = _getCollateralFromSeed(collateralSeed);
        // Here, we bound the amount to be between 1 and MAX_DEPOSIT
        uint256 collateralBounded = bound(collateralAmount, 1, MAX_DEPOSIT);

        // We mint some fake ERC20Mock selected tokens to the user and we approve contract to sent them,
        // so we can simulate the deposit of them as collateral in dsce
        collateralToken.mint(msg.sender, collateralBounded);
        vm.startPrank(msg.sender);
        // Here, is the approval to the dsce contract to take the tokens from the user
        collateralToken.approve(address(dsce), collateralBounded);
        // And finally we deposit the tokens as collateral
        dsce.depositCollateral(address(collateralToken), collateralBounded);
        vm.stopPrank();
        // Maybe double push but its okay
        users.push(msg.sender);
    }

    // Redeem Collateral
    // This functions simulates the redeemFunction of dsce contract but with randomize valid input data
    function redeemCollateral(uint256 collateralSeed, uint256 collateralAmount) public {
        // Like that we take the address of the collateral token we gonna redeem but it is random which one
        ERC20Mock collateralToken = _getCollateralFromSeed(collateralSeed);
        // Here, we bound the amount to be between 0 and balance of the user
        uint256 collateralBounded =
            bound(collateralAmount, 0, dsce.s_collateralBalances(msg.sender, address(collateralToken)));
        // If the amount is 0, we return because it will revert with NotZero error
        if (collateralBounded == 0) {
            return;
        }
        // Redeem the tokens from the dsce contract
        dsce.redeemCollateral(address(collateralToken), collateralBounded);
    }

    // Mint
    function mintDsc(uint256 amountToMint, uint256 addressSeed) public {
        if (users.length == 0) {
            return;
        }
        address minter = users[addressSeed % users.length];
        // Get the user info so to get the totalDscMinted and totalCollateralInUSD and make sure we
        // do not break the health factor with this minting, so to bound right the given random amountToMint
        (uint256 totalDscMinted, uint256 totalCollateralInUSD) = dsce.getUserInformation(minter);
        int256 maxDscToMint = (int256(totalCollateralInUSD) / 2) - int256(totalDscMinted);
        if (maxDscToMint < 0) {
            return;
        }
        // Here, we bound the amount to be between 1 and MAX_DEPOSIT
        uint256 amountBounded = bound(amountToMint, 0, uint256(maxDscToMint));
        if (amountBounded == 0) {
            return;
        }
        vm.startPrank(minter);
        // Mint the tokens
        dsce.mintDsc(amountBounded);
        vm.stopPrank();
    }

    // Helper functions
    // With this function we only get valid addresses as collateral, either wbtc or weth
    function _getCollateralFromSeed(uint256 seed) private view returns (ERC20Mock) {
        // From this random seed that is given we take true or false and return weth or wbtc
        if (seed % 2 == 0) {
            return weth;
        } else {
            return wbtc;
        }
    }
}
