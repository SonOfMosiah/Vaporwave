// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import "./interfaces/IVault.sol";
import "./interfaces/IVlpManager.sol";
import "../tokens/interfaces/IMintable.sol";

/// Caller is not a valid handler
error InvalidHandler();
/// Cooldown duration greater than the max allowed
error InvalidCooldownDuration();
/// The contract is in private mode
error PrivateMode();
/// Amount must be greater than 0
error InvalidAmount();
/// Amount out must be greater than the minimum out
error InsufficientOutput();
/// Must wait the cooldown duration
error Cooldown();

/// @title Vaporwave VLP Manager
contract VlpManager is ReentrancyGuard, Ownable, IVlpManager {
    using SafeERC20 for IERC20;

    uint8 public constant USD_DECIMALS = 30;
    uint32 public constant MAX_COOLDOWN_DURATION = 48 hours; // 172800 seconds
    /// Helper to avoid truncation errors in price calculations
    uint128 public constant PRICE_PRECISION = 1e30;

    /// The vault address
    IVault public immutable vault;
    /// VWAVE LP token address
    address public immutable vlp;

    uint256 public override cooldownDuration;
    /// Mapping of addresses to the time they last added liquidity
    mapping(address => uint256) public override lastAddedAt;

    uint256 public aumAddition;
    uint256 public aumDeduction;

    bool public inPrivateMode;
    /// Mapping of handler addresses
    mapping(address => bool) public isHandler;

    /// @notice Emitted when liquidity is added
    event AddLiquidity(
        address account,
        address token,
        uint256 amount,
        uint256 aumInUsd,
        uint256 vlpSupply,
        uint256 usdAmount,
        uint256 mintAmount
    );

    /// @notice Emitted when liquidity is removed
    event RemoveLiquidity(
        address account,
        address token,
        uint256 vlpAmount,
        uint256 aumInUsd,
        uint256 vlpSupply,
        uint256 usdAmount,
        uint256 amountOut
    );

    constructor(
        address _vault,
        address _vlp,
        uint256 _cooldownDuration
    ) {
        vault = IVault(_vault);
        vlp = _vlp;
        cooldownDuration = _cooldownDuration;
    }

    /// @notice Set the inPrivateMode flag
    /// @param _inPrivateMode True if the VLP Manager is in private mode, false otherwise
    function setInPrivateMode(bool _inPrivateMode) external onlyOwner {
        inPrivateMode = _inPrivateMode;
    }

    /// @notice Set the address of a handler
    /// @param _handler Address of the handler to set
    /// @param _isActive True if the address is a handler, false otherwise
    function setHandler(address _handler, bool _isActive) external onlyOwner {
        isHandler[_handler] = _isActive;
    }

    /// @notice Set the cooldown duration
    /// @param _cooldownDuration Cooldown duration in seconds
    function setCooldownDuration(uint256 _cooldownDuration) external onlyOwner {
        if (_cooldownDuration > MAX_COOLDOWN_DURATION) {
            revert InvalidCooldownDuration();
        }
        cooldownDuration = _cooldownDuration;
    }

    /// @notice Set the Assets Under Management (AUM) adjustment
    /// @param _aumAddition AUM addition
    /// @param _aumDeduction AUM deduction
    function setAumAdjustment(uint256 _aumAddition, uint256 _aumDeduction)
        external
        onlyOwner
    {
        aumAddition = _aumAddition;
        aumDeduction = _aumDeduction;
    }

    /// @notice Add liquidity to the VLP
    /// @param _token Address of the token to add liquidity to
    /// @param _amount Amount of tokens to add to the VLP
    /// @param _minUsd Minimum amount in USD to add to the VLP
    /// @param _minVlp Minimum amount of VLP to add
    function addLiquidity(
        address _token,
        uint256 _amount,
        uint256 _minUsd,
        uint256 _minVlp
    ) external override nonReentrant returns (uint256) {
        if (inPrivateMode) {
            revert PrivateMode();
        }
        return
            _addLiquidity(
                msg.sender,
                msg.sender,
                _token,
                _amount,
                _minUsd,
                _minVlp
            );
    }

    /// @notice Add liquidity for `_account`
    /// @param _fundingAccount Address of the funding account
    /// @param _account Address of the liquidity account
    /// @param _token Address of the token to add liquidity to
    /// @param _amount Amount of tokens to add to the VLP
    /// @param _minUsd Minimum amount in USD to add to the VLP
    /// @param _minVlp Minimum amount of VLP to add
    function addLiquidityForAccount(
        address _fundingAccount,
        address _account,
        address _token,
        uint256 _amount,
        uint256 _minUsd,
        uint256 _minVlp
    ) external override nonReentrant returns (uint256) {
        _validateHandler();
        return
            _addLiquidity(
                _fundingAccount,
                _account,
                _token,
                _amount,
                _minUsd,
                _minVlp
            );
    }

    /// @notice Remove liquidity from the VLP
    /// @param _tokenOut Address of the token to remove
    /// @param _vlpAmount Amount of VLP to remove
    /// @param _minOut Minimum amount of tokens to remove from the VLP
    /// @param _receiver Address to receive the withdrawn tokens
    function removeLiquidity(
        address _tokenOut,
        uint256 _vlpAmount,
        uint256 _minOut,
        address _receiver
    ) external override nonReentrant returns (uint256) {
        if (inPrivateMode) {
            revert PrivateMode();
        }
        return
            _removeLiquidity(
                msg.sender,
                _tokenOut,
                _vlpAmount,
                _minOut,
                _receiver
            );
    }

    /// @notice Remove liquidity for a third-party account
    /// @param _account Address of the liquidity account
    /// @param _tokenOut Addrss of the token to remove
    /// @param _vlpAmount Amount of VLP to remove
    /// @param _minOut Minimum amount of tokens to remove from the VLP
    /// @param _receiver Address to receive the withdrawn tokens
    function removeLiquidityForAccount(
        address _account,
        address _tokenOut,
        uint256 _vlpAmount,
        uint256 _minOut,
        address _receiver
    ) external override nonReentrant returns (uint256) {
        _validateHandler();
        return
            _removeLiquidity(
                _account,
                _tokenOut,
                _vlpAmount,
                _minOut,
                _receiver
            );
    }

    /// @notice Get assets under management (AUM)
    /// @return Array with 2 values, min AUM and max AUm
    function getAums() public view returns (uint256[] memory) {
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = getAum(true);
        amounts[1] = getAum(false);
        return amounts;
    }

    /// @notice Get Assets Under Management(AUM)
    /// @param maximise True if the maximum AUM should be returned, false otherwise
    /// @return AUM
    function getAum(bool maximise) public view returns (uint256) {
        uint256 length = vault.allAllowlistedTokensLength();
        uint256 aum = aumAddition;

        for (uint256 i = 0; i < length; i++) {
            address token = vault.allAllowlistedTokens(i);
            bool isAllowlisted = vault.allowlistedTokens(token);

            if (!isAllowlisted) {
                continue;
            }

            uint256 tokenAum = getTokenAum(token, maximise);
            aum += tokenAum;
        }

        return aumDeduction > aum ? 0 : aum - aumDeduction;
    }

    // returns 30 decimals
    function getTokenAum(address _token, bool _maximise)
        public
        view
        override
        returns (uint256)
    {
        bool isAllowlisted = vault.allowlistedTokens(_token);

        if (!isAllowlisted) {
            return 0;
        }

        uint256 price = _maximise
            ? vault.getMaxPrice(_token)
            : vault.getMinPrice(_token);
        uint256 poolAmount = vault.poolAmounts(_token);
        uint256 decimals = vault.tokenDecimals(_token);
        uint256 tokenAum;
        uint256 shortProfits;

        if (vault.stableTokens(_token)) {
            tokenAum += ((poolAmount * price) / (10**decimals));
        } else {
            uint256 size = vault.globalShortSizes(_token);
            if (size > 0) {
                uint256 averagePrice = vault.globalShortAveragePrices(_token);
                uint256 priceDelta = averagePrice > price
                    ? averagePrice - price
                    : price - averagePrice;
                uint256 delta = (size * priceDelta) / averagePrice;
                if (price > averagePrice) {
                    tokenAum += delta;
                } else {
                    shortProfits += delta;
                }
            }
            tokenAum += vault.guaranteedUsd(_token);

            uint256 reservedAmount = vault.reservedAmounts(_token);
            tokenAum += (poolAmount -
                (reservedAmount * price) /
                (10**decimals));
        }

        tokenAum = shortProfits > tokenAum ? 0 : tokenAum - shortProfits;
        return tokenAum;
    }

    function _addLiquidity(
        address _fundingAccount,
        address _account,
        address _token,
        uint256 _amount,
        uint256 _minUsd,
        uint256 _minVlp
    ) private returns (uint256) {
        if (_amount == 0) {
            revert InvalidAmount();
        }

        // calculate aum before buyUSD
        uint256 aumInUsd = getAum(true);
        uint256 vlpSupply = IERC20(vlp).totalSupply();

        IERC20(_token).safeTransferFrom(
            _fundingAccount,
            address(vault),
            _amount
        );
        uint256 usdAmount = vault.buy(_token);
        if (usdAmount < _minUsd) {
            revert InsufficientOutput();
        }

        uint256 decimals = IERC20Metadata(vlp).decimals();
        uint256 mintAmount = aumInUsd == 0
            ? (usdAmount * (10**decimals)) / (10**USD_DECIMALS)
            : (usdAmount * vlpSupply) / aumInUsd;
        if (mintAmount < _minVlp) {
            revert InsufficientOutput();
        }

        IMintable(vlp).mint(_account, mintAmount);
        // solhint-disable-next-line not-rely-on-time
        lastAddedAt[_account] = block.timestamp;

        emit AddLiquidity(
            _account,
            _token,
            _amount,
            aumInUsd,
            vlpSupply,
            usdAmount,
            mintAmount
        );

        return mintAmount;
    }

    function _removeLiquidity(
        address _account,
        address _tokenOut,
        uint256 _vlpAmount,
        uint256 _minOut,
        address _receiver
    ) private returns (uint256) {
        if (_vlpAmount == 0) {
            revert InvalidAmount();
        }
        // solhint-disable-next-line not-rely-on-time
        if (lastAddedAt[_account] + cooldownDuration <= block.timestamp) {
            revert Cooldown();
        }

        // calculate aum before sell
        uint256 aumInUsd = getAum(false);
        uint256 vlpSupply = IERC20(vlp).totalSupply();

        uint256 usdAmount = (_vlpAmount * aumInUsd) / vlpSupply;

        IMintable(vlp).burn(_account, _vlpAmount);

        uint256 amountOut = vault.sell(_tokenOut, _receiver, usdAmount);
        if (amountOut < _minOut) {
            revert InsufficientOutput();
        }

        emit RemoveLiquidity(
            _account,
            _tokenOut,
            _vlpAmount,
            aumInUsd,
            vlpSupply,
            usdAmount,
            amountOut
        );

        return amountOut;
    }

    function _validateHandler() private view {
        if (!isHandler[msg.sender]) {
            revert InvalidHandler();
        }
    }
}
