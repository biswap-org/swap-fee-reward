pragma solidity 0.6.6;
interface IOracle {
    function consult(address tokenIn, uint amountIn, address tokenOut) external view returns (uint amountOut);
}