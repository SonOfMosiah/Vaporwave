// SPDX-License-Identifier: GNU-GPL-3.0-or-later
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";

import "./interfaces/IUniswapV2Pair.sol";
import "./libraries/FixedPoint.sol";
import "./libraries/UniswapV2OracleLibrary.sol";

/// Pair has no liquidity
error NoReserves();
/// Period must be greater than zero (0)
error InvalidPeriod();
/// Price can only be updated once per period
error PeriodNotElapsed();
/// Token is not one of the pair's tokens
error InvalidToken();

/// @title Vaporwave UniswapV2 Price Oracle
/// @dev Gets the time weighted average price (twap) of a token based off of the UniswapV2Pair
/// @dev fixed window oracle that recomputes the average price for the entire period once every period
/// @dev note that the price average is only guaranteed to be over at least 1 period, but may be over a longer period
contract UniswapV2Oracle is Ownable {
    using FixedPoint for *;

    /// The period length in seconds (how often the price average can be updated)
    uint256 public period = 5 minutes;

    /// Address of the pair
    IUniswapV2Pair public immutable pair;
    /// Address of token0
    address public immutable token0;
    /// Address of token1
    address public immutable token1;

    /// The price0Cumulative used during the last period
    uint256 public price0CumulativeLast;
    /// The price1Cumulative used during the last period
    uint256 public price1CumulativeLast;
    /// The timestamp of the last price update
    uint32 public blockTimestampLast;
    /// The TWAP for token 0
    FixedPoint.uq112x112 public price0Average;
    /// The TWAP for token 1
    FixedPoint.uq112x112 public price1Average;

    constructor(IUniswapV2Pair _pair) {
        pair = _pair;
        token0 = _pair.token0();
        token1 = _pair.token1();
        price0CumulativeLast = _pair.price0CumulativeLast(); // fetch the current accumulated price value (1 / 0)
        price1CumulativeLast = _pair.price1CumulativeLast(); // fetch the current accumulated price value (0 / 1)
        uint112 reserve0;
        uint112 reserve1;
        (reserve0, reserve1, blockTimestampLast) = _pair.getReserves();

        // ensure that there's liquidity in the pair
        if (reserve0 == 0 || reserve1 == 0) {
            revert NoReserves();
        }
    }

    /// @notice Set the period length to `_period` seconds
    /// @dev Reverts if `_period` is zero (0)
    /// @param _period The period length in seconds
    function setPeriod(uint256 _period) external onlyOwner {
        if (period == 0) {
            revert InvalidPeriod();
        }
        period = _period;
    }

    /// @notice Update the price average for the entire period
    /// @dev Reverts if the period has not elapsed
    function update() external {
        (
            uint256 price0Cumulative,
            uint256 price1Cumulative,
            uint32 blockTimestamp
        ) = UniswapV2OracleLibrary.currentCumulativePrices(address(pair));
        uint32 timeElapsed;
        unchecked {
            timeElapsed = blockTimestamp - blockTimestampLast; // overflow is desired
        }

        // ensure that at least one full period has passed since the last update
        if (timeElapsed < period) {
            revert PeriodNotElapsed();
        }

        // overflow is desired, casting never truncates
        // cumulative price is in (uq112x112 price * seconds) units so we simply wrap it after division by time elapsed
        unchecked {
            price0Average = FixedPoint.uq112x112(
                uint224((price0Cumulative - price0CumulativeLast) / timeElapsed)
            );
            price1Average = FixedPoint.uq112x112(
                uint224((price1Cumulative - price1CumulativeLast) / timeElapsed)
            );
        }

        price0CumulativeLast = price0Cumulative;
        price1CumulativeLast = price1Cumulative;
        blockTimestampLast = blockTimestamp;
    }

    /// @notice Get the price average for `_amountIn` of `_token`
    /// @dev This will always return 0 before update has been called successfully for the first time.
    /// @param _token The token to get the price average for
    /// @param _amountIn The amount of `_token` to get the price average for
    /// @return amountOut (The price of `amountIn` tokens denominated by the pair token)
    function consult(address _token, uint256 _amountIn)
        external
        view
        returns (uint256 amountOut)
    {
        if (_token == token0) {
            amountOut = price0Average.mul(_amountIn).decode144();
        } else {
            if (_token != token1) {
                revert InvalidToken();
            }
            amountOut = price1Average.mul(_amountIn).decode144();
        }
    }
}
