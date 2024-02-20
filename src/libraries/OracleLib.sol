//SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";


// Library that checks ChainLink systems that provide price feeds for the collateral tokens
// that they provide stale data, DSCEngine will become unusable if the price feeds are not updated
library OracleLib {
    // Custom error
    error OracleLib__StalePrice();

    // Maximum age for a price feed to be considered fresh
    uint256 private constant MAX_PRICE_AGE = 3 hours;

    /**
    * @notice Fetches the latest round data from the given price feed and checks if it is stale.
    * Basically, it does every that AggregatorV3Interface.latestRoundData() does, but also checks if the data is stale.
    * @dev This function fetches the latest round data from the given AggregatorV3Interface price feed.
    * If the data is older than MAX_PRICE_AGE, it reverts with an OracleLib__StalePrice error.
    * @param priceFeed The price feed to fetch the latest round data from.
    * @return roundId The round ID of the latest round.
    * @return answer The price from the latest round.
    * @return startedAt The timestamp when the round started.
    * @return updatedAt The timestamp when the round was last updated.
    * @return answeredInRound The round ID in which the answer was provided.
    */
    function staleChecksLatestRoundData(AggregatorV3Interface priceFeed)
        public
        view
        returns (uint80, int256, uint256, uint256, uint80)
    {
        // Fetch the latest round data from the price feed
        (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) =
            priceFeed.latestRoundData();
        // How mane seconds have passed since the price was last updated
        uint256 secondsSince = block.timestamp - updatedAt;
        // If these seconds are more than the maximum allowed, revert
        if (secondsSince > MAX_PRICE_AGE) {
            revert OracleLib__StalePrice();
        }
        // Else , return the appropriate data
        return (roundId, answer, startedAt, updatedAt, answeredInRound);
    }
}
