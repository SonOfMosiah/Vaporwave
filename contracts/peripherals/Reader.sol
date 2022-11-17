// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import "../core/interfaces/IVault.sol";

/// @title Vaporwave Reader
contract Reader is Ownable {
    /// USD Decimals
    uint8 public constant USD_DECIMALS = 30;
    /// Number of properties for a position
    uint8 public constant POSITION_PROPS_LENGTH = 9;
    /// Helper to avoid truncation errors in basis points calculations
    uint16 public constant BASIS_POINTS_DIVISOR = 10000;
    /// Helper to avoid truncation errors in price calculations
    uint128 public constant PRICE_PRECISION = 1e30;

    /// True if there is a max global short size
    bool public hasMaxGlobalShortSizes;

    /// @notice Set if the contract has max global short sizes to `_hasMaxGlobalShortSizes`
    /// @param _hasMaxGlobalShortSizes True if the contract has max global short sizes
    function setConfig(bool _hasMaxGlobalShortSizes) public onlyOwner {
        hasMaxGlobalShortSizes = _hasMaxGlobalShortSizes;
    }

    /// @notice Get the fee amounts
    /// @param _vault The vault address
    /// @param _tokens An array of tokens to query for fees
    /// @return amounts An array of fee amounts
    function getFees(address _vault, address[] memory _tokens)
        public
        view
        returns (uint256[] memory amounts)
    {
        amounts = new uint256[](_tokens.length);
        for (uint256 i = 0; i < _tokens.length; i++) {
            amounts[i] = IVault(_vault).feeReserves(_tokens[i]);
        }
        return amounts;
    }

    /// @notice Get funding rates for an array of tokens
    /// @param _vault The vault address
    /// @param _weth The WETH address
    /// @param _tokens An array of tokens to query for funding rates
    /// @return fundingRates An array of funding rates
    function getFundingRates(
        address _vault,
        address _weth,
        address[] memory _tokens
    ) public view returns (uint256[] memory fundingRates) {
        uint256 propsLength = 2;
        fundingRates = new uint256[](_tokens.length * propsLength);
        IVault vault = IVault(_vault);

        for (uint256 i = 0; i < _tokens.length; i++) {
            address token = _tokens[i];
            if (token == address(0)) {
                token = _weth;
            }

            uint256 fundingRateFactor = vault.stableTokens(token)
                ? vault.stableFundingRateFactor()
                : vault.fundingRateFactor();
            uint256 reservedAmount = vault.reservedAmounts(token);
            uint256 poolAmount = vault.poolAmounts(token);

            if (poolAmount > 0) {
                fundingRates[i * propsLength] =
                    (fundingRateFactor * reservedAmount) /
                    poolAmount;
            }

            if (vault.cumulativeFundingRates(token) > 0) {
                uint256 nextRate = vault.getNextFundingRate(token);
                uint256 baseRate = vault.cumulativeFundingRates(token);
                fundingRates[i * propsLength + 1] = baseRate + nextRate;
            }
        }

        return fundingRates;
    }

    /// @notice Get the token balances for `_account`
    /// @dev Address(0) is used for the native currency
    /// @param _account The account to query for token balances
    /// @param _tokens An array of tokens to query for balances
    /// @return balances An array of token balances
    function getTokenBalances(address _account, address[] memory _tokens)
        public
        view
        returns (uint256[] memory balances)
    {
        balances = new uint256[](_tokens.length);
        for (uint256 i = 0; i < _tokens.length; i++) {
            address token = _tokens[i];
            if (token == address(0)) {
                balances[i] = _account.balance;
                continue;
            }
            balances[i] = IERC20(token).balanceOf(_account);
        }
        return balances;
    }

    /// @notice Get the token balances for `_account` + total supplies
    /// @dev Address(0) is used for the native currency
    /// @param _account The account to query for token balances
    /// @param _tokens An array of tokens to query for balances
    /// @return balances An array of token balances and total supplies
    function getTokenBalancesWithSupplies(
        address _account,
        address[] memory _tokens
    ) public view returns (uint256[] memory balances) {
        uint256 propsLength = 2;
        balances = new uint256[](_tokens.length * propsLength);
        for (uint256 i = 0; i < _tokens.length; i++) {
            address token = _tokens[i];
            if (token == address(0)) {
                balances[i * propsLength] = _account.balance;
                balances[i * propsLength + 1] = 0;
                continue;
            }
            balances[i * propsLength] = IERC20(token).balanceOf(_account);
            balances[i * propsLength + 1] = IERC20(token).totalSupply();
        }
        return balances;
    }

    /// @notice Get the positions for `_account`
    /// @param _vault The vault address
    /// @param _account The account to query for positions
    /// @param _collateralTokens An array of collateral tokens
    /// @param _indexTokens An array of index tokens
    /// @param _isLong An array of booleans indicating whether the position is long or short
    /* @return amounts An array of positions
    * (size, collateral, average prirce, entry funding rate, 
    has realized profit (bool), realized PnL, last increased time, has profit (bool), delta)
    */
    function getPositions(
        address _vault,
        address _account,
        address[] memory _collateralTokens,
        address[] memory _indexTokens,
        bool[] memory _isLong
    ) public view returns (uint256[] memory amounts) {
        amounts = new uint256[](
            _collateralTokens.length * POSITION_PROPS_LENGTH
        );

        for (uint256 i = 0; i < _collateralTokens.length; i++) {
            {
                (
                    uint256 size,
                    uint256 collateral,
                    uint256 averagePrice,
                    uint256 entryFundingRate,
                    ,
                    /* reserveAmount */
                    uint256 realisedPnl,
                    bool hasRealisedProfit,
                    uint256 lastIncreasedTime
                ) = IVault(_vault).getPosition(
                        _account,
                        _collateralTokens[i],
                        _indexTokens[i],
                        _isLong[i]
                    );

                amounts[i * POSITION_PROPS_LENGTH] = size;
                amounts[i * POSITION_PROPS_LENGTH + 1] = collateral;
                amounts[i * POSITION_PROPS_LENGTH + 2] = averagePrice;
                amounts[i * POSITION_PROPS_LENGTH + 3] = entryFundingRate;
                amounts[i * POSITION_PROPS_LENGTH + 4] = hasRealisedProfit
                    ? 1
                    : 0;
                amounts[i * POSITION_PROPS_LENGTH + 5] = realisedPnl;
                amounts[i * POSITION_PROPS_LENGTH + 6] = lastIncreasedTime;
            }

            uint256 size = amounts[i * POSITION_PROPS_LENGTH];
            uint256 averagePrice = amounts[i * POSITION_PROPS_LENGTH + 2];
            uint256 lastIncreasedTime = amounts[i * POSITION_PROPS_LENGTH + 6];
            if (averagePrice > 0) {
                (bool hasProfit, uint256 delta) = IVault(_vault).getDelta(
                    _indexTokens[i],
                    size,
                    averagePrice,
                    _isLong[i],
                    lastIncreasedTime
                );
                amounts[i * POSITION_PROPS_LENGTH + 7] = hasProfit ? 1 : 0;
                amounts[i * POSITION_PROPS_LENGTH + 8] = delta;
            }
        }

        return amounts;
    }
}
