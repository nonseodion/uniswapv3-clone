pragma solidity ^0.8.14;

import { UniswapV3Pool } from "./UniswapV3Pool.sol";
import {IERC20Minimal as IERC20} from "./interfaces/IERC20Minimal.sol";
import {Common} from "prb-math/Common.sol";

contract UniswapV3Manager{
  struct CallbackData {
    address token0;
    address token1;
    address payer;
  }

  function swap(address pool, address recipient, bytes calldata data) external {
    UniswapV3Pool(pool).swap(recipient, data);
  }

  function mint(address pool, address owner, uint128 amount, int24 lowerTick, int24 upperTick, bytes calldata data) external {
    UniswapV3Pool(pool).mint(
      owner,
      amount,
      lowerTick,
      upperTick,
      data
    );
  }

  function uniswapV3MintCallback(
      uint256 amount0Owed,
      uint256 amount1Owed,
      bytes calldata data
  ) external {
    CallbackData memory extra = abi.decode(data, (CallbackData)); 
    IERC20(extra.token0).transferFrom(extra.payer, msg.sender, amount0Owed);
    IERC20(extra.token1).transferFrom(extra.payer, msg.sender, amount1Owed);
  }

  function uniswapV3SwapCallback(
      int256 amount0Delta,
      int256 amount1Delta,
      bytes calldata data
  ) external {
    CallbackData memory extra = abi.decode(data, (CallbackData)); 
    if(amount0Delta > 0) IERC20(extra.token0).transferFrom(extra.payer, msg.sender, uint(amount0Delta));
    if(amount1Delta > 0) IERC20(extra.token0).transferFrom(extra.payer, msg.sender, uint(amount1Delta));
  }
}
