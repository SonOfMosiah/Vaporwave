// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./interfaces/IRouter.sol";
import "./interfaces/IVault.sol";
import "./interfaces/IPositionRouter.sol";

import "../peripherals/interfaces/ITimelock.sol";
import "./BasePositionManager.sol";

/// Sender does not have function permissions
error Forbidden();
/// The request has expired
error RequestExpired();
/// The minimum delay has not yet passed
error DelayNotPassed();
/// The execution fee is less than the minimum fee
error InvalidExecutionFee();
/// Incorrect msg.value sent with the transaction
error InvalidValue();
/// Invalid token swap path
error InvalidPath();

/// @title Vaporwave Position Router
contract PositionRouter is BasePositionManager, IPositionRouter {
    using SafeERC20 for IERC20;

    struct IncreasePositionRequest {
        address account;
        address[] path;
        address indexToken;
        uint256 amountIn;
        uint256 minOut;
        uint256 sizeDelta;
        bool isLong;
        uint256 acceptablePrice;
        uint256 executionFee;
        uint256 blockNumber;
        uint256 blockTime;
        bool hasCollateralInETH;
    }

    struct DecreasePositionRequest {
        address account;
        address[] path;
        address indexToken;
        uint256 collateralDelta;
        uint256 sizeDelta;
        bool isLong;
        address receiver;
        uint256 acceptablePrice;
        uint256 minOut;
        uint256 executionFee;
        uint256 blockNumber;
        uint256 blockTime;
        bool withdrawETH;
    }

    uint256 public minExecutionFee;

    uint256 public minBlockDelayKeeper;
    uint256 public minTimeDelayPublic;
    uint256 public maxTimeDelay;

    bool public isLeverageEnabled = true;

    bytes32[] public increasePositionRequestKeys;
    bytes32[] public decreasePositionRequestKeys;

    uint256 public increasePositionRequestKeysStart;
    uint256 public decreasePositionRequestKeysStart;

    /// Mapping of position keepers
    mapping(address => bool) public isPositionKeeper;

    /// Mapping of user increase position index
    mapping(address => uint256) public increasePositionsIndex;
    /// Mapping of increase position requests
    mapping(bytes32 => IncreasePositionRequest) public increasePositionRequests;

    /// Mapping of user decrease position index
    mapping(address => uint256) public decreasePositionsIndex;
    /// Mapping of decrease position requests
    mapping(bytes32 => DecreasePositionRequest) public decreasePositionRequests;

    /// @notice Emitted when an increase position is created
    event CreateIncreasePosition(
        address indexed account,
        address[] path,
        address indexToken,
        uint256 amountIn,
        uint256 minOut,
        uint256 sizeDelta,
        bool isLong,
        uint256 acceptablePrice,
        uint256 executionFee,
        uint256 index,
        uint256 blockNumber,
        uint256 blockTime,
        uint256 gasPrice
    );

    /// @notice Emitted when an increase position is executed
    event ExecuteIncreasePosition(
        address indexed account,
        address[] path,
        address indexToken,
        uint256 amountIn,
        uint256 minOut,
        uint256 sizeDelta,
        bool isLong,
        uint256 acceptablePrice,
        uint256 executionFee,
        uint256 blockGap,
        uint256 timeGap
    );

    /// @notice Emitted when an increase position is cancelled
    event CancelIncreasePosition(
        address indexed account,
        address[] path,
        address indexToken,
        uint256 amountIn,
        uint256 minOut,
        uint256 sizeDelta,
        bool isLong,
        uint256 acceptablePrice,
        uint256 executionFee,
        uint256 blockGap,
        uint256 timeGap
    );

    /// @notice Emitted when a decrease position is created
    event CreateDecreasePosition(
        address indexed account,
        address[] path,
        address indexToken,
        uint256 collateralDelta,
        uint256 sizeDelta,
        bool isLong,
        address receiver,
        uint256 acceptablePrice,
        uint256 minOut,
        uint256 executionFee,
        uint256 index,
        uint256 blockNumber,
        uint256 blockTime
    );

    /// @notice Emitted when a decrease position is executed
    event ExecuteDecreasePosition(
        address indexed account,
        address[] path,
        address indexToken,
        uint256 collateralDelta,
        uint256 sizeDelta,
        bool isLong,
        address receiver,
        uint256 acceptablePrice,
        uint256 minOut,
        uint256 executionFee,
        uint256 blockGap,
        uint256 timeGap
    );

    /// @notice Emitted when a decrease position is cancelled
    event CancelDecreasePosition(
        address indexed account,
        address[] path,
        address indexToken,
        uint256 collateralDelta,
        uint256 sizeDelta,
        bool isLong,
        address receiver,
        uint256 acceptablePrice,
        uint256 minOut,
        uint256 executionFee,
        uint256 blockGap,
        uint256 timeGap
    );

    /// @notice Emitted when a position keeper is updated
    /// @param account The position keeper address
    /// @param isActive Whether the position keeper is active
    event SetPositionKeeper(address indexed account, bool isActive);
    /// @notice Emitted when the minimum execution fee is updated
    /// @param minExecutionFee The new minimum execution fee
    event SetMinExecutionFee(uint256 minExecutionFee);
    /// @notice Emitted when the isLeverageEnabled variable is updated
    /// @param isLeverageEnabled Whether leverage is enabled or not
    event SetIsLeverageEnabled(bool isLeverageEnabled);
    /// @notice Emitted when the delay values are updated
    /// @param minBlockDelayKeeper The new minimum block delay for the keeper
    /// @param minTimeDelayPublic The new minimum time delay for the public
    /// @param maxTimeDelay The new maximum time delay
    event SetDelayValues(
        uint256 minBlockDelayKeeper,
        uint256 minTimeDelayPublic,
        uint256 maxTimeDelay
    );
    /// @notice Emitted when the request keys start values are updated
    /// @param increasePositionRequestKeysStart The new increase position request keys start
    /// @param decreasePositionRequestKeysStart The new decrease position request keys start
    event SetRequestKeysStartValues(
        uint256 increasePositionRequestKeysStart,
        uint256 decreasePositionRequestKeysStart
    );

    modifier onlyPositionKeeper() {
        if (!isPositionKeeper[msg.sender]) {
            revert Forbidden();
        }
        _;
    }

    constructor(
        address _vault,
        address _router,
        address _weth,
        uint256 _depositFee,
        uint256 _minExecutionFee
    ) BasePositionManager(_vault, _router, _weth, _depositFee) {
        minExecutionFee = _minExecutionFee;
    }

    /// @notice Set `_account` as a position keeper true/false: `_isActive`
    /// @param _account Address of the account to set as a position keeper
    /// @param _isActive True/false to set the account as a position keeper
    function setPositionKeeper(address _account, bool _isActive)
        external
        onlyAdmin
    {
        isPositionKeeper[_account] = _isActive;
        emit SetPositionKeeper(_account, _isActive);
    }

    /// @notice Set the minimum execution fee to `_minExecutionFee`
    /// @param _minExecutionFee The nex minimum execution fee
    function setMinExecutionFee(uint256 _minExecutionFee) external onlyAdmin {
        minExecutionFee = _minExecutionFee;
        emit SetMinExecutionFee(_minExecutionFee);
    }

    /// @notice Set the isLeverageEnabled flag to `_isLeverageEnabled`
    /// @param _isLeverageEnabled True to enable leverage, false otherwise
    function setIsLeverageEnabled(bool _isLeverageEnabled) external onlyAdmin {
        isLeverageEnabled = _isLeverageEnabled;
        emit SetIsLeverageEnabled(_isLeverageEnabled);
    }

    /// @notice Set the delay values
    /// @dev Emits an event `SetDelayValues`
    /// @param _minBlockDelayKeeper The minimum block delay for the keeper
    /// @param _minTimeDelayPublic The minimum time delay for the public
    /// @param _maxTimeDelay The maximum time delay
    function setDelayValues(
        uint256 _minBlockDelayKeeper,
        uint256 _minTimeDelayPublic,
        uint256 _maxTimeDelay
    ) external onlyAdmin {
        minBlockDelayKeeper = _minBlockDelayKeeper;
        minTimeDelayPublic = _minTimeDelayPublic;
        maxTimeDelay = _maxTimeDelay;
        emit SetDelayValues(
            _minBlockDelayKeeper,
            _minTimeDelayPublic,
            _maxTimeDelay
        );
    }

    /// @notice Set the request keys start values
    /// @dev Emits an event `SetRequestKeysStartValues`
    /// @param _increasePositionRequestKeysStart The start value for the increase position request key
    /// @param _decreasePositionRequestKeysStart The start value for the decrease position request key
    function setRequestKeysStartValues(
        uint256 _increasePositionRequestKeysStart,
        uint256 _decreasePositionRequestKeysStart
    ) external onlyAdmin {
        increasePositionRequestKeysStart = _increasePositionRequestKeysStart;
        decreasePositionRequestKeysStart = _decreasePositionRequestKeysStart;

        emit SetRequestKeysStartValues(
            _increasePositionRequestKeysStart,
            _decreasePositionRequestKeysStart
        );
    }

    /// @notice Execute increase positions
    /// @dev Function executes all increase positions from index `increasePositionRequestKeysStart` to `_endIndex`
    /// @param _endIndex The index of the increase position to stop execution
    /// @param _executionFeeReceiver The address to receive the execution fees
    function executeIncreasePositions(
        uint256 _endIndex,
        address payable _executionFeeReceiver
    ) external override onlyPositionKeeper {
        uint256 index = increasePositionRequestKeysStart;
        uint256 length = increasePositionRequestKeys.length;

        if (index >= length) {
            return;
        }

        if (_endIndex > length) {
            _endIndex = length;
        }

        while (index < _endIndex) {
            bytes32 key = increasePositionRequestKeys[index];

            // if the request was executed then delete the key from the array
            // if the request was not executed then break from the loop, this can happen if the
            // minimum number of blocks has not yet passed
            // an error could be thrown if the request is too old or if the slippage is
            // higher than what the user specified, or if there is insufficient liquidity for the position
            // in case an error was thrown, cancel the request
            try
                this.executeIncreasePosition(key, _executionFeeReceiver)
            returns (bool _wasExecuted) {
                if (!_wasExecuted) {
                    break;
                }
            } catch {
                // wrap this call in a try catch to prevent invalid cancels from blocking the loop
                try
                    this.cancelIncreasePosition(key, _executionFeeReceiver)
                returns (bool _wasCancelled) {
                    if (!_wasCancelled) {
                        break;
                    }
                    // solhint-disable-next-line no-empty-blocks
                } catch {}
            }

            delete increasePositionRequestKeys[index];
            index++;
        }

        increasePositionRequestKeysStart = index;
    }

    /// @notice Execute decrease positions
    /// @dev Function executes all decrease positions from index `decreasePositionRequestKeysStart` to `_endIndex`
    /// @param _endIndex The index of the increase position to stop execution
    /// @param _executionFeeReceiver The address to receive the execution fees
    function executeDecreasePositions(
        uint256 _endIndex,
        address payable _executionFeeReceiver
    ) external override onlyPositionKeeper {
        uint256 index = decreasePositionRequestKeysStart;
        uint256 length = decreasePositionRequestKeys.length;

        if (index >= length) {
            return;
        }

        if (_endIndex > length) {
            _endIndex = length;
        }

        while (index < _endIndex) {
            bytes32 key = decreasePositionRequestKeys[index];

            // if the request was executed then delete the key from the array
            // if the request was not executed then break from the loop, this can happen if the
            // minimum number of blocks has not yet passed
            // an error could be thrown if the request is too old
            // in case an error was thrown, cancel the request
            try
                this.executeDecreasePosition(key, _executionFeeReceiver)
            returns (bool _wasExecuted) {
                if (!_wasExecuted) {
                    break;
                }
            } catch {
                // wrap this call in a try catch to prevent invalid cancels from blocking the loop
                try
                    this.cancelDecreasePosition(key, _executionFeeReceiver)
                returns (bool _wasCancelled) {
                    if (!_wasCancelled) {
                        break;
                    }
                    // solhint-disable-next-line no-empty-blocks
                } catch {}
            }

            delete decreasePositionRequestKeys[index];
            index++;
        }

        decreasePositionRequestKeysStart = index;
    }

    /// @notice Create an increase position
    /// @param _path The path of the token swap
    /// @param _indexToken The address of the token to long or short
    /// @param _amountIn The amount of tokens to swap in
    /// @param _minOut The minimun tokens to swap out
    /// @param _sizeDelta The size delta
    /// @param _isLong True if the position is long, false if short
    /// @param _acceptablePrice The acceptable price
    /// @param _executionFee The execution fee
    /// @param _referralCode The trader's referral code
    function createIncreasePosition(
        address[] memory _path,
        address _indexToken,
        uint256 _amountIn,
        uint256 _minOut,
        uint256 _sizeDelta,
        bool _isLong,
        uint256 _acceptablePrice,
        uint256 _executionFee,
        bytes32 _referralCode
    ) external payable nonReentrant {
        if (_executionFee < minExecutionFee) {
            revert InvalidExecutionFee();
        }
        if (msg.value != _executionFee) {
            revert InvalidValue();
        }
        if (_path.length != 1 && _path.length != 2) {
            revert InvalidPathLength();
        }

        _transferInETH();
        _setTraderReferralCode(_referralCode);

        if (_amountIn > 0) {
            IRouter(router).pluginTransfer(
                _path[0],
                msg.sender,
                address(this),
                _amountIn
            );
        }

        _createIncreasePosition(
            msg.sender,
            _path,
            _indexToken,
            _amountIn,
            _minOut,
            _sizeDelta,
            _isLong,
            _acceptablePrice,
            _executionFee,
            false
        );
    }

    /// @notice Create an increase position with ETH
    /// @param _path The path of the token swap
    /// @param _indexToken The address of the token to long or short
    /// @param _minOut The minimun tokens to swap out
    /// @param _sizeDelta The size delta
    /// @param _isLong True if the position is long, false if short
    /// @param _acceptablePrice The acceptable price
    /// @param _executionFee The execution fee
    /// @param _referralCode The trader's referral code
    function createIncreasePositionETH(
        address[] memory _path,
        address _indexToken,
        uint256 _minOut,
        uint256 _sizeDelta,
        bool _isLong,
        uint256 _acceptablePrice,
        uint256 _executionFee,
        bytes32 _referralCode
    ) external payable nonReentrant {
        if (_executionFee < minExecutionFee) {
            revert InvalidExecutionFee();
        }
        if (msg.value != _executionFee) {
            revert InvalidValue();
        }
        if (_path.length != 1 && _path.length != 2) {
            revert InvalidPathLength();
        }
        if (_path[0] != weth) {
            revert InvalidPath();
        }

        _transferInETH();
        _setTraderReferralCode(_referralCode);

        uint256 amountIn = msg.value - _executionFee;

        _createIncreasePosition(
            msg.sender,
            _path,
            _indexToken,
            amountIn,
            _minOut,
            _sizeDelta,
            _isLong,
            _acceptablePrice,
            _executionFee,
            true
        );
    }

    /// @notice Create an decrease position
    /// @param _path The path of the token swap
    /// @param _indexToken The address of the token to long or short
    /// @param _collateralDelta The collateral delta
    /// @param _sizeDelta The size delta
    /// @param _isLong True if the position is long, false if short
    /// @param _receiver The receiver
    /// @param _acceptablePrice The acceptable price
    /// @param _minOut The minimum amount to swap out
    /// @param _executionFee The execution fee
    /// @param _withdrawETH True if withdrawing ETH, false otherwise
    function createDecreasePosition(
        address[] memory _path,
        address _indexToken,
        uint256 _collateralDelta,
        uint256 _sizeDelta,
        bool _isLong,
        address _receiver,
        uint256 _acceptablePrice,
        uint256 _minOut,
        uint256 _executionFee,
        bool _withdrawETH
    ) external payable nonReentrant {
        if (_executionFee < minExecutionFee) {
            revert InvalidExecutionFee();
        }
        if (msg.value != _executionFee) {
            revert InvalidValue();
        }
        if (_path.length != 1 && _path.length != 2) {
            revert InvalidPathLength();
        }

        if (_withdrawETH) {
            if (_path[_path.length - 1] != weth) {
                revert InvalidPath();
            }
        }

        _transferInETH();

        _createDecreasePosition(
            msg.sender,
            _path,
            _indexToken,
            _collateralDelta,
            _sizeDelta,
            _isLong,
            _receiver,
            _acceptablePrice,
            _minOut,
            _executionFee,
            _withdrawETH
        );
    }

    /// @notice Get the length of the request queue
    function getRequestQueueLengths()
        external
        view
        returns (
            uint256,
            uint256,
            uint256,
            uint256
        )
    {
        return (
            increasePositionRequestKeysStart,
            increasePositionRequestKeys.length,
            decreasePositionRequestKeysStart,
            decreasePositionRequestKeys.length
        );
    }

    /// @notice Execute an increase position
    /// @dev Emit an event `ExecuteIncreasePosition`
    /// @param _key The key for the request
    /// @param _executionFeeReceiver The account to receive the execution fee
    /// @return The execution success
    function executeIncreasePosition(
        bytes32 _key,
        address payable _executionFeeReceiver
    ) public nonReentrant returns (bool) {
        IncreasePositionRequest memory request = increasePositionRequests[_key];
        // if the request was already executed or cancelled, return true so that the executeIncreasePositions loop will continue executing the next request
        if (request.account == address(0)) {
            return true;
        }

        bool shouldExecute = _validateExecution(
            request.blockNumber,
            request.blockTime,
            request.account
        );
        if (!shouldExecute) {
            return false;
        }

        delete increasePositionRequests[_key];

        if (request.amountIn > 0) {
            uint256 amountIn = request.amountIn;

            if (request.path.length > 1) {
                IERC20(request.path[0]).safeTransfer(vault, request.amountIn);
                amountIn = _swap(request.path, request.minOut, address(this));
            }

            uint256 afterFeeAmount = _collectFees(
                msg.sender,
                request.path,
                amountIn,
                request.indexToken,
                request.isLong,
                request.sizeDelta
            );
            IERC20(request.path[request.path.length - 1]).safeTransfer(
                vault,
                afterFeeAmount
            );
        }

        _increasePosition(
            request.account,
            request.path[request.path.length - 1],
            request.indexToken,
            request.sizeDelta,
            request.isLong,
            request.acceptablePrice
        );

        _transferOutETH(request.executionFee, _executionFeeReceiver);

        emit ExecuteIncreasePosition(
            request.account,
            request.path,
            request.indexToken,
            request.amountIn,
            request.minOut,
            request.sizeDelta,
            request.isLong,
            request.acceptablePrice,
            request.executionFee,
            block.number - request.blockNumber,
            // solhint-disable-next-line not-rely-on-time
            block.timestamp - request.blockTime
        );

        return true;
    }

    /// @notice Cancel an increase position
    /// @param _key The key for the request
    /// @param _executionFeeReceiver The account to receiver the execution fee
    /// @return The success of the cancellation
    function cancelIncreasePosition(
        bytes32 _key,
        address payable _executionFeeReceiver
    ) public nonReentrant returns (bool) {
        IncreasePositionRequest memory request = increasePositionRequests[_key];
        // if the request was already executed or cancelled, return true so that the executeIncreasePositions loop will continue executing the next request
        if (request.account == address(0)) {
            return true;
        }

        bool shouldCancel = _validateCancellation(
            request.blockNumber,
            request.blockTime,
            request.account
        );
        if (!shouldCancel) {
            return false;
        }

        delete increasePositionRequests[_key];

        if (request.hasCollateralInETH) {
            _transferOutETHWithGasLimit(
                request.amountIn,
                payable(request.account)
            );
        } else {
            IERC20(request.path[0]).safeTransfer(
                request.account,
                request.amountIn
            );
        }

        _transferOutETH(request.executionFee, _executionFeeReceiver);

        emit CancelIncreasePosition(
            request.account,
            request.path,
            request.indexToken,
            request.amountIn,
            request.minOut,
            request.sizeDelta,
            request.isLong,
            request.acceptablePrice,
            request.executionFee,
            block.number - request.blockNumber,
            // solhint-disable-next-line not-rely-on-time
            block.timestamp - request.blockTime
        );

        return true;
    }

    /// @notice Execute a decrease position
    /// @param _key The key of the request
    /// @param _executionFeeReceiver The account to receive the execution fee
    /// @return The success of the execution
    function executeDecreasePosition(
        bytes32 _key,
        address payable _executionFeeReceiver
    ) public nonReentrant returns (bool) {
        DecreasePositionRequest memory request = decreasePositionRequests[_key];
        // if the request was already executed or cancelled, return true so that the executeDecreasePositions loop will continue executing the next request
        if (request.account == address(0)) {
            return true;
        }

        bool shouldExecute = _validateExecution(
            request.blockNumber,
            request.blockTime,
            request.account
        );
        if (!shouldExecute) {
            return false;
        }

        delete decreasePositionRequests[_key];

        uint256 amountOut = _decreasePosition(
            request.account,
            request.path[0],
            request.indexToken,
            request.collateralDelta,
            request.sizeDelta,
            request.isLong,
            address(this),
            request.acceptablePrice
        );

        if (request.path.length > 1) {
            IERC20(request.path[0]).safeTransfer(vault, amountOut);
            amountOut = _swap(request.path, request.minOut, address(this));
        }

        if (request.withdrawETH) {
            _transferOutETHWithGasLimit(amountOut, payable(request.receiver));
        } else {
            IERC20(request.path[request.path.length - 1]).safeTransfer(
                request.receiver,
                amountOut
            );
        }

        _transferOutETH(request.executionFee, _executionFeeReceiver);

        emit ExecuteDecreasePosition(
            request.account,
            request.path,
            request.indexToken,
            request.collateralDelta,
            request.sizeDelta,
            request.isLong,
            request.receiver,
            request.acceptablePrice,
            request.minOut,
            request.executionFee,
            block.number - request.blockNumber,
            // solhint-disable-next-line not-rely-on-time
            block.timestamp - request.blockTime
        );

        return true;
    }

    /// @notice Cancel an decrease position
    /// @param _key The key for the request
    /// @param _executionFeeReceiver The account to receiver the execution fee
    /// @return The success of the cancellation
    function cancelDecreasePosition(
        bytes32 _key,
        address payable _executionFeeReceiver
    ) public nonReentrant returns (bool) {
        DecreasePositionRequest memory request = decreasePositionRequests[_key];
        // if the request was already executed or cancelled, return true so that the executeDecreasePositions loop will continue executing the next request
        if (request.account == address(0)) {
            return true;
        }

        bool shouldCancel = _validateCancellation(
            request.blockNumber,
            request.blockTime,
            request.account
        );
        if (!shouldCancel) {
            return false;
        }

        delete decreasePositionRequests[_key];

        _transferOutETH(request.executionFee, _executionFeeReceiver);

        emit CancelDecreasePosition(
            request.account,
            request.path,
            request.indexToken,
            request.collateralDelta,
            request.sizeDelta,
            request.isLong,
            request.receiver,
            request.acceptablePrice,
            request.minOut,
            request.executionFee,
            block.number - request.blockNumber,
            // solhint-disable-next-line not-rely-on-time
            block.timestamp - request.blockTime
        );

        return true;
    }

    /// @notice Get the request path for an increase position
    /// @param _key The key for the request
    /// @return The token swap path for the request
    function getIncreasePositionRequestPath(bytes32 _key)
        public
        view
        returns (address[] memory)
    {
        IncreasePositionRequest memory request = increasePositionRequests[_key];
        return request.path;
    }

    /// @notice Get the request path for a decrease position
    /// @param _key The key for the request
    /// @return The token swap path for the request
    function getDecreasePositionRequestPath(bytes32 _key)
        public
        view
        returns (address[] memory)
    {
        DecreasePositionRequest memory request = decreasePositionRequests[_key];
        return request.path;
    }

    /// @notice Get a request key
    /// @param _account The account associated with the request
    /// @param _index The index of the requestd
    function getRequestKey(address _account, uint256 _index)
        public
        pure
        returns (bytes32)
    {
        return keccak256(abi.encodePacked(_account, _index));
    }

    function _setTraderReferralCode(bytes32 _referralCode) internal {
        if (_referralCode != bytes32(0) && referralStorage != address(0)) {
            IReferralStorage(referralStorage).setTraderReferralCode(
                msg.sender,
                _referralCode
            );
        }
    }

    function _createIncreasePosition(
        address _account,
        address[] memory _path,
        address _indexToken,
        uint256 _amountIn,
        uint256 _minOut,
        uint256 _sizeDelta,
        bool _isLong,
        uint256 _acceptablePrice,
        uint256 _executionFee,
        bool _hasCollateralInETH
    ) internal {
        uint256 index = increasePositionsIndex[_account] + 1;
        increasePositionsIndex[_account] = index;

        IncreasePositionRequest memory request = IncreasePositionRequest(
            _account,
            _path,
            _indexToken,
            _amountIn,
            _minOut,
            _sizeDelta,
            _isLong,
            _acceptablePrice,
            _executionFee,
            block.number,
            // solhint-disable-next-line not-rely-on-time
            block.timestamp,
            _hasCollateralInETH
        );

        bytes32 key = getRequestKey(_account, index);
        increasePositionRequests[key] = request;

        increasePositionRequestKeys.push(key);

        emit CreateIncreasePosition(
            _account,
            _path,
            _indexToken,
            _amountIn,
            _minOut,
            _sizeDelta,
            _isLong,
            _acceptablePrice,
            _executionFee,
            index,
            block.number,
            // solhint-disable-next-line not-rely-on-time
            block.timestamp,
            tx.gasprice
        );
    }

    function _createDecreasePosition(
        address _account,
        address[] memory _path,
        address _indexToken,
        uint256 _collateralDelta,
        uint256 _sizeDelta,
        bool _isLong,
        address _receiver,
        uint256 _acceptablePrice,
        uint256 _minOut,
        uint256 _executionFee,
        bool _withdrawETH
    ) internal {
        uint256 index = decreasePositionsIndex[_account] + 1;
        decreasePositionsIndex[_account] = index;

        DecreasePositionRequest memory request = DecreasePositionRequest(
            _account,
            _path,
            _indexToken,
            _collateralDelta,
            _sizeDelta,
            _isLong,
            _receiver,
            _acceptablePrice,
            _minOut,
            _executionFee,
            block.number,
            // solhint-disable-next-line not-rely-on-time
            block.timestamp,
            _withdrawETH
        );

        bytes32 key = getRequestKey(_account, index);
        decreasePositionRequests[key] = request;

        decreasePositionRequestKeys.push(key);

        emit CreateDecreasePosition(
            _account,
            _path,
            _indexToken,
            _collateralDelta,
            _sizeDelta,
            _isLong,
            _receiver,
            _acceptablePrice,
            _minOut,
            _executionFee,
            index,
            block.number,
            // solhint-disable-next-line not-rely-on-time
            block.timestamp
        );
    }

    function _validateExecution(
        uint256 _positionBlockNumber,
        uint256 _positionBlockTime,
        address _account
    ) internal view returns (bool) {
        // solhint-disable-next-line not-rely-on-time
        if (_positionBlockTime + maxTimeDelay <= block.timestamp) {
            revert RequestExpired();
        }

        bool isKeeperCall = msg.sender == address(this) ||
            isPositionKeeper[msg.sender];

        if (!isLeverageEnabled && !isKeeperCall) {
            revert Forbidden();
        }

        if (isKeeperCall) {
            return _positionBlockNumber + minBlockDelayKeeper <= block.number;
        }

        if (msg.sender != _account) {
            revert Forbidden();
        }

        // solhint-disable-next-line not-rely-on-time
        if (_positionBlockTime + minTimeDelayPublic > block.timestamp) {
            revert DelayNotPassed();
        }

        return true;
    }

    function _validateCancellation(
        uint256 _positionBlockNumber,
        uint256 _positionBlockTime,
        address _account
    ) internal view returns (bool) {
        bool isKeeperCall = msg.sender == address(this) ||
            isPositionKeeper[msg.sender];

        if (!isLeverageEnabled && !isKeeperCall) {
            revert Forbidden();
        }

        if (isKeeperCall) {
            return _positionBlockNumber + minBlockDelayKeeper <= block.number;
        }

        if (msg.sender != _account) {
            revert Forbidden();
        }

        // solhint-disable-next-line not-rely-on-time
        if (_positionBlockTime + minTimeDelayPublic > block.timestamp) {
            revert DelayNotPassed();
        }

        return true;
    }
}
