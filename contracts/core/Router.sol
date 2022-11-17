// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import "../tokens/interfaces/IWETH.sol";
import "./interfaces/IVault.sol";
import "./interfaces/IRouter.sol";

/// Sender must be `weth`
error InvalidSender();
/// Invalid token swap path
error InvalidPath();
/// Price is less than the limit for a long position
error PriceTooLow();
/// Price is greater than the limit for a short position
error PriceTooHigh();
/// Sender is not a plugin
error InvalidPlugin();
/// sender is not approved as a plugin
error UnapprovedPlugin();
/// Amount out is less than the minimum out
error InsufficientAmountOut();

/// @title Vaporwave Router
contract Router is Ownable, IRouter {
    using SafeERC20 for IERC20;
    using Address for address payable;

    /// Wrapped Ether (WETH) token
    address public weth; // wrapped ETH
    /// Vault address
    address public vault;

    /// Mapping of plugin addresses
    mapping(address => bool) public plugins;
    /// Mapping of accounts to their approved plugins
    mapping(address => mapping(address => bool)) public approvedPlugins;

    event Swap(
        address account,
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 amountOut
    );

    constructor(address _vault, address _weth) {
        vault = _vault;
        weth = _weth;
    }

    receive() external payable {
        if (msg.sender != weth) {
            revert InvalidSender();
        }
    }

    /// @notice Add `_plugin` as a plugin to the router
    /// @param _plugin The address of the plugin to add
    function addPlugin(address _plugin) external override onlyOwner {
        plugins[_plugin] = true;
    }

    /// @notice Remove `_plugin` as a plugin from the router
    /// @param _plugin The address of the plugin to remove
    function removePlugin(address _plugin) external onlyOwner {
        plugins[_plugin] = false;
    }

    /// @notice Approve `_plugin` as a plugin
    /// @param _plugin The address of the plugin to approve
    function approvePlugin(address _plugin) external {
        approvedPlugins[msg.sender][_plugin] = true;
    }

    /// @notice Deny `_plugin` as a plugin
    /// @param _plugin The address of the plugin to deny
    function denyPlugin(address _plugin) external {
        approvedPlugins[msg.sender][_plugin] = false;
    }

    /// @notice Transfer `_amount` of `_token` tokens from `_account to `_receiver`
    /// @param _token The token to transfer
    /// @param _account The address of the account to transfer from
    /// @param _receiver The address of the account to transfer to
    /// @param _amount The amount of tokens to transfer
    function pluginTransfer(
        address _token,
        address _account,
        address _receiver,
        uint256 _amount
    ) external override {
        _validatePlugin(_account);
        IERC20(_token).safeTransferFrom(_account, _receiver, _amount);
    }

    /// @notice Increase the position of `_account` with `_collateralToken` collateral and `_indexToken` index
    /// @param _account The address of the account to increase the position of
    /// @param _collateralToken The token to use as collateral
    /// @param _indexToken The address of the token to long or short
    /// @param _sizeDelta The size delta
    /// @param _isLong True if the position is long, false if it is short
    function pluginIncreasePosition(
        address _account,
        address _collateralToken,
        address _indexToken,
        uint256 _sizeDelta,
        bool _isLong
    ) external override {
        _validatePlugin(_account);
        IVault(vault).increasePosition(
            _account,
            _collateralToken,
            _indexToken,
            _sizeDelta,
            _isLong
        );
    }

    /// @notice Decrease the position of `_account` with `_collateralToken` collateral and `_indexToken` index
    /// @param _account The address of the account to decrease the position of
    /// @param _collateralToken The token to use as collateral
    /// @param _indexToken The address of the token to long or short
    /// @param _collateralDelta The collateral delta
    /// @param _sizeDelta The size delta
    /// @param _isLong True if the position is long, false if it is short
    /// @param _receiver The address of the account to receive the collateral
    function pluginDecreasePosition(
        address _account,
        address _collateralToken,
        address _indexToken,
        uint256 _collateralDelta,
        uint256 _sizeDelta,
        bool _isLong,
        address _receiver
    ) external override returns (uint256) {
        _validatePlugin(_account);
        return
            IVault(vault).decreasePosition(
                _account,
                _collateralToken,
                _indexToken,
                _collateralDelta,
                _sizeDelta,
                _isLong,
                _receiver
            );
    }

    /// @notice Make a direct token deposit to the vault pool
    /// @param _token The token to deposit
    /// @param _amount The amount of tokens to deposit
    function directPoolDeposit(address _token, uint256 _amount) external {
        IERC20(_token).safeTransferFrom(_sender(), vault, _amount);
        IVault(vault).directPoolDeposit(_token);
    }

    /// @notice Make a swap from ETH to a token
    /// @param _path The path of the token swap
    /// @param _minOut The minimum amount of tokens to swap out
    /// @param _receiver The address of the account to receive the tokens
    function swapETHToTokens(
        address[] memory _path,
        uint256 _minOut,
        address _receiver
    ) external payable {
        if (_path[0] != weth) {
            revert InvalidPath();
        }
        _transferETHToVault();
        uint256 amountOut = _swap(_path, _minOut, _receiver);
        emit Swap(
            msg.sender,
            _path[0],
            _path[_path.length - 1],
            msg.value,
            amountOut
        );
    }

    /// @notice Make a swap from a token to ETH
    /// @param _path The path of the token swap
    /// @param _amountIn The amount of tokens to swap in
    /// @param _minOut The minimum amount of ETH to swap out
    /// @param _receiver The address of the account to receive the ETH
    function swapTokensToETH(
        address[] memory _path,
        uint256 _amountIn,
        uint256 _minOut,
        address payable _receiver
    ) external {
        if (_path[0] != weth) {
            revert InvalidPath();
        }
        IERC20(_path[0]).safeTransferFrom(_sender(), vault, _amountIn);
        uint256 amountOut = _swap(_path, _minOut, address(this));
        _transferOutETH(amountOut, _receiver);
        emit Swap(
            msg.sender,
            _path[0],
            _path[_path.length - 1],
            _amountIn,
            amountOut
        );
    }

    /// @notice Increase a position
    /// @param _path The path of the token swap
    /// @param _indexToken The address of the token to long or short
    /// @param _amountIn The amount of tokens to swap in
    /// @param _minOut The minimum amount of tokens to swap out
    /// @param _sizeDelta The size delta
    /// @param _isLong True if the position is long, false if it is short
    /// @param _price The price of the position
    function increasePosition(
        address[] memory _path,
        address _indexToken,
        uint256 _amountIn,
        uint256 _minOut,
        uint256 _sizeDelta,
        bool _isLong,
        uint256 _price
    ) external {
        if (_amountIn > 0) {
            IERC20(_path[0]).safeTransferFrom(_sender(), vault, _amountIn);
        }
        if (_path.length > 1 && _amountIn > 0) {
            uint256 amountOut = _swap(_path, _minOut, address(this));
            IERC20(_path[_path.length - 1]).safeTransfer(vault, amountOut);
        }
        _increasePosition(
            _path[_path.length - 1],
            _indexToken,
            _sizeDelta,
            _isLong,
            _price
        );
    }

    /// @notice Increase a position with ETH
    /// @param _path The path of the token swap
    /// @param _indexToken The address of the token to long or short
    /// @param _minOut The minimum amount of tokens to swap out
    /// @param _sizeDelta The size delta
    /// @param _isLong True if the position is long, false if it is short
    /// @param _price The price of the position
    function increasePositionETH(
        address[] memory _path,
        address _indexToken,
        uint256 _minOut,
        uint256 _sizeDelta,
        bool _isLong,
        uint256 _price
    ) external payable {
        if (_path[0] != weth) {
            revert InvalidPath();
        }
        if (msg.value > 0) {
            _transferETHToVault();
        }
        if (_path.length > 1 && msg.value > 0) {
            uint256 amountOut = _swap(_path, _minOut, address(this));
            IERC20(_path[_path.length - 1]).safeTransfer(vault, amountOut);
        }
        _increasePosition(
            _path[_path.length - 1],
            _indexToken,
            _sizeDelta,
            _isLong,
            _price
        );
    }

    /// @notice Decrease a position
    /// @param _collateralToken The token used as collateral
    /// @param _indexToken The address of the token to long or short
    /// @param _collateralDelta The collateral delta
    /// @param _sizeDelta The size delta
    /// @param _isLong True if the position is long, false if it is short
    /// @param _receiver The address of the account to receive the tokens
    /// @param _price The price of the position
    function decreasePosition(
        address _collateralToken,
        address _indexToken,
        uint256 _collateralDelta,
        uint256 _sizeDelta,
        bool _isLong,
        address _receiver,
        uint256 _price
    ) external {
        _decreasePosition(
            _collateralToken,
            _indexToken,
            _collateralDelta,
            _sizeDelta,
            _isLong,
            _receiver,
            _price
        );
    }

    /// @notice Decrease a position with ETH
    /// @param _collateralToken The token used as collateral
    /// @param _indexToken The address of the token to long or short
    /// @param _collateralDelta The collateral delta
    /// @param _isLong True if the position is long, false if it is short
    /// @param _receiver The address of the account to receive the tokens
    /// @param _price The price of the position
    function decreasePositionETH(
        address _collateralToken,
        address _indexToken,
        uint256 _collateralDelta,
        uint256 _sizeDelta,
        bool _isLong,
        address payable _receiver,
        uint256 _price
    ) external {
        uint256 amountOut = _decreasePosition(
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

    /// @notice Decrease a position and swap the collateral token
    /// @param _path The path of the token swap
    /// @param _indexToken The address of the token to long or short
    /// @param _collateralDelta The collateral delta
    /// @param _sizeDelta The size delta
    /// @param _isLong True if the position is long, false if it is short
    /// @param _receiver The address of the account to receive the tokens
    /// @param _price The price of the position
    /// @param _minOut The minimum amount of tokens to swap out
    function decreasePositionAndSwap(
        address[] memory _path,
        address _indexToken,
        uint256 _collateralDelta,
        uint256 _sizeDelta,
        bool _isLong,
        address _receiver,
        uint256 _price,
        uint256 _minOut
    ) external {
        uint256 amount = _decreasePosition(
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

    /// @notice Decrease a position and swap the ETH
    /// @param _path The path of the token swap
    /// @param _indexToken The address of the token to long or short
    /// @param _collateralDelta The collateral delta
    /// @param _sizeDelta The size delta
    /// @param _isLong True if the position is long, false if it is short
    /// @param _receiver The address of the account to receive the tokens
    /// @param _price The price of the position
    /// @param _minOut The minimum amount of tokens to swap out
    function decreasePositionAndSwapETH(
        address[] memory _path,
        address _indexToken,
        uint256 _collateralDelta,
        uint256 _sizeDelta,
        bool _isLong,
        address payable _receiver,
        uint256 _price,
        uint256 _minOut
    ) external {
        if (_path[0] != weth) {
            revert InvalidPath();
        }
        uint256 amount = _decreasePosition(
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

    /// @notice Make a token swap
    /// @param _path The path of the token swap
    /// @param _amountIn The amount of tokens to swap in
    /// @param _minOut The minimum amount of tokens to swap out
    /// @param _receiver The address of the account to receive the tokens
    function swap(
        address[] memory _path,
        uint256 _amountIn,
        uint256 _minOut,
        address _receiver
    ) public override {
        IERC20(_path[0]).safeTransferFrom(_sender(), vault, _amountIn);
        uint256 amountOut = _swap(_path, _minOut, _receiver);
        emit Swap(
            msg.sender,
            _path[0],
            _path[_path.length - 1],
            _amountIn,
            amountOut
        );
    }

    function _increasePosition(
        address _collateralToken,
        address _indexToken,
        uint256 _sizeDelta,
        bool _isLong,
        uint256 _price
    ) private {
        if (_isLong) {
            if (IVault(vault).getMaxPrice(_indexToken) > _price) {
                revert PriceTooLow();
            }
        } else {
            if (IVault(vault).getMinPrice(_indexToken) < _price) {
                revert PriceTooHigh();
            }
        }

        IVault(vault).increasePosition(
            _sender(),
            _collateralToken,
            _indexToken,
            _sizeDelta,
            _isLong
        );
    }

    function _decreasePosition(
        address _collateralToken,
        address _indexToken,
        uint256 _collateralDelta,
        uint256 _sizeDelta,
        bool _isLong,
        address _receiver,
        uint256 _price
    ) private returns (uint256) {
        if (_isLong) {
            if (IVault(vault).getMinPrice(_indexToken) < _price) {
                revert PriceTooHigh();
            }
        } else {
            if (IVault(vault).getMaxPrice(_indexToken) > _price) {
                revert PriceTooLow();
            }
        }

        return
            IVault(vault).decreasePosition(
                _sender(),
                _collateralToken,
                _indexToken,
                _collateralDelta,
                _sizeDelta,
                _isLong,
                _receiver
            );
    }

    function _transferETHToVault() private {
        IWETH(weth).deposit{value: msg.value}();
        IERC20(weth).safeTransfer(vault, msg.value);
    }

    function _transferOutETH(uint256 _amountOut, address payable _receiver)
        private
    {
        IWETH(weth).withdraw(_amountOut);
        _receiver.sendValue(_amountOut);
    }

    function _swap(
        address[] memory _path,
        uint256 _minOut,
        address _receiver
    ) private returns (uint256) {
        if (_path.length == 2) {
            return _vaultSwap(_path[0], _path[1], _minOut, _receiver);
        }
        if (_path.length == 3) {
            uint256 midOut = _vaultSwap(_path[0], _path[1], 0, address(this));
            IERC20(_path[1]).safeTransfer(vault, midOut);
            return _vaultSwap(_path[1], _path[2], _minOut, _receiver);
        }

        revert InvalidPath();
    }

    function _vaultSwap(
        address _tokenIn,
        address _tokenOut,
        uint256 _minOut,
        address _receiver
    ) private returns (uint256) {
        uint256 amountOut = IVault(vault).swap(_tokenIn, _tokenOut, _receiver);

        if (amountOut < _minOut) {
            revert InsufficientAmountOut();
        }
        return amountOut;
    }

    function _sender() private view returns (address) {
        return msg.sender;
    }

    function _validatePlugin(address _account) private view {
        if (!plugins[msg.sender]) {
            revert InvalidPlugin();
        }
        if (!approvedPlugins[_account][msg.sender]) {
            revert UnapprovedPlugin();
        }
    }
}
