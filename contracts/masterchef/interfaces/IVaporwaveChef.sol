// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @notice Sender does not have permissions for this function
error Forbidden();

/// @notice Last distribution time cannot be 0
error InvalidLastDistributionTime();

/// @notice Amount must be greater than 0
error InvalidAmount();

/// @notice The user's current bonus multiplier must be between 1 and 100
error InvalidBonusMultiplier();

/// @notice Referrer cannot be the sender
error SelfReferral();

/// @notice Attempting to withdraw too many tokens
error InvalidWithdrawAmount();

/// @notice Allocation points must be greater than 0
error InvalidAllocationPoint();

/// @notice Weth transfer success returned false
error WethTransferFailed();

/// @notice Token is not a reward token
error InvalidRewardToken();

/// @notice Deposit Fee BP cannot be greater than max deposit fee BP
error InvalidDepositFee();

/// @notice Interface for Vaporwave MasterChef
/// @title Vaporwave MasterChef Interface
interface IVaporwaveMasterChef {
    /// @notice Emitted when rewards are depositted
    /// @param user The address of the user
    /// @param pid The pid
    /// @param amount The amount withdrawn
    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);

    /// @notice Emitted when a referral is recorded
    /// @param referrer The address of the referrer
    /// @param referral The address of the referral
    event Referral(address indexed referrer, address indexed referral);

    /// @notice Emitted when rewards are depositted
    /// @param user The address of the user
    /// @param pid The pid
    /// @param amount The amount withdrawn
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);

    /// @notice Emitted when rewards are depositted
    /// @param user The address of the user
    /// @param pid The pid
    /// @param amount The amount withdrawn
    event EmergencyWithdraw(
        address indexed user,
        uint256 indexed pid,
        uint256 amount
    );

    /// @notice Emitted when rewards are distributed
    /// @param rewardToken The reward token
    /// @param amount The amount of rewards distributed
    event DistributeRewards(address rewardToken, uint256 amount);

    function distributeRewards(address _rewardToken, uint256 _amount) external;

    function updatePool(uint256 _pid) external;

    function deposit(
        uint256 _pid,
        uint256 _amount,
        address _referrer
    ) external;

    function withdraw(uint256 _pid, uint256 _amount) external;

    function emergencyWithdraw(uint256 _pid) external;

    function pendingRewards(uint256 _pid, address _user)
        external
        view
        returns (uint256[] memory userPendingRewards);
}
