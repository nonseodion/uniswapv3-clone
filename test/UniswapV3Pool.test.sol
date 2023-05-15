pragma solidity ^0.8.14;

import { UniswapV3Pool } from "../src/UniswapV3Pool.sol";
import { ERC20Mintable, ERC20 } from "./ERC20Mintable.sol";
import "forge-std/Test.sol";

error NotEnoughLiquidity();

contract UnisapV3PoolTest is Test{
  ERC20Mintable token0;
  ERC20Mintable token1;
  UniswapV3Pool pool;
  bool shouldTransferInCallback;

  struct TestCaseParams {
    uint wethBalance;
    uint usdcBalance;
    int24 currentTick;
    int24 lowerTick;
    int24 upperTick;
    uint128 liquidity;
    uint128 currentSqrtP;
    bool shouldTransferInCallback;
    bool mintLiqudity;
  }

  function setUp() public{
    token0 = new ERC20Mintable("Ethereum", "Ether", 18);
    token1 = new ERC20Mintable("US Dollars", "USDC", 18);
  }

  function uniswapV3MintCallback(
      uint256 amount0Owed,
      uint256 amount1Owed,
      bytes calldata data
  ) external {
    if(shouldTransferInCallback){
      token0.transfer(msg.sender, amount0Owed);
      token1.transfer(msg.sender, amount1Owed);
    }
  }

  function uniswapV3SwapCallback(
      int256 amount0Delta,
      int256 amount1Delta,
      bytes calldata data
  ) external {
    if(shouldTransferInCallback){
      if(amount0Delta > 0) token0.transfer(msg.sender, uint(amount0Delta));
      if(amount1Delta > 0) token1.transfer(msg.sender, uint(amount1Delta));
    }
  }

  function xtestMintSuccess() public{
    uint256 expectedAmount0 = 0.998628802115141959 ether;
    uint256 expectedAmount1 = 5000.209190920489524100 ether;
    TestCaseParams memory params = TestCaseParams({
        wethBalance: 1 ether,
        usdcBalance: 5001 ether,
        currentTick: 85176,
        lowerTick: 84222,
        upperTick: 86129,
        liquidity: 1517882343751509868544,
        currentSqrtP: 5602277097478614198912276234240,
        shouldTransferInCallback: true,
        mintLiqudity: true
    });
    
    (uint amount0, uint amount1) = setupTestCase(params);
    assertEq( amount0, expectedAmount0, "Incorrect token0 deposited amount");
    assertEq( amount1, expectedAmount1, "Incorrect token1 deposited amount");

    bytes32 positionKey = keccak256(abi.encodePacked(address(this), params.lowerTick, params.upperTick));
    uint128 posLiquidity = pool.positions(positionKey);

    assertEq(posLiquidity, params.liquidity, "Incorrect position liquidity");

    (bool tickInitialized, uint128 tickLiquidity, ) = pool.ticks(params.lowerTick);
    assertTrue(tickInitialized, "Lower Tick not initialized");
    assertEq(tickLiquidity, params.liquidity, "Incorrect Lower Tick liquidity");

    (tickInitialized, tickLiquidity, ) = pool.ticks(params.lowerTick);
    assertTrue(tickInitialized, "Lower Tick not initialized");
    assertEq(tickLiquidity, params.liquidity, "Incorrect Upper Tick liquidity");

    (uint160 sqrtPrice96, int24 tick) = pool.slot0();
    assertEq(sqrtPrice96, params.currentSqrtP, "Incorrect current price");
    assertEq(tick, params.currentTick, "Current tick is incorrect");

    uint128 liquidity = pool.liquidity();
    assertEq(liquidity, params.liquidity, "Incorrect pool liquidity");
  }

  function xtestSwapOneForZeroSuccess() external{
    
    TestCaseParams memory params = TestCaseParams({
        wethBalance: 1 ether,
        usdcBalance: 5001 ether,
        currentTick: 85176,
        lowerTick: 84222,
        upperTick: 86129,
        liquidity: 1517882343751509868544,
        currentSqrtP: 5602277097478614198912276234240,
        shouldTransferInCallback: true,
        mintLiqudity: true
    });
    (uint poolBalance0Before, uint poolBalance1Before) = setupTestCase(params);

    uint userBalance1Before = ERC20(token1).balanceOf(address(this));
    token1.mint(address(this), 42 ether);
    int24 nextTick = 85184;
    uint160 nextPrice = 5604469350942327889444743441197;

    shouldTransferInCallback = true;
    uint userBalance0Before = ERC20(token0).balanceOf(address(this));
    (int amount0, int amount1) = pool.swap(address(this), false, 42 ether, "0x");
    shouldTransferInCallback = false;
    (uint160 price, int24 currentTick) = pool.slot0();

    // check for swap function return values
    assertEq(amount0, -0.008396714242162445 ether, "Invalid ETH out");
    assertEq(amount1, 42 ether, "Invalid USDC in");

    // check amount sent and transferred by this contract
    assertEq(ERC20(token1).balanceOf(address(this)), userBalance1Before, "Invalid USDC transferred");
    assertEq(ERC20(token0).balanceOf(address(this)), 0.008396714242162445 ether + userBalance0Before, "Invalid ETH transferred");

    // check amount sent and transferred by this contract
    assertEq(int(ERC20(token1).balanceOf(address(pool))), (int(poolBalance1Before) + amount1), "Invalid USDC transferred to pool");
    assertEq(int(ERC20(token0).balanceOf(address(pool))), int(poolBalance0Before) + amount0, "Invalid ETH transferred out of pool");

    // check pool state
    assertEq(price, nextPrice, "New price is incorrect");
    assertEq(currentTick, nextTick, "New Tick is incorrect");
  }

  function xtestSwapZeroForOneSuccess() external{
    
    TestCaseParams memory params = TestCaseParams({
        wethBalance: 1 ether,
        usdcBalance: 5001 ether,
        currentTick: 85176,
        lowerTick: 84222,
        upperTick: 86129,
        liquidity: 1517882343751509868544,
        currentSqrtP: 5602277097478614198912276234240,
        shouldTransferInCallback: true,
        mintLiqudity: true
    });
    (uint poolBalance0Before, uint poolBalance1Before) = setupTestCase(params);

    uint userBalance0Before = ERC20(token0).balanceOf(address(this));
    token0.mint(address(this), 0.01 ether);
    int24 nextTick = 85166;
    uint160 nextPrice = 5599668487149915539000862441472;

    shouldTransferInCallback = true;
    uint userBalance1Before = ERC20(token1).balanceOf(address(this));
    (int amount0, int amount1) = pool.swap(address(this), true, 0.01 ether, "0x");
    shouldTransferInCallback = false;
    (uint160 price, int24 currentTick) = pool.slot0();

    // check for swap function return values
    assertEq(amount0, 0.01 ether, "Invalid ETH in");
    assertEq(amount1, -49.97671830325024 ether, "Invalid USDC out");

    // check amount sent and transferred by this contract
    assertEq(ERC20(token1).balanceOf(address(this)), userBalance1Before + 49.97671830325024 ether, "Invalid USDC transferred");
    assertEq(ERC20(token0).balanceOf(address(this)), userBalance0Before, "Invalid ETH transferred");

    // check amount sent and transferred by this contract
    assertEq(int(ERC20(token1).balanceOf(address(pool))), (int(poolBalance1Before) + amount1), "Invalid USDC transferred out of pool");
    assertEq(int(ERC20(token0).balanceOf(address(pool))), int(poolBalance0Before) + amount0, "Invalid ETH transferred into pool");

    // check pool state
    assertEq(price, nextPrice, "New price is incorrect");
    assertEq(currentTick, nextTick, "New Tick is incorrect");
  }

  // test/UniswapV3Pool.t.sol
  function testSwapBuyEthNotEnoughLiquidity() public {

    uint256 swapAmount = 5300 ether;
    TestCaseParams memory params = TestCaseParams({
        wethBalance: 1 ether,
        usdcBalance: 5001 ether,
        currentTick: 85176,
        lowerTick: 84222,
        upperTick: 86129,
        liquidity: 1517882343751509868544,
        currentSqrtP: 5602277097478614198912276234240,
        shouldTransferInCallback: true,
        mintLiqudity: true
    });
    setupTestCase(params);

    token1.mint(address(this), swapAmount);

    vm.expectRevert(NotEnoughLiquidity.selector);
    pool.swap(address(this), false, swapAmount, "0x");
  }

  function setupTestCase(TestCaseParams memory params) internal returns (uint amount0, uint amount1){
    token0.mint(address(this), params.wethBalance);
    token1.mint(address(this), params.usdcBalance);

    pool = new UniswapV3Pool(
      address(token0),
      address(token1),
      params.currentSqrtP,
      params.currentTick
    ); 

    shouldTransferInCallback = params.shouldTransferInCallback;

    if(params.mintLiqudity){
      (amount0, amount1) = pool.mint(address(this), params.liquidity, params.lowerTick, params.upperTick, "0x");
    }

    if(shouldTransferInCallback != false) shouldTransferInCallback = false;
  }
}
