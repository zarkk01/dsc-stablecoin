//SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";

contract DSCEngineTest is Test {
    DeployDSC public deployDSC;
    DecentralizedStableCoin public dsc;
    DSCEngine public dscEngine;
    HelperConfig public config;
    address public ethUsdPriceFeed;
    address public btcUsdPriceFeed;
    address public wethAddress;

    address public USER = makeAddr("USER");
    uint256 public constant STARTING_ETHER = 100 ether;
    address public constant RANDOM_WRONG_TOKEN_ADDRESS = 0x7b79995e5f793A07Bc00c21412e50Ecae098E7f9;

    function setUp() public {
        vm.startBroadcast();
        deployDSC = new DeployDSC();
        vm.stopBroadcast();
        (dsc, dscEngine, config) = deployDSC.run();
        (ethUsdPriceFeed, btcUsdPriceFeed, wethAddress,,) = config.activeConfig();
        ERC20Mock(wethAddress).mint(USER, 100 ether);
        vm.deal(USER, 100 ether);
    }

    //////////////////
    // Constructor //
    /////////////////
    address[] public tokenAddresses;
    address[] public priceFeedAddresses;

    function testRevertsGivenWrongArrays() public {
        tokenAddresses.push(wethAddress);
        priceFeedAddresses.push(ethUsdPriceFeed);
        priceFeedAddresses.push(btcUsdPriceFeed);

        vm.expectRevert(DSCEngine.DSCEngine__NotEqualLength.selector);
        new DSCEngine(tokenAddresses, priceFeedAddresses, address(dsc));
    }

    //////////////////
    // Price Tests ///
    //////////////////
    function testGetUsdValue() public {
        (, int256 price,,,) = MockV3Aggregator(ethUsdPriceFeed).latestRoundData();
        uint256 ethAmount = 1 ether;
        uint256 expectedUsdValue = uint256(price) * ethAmount / 10 ** 8;
        console.log("Expected Value: ", expectedUsdValue);
        assertEq(dscEngine.getUsdValue(wethAddress, ethAmount), expectedUsdValue);
    }

    function testGetTokenAmountFromUsd() public {
        (, int256 price,,,) = MockV3Aggregator(ethUsdPriceFeed).latestRoundData();
        uint256 usdAmount = 100 ether;
        uint256 expectedTokenAmount = usdAmount * 10 ** 8 / uint256(price);
        (uint256 tokenAmountFromDebtCovered,) = dscEngine.getTokenAmountFromUsd(wethAddress, usdAmount);
        assertEq(tokenAmountFromDebtCovered, expectedTokenAmount);
    }

    ////////////////////////
    // Deposit Collateral //
    ///////////////////////
    function testDepositCollateralRevertsForZero() public {
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__NotZero.selector);
        dscEngine.depositCollateral(wethAddress, 0 ether);
        vm.stopPrank();
    }

    function testRevertsForNotAllowedCollateral() public {
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__NotAllowedCollateral.selector);
        dscEngine.depositCollateral(RANDOM_WRONG_TOKEN_ADDRESS, 1 ether);
        vm.stopPrank();
    }

    // Modifier to deposit collateral so to not write the same code again and again
    modifier depositedCollateral(uint256 amount) {
        // Pretending to be the user
        vm.startPrank(USER);
        // We approve this contract to spend the WETH and deposit 100 of them
        // We give the amount which in ETH but we multiply by 1e18 so to make it WEI
        ERC20Mock(wethAddress).approve(address(dscEngine), amount * 1e18);
        // Here, it is the deposit
        dscEngine.depositCollateral(wethAddress, amount * 1e18);
        vm.stopPrank();
        _;
    }

    // Test that if user deposits, his info (state) changes and his deposited collateral is added
    function testDepositCollateralAddsCollateralInUser() depositedCollateral(100) public {
        // Here, we take how much collateral the user has in USD in WEI
        (, uint256 totalCollateral) = dscEngine.getUserInformation(address(USER));
        // Here, we give the amount of collateral in USD in WEI and we expect back to see the WETH
        (uint256 givenUsdHowExpectedETH, ) = dscEngine.getTokenAmountFromUsd(wethAddress, totalCollateral);
        // Here, we expect the WETH to be as the WETH we deposited mean 100 WETH
        assertEq(givenUsdHowExpectedETH, 100 ether);
    }

    ////////////////////////
    // Redeem Collateral //
    ///////////////////////
    function testRedeemCollateralRevertsForZero() public {
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__NotZero.selector);
        dscEngine.redeemCollateral(wethAddress, 0 ether);
        vm.stopPrank();
    }

    function testRedeemCollateralIndeedRedeems() depositedCollateral(100) public {
        uint256 balanceOfUserBeforeRedeem = ERC20Mock(wethAddress).balanceOf(USER);
        vm.startPrank(USER);
        dscEngine.redeemCollateral(wethAddress, 20 ether);
        vm.stopPrank();
        uint256 balanceOfUserAfterRedeem = ERC20Mock(wethAddress).balanceOf(USER);
        assertEq(balanceOfUserBeforeRedeem + 20 ether, balanceOfUserAfterRedeem);
    }

    function testRedeemCollateralUpdatesMappings() depositedCollateral(100) public {
        vm.startPrank(USER);
        dscEngine.redeemCollateral(wethAddress, 20 ether);
        vm.stopPrank();
        assertEq(dscEngine.s_collateralBalances(USER, wethAddress), 80 ether);
    }

    ////////////////////
    // Mint DSC ////////
    ////////////////////
    function testMintDSCRevertsForZero() public {
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__NotZero.selector);
        dscEngine.mintDsc(0 ether);
        vm.stopPrank();
    }
}
