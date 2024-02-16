//SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Script , console } from "forge-std/Script.sol";
import { DecentralizedStableCoin } from "../src/DecentralizedStableCoin.sol";
import { DSCEngine } from "../src/DSCEngine.sol";
import { HelperConfig } from "./HelperConfig.s.sol";

contract DeployDSC is Script {
    HelperConfig public config;
    address public wethUsdPriceFeed;
    address public wbtcUsdPriceFeed;
    address public weth;
    address public wbtc;
    uint256 public deployerkey;

    address[] public priceFeeds;
    address[] public tokenAddresses;

    function run() external returns(DecentralizedStableCoin, DSCEngine) {
        config = new HelperConfig();
        (
            wethUsdPriceFeed,
            wbtcUsdPriceFeed,
            weth,
            wbtc,
            deployerkey
        ) = config.activeConfig();

        priceFeeds.push(wethUsdPriceFeed);
        priceFeeds.push(wbtcUsdPriceFeed);
        tokenAddresses.push(weth);
        tokenAddresses.push(wbtc);
        vm.startBroadcast(deployerkey);
        DecentralizedStableCoin dsc = new DecentralizedStableCoin();
        DSCEngine dscEngine = new DSCEngine(tokenAddresses,priceFeeds,address(dsc));
        dsc.transferOwnership(address(dscEngine));
        vm.stopBroadcast();
        return (dsc, dscEngine);
    }
}