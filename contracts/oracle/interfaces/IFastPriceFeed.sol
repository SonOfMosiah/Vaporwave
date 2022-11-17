// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IFastPriceFeed {
    function lastUpdatedAt() external view returns (uint256);
    function lastUpdatedBlock() external view returns (uint256);
    function setIsSpreadEnabled(bool _isSpreadEnabled) external;
    function setSigner(address _account, bool _isActive) external;
}
