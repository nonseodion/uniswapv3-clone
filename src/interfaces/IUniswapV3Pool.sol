pragma solidity ^0.8.14;

interface IUniswapV3Pool{
  struct MintCallbackData{
    address token0;
    address token1;
    address payer;
  }

  function slot0() external
    returns (
      uint160 sqrtPriceX96,
      // current tick
      int24 tick,
      uint16 observationIndex,
      uint16 observationCardinality,
      uint16 observationCardinalityNext
    );

  function token0() external returns (address);
  function token1() external returns (address);

  function mint(
    address owner,
    uint128 amount, 
    int24 lowerTick,
    int24 upperTick,
    bytes calldata data
  ) external returns(uint256 amount0, uint256 amount1);
}