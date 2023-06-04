pragma solidity ^0.8.14;

import { Math } from "./Math.sol";
import { mulDiv } from "prb-math/Common.sol";

import "forge-std/console.sol";

library SwapMath{

  function computeSwapStep(
    uint160 sqrtPriceCurrentX96,
    uint160 sqrtPriceTargetX96,
    uint128 liquidity,
    uint256 amountRemaining,
    uint24 fee
  ) internal
    returns(
      uint160 sqrtPriceNextX96,
      uint256 amountIn,
      uint256 amountOut,
      uint256 feeAmount
    ){
    uint256 amountRemainingLessFee = mulDiv( amountRemaining, 1e6 - fee, fee);
    bool zeroForOne = sqrtPriceCurrentX96 >= sqrtPriceTargetX96;
    
    amountIn = zeroForOne 
      ? uint256(Math.calcAmount0Delta(sqrtPriceCurrentX96, sqrtPriceTargetX96, int128(liquidity)))
      : uint256(Math.calcAmount1Delta(sqrtPriceCurrentX96, sqrtPriceTargetX96, int128(liquidity)));

    if(amountRemainingLessFee >= amountIn){
      sqrtPriceNextX96 = sqrtPriceTargetX96;
    }
    else {
      sqrtPriceNextX96 = Math.getNextSqrtPriceFromInputAmount(
        sqrtPriceCurrentX96,
        amountRemainingLessFee,
        liquidity,
        zeroForOne
      );
    }
    
    amountIn = uint256(Math.calcAmount0Delta(sqrtPriceCurrentX96, sqrtPriceNextX96, int128(liquidity)));
    amountOut = uint256(Math.calcAmount1Delta(sqrtPriceCurrentX96, sqrtPriceNextX96, int128(liquidity)));

    if(!zeroForOne){
      (amountIn, amountOut) = (amountOut, amountIn);
    }

    bool max = sqrtPriceNextX96 == sqrtPriceTargetX96;
    if(!max){
      feeAmount = amountRemaining - amountIn;
    }else {
      feeAmount = Math.mulDivRoundingUp(amountIn, fee, 1e6-fee);
    }
  }
}