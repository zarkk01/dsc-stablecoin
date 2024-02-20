//SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {MockV3Aggregator} from "../test/mocks/MockV3Aggregator.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {AggregatorV3Interface} from "chainlink-brownie-contracts/contracts/src/v0.4/interfaces/AggregatorV3Interface.sol";

/**
 * @title HelperConfig
 * @notice This contract is used to manage the configuration of the network.
 * @dev It inherits from the Script contract. It uses MockV3Aggregator and ERC20Mock for testing purposes.
 */
contract HelperConfig is Script {
    uint8 private constant DECIMALS = 8;
    // Hardcoded prices for testing when anvil is the deployer
    int256 private constant ETH_PRICE = 2000e8;
    int256 private constant BTC_PRICE = 40000e8;
    uint256 public constant DEFAULT_ANVIL_PRIVATE_KEY =
        0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;

    // The NetworkConfig struct to store the active network configuration and will be this that will be returned
    NetworkConfig public activeConfig;

    struct NetworkConfig {
        address wethUsdPriceFeed;
        address wbtcUsdPriceFeed;
        address weth;
        address wbtc;
        uint256 deployerkey;
    }

    // Constructor that sets the active network configuration
    constructor() {
        // If it is sepolia network then use the sepolia configuration
        if (block.chainid == 11155111) {
            activeConfig = getSepoliaConfig();
        } else {
            // Otherwise use the anvil configuration
            activeConfig = getOrCreateAnvilConfig();
        }
    }

    // TO:DO - Implement the getMainnetConfig function
    //    function getMainnetConfig() internal view returns(NetworkConfig memory){
    //    }

    // Function that returns the active network configuration of sepolia network
    function getSepoliaConfig() internal view returns (NetworkConfig memory) {
        // Take the priceFeeds from : https://docs.chain.link/data-feeds/price-feeds/addresses?network=ethereum&page=1
        return NetworkConfig({
            wethUsdPriceFeed: 0x694AA1769357215DE4FAC081bf1f309aDC325306,
            wbtcUsdPriceFeed: 0x1b44F3514812d835EB1BDB0acB33d3fA3351Ee43,
            // Those address are taken from etherscan
            weth: 0x7b79995e5f793A07Bc00c21412e50Ecae098E7f9,
            wbtc: 0x92f3B59a79bFf5dc60c0d59eA13a44D082B2bdFC,
            deployerkey: vm.envUint("SEPOLIA_PRIVATE_KEY")
        });
    }

    // Function that returns the active network configuration of anvil network, meaning the fake blockchain
    function getOrCreateAnvilConfig() internal returns (NetworkConfig memory) {
        // If there is already a configuration then return it, don't bother do it again
        if (activeConfig.wethUsdPriceFeed != address(0)) {
            return activeConfig;
        }

        // Start the tx broadcast
        vm.startBroadcast();
        // We mock the AggregatorV3Interface and we create the price feeds for WETH and WBTC
        MockV3Aggregator wethUsdPriceFeed = new MockV3Aggregator(DECIMALS, ETH_PRICE);
        MockV3Aggregator wbtcUsdPriceFeed = new MockV3Aggregator(DECIMALS, BTC_PRICE);
        // Then we mock the ERC20 for WETH and WBTC, creating them
        ERC20Mock weth = new ERC20Mock();
        ERC20Mock wbtc = new ERC20Mock();
        vm.stopBroadcast();

        // All ready to return our mocked / fake configuration
        return NetworkConfig({
            // Price Feeds we just mocked
            wethUsdPriceFeed: address(wethUsdPriceFeed),
            wbtcUsdPriceFeed: address(wbtcUsdPriceFeed),
            // We need the address of this coins on anvil network
            weth: address(weth),
            wbtc: address(wbtc),
            // The deployerkey is hardcoded
            deployerkey: DEFAULT_ANVIL_PRIVATE_KEY
        });
    }
}
