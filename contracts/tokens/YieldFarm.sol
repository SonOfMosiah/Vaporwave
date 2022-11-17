// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

import "./YieldToken.sol";

/// @title Vaporwave Yield Farm
contract YieldFarm is YieldToken, ReentrancyGuard {
    using SafeERC20 for IERC20;

    /// Staking token address
    address public stakingToken;

    constructor(
        string memory _name,
        string memory _symbol,
        address _stakingToken
    ) YieldToken(_name, _symbol, 0) {
        stakingToken = _stakingToken;
    }

    /// @notice Stake `_amount` tokens
    /// @dev mints yield farm tokens
    /// @param _amount Amount of tokens to stake
    function stake(uint256 _amount) external nonReentrant {
        IERC20(stakingToken).safeTransferFrom(
            msg.sender,
            address(this),
            _amount
        );
        _mint(msg.sender, _amount);
    }

    /// @notice Unstake `_amount` tokens
    /// @dev burns yield farm tokens
    /// @param _amount Amount of tokens to unstake
    function unstake(uint256 _amount) external nonReentrant {
        _burn(msg.sender, _amount);
        IERC20(stakingToken).safeTransfer(msg.sender, _amount);
    }
}
