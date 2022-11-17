// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IVwaveMigrator {
    function iouTokens(address _token) external view returns (address);
}
