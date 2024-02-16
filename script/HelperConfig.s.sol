//SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Script , console } from "forge-std/Script.sol";
import { MockV3Aggregator } from "../test/mocks/MockV3Aggregator.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

contract HelperConfig is Script {

    uint8 private constant DECIMALS = 8;
    int256 private constant ETH_PRICE = 2000e8;
    int256 private constant BTC_PRICE = 40000e8;
    uint256 public constant DEFAULT_ANVIL_PRIVATE_KEY = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;

    NetworkConfig public activeConfig;

    struct NetworkConfig {
        address wethUsdPriceFeed;
        address wbtcUsdPriceFeed;
        address weth;
        address wbtc;
        uint256 deployerkey;
    }

    constructor() {
        if(block.chainid == 11155111) {
            activeConfig = getSepoliaConfig();
        } else {
            activeConfig = getOrCreateAnvilConfig();
        }

    }

//    function getMainnetConfig() internal view returns(NetworkConfig memory){
//    }

    function getSepoliaConfig() internal view returns(NetworkConfig memory) {
        return NetworkConfig({
            wethUsdPriceFeed: 0x694AA1769357215DE4FAC081bf1f309aDC325306,
            wbtcUsdPriceFeed: 0x1b44F3514812d835EB1BDB0acB33d3fA3351Ee43,
            weth: 0x7b79995e5f793A07Bc00c21412e50Ecae098E7f9,
            wbtc: 0x92f3B59a79bFf5dc60c0d59eA13a44D082B2bdFC,
            deployerkey: vm.envUint("SEPOLIA_PRIVATE_KEY")
        });
    }

    function getOrCreateAnvilConfig() internal returns(NetworkConfig memory){
        if (activeConfig.wethUsdPriceFeed != address(0)) {
            return activeConfig;
        }

        vm.startBroadcast();
        MockV3Aggregator wethUsdPriceFeed = new MockV3Aggregator(DECIMALS, ETH_PRICE);
        MockV3Aggregator wbtcUsdPriceFeed = new MockV3Aggregator(DECIMALS, BTC_PRICE);
        ERC20Mock weth = new ERC20Mock();
        ERC20Mock wbtc = new ERC20Mock();
        vm.stopBroadcast();

        return NetworkConfig({
            wethUsdPriceFeed: address(wethUsdPriceFeed),
            wbtcUsdPriceFeed: address(wbtcUsdPriceFeed),
            weth: address(weth),
            wbtc: address(wbtc),
            deployerkey: DEFAULT_ANVIL_PRIVATE_KEY
        });
    }



}