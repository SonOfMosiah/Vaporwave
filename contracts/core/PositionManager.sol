// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./interfaces/IRouter.sol";
import "./interfaces/IVault.sol";
import "./interfaces/IOrderBook.sol";

import "../peripherals/interfaces/ITimelock.sol";
import "./BasePositionManager.sol";

/// Sender does not have function permissions
error Forbidden();
/// Wrong token at path index `index`
error InvalidPath(uint8 index);
/// Collateral token must be weth
error InvalidCollateralToken();
/// Size delta cannot be 0
error LongDeposit();
/// Cannot decrease the leverage
error LongLeverageDecrease();

/// @title Vaporwave Position Manager
contract PositionManager is BasePositionManager {
    using SafeERC20 for IERC20;

    /// The order book address
    address public orderBook;
    /// True if the contract is in legaacy mode
    bool public inLegacyMode;
    /// True if the contract should validate increase order
    bool public shouldValidateIncreaseOrder = true;

    /// Mapping of order keepers
    mapping(address => bool) public isOrderKeeper;
    /// Mapping of partners
    mapping(address => bool) public isPartner;
    /// Mapping of liquidators
    mapping(address => bool) public isLiquidator;

    /// @notice Emitted when an order keeper is updated
    /// @param account The address of the order keeper
    /// @param isActive Whether the order keeper is active
    event SetOrderKeeper(address indexed account, bool isActive);
    /// @notice Emitted when a liquidator is updated
    /// @param account The address of the liquidator
    /// @param isActive Whether the liquidator is active
    event SetLiquidator(address indexed account, bool isActive);
    /// @notice Emitted when a partner is updated
    /// @param account The address of the partner
    /// @param isActive Whether the partner is active
    event SetPartner(address account, bool isActive);
    /// @notice Emitted when the inLegacyMode variable is updated
    /// @param inLegacyMode Whether the contract is in legacy mode
    event SetInLegacyMode(bool inLegacyMode);
    /// @notice Emitted when the shouldValidateIncreaseOrder variable is updated
    /// @param shouldValidateIncreaseOrder Whether the contract should validate increase orders
    event SetShouldValidateIncreaseOrder(bool shouldValidateIncreaseOrder);

    modifier onlyOrderKeeper() {
        if (!isOrderKeeper[msg.sender]) {
            revert Forbidden();
        }
        _;
    }

    modifier onlyLiquidator() {
        if (!isLiquidator[msg.sender]) {
            revert Forbidden();
        }
        _;
    }

    modifier onlyPartnersOrLegacyMode() {
        if (!isPartner[msg.sender] && !inLegacyMode) {
            revert Forbidden();
        }
        _;
    }

    constructor(
        address _vault,
        address _router,
        address _weth,
        uint256 _depositFee,
        address _orderBook
    ) BasePositionManager(_vault, _router, _weth, _depositFee) {
        orderBook = _orderBook;
    }

    /// @notice Set a order keeper address
    /// @param _account Address of the order keeper to set
    /// @param _isActive True to add the account as an order keeper, false to remove the account
    function setOrderKeeper(address _account, bool _isActive)
        external
        onlyAdmin
    {
        isOrderKeeper[_account] = _isActive;
        emit SetOrderKeeper(_account, _isActive);
    }

    /// @notice Set `_account` as a liquidator true/false: `_isActive`
    /// @param _account Address of the liquidator to set
    /// @param _isActive True to add the account as a liquidator, false to remove the account
    function setLiquidator(address _account, bool _isActive)
        external
        onlyAdmin
    {
        isLiquidator[_account] = _isActive;
        emit SetLiquidator(_account, _isActive);
    }

    /// @notice Set `_account` as a partner true/false: `_isActive`
    /// @param _account Address of the partner to set
    /// @param _isActive True to add the account as a partner, false to remove the account
    function setPartner(address _account, bool _isActive) external onlyAdmin {
        isPartner[_account] = _isActive;
        emit SetPartner(_account, _isActive);
    }

    /// @notice Set the inLegacyMode flag to `_inLegacyMode`
    /// @param _inLegacyMode True to turn on legacy mode, false to turn off legacy mode
    function setInLegacyMode(bool _inLegacyMode) external onlyAdmin {
        inLegacyMode = _inLegacyMode;
        emit SetInLegacyMode(_inLegacyMode);
    }

    /// @notice Set the shouldValidateIncreaseOrder flag to `_shouldValidateIncreaseOrder`
    /// @param _shouldValidateIncreaseOrder True to turn on the validation of increase order, false to turn off the validation of increase order
    function setShouldValidateIncreaseOrder(bool _shouldValidateIncreaseOrder)
        external
        onlyAdmin
    {
        shouldValidateIncreaseOrder = _shouldValidateIncreaseOrder;
        emit SetShouldValidateIncreaseOrder(_shouldValidateIncreaseOrder);
    }

    /// @notice increase a position
    /// @param _path path of the token swap
    /// @param _indexToken The address of the token to long or short
    /// @param _amountIn amount of the token to swap in
    /// @param _minOut minimum amount of token to swap out
    /// @param _sizeDelta size delta of the position
    /// @param _isLong true if the position is long, false if the position is short
    /// @param _price price of the position
    function increasePosition(
        address[] memory _path,
        address _indexToken,
        uint256 _amountIn,
        uint256 _minOut,
        uint256 _sizeDelta,
        bool _isLong,
        uint256 _price
    ) external nonReentrant onlyPartnersOrLegacyMode {
        if (_path.length != 1 && _path.length != 2) {
            revert InvalidPathLength();
        }

        if (_amountIn > 0) {
            if (_path.length == 1) {
                IRouter(router).pluginTransfer(
                    _path[0],
                    msg.sender,
                    address(this),
                    _amountIn
                );
            } else {
                IRouter(router).pluginTransfer(
                    _path[0],
                    msg.sender,
                    vault,
                    _amountIn
                );
                _amountIn = _swap(_path, _minOut, address(this));
            }

            uint256 afterFeeAmount = _collectFees(
                msg.sender,
                _path,
                _amountIn,
                _indexToken,
                _isLong,
                _sizeDelta
            );
            IERC20(_path[_path.length - 1]).safeTransfer(vault, afterFeeAmount);
        }

        _increasePosition(
            msg.sender,
            _path[_path.length - 1],
            _indexToken,
            _sizeDelta,
            _isLong,
            _price
        );
    }

    /// @notice increase a position with ETH
    /// @param _path path of the token swap
    /// @param _indexToken The address of the token to long or short
    /// @param _minOut minimum amount of token to swap out
    /// @param _sizeDelta size delta of the position
    /// @param _isLong true if the position is long, false if the position is short
    /// @param _price price of the position
    function increasePositionETH(
        address[] memory _path,
        address _indexToken,
        uint256 _minOut,
        uint256 _sizeDelta,
        bool _isLong,
        uint256 _price
    ) external payable nonReentrant onlyPartnersOrLegacyMode {
        if (_path.length != 1 && _path.length != 2) {
            revert InvalidPathLength();
        }
        if (_path[0] != weth) {
            revert InvalidPath(0);
        }

        if (msg.value > 0) {
            _transferInETH();
            uint256 _amountIn = msg.value;

            if (_path.length > 1) {
                IERC20(weth).safeTransfer(vault, msg.value);
                _amountIn = _swap(_path, _minOut, address(this));
            }

            uint256 afterFeeAmount = _collectFees(
                msg.sender,
                _path,
                _amountIn,
                _indexToken,
                _isLong,
                _sizeDelta
            );
            IERC20(_path[_path.length - 1]).safeTransfer(vault, afterFeeAmount);
        }

        _increasePosition(
            msg.sender,
            _path[_path.length - 1],
            _indexToken,
            _sizeDelta,
            _isLong,
            _price
        );
    }

    /// @notice decrease a position
    /// @param _collateralToken address of the collateral token
    /// @param _indexToken The address of the token to long or short
    /// @param _collateralDelta collateral delta of the position
    /// @param _sizeDelta size delta of the position
    /// @param _isLong true if the position is long, false if the position is short
    /// @param _receiver address to receive the withdrawn token
    /// @param _price price of the position
    function decreasePosition(
        address _collateralToken,
        address _indexToken,
        uint256 _collateralDelta,
        uint256 _sizeDelta,
        bool _isLong,
        address _receiver,
        uint256 _price
    ) external nonReentrant onlyPartnersOrLegacyMode {
        _decreasePosition(
            msg.sender,
            _collateralToken,
            _indexToken,
            _collateralDelta,
            _sizeDelta,
            _isLong,
            _receiver,
            _price
        );
    }

    /// @notice decrease a position
    /// @param _collateralToken address of the collateral token
    /// @param _indexToken The address of the token to long or short
    /// @param _collateralDelta collateral delta of the position
    /// @param _sizeDelta size delta of the position
    /// @param _isLong true if the position is long, false if the position is short
    /// @param _receiver address to receive the withdrawn ETH
    /// @param _price price of the position
    function decreasePositionETH(
        address _collateralToken,
        address _indexToken,
        uint256 _collateralDelta,
        uint256 _sizeDelta,
        bool _isLong,
        address payable _receiver,
        uint256 _price
    ) external nonReentrant onlyPartnersOrLegacyMode {
        if (_collateralToken != weth) {
            revert InvalidCollateralToken();
        }

        uint256 amountOut = _decreasePosition(
            msg.sender,
            _collateralToken,
            _indexToken,
            _collateralDelta,
            _sizeDelta,
            _isLong,
            address(this),
            _price
        );
        _transferOutETH(amountOut, _receiver);
    }

    /// @notice decrease a position and swap the tokens
    /// @param _path path of the token swap
    /// @param _indexToken address of the token to long or short
    /// @param _collateralDelta collateral delta of the position
    /// @param _sizeDelta size delta of the position
    /// @param _isLong true if the position is long, false if the position is short
    /// @param _receiver address to receive the withdrawn token
    /// @param _price price of the position
    /// @param _minOut minimum amount of token to swap out
    function decreasePositionAndSwap(
        address[] memory _path,
        address _indexToken,
        uint256 _collateralDelta,
        uint256 _sizeDelta,
        bool _isLong,
        address _receiver,
        uint256 _price,
        uint256 _minOut
    ) external nonReentrant onlyPartnersOrLegacyMode {
        if (_path.length != 2) {
            revert InvalidPathLength();
        }

        uint256 amount = _decreasePosition(
            msg.sender,
            _path[0],
            _indexToken,
            _collateralDelta,
            _sizeDelta,
            _isLong,
            address(this),
            _price
        );
        IERC20(_path[0]).safeTransfer(vault, amount);
        _swap(_path, _minOut, _receiver);
    }

    /// @notice decrease a position and swap ETH
    /// @param _path path of the token swap
    /// @param _indexToken address of the token to long or short
    /// @param _collateralDelta collateral delta of the position
    /// @param _sizeDelta size delta of the position
    /// @param _isLong true if the position is long, false if the position is short
    /// @param _receiver address to receive the withdrawn ETH
    /// @param _price price of the position
    /// @param _minOut minimum amount of token to swap out
    function decreasePositionAndSwapETH(
        address[] memory _path,
        address _indexToken,
        uint256 _collateralDelta,
        uint256 _sizeDelta,
        bool _isLong,
        address payable _receiver,
        uint256 _price,
        uint256 _minOut
    ) external nonReentrant onlyPartnersOrLegacyMode {
        if (_path.length != 2) {
            revert InvalidPathLength();
        }
        if (_path[_path.length - 1] != weth) {
            revert InvalidPath(uint8(_path.length - 1));
        }

        uint256 amount = _decreasePosition(
            msg.sender,
            _path[0],
            _indexToken,
            _collateralDelta,
            _sizeDelta,
            _isLong,
            address(this),
            _price
        );
        IERC20(_path[0]).safeTransfer(vault, amount);
        uint256 amountOut = _swap(_path, _minOut, address(this));
        _transferOutETH(amountOut, _receiver);
    }

    /// @notice liquidate a position
    /// @param _collateralToken address of the collateral token
    /// @param _indexToken address of the token to long or short
    /// @param _isLong true if the position is long, false if the position is short
    /// @param _feeReceiver address to receive the fees
    function liquidatePosition(
        address _account,
        address _collateralToken,
        address _indexToken,
        bool _isLong,
        address _feeReceiver
    ) external nonReentrant onlyLiquidator {
        address _vault = vault;
        address timelock = IVault(_vault).owner();

        ITimelock(timelock).enableLeverage(_vault);
        IVault(_vault).liquidatePosition(
            _account,
            _collateralToken,
            _indexToken,
            _isLong,
            _feeReceiver
        );
        ITimelock(timelock).disableLeverage(_vault);
    }

    /// @notice execute a swap order
    /// @param _account address of the account
    /// @param _orderIndex index of the swap order
    /// @param _feeReceiver address to receive the fees
    function executeSwapOrder(
        address _account,
        uint256 _orderIndex,
        address payable _feeReceiver
    ) external onlyOrderKeeper {
        IOrderBook(orderBook).executeSwapOrder(
            _account,
            _orderIndex,
            _feeReceiver
        );
    }

    /// @notice execute an increase order
    /// @param _account address of the account
    /// @param _orderIndex index of the increase order
    /// @param _feeReceiver address to receive the fees
    function executeIncreaseOrder(
        address _account,
        uint256 _orderIndex,
        address payable _feeReceiver
    ) external onlyOrderKeeper {
        uint256 sizeDelta = _validateIncreaseOrder(_account, _orderIndex);

        address _vault = vault;
        address timelock = IVault(_vault).owner();

        ITimelock(timelock).enableLeverage(_vault);
        IOrderBook(orderBook).executeIncreaseOrder(
            _account,
            _orderIndex,
            _feeReceiver
        );
        ITimelock(timelock).disableLeverage(_vault);

        _emitIncreasePositionReferral(_account, sizeDelta);
    }

    /// @notice execute a decrease order
    /// @param _account address of the account
    /// @param _orderIndex index of the decrease order
    /// @param _feeReceiver address to receive the fees
    function executeDecreaseOrder(
        address _account,
        uint256 _orderIndex,
        address payable _feeReceiver
    ) external onlyOrderKeeper {
        address _vault = vault;
        address timelock = IVault(_vault).owner();

        (
            ,
            ,
            ,
            // _collateralToken
            // _collateralDelta
            // _indexToken
            uint256 _sizeDelta, // _isLong // triggerPrice // triggerAboveThreshold // executionFee
            ,
            ,
            ,

        ) = IOrderBook(orderBook).getDecreaseOrder(_account, _orderIndex);

        ITimelock(timelock).enableLeverage(_vault);
        IOrderBook(orderBook).executeDecreaseOrder(
            _account,
            _orderIndex,
            _feeReceiver
        );
        ITimelock(timelock).disableLeverage(_vault);

        _emitDecreasePositionReferral(_account, _sizeDelta);
    }

    function _validateIncreaseOrder(address _account, uint256 _orderIndex)
        internal
        view
        returns (uint256)
    {
        (
            address _purchaseToken,
            uint256 _purchaseTokenAmount,
            address _collateralToken,
            address _indexToken,
            uint256 _sizeDelta,
            bool _isLong, // triggerPrice // triggerAboveThreshold // executionFee
            ,
            ,

        ) = IOrderBook(orderBook).getIncreaseOrder(_account, _orderIndex);

        if (!shouldValidateIncreaseOrder) {
            return _sizeDelta;
        }

        // shorts are okay
        if (!_isLong) {
            return _sizeDelta;
        }

        // if the position size is not increasing, this is a collateral deposit
        if (_sizeDelta == 0) {
            revert LongDeposit();
        }

        IVault _vault = IVault(vault);
        (uint256 size, uint256 collateral, , , , , , ) = _vault.getPosition(
            _account,
            _collateralToken,
            _indexToken,
            _isLong
        );

        // if there is no existing position, do not charge a fee
        if (size == 0) {
            return _sizeDelta;
        }

        uint256 nextSize = size + _sizeDelta;
        uint256 collateralDelta = _vault.tokenToUsdMin(
            _purchaseToken,
            _purchaseTokenAmount
        );
        uint256 nextCollateral = collateral + collateralDelta;

        uint256 prevLeverage = (size * BASIS_POINTS_DIVISOR) / collateral;
        // allow for a maximum of a increasePositionBufferBps decrease since there might be some swap fees taken from the collateral
        uint256 nextLeverageWithBuffer = nextSize *
            BASIS_POINTS_DIVISOR +
            increasePositionBufferBps /
            nextCollateral;

        if (nextLeverageWithBuffer < prevLeverage) {
            revert LongLeverageDecrease();
        }

        return _sizeDelta;
    }
}
