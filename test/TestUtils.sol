pragma solidity ^0.8.14;

import { TickMath } from "../src/libraries/TickMath.sol";
import "prb-math/Common.sol";

abstract contract TestUtils {

  function tick(uint256 price) internal pure returns (int24 tick_){
    tick_ = TickMath.getTickAtSqrtRatio(
      // ABDKMath64x64.sqrt(int128(price))
    );
  }

  // function sqrtP(uint256 price) internal pure returns (uint160 sqrtPrice){
  //   tick = 
  // }
}