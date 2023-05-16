pragma solidity ^0.8.14;

import { TickMath } from "../src/libraries/TickMath.sol";
import { ABDKMath64x64 } from "../lib/abdk-libraries-solidity/ABDKMath64x64.sol";
import { FixedPoint96 } from "../src/libraries/FixedPoint96.sol";
import { UniswapV3Pool } from "../src/UniswapV3Pool.sol";
import { IERC20Minimal as IERC20 } from "../src/interfaces/IERC20Minimal.sol";
import { TickBitMap } from "../src/libraries/TickBitMap.sol";
import "forge-std/Test.sol";


abstract contract TestUtils is Test {
  function tick(uint256 price) internal pure returns (int24 tick_){
    tick_ = TickMath.getTickAtSqrtRatio(
      uint160(
        uint128(
          ABDKMath64x64.sqrt(int128(int256((price << 64))))
        )
      ) << (FixedPoint96.RESOLUTION - 64)
    );
  }

  function sqrtP(uint256 price) internal pure returns (uint160 sqrtPrice){
    sqrtPrice = TickMath.getSqrtRatioAtTick(tick(price));
  }

  struct ExpectedStateAfterMint {
    UniswapV3Pool pool;
    IERC20 token0;
    IERC20 token1;
    uint256 amount0;
    uint256 amount1;
    int24 lowerTick;
    int24 upperTick;
    uint128 liquidityGross;
    int128 liquidityNet;
    uint128 liquidity;
    uint160 sqrtPrice;
    int24 tick;
  }

  function assertMintState(ExpectedStateAfterMint memory expected) internal {
    assertEq( expected.token0.balanceOf(address(expected.pool)), expected.amount0, "Incorrect token0 deposited amount");
    assertEq( expected.token1.balanceOf(address(expected.pool)), expected.amount1, "Incorrect token1 deposited amount");

    bytes32 positionKey = keccak256(abi.encodePacked(address(this), expected.lowerTick, expected.upperTick));
    uint128 posLiquidity = expected.pool.positions(positionKey);

    assertEq(posLiquidity, expected.liquidity, "Incorrect position liquidity");

    (bool tickInitialized, uint128 liquidityGross, int128 liquidityNet) = expected.pool.ticks(expected.lowerTick);
    assertTrue(tickInitialized, "Lower Tick not initialized");
    assertEq(liquidityGross, expected.liquidityGross, "Incorrect Lower Tick Gross liquidity");
    assertEq(liquidityNet, expected.liquidityNet, "Incorrect Lower Tick Net liquidity");

    (tickInitialized, liquidityGross, liquidityNet) = expected.pool.ticks(expected.upperTick);
    assertTrue(tickInitialized, "Upper Tick not initialized");
    assertEq(liquidityGross, expected.liquidityGross, "Incorrect Upper Tick liquidity");
    assertEq(liquidityNet, -expected.liquidityNet, "Incorrect Upper Tick Net liquidity");

    assertTrue(tickInBitMap(expected.pool, expected.lowerTick), "Lower tick not initialized in bitmap");
    assertTrue(tickInBitMap(expected.pool, expected.upperTick), "Upper tick not initialized in bitmap");

    (uint160 sqrtPrice96, int24 tick_) = expected.pool.slot0();
    assertEq(sqrtPrice96, expected.sqrtPrice, "Incorrect current price");
    assertEq(tick_, expected.tick, "Current tick is incorrect");

    uint128 liquidity = expected.pool.liquidity();
    assertEq(liquidity, expected.liquidity, "Incorrect pool liquidity");
  }

  struct ExpectedStateAfterSwap {
    UniswapV3Pool pool;
    IERC20 token0;
    IERC20 token1;
    uint256 userBalance0;
    uint256 userBalance1;
    uint256 poolBalance0;
    uint256 poolBalance1;
    int24 tick;
    uint160 price;
    uint128 liquidity;
  }

  function assertSwapState(ExpectedStateAfterSwap memory expected) internal {
    
    // check amount sent and transferred by this contract
    assertEq(expected.token1.balanceOf(address(this)), expected.userBalance1, "Invalid user token1 balance");
    assertEq(expected.token0.balanceOf(address(this)), expected.userBalance0, "Invalid user token0 balance");

    // check amount sent and transferred by this contract
    assertEq(expected.token1.balanceOf(address(expected.pool)), expected.poolBalance1, "Invalid pool token1 balance");
    assertEq(expected.token0.balanceOf(address(expected.pool)), expected.poolBalance0, "Invalid pool token0 balance");

    (uint160 price, int24 tick_) = expected.pool.slot0();
    uint128 liquidity = expected.pool.liquidity();

    // check pool state
    assertEq(price, expected.price, "New price is incorrect");
    assertEq(tick_, expected.tick, "New Tick is incorrect");
    assertEq(liquidity, expected.liquidity, "New liquidity is incorrect");
  }


  function tickInBitMap(UniswapV3Pool pool, int24 tick_) internal view returns (bool){
    (int16 wordPos, uint8 bitPos) = TickBitMap.position(tick_);
    uint256 bitMap = pool.tickBitMap(wordPos);
    uint256 onlyTick = uint256(1) << bitPos;

    return (onlyTick & bitMap != 0);
  }
}