//SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {DecentralizedStableCoin} from "../src/DecentralizedStableCoin.sol";
import {DSCEngine} from "../src/DSCEngine.sol";
import {HelperConfig} from "./HelperConfig.s.sol";

/**
 * @title DeployDSC
 * @notice This contract is used to deploy the DecentralizedStableCoin (DSC) and DSCEngine contracts and set up their initial configuration.
 * @dev It inherits from the Script contract. It uses the HelperConfig contract to get the active network configuration.
 */
contract DeployDSC is Script {
    // HelperConfig contract instance and active configuration
    HelperConfig public config;
    address public wethUsdPriceFeed;
    address public wbtcUsdPriceFeed;
    address public weth;
    address public wbtc;
    uint256 public deployerkey;

    // Arrays to store the price feeds and token addresses and pass them to the DSCEngine constructor
    address[] public priceFeeds;
    address[] public tokenAddresses;

    // Main run function of the contract that deploys the DSC and DSCEngine contracts and returns them alongside
    // with the HelperConfig contract instance
    function run() external returns (DecentralizedStableCoin, DSCEngine, HelperConfig) {
        // Deploy HelperConfig
        config = new HelperConfig();
        // Get the active network configuration
        (wethUsdPriceFeed, wbtcUsdPriceFeed, weth, wbtc, deployerkey) = config.activeConfig();

        // Push the priceFeeds and tokens we took from HelperConfig to the arrays which will be passed to the DSCEngine constructor
        priceFeeds.push(wethUsdPriceFeed);
        priceFeeds.push(wbtcUsdPriceFeed);
        tokenAddresses.push(weth);
        tokenAddresses.push(wbtc);

        // Start the tx broadcast
        vm.startBroadcast(deployerkey);
        // Deploy the DSC and DSCEngine contracts
        DecentralizedStableCoin dsc = new DecentralizedStableCoin();
        // Pass the token addresses and price feeds to the DSCEngine constructor and the dsc address
        DSCEngine dscEngine = new DSCEngine(tokenAddresses, priceFeeds, address(dsc));
        // Transfer the ownership of the DSC to the DSCEngine
        dsc.transferOwnership(address(dscEngine));
        vm.stopBroadcast();

        // Return the DSC, DSCEngine and HelperConfig instances
        return (dsc, dscEngine, config);
    }
}
