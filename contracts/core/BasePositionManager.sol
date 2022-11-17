// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import "../tokens/interfaces/IWETH.sol";
import "./interfaces/IRouter.sol";
import "./interfaces/IVault.sol";
import "./interfaces/IOrderBook.sol";
import "./interfaces/IBasePositionManager.sol";

import "../peripherals/interfaces/ITimelock.sol";
import "../referrals/interfaces/IReferralStorage.sol";

/// Function can only be called by an admin
error OnlyAdmin();
/// Sender was not `weth`
error InvalidSender();
/// Price is less than the current limit for a long position
error PriceTooLow();
/// Price is greater than the current limit for a short position
error PriceTooHigh();
/// The size delta provided creates a long size greater than the max
error MaxLongsExceeded();
/// The size delta provided creates a short size greater than the max
error MaxShortsExceeded();
/// Path has an incorrect number of elements
error InvalidPathLength();
/// Amount out is less than the minimum out
error InsufficientAmountOut();

/// @title Vaporwave Base Position Manager
contract BasePositionManager is IBasePositionManager, ReentrancyGuard, Ownable {
    using SafeERC20 for IERC20;
    using Address for address payable;

    /// Helper used to avoid truncation errors in basis points calculations
    uint16 public constant BASIS_POINTS_DIVISOR = 10000;

    /// @notice Returns the address of admin
    /// @return The admin address
    address public admin;

    /// @notice Returns the address of the vault
    /// @return The vault address
    address public vault;

    /// @notice Returns the address of router
    /// @return The router address
    address public router;

    /// @notice Returns the WETH token contract address
    /// @return Wrapped Ether (WETH) token address
    address public weth;

    /// @notice Returns the deposit fee
    /// @dev to prevent using the deposit and withdrawal of collateral as a zero fee swap,
    /// there is a small depositFee charged if a collateral deposit results in the decrease
    /// of leverage for an existing position
    /// increasePositionBufferBps allows for a small amount of decrease of leverage
    /// @return The deposit fee
    uint256 public depositFee;

    /// @notice Returns the increase position buffer bps (100)
    /// @return 100
    uint256 public increasePositionBufferBps = 100;

    /// The referral storage address
    address public referralStorage;

    /// Mapping of token fee reserves
    mapping(address => uint256) public feeReserves;

    /// @notice Mapping of max global long sizes by token
    /// @return The max global long size for a token
    mapping(address => uint256) public maxGlobalLongSizes;

    /// @notice Mapping of max global short sizes by token
    /// @return The max global short size for a token
    mapping(address => uint256) public maxGlobalShortSizes;

    modifier onlyAdmin() {
        if (msg.sender != admin) {
            revert OnlyAdmin();
        }
        _;
    }

    constructor(
        address _vault,
        address _router,
        address _weth,
        uint256 _depositFee
    ) {
        vault = _vault;
        router = _router;
        weth = _weth;
        depositFee = _depositFee;

        admin = msg.sender;
    }

    receive() external payable {
        if (msg.sender != weth) {
            revert InvalidSender();
        }
    }

    /// @notice Set the admin address
    /// @param _admin The new admin address
    function setAdmin(address _admin) external onlyOwner {
        admin = _admin;
        emit SetAdmin(_admin);
    }

    /// @notice Set the deposit fee
    /// @param _depositFee The new deposit fee
    function setDepositFee(uint256 _depositFee) external onlyAdmin {
        depositFee = _depositFee;
        emit SetDepositFee(_depositFee);
    }

    /// @notice Set the increase position buffer basis points
    /// @param _increasePositionBufferBps The new increase position buffer basis points
    function setIncreasePositionBufferBps(uint256 _increasePositionBufferBps)
        external
        onlyAdmin
    {
        increasePositionBufferBps = _increasePositionBufferBps;
        emit SetIncreasePositionBufferBps(_increasePositionBufferBps);
    }

    /// @notice Set the referral storage address
    /// @param _referralStorage The new referral storage address
    function setReferralStorage(address _referralStorage) external onlyAdmin {
        referralStorage = _referralStorage;
        emit SetReferralStorage(_referralStorage);
    }

    /// @notice Set the max global sizes
    /// @param _tokens The array of tokens
    /// @param _longSizes The array of corresponding max global long sizes
    /// @param _shortSizes The array of corresponding max global short sizes
    function setMaxGlobalSizes(
        address[] memory _tokens,
        uint256[] memory _longSizes,
        uint256[] memory _shortSizes
    ) external onlyAdmin {
        for (uint256 i = 0; i < _tokens.length; i++) {
            address token = _tokens[i];
            maxGlobalLongSizes[token] = _longSizes[i];
            maxGlobalShortSizes[token] = _shortSizes[i];
        }

        emit SetMaxGlobalSizes(_tokens, _longSizes, _shortSizes);
    }

    /// @notice Withdraw fees from the contract
    /// @param _token The token to withdraw
    /// @param _receiver The receiver of the fees
    function withdrawFees(address _token, address _receiver)
        external
        onlyAdmin
    {
        uint256 amount = feeReserves[_token];
        if (amount == 0) {
            return;
        }

        feeReserves[_token] = 0;
        IERC20(_token).safeTransfer(_receiver, amount);

        emit WithdrawFees(_token, _receiver, amount);
    }

    /// @notice Make a token approval call
    /// @param _token The token to approve
    /// @param _spender The spender of the token
    /// @param _amount The amount of token allowance to grant
    function approve(
        address _token,
        address _spender,
        uint256 _amount
    ) external onlyOwner {
        IERC20(_token).approve(_spender, _amount);
    }

    /// @notice Transfer ETH
    /// @param _receiver The receiver of the ETH
    /// @param _amount The amount of ETH to transfer
    function sendValue(address payable _receiver, uint256 _amount)
        external
        onlyOwner
    {
        _receiver.sendValue(_amount);
    }

    function _increasePosition(
        address _account,
        address _collateralToken,
        address _indexToken,
        uint256 _sizeDelta,
        bool _isLong,
        uint256 _price
    ) internal {
        address _vault = vault;

        if (_isLong) {
            if (IVault(_vault).getMaxPrice(_indexToken) > _price) {
                revert PriceTooLow();
            }
        } else {
            if (IVault(_vault).getMinPrice(_indexToken) < _price) {
                revert PriceTooHigh();
            }
        }

        if (_isLong) {
            uint256 maxGlobalLongSize = maxGlobalLongSizes[_indexToken];
            if (
                maxGlobalLongSize > 0 &&
                IVault(_vault).guaranteedUsd(_indexToken) + _sizeDelta >
                maxGlobalLongSize
            ) {
                revert MaxLongsExceeded();
            }
        } else {
            uint256 maxGlobalShortSize = maxGlobalShortSizes[_indexToken];
            if (
                maxGlobalShortSize > 0 &&
                IVault(_vault).globalShortSizes(_indexToken) + _sizeDelta >
                maxGlobalShortSize
            ) {
                revert MaxShortsExceeded();
            }
        }

        address timelock = IVault(_vault).owner();

        ITimelock(timelock).enableLeverage(_vault);
        IRouter(router).pluginIncreasePosition(
            _account,
            _collateralToken,
            _indexToken,
            _sizeDelta,
            _isLong
        );
        ITimelock(timelock).disableLeverage(_vault);

        _emitIncreasePositionReferral(_account, _sizeDelta);
    }

    function _decreasePosition(
        address _account,
        address _collateralToken,
        address _indexToken,
        uint256 _collateralDelta,
        uint256 _sizeDelta,
        bool _isLong,
        address _receiver,
        uint256 _price
    ) internal returns (uint256) {
        address _vault = vault;

        if (_isLong) {
            if (IVault(_vault).getMaxPrice(_indexToken) > _price) {
                revert PriceTooLow();
            }
        } else {
            if (IVault(_vault).getMinPrice(_indexToken) < _price) {
                revert PriceTooHigh();
            }
        }

        address timelock = IVault(_vault).owner();

        ITimelock(timelock).enableLeverage(_vault);
        uint256 amountOut = IRouter(router).pluginDecreasePosition(
            _account,
            _collateralToken,
            _indexToken,
            _collateralDelta,
            _sizeDelta,
            _isLong,
            _receiver
        );
        ITimelock(timelock).disableLeverage(_vault);

        _emitDecreasePositionReferral(_account, _sizeDelta);

        return amountOut;
    }

    function _emitIncreasePositionReferral(address _account, uint256 _sizeDelta)
        internal
    {
        address _referralStorage = referralStorage;
        if (_referralStorage == address(0)) {
            return;
        }

        (bytes32 referralCode, address referrer) = IReferralStorage(
            _referralStorage
        ).getTraderReferralInfo(_account);
        emit IncreasePositionReferral(
            _account,
            _sizeDelta,
            IVault(vault).marginFeeBasisPoints(),
            referralCode,
            referrer
        );
    }

    function _emitDecreasePositionReferral(address _account, uint256 _sizeDelta)
        internal
    {
        address _referralStorage = referralStorage;
        if (_referralStorage == address(0)) {
            return;
        }

        (bytes32 referralCode, address referrer) = IReferralStorage(
            _referralStorage
        ).getTraderReferralInfo(_account);

        if (referralCode == bytes32(0)) {
            return;
        }

        emit DecreasePositionReferral(
            _account,
            _sizeDelta,
            IVault(vault).marginFeeBasisPoints(),
            referralCode,
            referrer
        );
    }

    function _swap(
        address[] memory _path,
        uint256 _minOut,
        address _receiver
    ) internal returns (uint256) {
        if (_path.length == 2) {
            return _vaultSwap(_path[0], _path[1], _minOut, _receiver);
        }
        revert InvalidPathLength();
    }

    function _vaultSwap(
        address _tokenIn,
        address _tokenOut,
        uint256 _minOut,
        address _receiver
    ) internal returns (uint256) {
        uint256 amountOut = IVault(vault).swap(_tokenIn, _tokenOut, _receiver);
        if (amountOut < _minOut) {
            revert InsufficientAmountOut();
        }
        return amountOut;
    }

    function _transferInETH() internal {
        if (msg.value != 0) {
            IWETH(weth).deposit{value: msg.value}();
        }
    }

    function _transferOutETH(uint256 _amountOut, address payable _receiver)
        internal
    {
        IWETH(weth).withdraw(_amountOut);
        _receiver.sendValue(_amountOut);
    }

    function _transferOutETHWithGasLimit(
        uint256 _amountOut,
        address payable _receiver
    ) internal {
        IWETH(weth).withdraw(_amountOut);
        _receiver.transfer(_amountOut);
    }

    function _collectFees(
        address _account,
        address[] memory _path,
        uint256 _amountIn,
        address _indexToken,
        bool _isLong,
        uint256 _sizeDelta
    ) internal returns (uint256) {
        bool shouldDeductFee = _shouldDeductFee(
            _account,
            _path,
            _amountIn,
            _indexToken,
            _isLong,
            _sizeDelta
        );

        if (shouldDeductFee) {
            uint256 afterFeeAmount = (_amountIn *
                (BASIS_POINTS_DIVISOR - depositFee)) / BASIS_POINTS_DIVISOR;
            uint256 feeAmount = _amountIn - afterFeeAmount;
            address feeToken = _path[_path.length - 1];
            feeReserves[feeToken] = feeReserves[feeToken] + feeAmount;
            return afterFeeAmount;
        }

        return _amountIn;
    }

    function _shouldDeductFee(
        address _account,
        address[] memory _path,
        uint256 _amountIn,
        address _indexToken,
        bool _isLong,
        uint256 _sizeDelta
    ) internal view returns (bool) {
        // if the position is a short, do not charge a fee
        if (!_isLong) {
            return false;
        }

        // if the position size is not increasing, this is a collateral deposit
        if (_sizeDelta == 0) {
            return true;
        }

        address collateralToken = _path[_path.length - 1];

        IVault _vault = IVault(vault);
        (uint256 size, uint256 collateral, , , , , , ) = _vault.getPosition(
            _account,
            collateralToken,
            _indexToken,
            _isLong
        );

        // if there is no existing position, do not charge a fee
        if (size == 0) {
            return false;
        }

        uint256 nextSize = size + _sizeDelta;
        uint256 collateralDelta = _vault.tokenToUsdMin(
            collateralToken,
            _amountIn
        );
        uint256 nextCollateral = collateral + collateralDelta;

        uint256 prevLeverage = (size * BASIS_POINTS_DIVISOR) / collateral;
        // allow for a maximum of a increasePositionBufferBps decrease since there might be some swap fees taken from the collateral
        uint256 nextLeverage = (nextSize *
            (BASIS_POINTS_DIVISOR + increasePositionBufferBps)) /
            nextCollateral;

        // deduct a fee if the leverage is decreased
        return nextLeverage < prevLeverage;
    }
}
