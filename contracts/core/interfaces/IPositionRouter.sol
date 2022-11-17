// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// Interface for the PositionRouter
interface IPositionRouter {
    function executeIncreasePositions(
        uint256 _count,
        address payable _executionFeeReceiver
    ) external;

    function executeDecreasePositions(
        uint256 _count,
        address payable _executionFeeReceiver
    ) external;
}
