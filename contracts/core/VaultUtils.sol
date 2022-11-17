// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import "./interfaces/IVlpManager.sol";
import "./interfaces/IVault.sol";
import "./interfaces/IVaultUtils.sol";

/// The losses exceed the collateral amount
error LossesExceedCollateral();
/// The fees exceed the collateral amount
error FeesExceedCollateral();
/// Max leverage amount is exceeded
error MaxLeverageExceeded();

/// @title Vaporwave Vault Utils
/// @dev A utility contract to validate requests and calculate fees
contract VaultUtils is IVaultUtils, Ownable {
    struct Position {
        uint256 size;
        uint256 collateral;
        uint256 averagePrice;
        uint256 entryFundingRate;
        uint256 reserveAmount;
        int256 realisedPnl;
        uint256 lastIncreasedTime;
    }

    /// The vault address
    IVault public immutable vault;
    /// The vlp manager address
    IVlpManager public immutable vlpManager;

    /// Helper to avoid truncation errors in basis points calculations
    uint16 public constant BASIS_POINTS_DIVISOR = 10000;
    /// Helper to avoid truncation errors in funding rate calculations
    uint32 public constant FUNDING_RATE_PRECISION = 1e6;

    constructor(IVault _vault, IVlpManager _vlpManager) {
        vault = _vault;
        vlpManager = _vlpManager;
    }

    /// @dev Function does nothing, included to satisfy the IVaultUtils interface
    function validateIncreasePosition(
        address, /* _account */
        address, /* _collateralToken */
        address, /* _indexToken */
        uint256, /* _sizeDelta */
        bool /* _isLong */ // solhint-disable-next-line no-empty-blocks
    ) external view override {
        // no additional validations
    }

    /// @dev Function does nothing, included to satisfy the IVaultUtils interface
    function validateDecreasePosition(
        address, /* _account */
        address, /* _collateralToken */
        address, /* _indexToken */
        uint256, /* _collateralDelta */
        uint256, /* _sizeDelta */
        bool, /* _isLong */
        address /* _receiver */ // solhint-disable-next-line no-empty-blocks
    ) external view override {
        // no additional validations
    }

    /// @notice Validates a liquidation request, will revert if the request is invalid
    /// @param _account The account to liquidate
    /// @param _collateralToken The collateral token to liquidate
    /// @param _indexToken The index token of the position
    /// @param _isLong True if the position is long, false if the position is short
    /// @param _raise True if checks should be performed against remaining collateral
    function validateLiquidation(
        address _account,
        address _collateralToken,
        address _indexToken,
        bool _isLong,
        bool _raise
    ) public view override returns (uint256, uint256) {
        Position memory position = _getPosition(
            _account,
            _collateralToken,
            _indexToken,
            _isLong
        );
        IVault _vault = vault;

        (bool hasProfit, uint256 delta) = _vault.getDelta(
            _indexToken,
            position.size,
            position.averagePrice,
            _isLong,
            position.lastIncreasedTime
        );
        uint256 marginFees = getFundingFee(
            _account,
            _collateralToken,
            _indexToken,
            _isLong,
            position.size,
            position.entryFundingRate
        );
        marginFees += getPositionFee(
            _account,
            _collateralToken,
            _indexToken,
            _isLong,
            position.size
        );

        if (!hasProfit && position.collateral < delta) {
            if (_raise) {
                revert LossesExceedCollateral();
            }
            return (1, marginFees);
        }

        uint256 remainingCollateral = position.collateral;
        if (!hasProfit) {
            remainingCollateral = position.collateral - delta;
        }

        if (remainingCollateral < marginFees) {
            if (_raise) {
                revert FeesExceedCollateral();
            }
            // cap the fees to the remainingCollateral
            return (1, remainingCollateral);
        }

        if (remainingCollateral < marginFees + _vault.liquidationFeeUsd()) {
            if (_raise) {
                revert FeesExceedCollateral();
            }
            return (1, marginFees);
        }

        if (
            remainingCollateral * _vault.maxLeverage() <
            position.size * BASIS_POINTS_DIVISOR
        ) {
            if (_raise) {
                revert MaxLeverageExceeded();
            }
            return (2, marginFees);
        }

        return (0, marginFees);
    }

    /// @notice Get the entry funding rate
    /// @dev The entry funding rate is the cumulative funding rate at the time of entry
    /// @param _collateralToken Address of the collateral token
    /// @return The entry funding rate
    function getEntryFundingRate(
        address _collateralToken,
        address, /* _indexToken */
        bool /* _isLong */
    ) public view override returns (uint256) {
        return vault.cumulativeFundingRates(_collateralToken);
    }

    /// @notice Get the position fee
    /// @param _sizeDelta The change in the position size
    /// @return The position fee
    function getPositionFee(
        address, /* _account */
        address, /* _collateralToken */
        address, /* _indexToken */
        bool, /* _isLong */
        uint256 _sizeDelta
    ) public view override returns (uint256) {
        if (_sizeDelta == 0) {
            return 0;
        }
        uint256 afterFeeUsd = (_sizeDelta *
            (BASIS_POINTS_DIVISOR - vault.marginFeeBasisPoints())) /
            BASIS_POINTS_DIVISOR;
        return _sizeDelta - afterFeeUsd;
    }

    /// @notice Get the funding fee
    /// @param _collateralToken The address of the collateral token
    /// @param _size The size of the position
    /// @param _entryFundingRate The entry funding rate
    /// @return The funding fee
    function getFundingFee(
        address, /* _account */
        address _collateralToken,
        address, /* _indexToken */
        bool, /* _isLong */
        uint256 _size,
        uint256 _entryFundingRate
    ) public view override returns (uint256) {
        if (_size == 0) {
            return 0;
        }

        uint256 fundingRate = vault.cumulativeFundingRates(_collateralToken) -
            _entryFundingRate;
        if (fundingRate == 0) {
            return 0;
        }

        return (_size * fundingRate) / FUNDING_RATE_PRECISION;
    }

    /// @notice Get the basis points for the buy usd fee
    /// @param _token The address of the token
    /// @param _usdAmount The amount of usd to buy
    /// @return The basis points for the buy usd fee
    function getBuyUsdFeeBasisPoints(address _token, uint256 _usdAmount)
        public
        view
        override
        returns (uint256)
    {
        return
            getFeeBasisPoints(
                _token,
                _usdAmount,
                vault.mintBurnFeeBasisPoints(),
                vault.taxBasisPoints(),
                true
            );
    }

    /// @notice Get the basis points for the sell usd fee
    /// @param _token The address of the token
    /// @param _usdAmount The amount of usd to sell
    /// @return The basis points for the sell usd fee
    function getSellUsdFeeBasisPoints(address _token, uint256 _usdAmount)
        public
        view
        override
        returns (uint256)
    {
        return
            getFeeBasisPoints(
                _token,
                _usdAmount,
                vault.mintBurnFeeBasisPoints(),
                vault.taxBasisPoints(),
                false
            );
    }

    /// @notice Get the basis points for the swap fee
    /// @param _tokenIn The address of the token to swap in
    /// @param _tokenOut The address of the token to swap out
    /// @param _usdAmount The amount to swap in usd
    /// @return The basis points for the swap fee
    function getSwapFeeBasisPoints(
        address _tokenIn,
        address _tokenOut,
        uint256 _usdAmount
    ) public view override returns (uint256) {
        bool isStableSwap = vault.stableTokens(_tokenIn) &&
            vault.stableTokens(_tokenOut);
        uint256 baseBps = isStableSwap
            ? vault.stableSwapFeeBasisPoints()
            : vault.swapFeeBasisPoints();
        uint256 taxBps = isStableSwap
            ? vault.stableTaxBasisPoints()
            : vault.taxBasisPoints();
        uint256 feesBasisPoints0 = getFeeBasisPoints(
            _tokenIn,
            _usdAmount,
            baseBps,
            taxBps,
            true
        );
        uint256 feesBasisPoints1 = getFeeBasisPoints(
            _tokenOut,
            _usdAmount,
            baseBps,
            taxBps,
            false
        );
        // use the higher of the two fee basis points
        return
            feesBasisPoints0 > feesBasisPoints1
                ? feesBasisPoints0
                : feesBasisPoints1;
    }

    /*
     * @dev cases to consider
     * 1. initialAmount is far from targetAmount, action increases balance slightly => high rebate
     * 2. initialAmount is far from targetAmount, action increases balance largely => high rebate
     * 3. initialAmount is close to targetAmount, action increases balance slightly => low rebate
     * 4. initialAmount is far from targetAmount, action reduces balance slightly => high tax
     * 5. initialAmount is far from targetAmount, action reduces balance largely => high tax
     * 6. initialAmount is close to targetAmount, action reduces balance largely => low tax
     * 7. initialAmount is above targetAmount, nextAmount is below targetAmount and vice versa
     * 8. a large swap should have similar fees as the same trade split into multiple smaller swaps
     */
    function getFeeBasisPoints(
        address _token,
        uint256 _usdvDelta,
        uint256 _feeBasisPoints,
        uint256 _taxBasisPoints,
        bool _increment
    ) public view override returns (uint256) {
        if (!vault.hasDynamicFees()) {
            return _feeBasisPoints;
        }

        // uint256 initialAmount = vault.usdvAmounts(_token); // Question: how does this change affect the protocol?
        uint256 initialAmount = getTokenAum(_token, false);
        uint256 nextAmount = initialAmount + _usdvDelta;
        if (!_increment) {
            nextAmount = _usdvDelta > initialAmount
                ? 0
                : initialAmount - _usdvDelta;
        }

        uint256 targetAmount = vault.getTargetUsdAmount(_token);
        if (targetAmount == 0) {
            return _feeBasisPoints;
        }

        uint256 initialDiff = initialAmount > targetAmount
            ? initialAmount - targetAmount
            : targetAmount - initialAmount;
        uint256 nextDiff = nextAmount > targetAmount
            ? nextAmount - targetAmount
            : targetAmount - nextAmount;

        // action improves relative asset balance
        if (nextDiff < initialDiff) {
            uint256 rebateBps = (_taxBasisPoints * initialDiff) / targetAmount;
            return
                rebateBps > _feeBasisPoints ? 0 : _feeBasisPoints - rebateBps;
        }

        uint256 averageDiff = initialDiff + nextDiff / 2;
        if (averageDiff > targetAmount) {
            averageDiff = targetAmount;
        }
        uint256 taxBps = (_taxBasisPoints * averageDiff) / targetAmount;
        return _feeBasisPoints + taxBps;
    }

    /// @notice Get the assets under management (AUM)
    /// @param maximise True to return the maximum AUM, false to return the minimum AUM
    /// @return The assets under management (AUM)
    function getAum(bool maximise) public view override returns (uint256) {
        return vlpManager.getAum(maximise);
    }

    /// @notice Get the assets under management (AUM) in `_token`
    /// @param _token The address of the token
    /// @param maximise True to return the maximum AUM, false to return the minimum AUM
    /// @return The assets under management (AUM) in `_token`
    function getTokenAum(address _token, bool maximise)
        public
        view
        override
        returns (uint256)
    {
        return vlpManager.getTokenAum(_token, maximise);
    }

    /// @dev Always returns true, included to satisfy the IVaultUtils interface
    function updateCumulativeFundingRate(
        address, /* _collateralToken */
        address /* _indexToken */
    ) public pure override returns (bool) {
        return true;
    }

    function _getPosition(
        address _account,
        address _collateralToken,
        address _indexToken,
        bool _isLong
    ) internal view returns (Position memory) {
        IVault _vault = vault;
        Position memory position;
        {
            (
                uint256 size,
                uint256 collateral,
                uint256 averagePrice,
                uint256 entryFundingRate, /* reserveAmount */ /* realisedPnl */ /* hasProfit */
                ,
                ,
                ,
                uint256 lastIncreasedTime
            ) = _vault.getPosition(
                    _account,
                    _collateralToken,
                    _indexToken,
                    _isLong
                );
            position.size = size;
            position.collateral = collateral;
            position.averagePrice = averagePrice;
            position.entryFundingRate = entryFundingRate;
            position.lastIncreasedTime = lastIncreasedTime;
        }
        return position;
    }
}
