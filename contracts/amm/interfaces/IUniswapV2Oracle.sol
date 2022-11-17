// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// Interface for UniswapV2 Price Oracle
interface IUniswapV2Oracle {
    function consult(address token, uint256 amountIn)
        external
        view
        returns (uint256);
}
