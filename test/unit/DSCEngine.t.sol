//SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Test , console }  from "forge-std/Test.sol";
import { DeployDSC } from "../../script/DeployDSC.s.sol";
import { HelperConfig } from "../../script/HelperConfig.s.sol";
import { DecentralizedStableCoin } from "../../src/DecentralizedStableCoin.sol";
import { DSCEngine } from "../../src/DSCEngine.sol";
import { ERC20Mock } from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import { MockV3Aggregator } from "../mocks/MockV3Aggregator.sol";


contract DSCEngineTest is Test {
    DeployDSC public deployDSC;
    DecentralizedStableCoin public dsc;
    DSCEngine public dscEngine;
    HelperConfig public config;
    address public ethUsdPriceFeed;
    address public wethAddress;

    address public USER = makeAddr("USER");
    uint256 public constant STARTING_ETHER = 100 ether;

    function setUp() public {
        vm.startBroadcast();
        deployDSC = new DeployDSC();
        vm.stopBroadcast();
        (dsc, dscEngine, config) = deployDSC.run();
        (ethUsdPriceFeed,,wethAddress,,) = config.activeConfig();
        vm.deal(USER, 100 ether);
//        ERC20Mock(wethAddress).mint(USER, 100 ether);
    }


    //////////////////
    // Price Tests //
    //////////////////
    function testGetUsdValue() public {
        (,int256 price,,,) = MockV3Aggregator(ethUsdPriceFeed).latestRoundData();
        uint256 ethAmount = 15 ether;
        uint256 expectedUsdValue = uint256(price) * ethAmount / 10**8;
        assertEq(dscEngine.getUsdValue(wethAddress, ethAmount), expectedUsdValue);
    }

    ////////////////////////
    // Deposit Collateral //
    ///////////////////////
//    function testDepositCollateralRevertsForZero() public {
//        vm.startPrank(USER);
//        vm.expectRevert(DSCEngine.DSCEngine__NotZero.selector);
//        dscEngine.depositCollateral(wethAddress, 0 ether);
//
//        ERC20Mock(wethAddress).mint(USER,100 ether);
//        ERC20Mock(wethAddress).approve(address(dscEngine), 1 ether);
//
//        vm.stopPrank();
//
//    }

//    function testDepositCollateralAddsDepositorOnArray() public {
//        vm.startPrank(USER);
//        ERC20Mock(wethAddress).approve(address(dscEngine), 1 ether);
//        dscEngine.depositCollateral(wethAddress, 1 ether);
//        vm.stopPrank();
//
//        assertEq(dscEngine.s_collateralBalances(USER, wethAddress), 1 ether);
//    }
}