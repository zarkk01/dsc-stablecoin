//SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

// Library that checks ChainLink systems that provide price feeds for the collateral tokens
// that they provide stale data, DSCEngine will become unusable if the price feeds are not updated
library OracleLib {
    error OracleLib__StalePrice();

    uint256 private constant MAX_PRICE_AGE = 3 hours;

    function staleChecksLatestRoundData(AggregatorV3Interface priceFeed)
        public
        view
        returns (uint80, int256, uint256, uint256, uint80)
    {
        priceFeed.latestRoundData();
        (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) =
            priceFeed.latestRoundData();
        uint256 secondsSince = block.timestamp - updatedAt;
        if (secondsSince > MAX_PRICE_AGE) {
            revert OracleLib__StalePrice();
        }
        return (roundId, answer, startedAt, updatedAt, answeredInRound);
    }
}
