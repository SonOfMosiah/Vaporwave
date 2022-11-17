// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// Interface for the VLP Manager
interface IVlpManager {
    function cooldownDuration() external returns (uint256);

    function lastAddedAt(address _account) external returns (uint256);

    function addLiquidity(
        address _token,
        uint256 _amount,
        uint256 _minUsdv,
        uint256 _minVlp
    ) external returns (uint256);

    function addLiquidityForAccount(
        address _fundingAccount,
        address _account,
        address _token,
        uint256 _amount,
        uint256 _minUsdv,
        uint256 _minVlp
    ) external returns (uint256);

    function removeLiquidity(
        address _tokenOut,
        uint256 _vlpAmount,
        uint256 _minOut,
        address _receiver
    ) external returns (uint256);

    function removeLiquidityForAccount(
        address _account,
        address _tokenOut,
        uint256 _vlpAmount,
        uint256 _minOut,
        address _receiver
    ) external returns (uint256);

    function getAum(bool maximise) external view returns (uint256);

    function getTokenAum(address _token, bool maximise)
        external
        view
        returns (uint256);
}
