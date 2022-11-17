// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "../core/interfaces/IVlpManager.sol";

import "./interfaces/IRewardTracker.sol";
import "./interfaces/IRewardTracker.sol";

/// Allowance is less than the attempted transfer amount
error InsufficientAllowance();
/// Token cannot interact with the zero address
error ZeroAddress();
/// Must wait for the cooldown period to end to transfer
error TransferCooldown();

// provide a way to transfer staked VLP tokens by unstaking from the sender
// and staking for the receiver
// tests in RewardRouterV2.js
/// @title Vaporwave Staked VLP token contract
contract StakedVlp {
    /// The VLP token address
    address public vlp;
    /// The VLP manager address
    IVlpManager public vlpManager;
    /// The staked VLP tracker address
    address public stakedVlpTracker;
    /// The fee VLP tracker address
    address public feeVlpTracker;

    /// Mapping of token owners to their spender allowances
    mapping(address => mapping(address => uint256)) public allowances;

    /// @notice Emitted when a token approval is made
    /// @param owner The owner of the tokens
    /// @param spender The address that is allowed to spend the tokens
    /// @param value The amount of tokens approved
    event Approval(
        address indexed owner,
        address indexed spender,
        uint256 value
    );

    constructor(
        address _vlp,
        IVlpManager _vlpManager,
        address _stakedVlpTracker,
        address _feeVlpTracker
    ) {
        vlp = _vlp;
        vlpManager = _vlpManager;
        stakedVlpTracker = _stakedVlpTracker;
        feeVlpTracker = _feeVlpTracker;
    }

    /// @notice Approve `_spender` to transfer `_amount` tokens
    /// @param _spender The address that is allowed to spend the tokens
    /// @param _amount The amount of tokens approved
    /// @return Whether the approval was successful
    function approve(address _spender, uint256 _amount)
        external
        returns (bool)
    {
        _approve(msg.sender, _spender, _amount);
        return true;
    }

    /// @notice Transfer `_amount` tokens to `_recipient`
    /// @param _recipient The address that will receive the tokens
    /// @param _amount The amount of tokens to transfer
    /// @return Whether the transfer was successful
    function transfer(address _recipient, uint256 _amount)
        external
        returns (bool)
    {
        _transfer(msg.sender, _recipient, _amount);
        return true;
    }

    /// @notice Transfer `_amount` tokens from `_sender` to `_recipient`
    /// @param _sender The address that will send the tokens
    /// @param _recipient The address that will receive the tokens
    /// @param _amount The amount of tokens to transfer
    /// @return Whether the transfer was successful
    function transferFrom(
        address _sender,
        address _recipient,
        uint256 _amount
    ) external returns (bool) {
        if (allowances[_sender][msg.sender] < _amount) {
            revert InsufficientAllowance();
        }
        unchecked {
            uint256 nextAllowance = allowances[_sender][msg.sender] - _amount;
            _approve(_sender, msg.sender, nextAllowance);
        }
        _transfer(_sender, _recipient, _amount);
        return true;
    }

    /// @notice Get the allowance of `_spender` for `_owner`
    /// @param _owner The address that owns the tokens
    /// @param _spender The address that is allowed to spend the tokens
    /// @return The amount of tokens that `_spender` is allowed to spend for `_owner`
    function allowance(address _owner, address _spender)
        external
        view
        returns (uint256)
    {
        return allowances[_owner][_spender];
    }

    /// @notice Get the token balance of `_account`
    /// @param _account The address to query for the token balance
    /// @return The amount of tokens that `_account` owns
    function balanceOf(address _account) external view returns (uint256) {
        return IRewardTracker(stakedVlpTracker).depositBalances(_account, vlp);
    }

    /// @notice Get the total supply
    /// @return The total supply
    function totalSupply() external view returns (uint256) {
        return IERC20(stakedVlpTracker).totalSupply();
    }

    /// @notice Get the token name
    /// @return The token name (StakedVlp)
    function name() external pure returns (string memory) {
        return "StakedVlp";
    }

    /// @notice Get the token symbol
    /// @return The token symbol (sVLP)
    function symbol() external pure returns (string memory) {
        return "sVLP";
    }

    /// @notice Get the token decimals (18)
    /// @return The token decimals (18)
    function decimals() external pure returns (uint8) {
        return 18;
    }

    function _approve(
        address _owner,
        address _spender,
        uint256 _amount
    ) private {
        if (_owner == address(0) || _spender == address(0)) {
            revert ZeroAddress();
        }

        allowances[_owner][_spender] = _amount;

        emit Approval(_owner, _spender, _amount);
    }

    function _transfer(
        address _sender,
        address _recipient,
        uint256 _amount
    ) private {
        if (_sender == address(0) || _recipient == address(0)) {
            revert ZeroAddress();
        }

        if (
            vlpManager.lastAddedAt(_sender) + vlpManager.cooldownDuration() >
            // solhint-disable-next-line not-rely-on-time
            block.timestamp
        ) {
            revert TransferCooldown();
        }

        IRewardTracker(stakedVlpTracker).unstakeForAccount(
            _sender,
            feeVlpTracker,
            _amount,
            _sender
        );
        IRewardTracker(feeVlpTracker).unstakeForAccount(
            _sender,
            vlp,
            _amount,
            _sender
        );

        IRewardTracker(feeVlpTracker).stakeForAccount(
            _sender,
            _recipient,
            vlp,
            _amount
        );
        IRewardTracker(stakedVlpTracker).stakeForAccount(
            _recipient,
            _recipient,
            feeVlpTracker,
            _amount
        );
    }
}
