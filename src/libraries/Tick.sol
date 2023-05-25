pragma solidity ^0.8.14;

import {LiquidityMath} from "./LiquidityMath.sol";
import "forge-std/Test.sol";

library Tick {
    struct Info {
        bool initialized;
        uint128 liquidityGross;
        int128 liquidityNet;
        uint256 feeGrowthOutside0X128;
        uint256 feeGrowthOutside1X128;
    }

    function update(
        mapping(int24 => Info) storage self,
        int24 tick,
        int24 currentTick,
        int128 liquidityDelta,
        uint256 feeGrowthGlobal0X128,
        uint256 feeGrowthGlobal1X128,
        bool upper
    ) internal returns (bool flipped) {
        Info storage tickInfo = self[tick];
        uint128 liquidityBefore = tickInfo.liquidityGross;
        uint128 liquidityAfter = LiquidityMath.addLiquidity(
            liquidityBefore,
            liquidityDelta
        );

        tickInfo.liquidityNet = upper
            ? tickInfo.liquidityNet - liquidityDelta
            : tickInfo.liquidityNet + liquidityDelta;

        flipped = (liquidityAfter == 0) != (liquidityBefore == 0);

        if (liquidityBefore == 0) {
            if (tick < currentTick) {
                tickInfo.feeGrowthOutside0X128 = feeGrowthGlobal0X128;
                tickInfo.feeGrowthOutside1X128 = feeGrowthGlobal1X128;
            }
            tickInfo.initialized = true;
        }

        tickInfo.liquidityGross = liquidityAfter;
    }

    function cross(
        mapping(int24 => Info) storage self,
        int24 tick,
        uint256 feeGrowthGlobal0X128,
        uint256 feeGrowthGlobal1X128
    ) internal returns (int128 liquidityNet) {
        Info storage info = self[tick];
        info.feeGrowthOutside0X128 =
            feeGrowthGlobal0X128 -
            info.feeGrowthOutside0X128;
        info.feeGrowthOutside1X128 =
            feeGrowthGlobal1X128 -
            info.feeGrowthOutside1X128;
        liquidityNet = info.liquidityNet;
    }

    function getFreeGrowthInside(
        mapping(int24 => Info) storage self,
        int24 lowerTick_,
        int24 upperTick_,
        int24 currentTick,
        uint256 feeGrowthGlobal0X128,
        uint256 feeGrowthGlobal1X128
    ) internal view returns (uint256 feeGrowthInside0X128, uint256 feeGrowthInside1X128) {
      Info memory lowerTickInfo = self[lowerTick_];
      Info memory upperTickInfo = self[upperTick_];

      uint256 feeGrowthBelow0X128;
      uint256 feeGrowthBelow1X128;
      if(currentTick >= lowerTick_){
        feeGrowthBelow0X128 = lowerTickInfo.feeGrowthOutside0X128;
        feeGrowthBelow1X128 = lowerTickInfo.feeGrowthOutside1X128;
      }else {
        feeGrowthBelow0X128 = feeGrowthGlobal0X128 - lowerTickInfo.feeGrowthOutside0X128;
        feeGrowthBelow1X128 = feeGrowthGlobal1X128 - lowerTickInfo.feeGrowthOutside1X128;
      }

      uint256 feeGrowthAbove0X128;
      uint256 feeGrowthAbove1X128;
      if(currentTick < upperTick_){
        feeGrowthAbove0X128 = upperTickInfo.feeGrowthOutside0X128;
        feeGrowthAbove1X128 = upperTickInfo.feeGrowthOutside1X128;
      }else {
        feeGrowthAbove0X128 = feeGrowthGlobal0X128 - upperTickInfo.feeGrowthOutside0X128;
        feeGrowthAbove1X128 = feeGrowthGlobal1X128 - upperTickInfo.feeGrowthOutside1X128;
      }

      feeGrowthInside0X128 = feeGrowthGlobal0X128 - feeGrowthBelow0X128 - feeGrowthAbove0X128;
      feeGrowthInside1X128 = feeGrowthGlobal1X128 - feeGrowthBelow1X128 - feeGrowthAbove1X128;
    }
}
