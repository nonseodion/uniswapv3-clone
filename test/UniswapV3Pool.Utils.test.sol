pragma solidity ^0.8.14;

import "forge-std/Test.sol";
import {LiquidityMath} from "../src/libraries/LiquidityMath.sol";
import { TestUtils } from "./TestUtils.sol";

abstract contract UniswapV3PoolUtils is TestUtils{
  struct TestCaseParams {
    uint wethBalance;
    uint usdcBalance;
    uint256 currentPrice;
    LiquidityRange[] liquidity;
    bool transferInMintCallback;
    bool transferInSwapCallback;
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
  ) internal  returns (LiquidityRange memory range){
    range.lowerTick = tick(lowerPrice);
    range.upperTick = tick(upperPrice);
    range.amount = LiquidityMath.getLiquidityForAmounts(
      sqrtP(currentPrice), 
      sqrtP(lowerPrice), 
      sqrtP(upperPrice), 
      amount0, 
      amount1
    );
  }
}