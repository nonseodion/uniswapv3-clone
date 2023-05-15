pragma solidity ^0.8.14;

import { UniswapV3Pool } from "./UniswapV3Pool.sol";

contract Quoter {
  function quote(
    uint256 amountIn,
    address pool,
    bool zeroForOne
  ) public returns (uint256 amountOut, uint160 sqrtPriceAfter, int24 tick){
    try 
        UniswapV3Pool(pool).swap(
        address(this),
        zeroForOne,
        amountIn,
        abi.encode(pool)
      )
    {}
    catch(bytes memory reason){
      (amountOut, sqrtPriceAfter, tick) = abi.decode(reason, (uint256, uint160, int24));
    }
  }

  function uniswapV3SwapCallback(
      int256 amount0Delta,
      int256 amount1Delta,
      bytes calldata data
  ) external {
    uint256 amountOut = amount0Delta > 0
      ? uint256(-amount1Delta)
      : uint256(-amount0Delta);

    address pool = abi.decode(data, (address));
    (uint160 slot, int24 tick) = UniswapV3Pool(pool).slot0();
    
    assembly{
      let freeMemoryPointer := mload(0x40)
      mstore(freeMemoryPointer, amountOut)
      mstore(add(freeMemoryPointer, 0x20), slot)
      mstore(add(freeMemoryPointer, 0x40), tick)
      revert(freeMemoryPointer, 0x60)
    }
  }  
}