pragma solidity ^0.8.14;

import { UniswapV3Pool } from "./UniswapV3Pool.sol";
import { IERC20Minimal as IERC20 } from "./interfaces/IERC20Minimal.sol";
import { LiquidityMath } from "./libraries/LiquidityMath.sol";
import { TickMath } from "./libraries/TickMath.sol";

contract UniswapV3Manager{
  error SlippageCheckFailed(uint256 amount0, uint256 amount1);

  struct CallbackData {
    address token0;
    address token1;
    address payer;
  }

  function swap(address pool, address recipient, uint256 amount, uint160 minSqrtPriceX69, bool zeroForOne, bytes calldata data) external {
    UniswapV3Pool(pool).swap(recipient, zeroForOne, amount, minSqrtPriceX69, data);
  }

  function mint(
    address pool, 
    address owner, 
    int24 lowerTick, 
    int24 upperTick,
    uint256 amount0Desired, 
    uint256 amount1Desired, 
    uint256 amount0Min, 
    uint256 amount1Min,  
    bytes calldata data
  ) external {
    uint128 liquidity;
    {
      uint160 sqrtPriceAX96 = TickMath.getSqrtRatioAtTick(lowerTick);
      uint160 sqrtPriceBX96 = TickMath.getSqrtRatioAtTick(lowerTick);
      (uint160 currentPrice, ) = UniswapV3Pool(pool).slot0();
      
      liquidity = LiquidityMath.getLiquidityForAmounts(
        currentPrice,
        sqrtPriceAX96,
        sqrtPriceBX96,
        amount0Desired,
        amount1Desired
      );
    }

    (uint256 amount0, uint256 amount1) = UniswapV3Pool(pool).mint(
      owner,
      liquidity,
      lowerTick,
      upperTick,
      data
    );

    if(amount0 < amount0Min || amount1 < amount1Min){
      revert SlippageCheckFailed(amount0, amount1);
    }
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

  function uniswapV3FlashCallback(bytes calldata data) external {
    (uint256 amount0, uint256 amount1) = abi.decode(data, (uint256, uint256));
    IERC20 token0 = IERC20(UniswapV3Pool(msg.sender).token0());
    IERC20 token1 = IERC20(UniswapV3Pool(msg.sender).token1());

    token0.transfer(msg.sender, amount0);
    token1.transfer(msg.sender, amount1);
  }
}
