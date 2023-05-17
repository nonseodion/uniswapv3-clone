pragma solidity ^0.8.14;

import { IERC20Minimal as IERC20 } from "./interfaces/IERC20Minimal.sol";
import { IUniswapV3MintCallback } from "./interfaces/IUniswapV3MintCallback.sol";
import { IUniswapV3SwapCallback } from "./interfaces/IUniswapV3SwapCallback.sol";
import { BitMath } from "./libraries/BitMath.sol";
import { Math } from "./libraries/Math.sol";
import { TickMath } from "./libraries/TickMath.sol";
import {SwapMath} from "./libraries/SwapMath.sol";
import { Tick } from "./libraries/Tick.sol";
import { Position } from "./libraries/Position.sol";
import { TickBitMap } from "./libraries/TickBitMap.sol";
import {LiquidityMath} from "./libraries/LiquidityMath.sol";
import "forge-std/console.sol";


contract UniswapV3Pool {
  using Tick for mapping(int24 => Tick.Info);
  using Position for mapping(bytes32 => Position.Info);
  using Position for Position.Info;
  using TickBitMap for mapping(int16 => uint256);
  mapping(int16 => uint256) public tickBitMap;

  int24 constant MIN_TICK = -887272;
  int24 constant MAX_TICK = 887272;

  address immutable token0;
  address immutable token1;

  struct Slot0 {
    // current price in Q notation
    uint160 sqrtPriceX96;
    // current tick
    int24 tick;
  }

  struct SwapState {
    uint256 amountSpecifiedRemaining;
    uint256 amountCalculated;
    uint160 sqrtPriceX96;
    int24 tick;
    uint128 liquidity;
  }

  struct StepState {
    uint160 sqrtPriceStartX96;
    int24 nextTick;
    uint160 sqrtPriceNextX96;
    uint256 amountIn;
    uint256 amountOut;
  }

  Slot0 public slot0;

  uint128 public liquidity;

  mapping(bytes32 => Position.Info) public positions;
  mapping(int24 => Tick.Info) public ticks;

  event Mint(address minter, address owner, int24 lowerTick, int24 upperTick, uint128 amount, uint amount0, uint amount1);
  event Swap(address swapper, address recipient, int256 amount0Delta, int256 amount1Delta, uint160 sqrtPriceX96, uint128 liquidity, int24 tick);

  error InvalidTickRange();
  error ZeroLiquidity();
  error InsufficientInputAmount();
  error NotEnoughLiquidity();

  constructor(address _token0, address _token1, uint160 _currentPrice, int24 _tick){
    token0 = _token0;
    token1 = _token1;

    slot0 = Slot0({tick: _tick, sqrtPriceX96: _currentPrice});
  }

  function mint(
    address owner,
    uint128 amount, 
    int24 lowerTick,
    int24 upperTick,
    bytes calldata data
  ) public returns(uint amount0, uint amount1){
    if(
      lowerTick >= upperTick 
      || lowerTick < MIN_TICK
      || upperTick > MAX_TICK
    ) revert InvalidTickRange();
    // console.log("1");

    if(amount == 0) revert ZeroLiquidity();

    bool flipUpper = ticks.update(upperTick, int128(amount), true);
    bool flipLower = ticks.update(lowerTick, int128(amount), false);
    if(flipUpper) tickBitMap.flipTick(upperTick, 1);
    if(flipLower) tickBitMap.flipTick(lowerTick, 1);
 
    Position.Info storage position = positions.get(owner, lowerTick, upperTick);
    position.update(amount);

    Slot0 memory slot0_ = slot0;
    // amount0 = 0.998976618347425280 ether;
    // amount1 = 5000 ether;
    // console.log("2");
    if(lowerTick > slot0_.tick){
      // console.log("22");
      amount0 = Math.calcAmount0Delta(
        TickMath.getSqrtRatioAtTick(lowerTick), 
        TickMath.getSqrtRatioAtTick(upperTick), 
        amount
      );
    } else if(upperTick > slot0_.tick){
      // console.log("3");
      amount0 = Math.calcAmount0Delta(
        slot0_.sqrtPriceX96, 
        TickMath.getSqrtRatioAtTick(upperTick), 
        amount
      );

      amount1 = Math.calcAmount1Delta(
        slot0_.sqrtPriceX96, 
        TickMath.getSqrtRatioAtTick(lowerTick), 
        amount
      );

      liquidity += amount;
    } else {
      // console.log("4");
      amount1 = Math.calcAmount1Delta(
        TickMath.getSqrtRatioAtTick(lowerTick), 
        TickMath.getSqrtRatioAtTick(upperTick), 
        amount
      );
    }
    {
      uint balance0Before; 
      uint balance1Before;

      if(amount0 > 0) balance0Before = balance0();
      if(amount1 > 0) balance1Before = balance1();
      
      IUniswapV3MintCallback(msg.sender).uniswapV3MintCallback(amount0, amount1, data);
      if(amount0 > 0 && balance0Before + amount0 > balance0())
        revert InsufficientInputAmount();
      if(amount1 > 0 && balance1Before + amount1 > balance1())
        revert InsufficientInputAmount();
    }

    emit Mint(msg.sender, owner, lowerTick, upperTick, amount, amount0, amount1);
  }

  function swap(address recipient, bool zeroForOne, uint amountSpecified, bytes calldata data) external returns(int amount0, int amount1){
    // int24 nextTick = 85184;
    // uint160 nextPrice = 5604469350942327889444743441197;
    uint128 liquidity_ = liquidity;
    SwapState memory swapState = SwapState(
      amountSpecified,
      0,
      slot0.sqrtPriceX96,
      slot0.tick,
      liquidity_
    );
    
    // console.log("before loop");
    while (swapState.amountSpecifiedRemaining > 0){
      // console.log("loopstart");
      StepState memory stepState;
      
      stepState.sqrtPriceStartX96 = swapState.sqrtPriceX96;
      // console.log("1");
      (stepState.nextTick, ) = tickBitMap.nextInitializedTickWithinOneWord(
        swapState.tick,
        1,
        zeroForOne
      );
      // console.log("2");

      stepState.sqrtPriceNextX96 = TickMath.getSqrtRatioAtTick(stepState.nextTick);

      (swapState.sqrtPriceX96, stepState.amountIn, stepState.amountOut) = SwapMath.computeSwapStep(
        swapState.sqrtPriceX96,
        stepState.sqrtPriceNextX96,
        swapState.liquidity,
        swapState.amountSpecifiedRemaining
      );

      if(swapState.sqrtPriceX96 == stepState.sqrtPriceNextX96){
        int128 liquidityDelta = ticks.cross(stepState.nextTick);

        if(zeroForOne) liquidityDelta = -liquidityDelta;

        swapState.liquidity = LiquidityMath.addLiquidity(
          swapState.liquidity,
          liquidityDelta
        );

        if(swapState.liquidity == 0) revert NotEnoughLiquidity();

        swapState.tick = zeroForOne ? stepState.nextTick - 1 : stepState.nextTick;
      }
      else{
        swapState.tick = TickMath.getTickAtSqrtRatio(swapState.sqrtPriceX96);
      }

      // console.log(uint24(swapState.tick), stepState.amountIn);
      // console.log(swapState.amountSpecifiedRemaining, swapState.amountCalculated, stepState.amountOut);
      swapState.amountSpecifiedRemaining -= stepState.amountIn;
      swapState.amountCalculated += stepState.amountOut;
    }


    if(swapState.liquidity != liquidity_) liquidity = swapState.liquidity;

    if(slot0.tick != swapState.tick){
      slot0 = Slot0(swapState.sqrtPriceX96, swapState.tick);
    }

    (amount0, amount1) = zeroForOne 
      ? (
        int256(amountSpecified - swapState.amountSpecifiedRemaining),
        -int256(swapState.amountCalculated)
      )
      : (
        -int256(swapState.amountCalculated),
        int256(amountSpecified - swapState.amountSpecifiedRemaining)
      );

    if(zeroForOne){
      IERC20(token1).transfer(recipient, uint256(-amount1));

      uint balanceBefore = balance0();
      IUniswapV3SwapCallback(msg.sender).uniswapV3SwapCallback(amount0, amount1, data);
      if(balanceBefore + uint256(amount0) > balance0())
        revert InsufficientInputAmount();
    }else {
      IERC20(token0).transfer(recipient, uint256(-amount0));

      uint balanceBefore = balance1();
      IUniswapV3SwapCallback(msg.sender).uniswapV3SwapCallback(amount0, amount1, data);
      if(balanceBefore + uint256(amount1) > balance1())
        revert InsufficientInputAmount();
    }

    emit Swap(
      msg.sender,
      recipient,
      amount0,
      amount1,
      slot0.sqrtPriceX96,
      liquidity,
      slot0.tick
    );
  }

  function balance0() internal view returns (uint) {
    return IERC20(token0).balanceOf(address(this));
  }

  function balance1() internal view returns (uint) {
    return IERC20(token1).balanceOf(address(this));
  }
}