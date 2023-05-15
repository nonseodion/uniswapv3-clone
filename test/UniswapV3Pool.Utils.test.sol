pragma solidity ^0.8.14;

import "forge-std/Test.sol";

abstract contract UniswapV3PoolUtils is Test{
  struct TestCaseParams {
    uint wethBalance;
    uint usdcBalance;
    int24 currentTick;
    int24 lowerTick;
    int24 upperTick;
    uint128 liquidity;
    uint128 currentSqrtP;
    bool shouldTransferInCallback;
    bool mintLiqudity;
  }

  struct LiquidityRange {
    int24 lowerTick;
    int24 upperTick;
    uint128 amount;
  } 

  function liquidityRange (
    uint256 lowerPrice,
    uint256 upperPrice,
    uint256 amount0,
    uint256 amount1,
    uint256 currentPrice
  ) internal returns (LiquidityRange memory range){
    range.lowerTick = 
  }
}