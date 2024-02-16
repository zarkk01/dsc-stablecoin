//SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Test , console }  from "forge-std/Test.sol";
import { DeployDSC } from "../../script/DeployDSC.s.sol";
import { DecentralizedStableCoin } from "../../src/DecentralizedStableCoin.sol";

contract DSCEngineTest is Test {
    DeployDSC public deployDSC;

    function setUp() public {
        vm.startBroadcast();
        deployDSC = new DeployDSC();
        vm.stopBroadcast();
    }
}