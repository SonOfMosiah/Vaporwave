// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// Interface for BasePositionManager
interface IBasePositionManager {
    /// @notice Emitted when the deposit fee is set
    /// @param depositFee The new deposit fee
    event SetDepositFee(uint256 depositFee);

    /// @notice Emitted when the increase position buffer basis points are set
    /// @param increasePositionBufferBps The new increase position buffer basis points
    event SetIncreasePositionBufferBps(uint256 increasePositionBufferBps);

    /// @notice Emitted when the referral storage address is set
    /// @param referralStorage The new referral storage address
    event SetReferralStorage(address referralStorage);

    /// @notice Emitted when the admin address is set
    /// @param admin The new admin address
    event SetAdmin(address admin);

    /// @notice Emitted when fees are withdrawn
    /// @param token The token withdrawn
    /// @param receiver The receiver of the funds
    /// @param amount The amount withdrawn
    event WithdrawFees(address token, address receiver, uint256 amount);

    /// @notice Emitted when the max global long and short sizes are set
    /// @param tokens The array of tokens
    /// @param longSizes The array of max long sizes
    /// @param shortSizes The array of max short sizes
    event SetMaxGlobalSizes(
        address[] tokens,
        uint256[] longSizes,
        uint256[] shortSizes
    );

    event IncreasePositionReferral(
        address account,
        uint256 sizeDelta,
        uint256 marginFeeBasisPoints,
        bytes32 referralCode,
        address referrer
    );

    event DecreasePositionReferral(
        address account,
        uint256 sizeDelta,
        uint256 marginFeeBasisPoints,
        bytes32 referralCode,
        address referrer
    );

    function maxGlobalLongSizes(address _token) external view returns (uint256);

    function maxGlobalShortSizes(address _token)
        external
        view
        returns (uint256);
}
