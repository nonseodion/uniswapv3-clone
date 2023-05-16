pragma solidity ^0.8.14;

import {FixedPoint96} from "./FixedPoint96.sol";
import {mulDiv} from "prb-math/Common.sol";
import "forge-std/console.sol";

library Math {
  function calcAmount0Delta(
    uint160 sqrtPriceAX96,
    uint160 sqrtPriceBX96,
    uint128 liquidity
  ) internal pure returns (uint amount) {
    if(sqrtPriceBX96 > sqrtPriceAX96){
      (sqrtPriceAX96, sqrtPriceBX96) = (sqrtPriceBX96, sqrtPriceAX96);
    }

    amount = divRoundingUp(
      mulDivRoundingUp(
        uint256(liquidity) << FixedPoint96.RESOLUTION,
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
  ) internal pure returns (uint amount){
    if(sqrtPriceBX96 > sqrtPriceAX96){
      (sqrtPriceAX96, sqrtPriceBX96) = (sqrtPriceBX96, sqrtPriceAX96);
    }

    amount = mulDivRoundingUp(liquidity, sqrtPriceAX96 - sqrtPriceBX96, FixedPoint96.Q96);
  }

  function getNextSqrtPriceFromInputAmount(
    uint160 sqrtPriceX96,
    uint256 amountIn,
    uint128 liquidity,
    bool zeroForOne
  ) internal  returns (uint160 nextSqrtPrice){

    nextSqrtPrice = zeroForOne 
      ? getNextSqrtPriceFromAmount0RoundingUp(sqrtPriceX96, amountIn, liquidity)
      : getNextSqrtPriceFromAmount1RoundingDown(sqrtPriceX96, amountIn, liquidity);
  }

  function getNextSqrtPriceFromAmount0RoundingUp(
    uint160 sqrtPriceX96,
    uint256 amountIn,
    uint128 liquidity
  ) internal returns(uint160) {
    uint256 numerator = uint256(liquidity) << FixedPoint96.RESOLUTION;
    uint256 product = amountIn * sqrtPriceX96;
    
    if(product / amountIn == sqrtPriceX96){
      uint256 denominator = numerator + product;
      if(denominator >= numerator){
        uint160 sqrtPriceNextX96 = uint160(mulDivRoundingUp(
          numerator,
          sqrtPriceX96,
          denominator
        ));

        return sqrtPriceNextX96;
      }
    }

    return uint160(
      divRoundingUp(numerator, amountIn + (liquidity / sqrtPriceX96))
    );
  }

  function getNextSqrtPriceFromAmount1RoundingDown(
    uint160 sqrtPriceX96,
    uint256 amountIn,
    uint128 liquidity
  ) internal returns(uint160) {
    return sqrtPriceX96 + uint160((amountIn << FixedPoint96.RESOLUTION) / liquidity);
  }

  function mulDivRoundingUp(uint a, uint b, uint denominator) internal pure returns (uint256 result) {
    result = mulDiv(a, b, denominator);
    if(mulmod(a, b, denominator) > 0){
      require(result < type(uint256).max, "OVERFLOW");
      result++;
    }
  }

  function divRoundingUp(uint numerator, uint denominator) internal pure returns (uint256 result) {
    assembly{
      result := add(
        div(numerator, denominator),
        gt(mod(numerator, denominator), 0)
      )
    }
  }
}
