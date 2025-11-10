// SPDX-License-Identifier: MIT
pragma solidity >0.8.0;

import {
    AggregatorV3Interface
} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

contract Oracle is AggregatorV3Interface {
    /**
     * @notice Returns the number of decimals the aggregator responses represent
     */
    function decimals() external pure returns (uint8) {
        return 8;
    }

    /**
     * @notice Returns the description of the aggregator
     */
    function description() external pure returns (string memory) {
        return "Mock ETH/USD Price Feed";
    }

    /**
     * @notice Returns the version of the aggregator
     */
    function version() external pure returns (uint256) {
        return 1;
    }

    /**
     * @notice Returns the latest round data from the aggregator
     */
    function latestRoundData()
        external
        view
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        )
    {
        return (1, 411788170000, block.timestamp, block.timestamp, 1);
    }

    /**
     * @notice Returns the round data for a specific round ID
     */
    function getRoundData(
        uint80 _roundId
    )
        external
        view
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        )
    {
        return (
            _roundId,
            411788170000,
            block.timestamp,
            block.timestamp,
            _roundId
        );
    }
}
