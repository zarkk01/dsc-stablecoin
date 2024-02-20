//SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Test , console } from "forge-std/Test.sol";
import { StdInvariant } from "forge-std/StdInvariant.sol";
import { DeployDSC } from "../../script/DeployDSC.s.sol";
import { DSCEngine } from "../../src/DSCEngine.sol";
import { DecentralizedStableCoin } from "../../src/DecentralizedStableCoin.sol";
import { HelperConfig } from "../../script/HelperConfig.s.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Handler } from "./Handler.t.sol";

contract InvariantsTest is StdInvariant, Test {

    DeployDSC deployer;
    DecentralizedStableCoin dsc;
    DSCEngine dsce;
    HelperConfig helperConfig;
    Handler handler;
    address weth;
    address wbtc;

    function setUp() external {
        deployer = new DeployDSC();
        (dsc, dsce, helperConfig) = deployer.run();
        (,,weth,wbtc,) = helperConfig.activeConfig();
        handler = new Handler(dsce, dsc);
        targetContract(address(handler));
    }

    function invariant_protocolMustNeverHasSupplyLessThanValue() external {
        uint256 totalSupply = IERC20(dsc).totalSupply();
        uint256 totalWeth = IERC20(weth).balanceOf(address(dsce));
        uint256 totalWbtc = IERC20(wbtc).balanceOf(address(dsce));
        uint256 totalUSDValue = dsce.getUsdValue(weth, totalWeth) + dsce.getUsdValue(wbtc, totalWbtc);
        assertTrue(totalSupply <= totalUSDValue);
    }
}