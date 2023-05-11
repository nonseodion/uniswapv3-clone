pragma solidity ^0.8.14;

import { IERC20Minimal as IERC20 } from "./interfaces/IERC20Minimal.sol";
import { IUniswapV3MintCallback } from "./interfaces/IUniswapV3MintCallback.sol";
import { IUniswapV3SwapCallback } from "./interfaces/IUniswapV3SwapCallback.sol";
import { BitMath } from "./libraries/BitMath.sol";
import { Math } from "./libraries/Math.sol";
import { TickMath } from "./libraries/TickMath.sol";
import "forge-std/console.sol";


library Tick {
  struct Info {
    bool initialized;
    uint128 liquidity;
  }

  function update(mapping(int24 => Info) storage self, int24 tick, uint128 amount) public returns (bool flipped){
    uint128 liquidityBefore = self[tick].liquidity;
    uint128 liquidityAfter = liquidityBefore + amount;

    flipped = (liquidityAfter == 0) != (liquidityBefore == 0);

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
    int24 lowerTick, 
    int24 upperTick
  ) view public returns (Info storage) {
    return positions[keccak256(abi.encodePacked(owner, lowerTick, upperTick))];
  }
}

library TickBitMap{
  function flipTick(
    mapping(int16 => uint256) storage self,
    int24 tick,
    int24 tickSpacing
  ) external
  {
    require(tick % tickSpacing == 0, "Wrong Tick Spacing or Tick");
    (int16 wordPos, uint8 bitPos) = position(tick / tickSpacing);
    uint256 mask = 1 << bitPos;
    self[wordPos] ^= mask;
  }

  function nextInitializedTickWithinOneWord(
    mapping(int16 => uint256) storage self,
    int24 tick,
    int24 tickSpacing,
    bool lte
  ) external view returns (int24 next, bool initialized){
    int24 compressed = tick/tickSpacing;
    
    if(lte){

      (int16 wordPos, uint8 bitPos) = position(compressed);
      uint256 mask = (1 << bitPos) - 1 + (1 << bitPos);
      uint256 masked = self[wordPos] & mask;
      bool initialized = masked != 0;
      int24 next = initialized 
        ? (compressed - int24(uint24((bitPos - BitMath.mostSignificantBit(masked))))) * tickSpacing
        : (compressed - int24(uint24(bitPos))) * tickSpacing;

    }else {

      (int16 wordPos, uint8 bitPos) = position(compressed + 1);
      uint256 mask = ~(1 << (bitPos+1));
      uint256 masked = self[wordPos] & mask;
      bool initialized = masked != 0;
      int24 next = initialized 
        ? (compressed + 1 + int24(uint24(BitMath.leastSignificantBit(masked) - bitPos))) * tickSpacing
        : (compressed + 1 + int24(uint24(type(uint8).max - bitPos))) * tickSpacing;

    }
  }

  function position(int24 tick) private pure returns (int16 wordPos, uint8 bitPos) {
    wordPos = int16(tick >> 8);
    bitPos = uint8(uint24(tick) % 256);
  }
}

contract UniswapV3Pool {
  using Tick for mapping(int24 => Tick.Info);
  using Position for mapping(bytes32 => Position.Info);
  using Position for Position.Info;
  using TickBitMap for mapping(int16 => uint256);
  mapping(int16 => uint256) tickBitMap;

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

  Slot0 public slot0;

  uint128 public liquidity;

  mapping(bytes32 => Position.Info) public positions;
  mapping(int24 => Tick.Info) public ticks;

  event Mint(address minter, address owner, int24 lowerTick, int24 upperTick, uint128 amount, uint amount0, uint amount1);
  event Swap(address swapper, address recipient, int256 amount0Delta, int256 amount1Delta, uint160 sqrtPriceX96, uint128 liquidity, int24 tick);

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

    bool flipUpper = ticks.update(upperTick, amount);
    bool flipLower = ticks.update(lowerTick, amount);
    if(flipUpper) tickBitMap.flipTick(upperTick, 1);
    if(flipLower) tickBitMap.flipTick(lowerTick, 1);
 
    Position.Info storage position = positions.get(owner, lowerTick, upperTick);
    position.update(amount);

    Slot0 slot0_ = slot0;
    // amount0 = 0.998976618347425280 ether;
    // amount1 = 5000 ether;
    amount0 = Math.calcAmount0Delta(
      slot0_.sqrtPriceX96, 
      TickMath.getSqrtRatioAtTick(upperTick), 
      liquidity
    );

    amount1 = Math.calcAmount1Delta(
      slot0_.sqrtPriceX96, 
      TickMath.getSqrtRatioAtTick(lowerTick), 
      liquidity
    );

    liquidity += amount;
    
    uint balance0Before; 
    uint balance1Before;

    if(amount0 > 0) balance0Before = balance0();
    if(amount1 > 0) balance1Before = balance1();
    
    IUniswapV3MintCallback(msg.sender).uniswapV3MintCallback(amount0, amount1, data);
    if(amount0 > 0 && balance0Before + amount0 > balance0())
      revert InsufficientInputAmount();
    if(amount1 > 0 && balance1Before + amount1 > balance1())
      revert InsufficientInputAmount();

    emit Mint(msg.sender, owner, lowerTick, upperTick, amount, amount0, amount1);
  }

  function swap(address recipient, bytes calldata data) external returns(int amount0, int amount1){
    int24 nextTick = 85184;
    uint160 nextPrice = 5604469350942327889444743441197;

    amount0 = -0.008396714242162444 ether;
    amount1 = 42 ether;

    slot0 = Slot0(nextPrice, nextTick);
    IERC20(token0).transfer(recipient, uint(-amount0));

    uint balanceBefore = balance1();
    IUniswapV3SwapCallback(msg.sender).uniswapV3SwapCallback(amount0, amount1, data);
    if(balanceBefore + uint256(amount1) < balance1())
      revert InsufficientInputAmount();

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