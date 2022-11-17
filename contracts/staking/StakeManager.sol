// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";

import "./interfaces/IRewardTracker.sol";

/// @title Vaporwave Stake Manager
contract StakeManager is Ownable {
    /// @notice Stake `_amount` tokens for `_account`
    /// @param _rewardTracker The address of the reward tracker
    /// @param _account The account to stake for
    /// @param _token The token to stake
    /// @param _amount The amount of tokens to stake
    function stakeForAccount(
        address _rewardTracker,
        address _account,
        address _token,
        uint256 _amount
    ) external onlyOwner {
        IRewardTracker(_rewardTracker).stakeForAccount(
            _account,
            _account,
            _token,
            _amount
        );
    }
}
