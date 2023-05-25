pragma solidity ^0.8.14;

import { mulDiv } from "prb-math/Common.sol";
import { FixedPoint128 } from "../libraries/FixedPoint128.sol";
import { LiquidityMath } from "../libraries/LiquidityMath.sol";

library Position {
  struct Info {
    uint128 liquidity;
    uint256 feeGrowthInside0LastX128;
    uint256 feeGrowthInside1LastX128;
    uint256 tokensOwed0;
    uint256 tokensOwed1;
  }

  function update(
    Info storage self, 
    int128 liquidityDelta,
    uint256 feeGrowthInside0X128,
    uint256 feeGrowthInside1X128
  ) internal {
    uint256 tokensOwed0 = mulDiv(
      feeGrowthInside0X128 - self.feeGrowthInside0LastX128,
      self.liquidity,
      FixedPoint128.Q128
    );

    uint256 tokensOwed1 = mulDiv(
      feeGrowthInside1X128 - self.feeGrowthInside1LastX128,
      self.liquidity,
      FixedPoint128.Q128
    );

    self.liquidity = LiquidityMath.addLiquidity(
      self.liquidity, 
      liquidityDelta
    );

    self.feeGrowthInside0LastX128 = feeGrowthInside0X128;
    self.feeGrowthInside0LastX128 = feeGrowthInside0X128;
    
    if(tokensOwed0 > 0 || tokensOwed1 > 0){
      self.tokensOwed0 += tokensOwed0;
      self.tokensOwed1 += tokensOwed1;
    }
  }

  function get(
    mapping(bytes32 => Info) storage positions, 
    address owner, 
    int24 lowerTick, 
    int24 upperTick
  ) view public returns (Info storage) {
    return positions[keccak256(abi.encodePacked(owner, lowerTick, upperTick))];
  }
}