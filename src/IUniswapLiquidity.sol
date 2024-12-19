// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IUniswapLiquidity {
    function getAmountsForLiquidity(
        uint160 sqrtRatioX96,
        uint160 sqrtRatioAX96,
        uint160 sqrtRatioBX96,
        uint128 liquidity
    ) external view returns (uint256 amount0, uint256 amount1);
}
