pragma solidity ^0.8.14;

import {LiquidityMath} from "./LiquidityMath.sol";
import "forge-std/Test.sol";

library Tick {
  struct Info {
    bool initialized;
    uint128 liquidityGross;
    int128 liquidityNet;
  }

  function update(mapping(int24 => Info) storage self, int24 tick, int128 liquidityDelta, bool upper) internal returns (bool flipped){
    uint128 liquidityBefore = self[tick].liquidityGross;
    uint128 liquidityAfter = LiquidityMath.addLiquidity(liquidityBefore, liquidityDelta);

    self[tick].liquidityNet = upper
      ? self[tick].liquidityNet - liquidityDelta
      : self[tick].liquidityNet + liquidityDelta;
      
    flipped = (liquidityAfter == 0) != (liquidityBefore == 0);

    if(liquidityBefore == 0){
      self[tick].initialized = true;
    }

    self[tick].liquidityGross = liquidityAfter;
  }

  function cross(mapping(int24 => Info) storage self, int24 tick) internal view returns (int128 liquidityNet) {
    Info memory info = self[tick];
    liquidityNet = info.liquidityNet;
  }
}