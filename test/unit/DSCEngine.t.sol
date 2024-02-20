//SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";


/**
 * @title DSCEngineTest
 * @notice This contract is used to test the functionality of the DSCEngine contract.
 * @dev It inherits from the Test contract. It uses DeployDSC, HelperConfig, DecentralizedStableCoin,
 * DSCEngine, ERC20Mock, and MockV3Aggregator for testing purposes.
 */
contract DSCEngineTest is Test {
    // Contracts to be used in the tests
    DeployDSC public deployer;
    DecentralizedStableCoin public dsc;
    DSCEngine public dscEngine;
    HelperConfig public config;

    // Addresses to be used in the tests
    address public ethUsdPriceFeed;
    address public btcUsdPriceFeed;
    address public wethAddress;

    // Our fake user which will start with 100 WETH
    address public USER = makeAddr("USER");
    uint256 public constant STARTING_ETHER = 100 ether;
    // Random wrong token address to test reverts
    address public constant RANDOM_WRONG_TOKEN_ADDRESS = 0x7b79995e5f793A07Bc00c21412e50Ecae098E7f9;

    // SetUp function that will be run before tests and will deploy the DSC and get the contracts
    // Also, it will give 100 WETH to the user and will mint fake Mock ETH for him so to deposit on our contract
    function setUp() public {
        vm.startBroadcast();
        // Deploy the contracts using the DeployDSC script
        deployer = new DeployDSC();
        vm.stopBroadcast();
        // Run the deployer and get the contracts
        (dsc, dscEngine, config) = deployer.run();
        // From the config take the feeds and the WETH address for the fake Mock ETH
        (ethUsdPriceFeed, btcUsdPriceFeed, wethAddress,,) = config.activeConfig();
        // For this fake Mock ETH, we mint 100
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
    function testDepositCollateralAddsCollateralInUser() public depositedCollateral(100) {
        // Here, we take how much collateral the user has in USD in WEI
        (, uint256 totalCollateral) = dscEngine.getUserInformation(address(USER));
        // Here, we give the amount of collateral in USD in WEI and we expect back to see the WETH
        (uint256 givenUsdHowExpectedETH,) = dscEngine.getTokenAmountFromUsd(wethAddress, totalCollateral);
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

    function testRedeemCollateralIndeedRedeems() public depositedCollateral(100) {
        uint256 balanceOfUserBeforeRedeem = ERC20Mock(wethAddress).balanceOf(USER);
        vm.startPrank(USER);
        dscEngine.redeemCollateral(wethAddress, 20 ether);
        vm.stopPrank();
        uint256 balanceOfUserAfterRedeem = ERC20Mock(wethAddress).balanceOf(USER);
        assertEq(balanceOfUserBeforeRedeem + 20 ether, balanceOfUserAfterRedeem);
    }

    function testRedeemCollateralUpdatesMappings() public depositedCollateral(100) {
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

    function testMintDscUpdatesUserInfo() public depositedCollateral(100) {
        vm.startPrank(USER);
        dscEngine.mintDsc(50);
        (uint256 expectedMintedDsc,) = dscEngine.getUserInformation(USER);
        vm.stopPrank();
        assertEq(expectedMintedDsc, 50);
    }

    /////////////////////
    // Burn DSC /////////
    /////////////////////
    function testRevertsForZeroBurnAmount() public depositedCollateral(1) {
        vm.startPrank(USER);
        dscEngine.mintDsc(1000);
        vm.expectRevert(DSCEngine.DSCEngine__NotZero.selector);
        dscEngine.burnDsc(0);
        vm.stopPrank();
    }

    function testBurnMethodIndeedBurnsDSC() public depositedCollateral(1) {
        vm.startPrank(USER);
        dscEngine.mintDsc(1000);
        dsc.approve(address(dscEngine), 500);
        dscEngine.burnDsc(500);
        vm.stopPrank();
        assertEq(dscEngine.s_mintedDsc(USER), 500);
    }

    ////////////////////
    // Liquidate //////
    ///////////////////
    modifier depositedAndMinted() {
        vm.startPrank(USER);
        ERC20Mock(wethAddress).approve(address(dscEngine), 1 * 1e18);
        dscEngine.depositCollateral(wethAddress, 1 * 1e18);
        dscEngine.mintDsc(1);
        vm.stopPrank();
        _;
    }

    function testRevertsForZeroDebtAmountToBeLiquidated() public {
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__NotZero.selector);
        dscEngine.liquidate(wethAddress, USER, 0);
    }
}
