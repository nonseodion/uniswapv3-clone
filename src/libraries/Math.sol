pragma solidity ^0.8.14;

import {FixedPoint96} from "./FixedPoint96.sol";
import "prb-math/Common.sol";

library Math {
  function calcAmount0Delta(
    uint160 sqrtPriceAX96,
    uint160 sqrtPriceBX96,
    uint128 liquidity
  ) external returns (uint amount) {
    if(sqrtPriceBX96 > sqrtPriceAX96){
      (sqrtPriceAX96, sqrtPriceBX96) = (sqrtPriceBX96, sqrtPriceAX96);
    }

    amount = divRoundingUp(
      mulDivRoundingUp(
        liquidity << FixedPoint96.RESOLUTION,
        sqrtPriceAX96 - sqrtPriceBX96,
        sqrtPriceAX96
      ),
      sqrtPriceBX96
    );
  }

  function calcAmount1Delta(
    uint160 sqrtPriceAX96,
    uint160 sqrtPriceBX96,
    uint128 liquidity
  ) external returns (uint amount){
    if(sqrtPriceBX96 > sqrtPriceAX96){
      (sqrtPriceAX96, sqrtPriceBX96) = (sqrtPriceBX96, sqrtPriceAX96);
    }

    amount = mulDivRoundingUp(liquidity, sqrtPriceAX96 - sqrtPriceBX96, FixedPoint96.Q96);
  }

  function mulDivRoundingUp(uint a, uint b, uint denominator) internal returns (uint256 result) {
    result = mulDiv(a, b, denominator);
    if(mulmod(a, b, denominator) > 0){
      require(result < type(uint256).max, "OVERFLOW");
      result++;
    }
  }

  function divRoundingUp(uint numerator, uint denominator) internal returns (uint256 result) {
    assembly{
      result := add(
        div(numerator, denominator),
        gt(mod(numerator, denominator), 0)
      )
    }
  }
}