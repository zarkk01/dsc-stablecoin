//SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {Handler} from "./Handler.t.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";


/**
 * @title InvariantsTest
 * @notice This contract is used to test the invariants of the DSCEngine contract.
 * @dev It inherits from the StdInvariant and Test contracts. It uses DeployDSC, DecentralizedStableCoin, DSCEngine,
 * HelperConfig, IERC20, and Handler for testing purposes.
 */
contract InvariantsTest is StdInvariant, Test {
    DeployDSC deployer;
    DecentralizedStableCoin dsc;
    DSCEngine dsce;
    HelperConfig helperConfig;
    Handler handler;
    address weth;
    address wbtc;

    // SetUp function that will be run before tests and will deploy the DSC and get the contracts
    // also set the handler contract as the target contract in which the invariants will be tested
    // with random values
    function setUp() external {
        // Deploy the contracts using the DeployDSC script
        deployer = new DeployDSC();
        // Get the contracts
        (dsc, dsce, helperConfig) = deployer.run();
        // From the config take the feeds
        (,, weth, wbtc,) = helperConfig.activeConfig();
        handler = new Handler(dsce, dsc);
        targetContract(address(handler));
    }

    function invariant_protocolMustNeverHasSupplyLessThanValue() external {
        // Total supply easy to get using the totalSupply() function of the IERC20 interface
        uint256 totalSupply = IERC20(dsc).totalSupply();
        // Total value of the protocol is the total value of the WETH and WBTC in USD
        // We check it seeing how much DSCEngine has of each token using balanceOf() function
        uint256 totalWeth = IERC20(weth).balanceOf(address(dsce));
        uint256 totalWbtc = IERC20(wbtc).balanceOf(address(dsce));
        // Then we add them to find the total value in USD
        uint256 totalUSDValue = dsce.getUsdValue(weth, totalWeth) + dsce.getUsdValue(wbtc, totalWbtc);
        // Since we want our protocol to be overcollateralized, we check that the total supply is less than the total value
        assertTrue(totalSupply <= totalUSDValue);
    }
}
