pragma solidity ^0.8.14;

import { IERC20Minimal as IERC20 } from "./interfaces/IERC20Minimal.sol";
import { IUniswapV3MintCallback } from "./interfaces/IUniswapV3MintCallback.sol";

library Tick {
  struct Info {
    bool initialized;
    uint128 liquidity;
  }

  function update(mapping(int24 => Info) storage self, int24 tick, uint128 amount) public{
    uint128 liquidityBefore = self[tick].liquidity;
    uint128 liquidityAfter = liquidityBefore + amount;

    if(liquidityBefore == 0){
      self[tick].initialized = true;
    }

    self[tick].liquidity = liquidityAfter;
  }
}

library Position {
  struct Info {
    uint128 liquidity;
  }

  function update(Info storage self, uint128 amount) public {
    self.liquidity += amount;
  }

  function get(
    mapping(bytes32 => Info) storage positions, 
    address owner, 
    int24 upperTick, 
    int24 lowerTick
  ) view public returns (Info storage) {
    return positions[keccak256(abi.encode(owner, upperTick, lowerTick))];
  }
}

contract UniswapV3Pool {
  using Tick for mapping(int24 => Tick.Info);
  using Position for mapping(bytes32 => Position.Info);
  using Position for Position.Info;

  int24 constant MIN_TICK = -887272;
  int24 constant MAX_TICK = -MIN_TICK;

  address immutable token0;
  address immutable token1;

  struct Slot0 {
    // current price in Q notation
    uint160 sqrtPriceX96;
    // current tick
    int24 tick;
  }

  Slot0 public slot0;

  uint128 public liquidity;

  mapping(bytes32 => Position.Info) public positions;
  mapping(int24 => Tick.Info) public ticks;

  event Mint(address minter, address owner, int24 lowerTick, int24 upperTick, uint128 amount, uint128 amount0, uint128 amount1);

  error InvalidTickRange();
  error ZeroLiquidity();
  error InsufficientInputAmount();

  constructor(address _token0, address _token1, uint160 _currentPrice, int24 _tick){
    token0 = _token0;
    token1 = _token1;

    slot0 = Slot0({tick: _tick, sqrtPriceX96: _currentPrice});
  }

  function mint(
    address owner,
    uint128 amount, 
    int24 upperTick, 
    int24 lowerTick
  ) public {
    if(
      lowerTick >= upperTick 
      || lowerTick < MIN_TICK
      || upperTick > MAX_TICK
    ) revert InvalidTickRange();

    if(amount == 0) revert ZeroLiquidity();

    ticks.update(upperTick, amount);
    ticks.update(lowerTick, amount);

    Position.Info storage position = positions.get(owner, upperTick, lowerTick);
    position.update(amount);
    
    liquidity += amount;

    uint128 amount0 = 0.998976618347425280 ether;
    uint128 amount1 = 5000 ether;
    uint balance0Before; 
    uint balance1Before;

    if(amount0 > 0) balance0Before = balance0();
    if(amount1 > 0) balance1Before = balance1();

    IUniswapV3MintCallback(msg.sender).uniswapV3MintCallback(amount0, amount1, "0x");

    if(amount0 > 0 && balance0Before + amount0 > balance0())
      revert InsufficientInputAmount();
    if(amount1 > 0 && balance1Before + amount1 > balance1())
      revert InsufficientInputAmount();

    emit Mint(msg.sender, owner, lowerTick, upperTick, amount, amount0, amount1);
  }

  function balance0() internal view returns (uint) {
    return IERC20(token0).balanceOf(address(this));
  }

  function balance1() internal view returns (uint) {
    return IERC20(token1).balanceOf(address(this));
  }
}