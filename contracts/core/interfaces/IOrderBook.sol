// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// Interface for the OrderBook contract
interface IOrderBook {
    /// @notice Emitted when an increase order is created
    event CreateIncreaseOrder(
        address indexed account,
        uint256 orderIndex,
        address purchaseToken,
        uint256 purchaseTokenAmount,
        address collateralToken,
        address indexToken,
        uint256 sizeDelta,
        bool isLong,
        uint256 triggerPrice,
        bool triggerAboveThreshold,
        uint256 executionFee
    );
    /// @notice Emitted when an increase order is cancelled
    event CancelIncreaseOrder(
        address indexed account,
        uint256 orderIndex,
        address purchaseToken,
        uint256 purchaseTokenAmount,
        address collateralToken,
        address indexToken,
        uint256 sizeDelta,
        bool isLong,
        uint256 triggerPrice,
        bool triggerAboveThreshold,
        uint256 executionFee
    );
    /// @notice Emitted when an increase order is executed
    event ExecuteIncreaseOrder(
        address indexed account,
        uint256 orderIndex,
        address purchaseToken,
        uint256 purchaseTokenAmount,
        address collateralToken,
        address indexToken,
        uint256 sizeDelta,
        bool isLong,
        uint256 triggerPrice,
        bool triggerAboveThreshold,
        uint256 executionFee,
        uint256 executionPrice
    );
    /// @notice Emitted when an increase order is updated
    event UpdateIncreaseOrder(
        address indexed account,
        uint256 orderIndex,
        address collateralToken,
        address indexToken,
        bool isLong,
        uint256 sizeDelta,
        uint256 triggerPrice,
        bool triggerAboveThreshold
    );
    /// @notice Emitted when an decrease order is created
    event CreateDecreaseOrder(
        address indexed account,
        uint256 orderIndex,
        address collateralToken,
        uint256 collateralDelta,
        address indexToken,
        uint256 sizeDelta,
        bool isLong,
        uint256 triggerPrice,
        bool triggerAboveThreshold,
        uint256 executionFee
    );
    /// @notice Emitted when an decrease order is cancelled
    event CancelDecreaseOrder(
        address indexed account,
        uint256 orderIndex,
        address collateralToken,
        uint256 collateralDelta,
        address indexToken,
        uint256 sizeDelta,
        bool isLong,
        uint256 triggerPrice,
        bool triggerAboveThreshold,
        uint256 executionFee
    );
    /// @notice Emitted when an decrease order is executed
    event ExecuteDecreaseOrder(
        address indexed account,
        uint256 orderIndex,
        address collateralToken,
        uint256 collateralDelta,
        address indexToken,
        uint256 sizeDelta,
        bool isLong,
        uint256 triggerPrice,
        bool triggerAboveThreshold,
        uint256 executionFee,
        uint256 executionPrice
    );
    /// @notice Emitted when an decrease order is updated
    event UpdateDecreaseOrder(
        address indexed account,
        uint256 orderIndex,
        address collateralToken,
        uint256 collateralDelta,
        address indexToken,
        uint256 sizeDelta,
        bool isLong,
        uint256 triggerPrice,
        bool triggerAboveThreshold
    );
    /// @notice Emitted when an swap order is created
    event CreateSwapOrder(
        address indexed account,
        uint256 orderIndex,
        address[] path,
        uint256 amountIn,
        uint256 minOut,
        uint256 triggerRatio,
        bool triggerAboveThreshold,
        bool shouldUnwrap,
        uint256 executionFee
    );
    /// @notice Emitted when an swap order is cancelled
    event CancelSwapOrder(
        address indexed account,
        uint256 orderIndex,
        address[] path,
        uint256 amountIn,
        uint256 minOut,
        uint256 triggerRatio,
        bool triggerAboveThreshold,
        bool shouldUnwrap,
        uint256 executionFee
    );
    /// @notice Emitted when an swap order is updated
    event UpdateSwapOrder(
        address indexed account,
        uint256 ordexIndex,
        address[] path,
        uint256 amountIn,
        uint256 minOut,
        uint256 triggerRatio,
        bool triggerAboveThreshold,
        bool shouldUnwrap,
        uint256 executionFee
    );
    /// @notice Emitted when an swap order is executed
    event ExecuteSwapOrder(
        address indexed account,
        uint256 orderIndex,
        address[] path,
        uint256 amountIn,
        uint256 minOut,
        uint256 amountOut,
        uint256 triggerRatio,
        bool triggerAboveThreshold,
        bool shouldUnwrap,
        uint256 executionFee
    );
    /// @notice Emitted when the contract is initialized
    event Initialize(
        address router,
        address vault,
        address weth,
        uint256 minExecutionFee,
        uint256 minPurchaseTokenAmountUsd
    );
    /// @notice Emitted when the minimum execution fee is updated
    /// @param minExecutionFee The new minimum execution fee
    event UpdateMinExecutionFee(uint256 minExecutionFee);
    /// @notice Emitted when the minimum purchase token amount in USD is updated
    /// @param minPurchaseTokenAmountUsd The new minimum purchase token amount in USD
    event UpdateMinPurchaseTokenAmountUsd(uint256 minPurchaseTokenAmountUsd);

    /// @notice Get swap order
    /// @param _account The account address
    /// @param _orderIndex The index of the order
    function getSwapOrder(address _account, uint256 _orderIndex)
        external
        view
        returns (
            address path0,
            address path1,
            address path2,
            uint256 amountIn,
            uint256 minOut,
            uint256 triggerRatio,
            bool triggerAboveThreshold,
            bool shouldUnwrap,
            uint256 executionFee
        );

    /// @notice Get an increase order
    /// @param _account The account that created the order
    /// @param _orderIndex The index of the order to get
    function getIncreaseOrder(address _account, uint256 _orderIndex)
        external
        view
        returns (
            address purchaseToken,
            uint256 purchaseTokenAmount,
            address collateralToken,
            address indexToken,
            uint256 sizeDelta,
            bool isLong,
            uint256 triggerPrice,
            bool triggerAboveThreshold,
            uint256 executionFee
        );

    /// @notice Get a decrease order
    /// @param _account The account that created the order
    /// @param _orderIndex The index of the order to get
    function getDecreaseOrder(address _account, uint256 _orderIndex)
        external
        view
        returns (
            address collateralToken,
            uint256 collateralDelta,
            address indexToken,
            uint256 sizeDelta,
            bool isLong,
            uint256 triggerPrice,
            bool triggerAboveThreshold,
            uint256 executionFee
        );

    /// @notice Execute a swap order
    /// @dev Emits an event `ExecuteSwapOrder`
    /// @param _account The account that created the swap order
    /// @param _orderIndex The index of the order to execute
    /// @param _feeReceiver The address to receive the fees
    function executeSwapOrder(
        address _account,
        uint256 _orderIndex,
        address payable _feeReceiver
    ) external;

    /// @notice Execute a decrease order
    /// @dev Emits an `ExecuteDecreaseOrder` event
    /// @param _address The account that owns the decrease order
    /// @param _orderIndex The index of the decrease order
    /// @param _feeReceiver The address to receive the fees
    function executeDecreaseOrder(
        address _address,
        uint256 _orderIndex,
        address payable _feeReceiver
    ) external;

    /// @notice Execute an increase order
    /// @dev Emits an `ExecuteIncreaseOrder` event
    /// @param _address The account that owns the order
    /// @param _orderIndex The index of the increase order
    /// @param _feeReceiver The address to receive the fees
    function executeIncreaseOrder(
        address _address,
        uint256 _orderIndex,
        address payable _feeReceiver
    ) external;
}
