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
import { IUniswapV3FlashCallback } from "./interfaces/IUniswapV3FlashCallback.sol";
import { IUniswapV3PoolDeployer } from "./interfaces/IUniswapV3PoolDeployer.sol";
import { mulDiv } from "prb-math/Common.sol";
import { FixedPoint128 } from "./libraries/FixedPoint128.sol";
import "forge-std/console.sol";


contract UniswapV3Pool {
  using Tick for mapping(int24 => Tick.Info);
  using Position for mapping(bytes32 => Position.Info);
  using Position for Position.Info;
  using TickBitMap for mapping(int16 => uint256);
  mapping(int16 => uint256) public tickBitMap;

  int24 constant MIN_TICK = -887272;
  int24 constant MAX_TICK = 887272;

  address public immutable token0;
  address public immutable token1;

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
    uint256 feeGrowthGlobalX128;
  }

  struct StepState {
    uint160 sqrtPriceStartX96;
    int24 nextTick;
    uint160 sqrtPriceNextX96;
    uint256 amountIn;
    uint256 amountOut;
    uint256 feeAmount;
  }

  struct ModifyPositionParams {
    address owner;
    int24 lowerTick;
    int24 upperTick;
    int128 liquidityDelta;
  }

  Slot0 public slot0;

  uint128 public liquidity;
  uint24 public fee;
  uint256 public feeGrowthGlobal0X128;
  uint256 public feeGrowthGlobal1X128;

  mapping(bytes32 => Position.Info) public positions;
  mapping(int24 => Tick.Info) public ticks;

  event Mint(address minter, address owner, int24 lowerTick, int24 upperTick, uint128 amount, uint amount0, uint amount1);
  event Collect(address owner, address recipient, int24 lowerTick, int24 upperTick, uint amount0, uint amount1);
  event Burn(address owner, int24 lowerTick, int24 upperTick, uint128 amount, uint amount0, uint amount1);
  event Swap(address swapper, address recipient, int256 amount0Delta, int256 amount1Delta, uint160 sqrtPriceX96, uint128 liquidity, int24 tick);
  event Flash(address borrower, uint256 amount0, uint256 amount1);

  error InvalidTickRange();
  error ZeroLiquidity();
  error InsufficientInputAmount();
  error NotEnoughLiquidity();
  error InvalidPriceLimit();

  constructor(){
    (, token0, token1, ) = IUniswapV3PoolDeployer(msg.sender).parameters(); 
  }

  function initialize(uint160 sqrtPriceX96) public {
    int24 tick = TickMath.getTickAtSqrtRatio(sqrtPriceX96);

    slot0 = Slot0({tick: tick, sqrtPriceX96: sqrtPriceX96});
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
    if(amount == 0) revert ZeroLiquidity();

    ( , int256 amount0_, int256 amount1_) = _modifyPosition(ModifyPositionParams({
      owner: owner,
      lowerTick: lowerTick,
      upperTick: upperTick,
      liquidityDelta: int128(amount)
    }));

    amount0 = uint256(amount0_);
    amount1 = uint256(amount1_);

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

  function burn(
    uint128 amount, 
    int24 lowerTick, 
    int24 upperTick
  ) public returns(int256 amount0, int256 amount1){
    Position.Info storage position;
    //todo: check the liquidityDelta
    (position, amount0, amount1) = _modifyPosition(ModifyPositionParams({
      owner: msg.sender,
      lowerTick: lowerTick,
      upperTick: upperTick,
      liquidityDelta: -int128(amount)
    }));

    if(amount0 < 0 || amount1 < 0){
      position.tokensOwed0 += uint256(-amount0);
      position.tokensOwed1 += uint256(-amount1);
    }

    emit Burn(msg.sender, lowerTick, upperTick, amount, uint256(-amount0), uint256(-amount1));
  }

  function collect(
    address recipient,
    int24 lowerTick,
    int24 upperTick,
    uint256 amount0Requested,
    uint256 amount1Requested
  ) public returns(uint128 amount0, uint128 amount1){
    Position.Info storage position = Position.get(positions, msg.sender, lowerTick, upperTick);
    amount0 = amount0Requested > position.tokensOwed0 ? position.tokensOwed0 : amount0Requested;
    amount1 = amount1Requested > position.tokensOwed1 ? position.tokensOwed1 : amount1Requested;
    
    position.tokensOwed0 -= amount0;
    position.tokensOwed1 -= amount1;

    if(amount0 > 0){
      IERC20(token0).transfer(recipient, amount0);
    }

    if(amount1 > 0){
      IERC20(token1).transfer(recipient, amount1);
    }

    emit Collect(msg.sender, recipient, lowerTick, upperTick, amount0, amount1);
  }

  function swap(
    address recipient, 
    bool zeroForOne, 
    uint256 amountSpecified, 
    uint160 sqrtPriceLimit,
    bytes calldata data
  ) external returns(int amount0, int amount1){
    if(zeroForOne 
        ? slot0.sqrtPriceX96 < sqrtPriceLimit || sqrtPriceLimit < TickMath.MIN_SQRT_RATIO
        : slot0.sqrtPriceX96 > sqrtPriceLimit || sqrtPriceLimit > TickMath.MAX_SQRT_RATIO
      ) revert InvalidPriceLimit();

    // int24 nextTick = 85184;
    // uint160 nextPrice = 5604469350942327889444743441197;
    uint128 liquidity_ = liquidity;
    SwapState memory swapState = SwapState(
      amountSpecified,
      0,
      slot0.sqrtPriceX96,
      slot0.tick,
      liquidity_,
      zeroForOne ? feeGrowthGlobal0X128 : feeGrowthGlobal1X128
    );
    

    while (
      swapState.amountSpecifiedRemaining > 0
      && swapState.sqrtPriceX96 != sqrtPriceLimit  
    ){
      StepState memory stepState;
      stepState.sqrtPriceStartX96 = swapState.sqrtPriceX96;
      (stepState.nextTick, ) = tickBitMap.nextInitializedTickWithinOneWord(
        swapState.tick,
        1,
        zeroForOne
      );

      stepState.sqrtPriceNextX96 = TickMath.getSqrtRatioAtTick(stepState.nextTick);

      (swapState.sqrtPriceX96, stepState.amountIn, stepState.amountOut, stepState.feeAmount) = SwapMath.computeSwapStep(
        swapState.sqrtPriceX96,
        (
          (
            zeroForOne 
              ? stepState.sqrtPriceNextX96 < sqrtPriceLimit
              : stepState.sqrtPriceNextX96 > sqrtPriceLimit
          ) 
          ? sqrtPriceLimit
          : stepState.sqrtPriceNextX96
        ),
        swapState.liquidity,
        swapState.amountSpecifiedRemaining,
        fee
      );

      swapState.feeGrowthGlobalX128 += mulDiv(
        stepState.feeAmount, 
        FixedPoint128.Q128,
        swapState.liquidity
      );

      if(swapState.sqrtPriceX96 == stepState.sqrtPriceNextX96){
        int128 liquidityDelta = ticks.cross(
          stepState.nextTick,
          zeroForOne ? swapState.feeGrowthGlobalX128 : feeGrowthGlobal1X128,
          zeroForOne ? feeGrowthGlobal0X128 : swapState.feeGrowthGlobalX128
        );

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

      feeGrowthGlobal0X128 = swapState.feeGrowthGlobalX128;
    }else {
      IERC20(token0).transfer(recipient, uint256(-amount0));

      uint balanceBefore = balance1();
      IUniswapV3SwapCallback(msg.sender).uniswapV3SwapCallback(amount0, amount1, data);
      if(balanceBefore + uint256(amount1) > balance1())
        revert InsufficientInputAmount();

      feeGrowthGlobal1X128 = swapState.feeGrowthGlobalX128;
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

  function flash(
    uint256 amount0,
    uint256 amount1,
    bytes calldata data
  ) external {
    uint256 balance0Before = balance0();
    uint256 balance1Before = balance1();

    if(amount0 > 0) IERC20(token0).transfer(msg.sender, amount0);
    if(amount1 > 0) IERC20(token1).transfer(msg.sender, amount1);

    IUniswapV3FlashCallback(msg.sender).uniswapV3FlashCallback(data);

    require(balance0Before <= balance0(), "Flash amount0 not repaid");
    require(balance1Before <= balance1(), "Flash amount1 not repaid");

    emit Flash(msg.sender, amount0, amount1);
  }

  function balance0() internal view returns (uint) {
    return IERC20(token0).balanceOf(address(this));
  }

  function balance1() internal view returns (uint) {
    return IERC20(token1).balanceOf(address(this));
  }

  function _modifyPosition( ModifyPositionParams memory params) internal returns (
    Position.Info storage position,
    int256 amount0, 
    int256 amount1
  ) {
    Slot0 memory slot0_;

    bool flipUpper = ticks.update(params.upperTick, slot0_.tick, params.liquidityDelta, feeGrowthGlobal0X128, feeGrowthGlobal1X128, true);
    bool flipLower = ticks.update(params.lowerTick, slot0_.tick, params.liquidityDelta, feeGrowthGlobal0X128, feeGrowthGlobal1X128, false);
    if(flipUpper) tickBitMap.flipTick(params.upperTick, 1);
    if(flipLower) tickBitMap.flipTick(params.lowerTick, 1);

    (uint256 feeGrowthInside0X128, uint256 feeGrowthInside1X128) = Tick.getFreeGrowthInside(
      ticks, params.lowerTick, params.upperTick, slot0_.tick, feeGrowthGlobal0X128, feeGrowthGlobal1X128
    );

    position = positions.get(params.owner, params.lowerTick, params.upperTick);
    position.update(
      params.liquidityDelta,
      feeGrowthInside0X128,
      feeGrowthInside1X128 
    );

    if(params.lowerTick > slot0_.tick){

      amount0 = Math.calcAmount0Delta(
        TickMath.getSqrtRatioAtTick(params.lowerTick), 
        TickMath.getSqrtRatioAtTick(params.upperTick), 
        params.liquidityDelta
      );
    } else if(params.upperTick > slot0_.tick){

      amount0 = Math.calcAmount0Delta(
        slot0_.sqrtPriceX96, 
        TickMath.getSqrtRatioAtTick(params.upperTick), 
        uint128(params.liquidityDelta)
      );

      amount1 = Math.calcAmount1Delta(
        slot0_.sqrtPriceX96, 
        TickMath.getSqrtRatioAtTick(params.lowerTick), 
        uint128(params.liquidityDelta)
      );

      liquidity = LiquidityMath.addLiquidity(liquidity, params.liquidityDelta) ;
    } else {

      amount1 = Math.calcAmount1Delta(
        TickMath.getSqrtRatioAtTick(params.lowerTick), 
        TickMath.getSqrtRatioAtTick(params.upperTick), 
        uint128(params.liquidityDelta)
      );
    }
  }
}