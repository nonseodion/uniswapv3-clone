pragma solidity ^0.8.14;

import { UniswapV3Pool } from "./UniswapV3Pool.sol";
import { IERC20Minimal as IERC20 } from "./interfaces/IERC20Minimal.sol";
import { LiquidityMath } from "./libraries/LiquidityMath.sol";
import { TickMath } from "./libraries/TickMath.sol";
import { Path } from "./libraries/Path.sol";
import { PoolAddress } from "./libraries/PoolAddress.sol";
import {UniswapV3Pool} from "./UniswapV3Pool.sol";
import "forge-std/Test.sol";

contract UniswapV3Manager{
  using Path for bytes;

  address public immutable factory;

  struct SwapCallbackData{
    bytes path;
    address payer;
  }

  struct MintCallbackData{
    address token0;
    address token1;
    address payer;
  }

  struct SwapSingleParams {
    address tokenIn;
    address tokenOut;
    uint24 tickSpacing;
    uint256 amountIn;
    uint160 sqrtPriceLimitX96;
  }

  struct SwapParams {
    bytes path;
    address recipient;
    uint256 amountIn;
    uint256 minAmountOut;
  }

  error SlippageCheckFailed(uint256 amount0, uint256 amount1);
  error TooLittleReceivedAmount(uint256 amountOut);

  constructor(address factory_){
    factory = factory_;
  }

  function swapSingle(SwapSingleParams calldata params) external returns (uint256 amountOut){
    amountOut = _swap(
      params.amountIn,
      msg.sender,
      params.sqrtPriceLimitX96,
      SwapCallbackData(abi.encodePacked(params.tokenIn, params.tickSpacing, params.tokenOut), msg.sender)
    );
  }

  function swap(SwapParams calldata params) external returns (uint256 amountOut){
    uint256 amountIn = params.amountIn;
    address payer = msg.sender;
    bytes memory path = params.path;

    while(true){
      bool hasMultiplePools = path.hasMultiplePools();
      amountOut = _swap(
        amountIn,
        hasMultiplePools ? address(this) : params.recipient,
        0,
        SwapCallbackData({
          path: path.getFirstPool(),
          payer: payer
        })
      );

      amountIn = amountOut;
      if(hasMultiplePools){
        path = path.skipToken();  
        payer = address(this);
      } else {  
        break;
      }
      if(amountOut < params.minAmountOut){
        revert TooLittleReceivedAmount(amountOut);
      }
    }
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
    MintCallbackData calldata data
  ) external returns (uint256 amount0, uint256 amount1) {
    uint128 liquidity;
    {
      uint160 sqrtPriceAX96 = TickMath.getSqrtRatioAtTick(lowerTick);
      uint160 sqrtPriceBX96 = TickMath.getSqrtRatioAtTick(upperTick);
      (uint160 currentPrice, , , , ) = UniswapV3Pool(pool).slot0();
      liquidity = LiquidityMath.getLiquidityForAmounts(
        currentPrice,
        sqrtPriceAX96,
        sqrtPriceBX96,
        amount0Desired,
        amount1Desired
      );
    }

    (amount0, amount1) = UniswapV3Pool(pool).mint(
      owner,
      liquidity,
      lowerTick,
      upperTick,
      abi.encode(data)
    );

    if(amount0 < amount0Min || amount1 < amount1Min){
      revert SlippageCheckFailed(amount0, amount1);
    }
  }

  function _swap(
    uint256 amountIn,
    address recipient,
    uint160 sqrtPriceLimitX96,
    SwapCallbackData memory data
  ) internal returns(uint256 amountOut) {
    (address tokenIn, address tokenOut, uint24 tickSpacing) = data.path.getFirstPool().decodeFirstPool();
    bool zeroForOne = tokenIn < tokenOut;
    address pool = getPool(tokenIn, tokenOut, tickSpacing);

    (int256 amount0Delta, int256 amount1Delta) = UniswapV3Pool(pool).swap(
      recipient, 
      zeroForOne, 
      amountIn, 
      sqrtPriceLimitX96 == 0
        ? (zeroForOne
            ? TickMath.MIN_SQRT_RATIO + 1
            : TickMath.MAX_SQRT_RATIO - 1
          )
        : sqrtPriceLimitX96, 
      abi.encode(data)
    );

    return zeroForOne ? uint256(-amount1Delta) : uint256(-amount0Delta);
  }

  function getPool(
    address tokenIn, 
    address tokenOut, 
    uint24 tickSpacing
  ) public view returns (address pool){
    (tokenIn, tokenOut) = tokenIn > tokenOut
      ? (tokenOut, tokenIn)
      : (tokenIn, tokenOut);

    pool = PoolAddress.computeAddress( 
      factory,
      tokenIn,
      tokenOut,
      tickSpacing
    );
  }

  function uniswapV3MintCallback(
      uint256 amount0Owed,
      uint256 amount1Owed,
      bytes calldata data
  ) external {
    MintCallbackData memory extra = abi.decode(data, (MintCallbackData)); 
    
    IERC20(extra.token0).transferFrom(extra.payer, msg.sender, amount0Owed);
    IERC20(extra.token1).transferFrom(extra.payer, msg.sender, amount1Owed);
  }

  function uniswapV3SwapCallback(
      int256 amount0Delta,
      int256 amount1Delta,
      bytes calldata data
  ) external {
    SwapCallbackData memory data_ = abi.decode(data, (SwapCallbackData)); 
    (address tokenIn, address tokenOut, ) = data_.path
      .getFirstPool()
      .decodeFirstPool();
    bool zeroForOne = tokenIn < tokenOut;
    uint256 amount = uint256(zeroForOne ? amount0Delta : amount1Delta);

    if(data_.payer == address(this)){
      IERC20(tokenIn).transfer(msg.sender, amount);
    }else {
      IERC20(tokenIn).transferFrom(data_.payer, msg.sender, amount);
    }
  }

  function uniswapV3FlashCallback(bytes calldata data) external {
    (uint256 amount0, uint256 amount1) = abi.decode(data, (uint256, uint256));
    IERC20 token0 = IERC20(UniswapV3Pool(msg.sender).token0());
    IERC20 token1 = IERC20(UniswapV3Pool(msg.sender).token1());

    token0.transfer(msg.sender, amount0);
    token1.transfer(msg.sender, amount1);
  }
}
