// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title Vaporwave Timelock Target Interface
interface ITimelockTarget {
    function transferOwnership(address _owner) external;

    function withdrawToken(
        address _token,
        address _account,
        uint256 _amount
    ) external;
}
