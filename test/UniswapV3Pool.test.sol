pragma solidity ^0.8.14;

import { UniswapV3Pool, TickMath } from "../src/UniswapV3Pool.sol";
import { ERC20Mintable, ERC20 } from "./ERC20Mintable.sol";
import { UniswapV3PoolUtils } from "./UniswapV3Pool.Utils.test.sol";
import { IERC20Minimal as IERC20 } from "../src/interfaces/IERC20Minimal.sol";
import "forge-std/Test.sol";

error NotEnoughLiquidity();

contract UnisapV3PoolTest is UniswapV3PoolUtils{
  ERC20Mintable token0;
  ERC20Mintable token1;
  UniswapV3Pool pool;
  bool shouldTransferInMintCallback;
  bool shouldTransferInSwapCallback;

  function setUp() public{
    token0 = new ERC20Mintable("Ethereum", "Ether", 18);
    token1 = new ERC20Mintable("US Dollars", "USDC", 18);
  }

  function uniswapV3MintCallback(
      uint256 amount0Owed,
      uint256 amount1Owed,
      bytes calldata data
  ) external {
    if(shouldTransferInMintCallback){
      token0.transfer(msg.sender, amount0Owed);
      token1.transfer(msg.sender, amount1Owed);
    }
  }

  function uniswapV3SwapCallback(
      int256 amount0Delta,
      int256 amount1Delta,
      bytes calldata data
  ) external {
    if(shouldTransferInSwapCallback){
      if(amount0Delta > 0) token0.transfer(msg.sender, uint(amount0Delta));
      if(amount1Delta > 0) token1.transfer(msg.sender, uint(amount1Delta));
    }
  }

  function xtestMint() public{
    LiquidityRange[] memory liquidity = new LiquidityRange[](1);
    liquidity[0] = liquidityRange(4545, 5500, 1 ether, 5000 ether, 5000);

    uint256 expectedAmount0 = 0.998995580131581600 ether;
    uint256 expectedAmount1 = 4999.999999999999999999 ether;
    TestCaseParams memory params = TestCaseParams({
        wethBalance: 1 ether,
        usdcBalance: 5000 ether,
        currentPrice: 5000,
        liquidity: liquidity,
        transferInMintCallback: true,
        transferInSwapCallback: true,
        mintLiqudity: true
    });
    
    setupTestCase(params);
    assertMintState(
      ExpectedStateAfterMint({
        pool: pool,
        token0: IERC20(address(token0)),
        token1: IERC20(address(token1)),
        amount0: expectedAmount0,
        amount1: expectedAmount1,
        lowerTick: params.liquidity[0].lowerTick,
        upperTick: params.liquidity[0].upperTick,
        liquidityGross: params.liquidity[0].amount,
        liquidityNet: int128(params.liquidity[0].amount),
        liquidity: params.liquidity[0].amount,
        sqrtPrice: sqrtP(params.currentPrice),
        tick: TickMath.getTickAtSqrtRatio(sqrtP(params.currentPrice))
      })
    );
  }

  function xtestBuyETHOnePriceRange() external{
    LiquidityRange[] memory liquidity = new LiquidityRange[](1);
    liquidity[0] = liquidityRange(4545, 5500, 1 ether, 5000 ether, 5000);

    TestCaseParams memory params = TestCaseParams({
        wethBalance: 1 ether,
        usdcBalance: 5000 ether,
        currentPrice: 5000,
        liquidity: liquidity,
        transferInMintCallback: true,
        transferInSwapCallback: true,
        mintLiqudity: true
    });
    (uint poolBalance0Before, uint poolBalance1Before) = setupTestCase(params);

    uint swapAmount = 42 ether;
    uint expectedAmount = 0.008396874645169943 ether;
    int24 nextTick = 85183;
    uint160 nextPrice = 5604415652688968742392013927525;

    uint userBalance0Before = ERC20(token0).balanceOf(address(this));
    uint userBalance1Before = ERC20(token1).balanceOf(address(this));

    token1.mint(address(this), 42 ether);

    pool.swap(address(this), false, 42 ether, "0x");

    assertSwapState(ExpectedStateAfterSwap({
      pool: pool,
      token0: IERC20(address(token0)),
      token1: IERC20(address(token1)),
      userBalance0: expectedAmount + userBalance0Before,
      userBalance1: userBalance1Before,
      poolBalance0: poolBalance0Before - expectedAmount,
      poolBalance1: poolBalance1Before + swapAmount,
      tick: nextTick,
      price: nextPrice,
      liquidity: params.liquidity[0].amount
    }));
  }

  function xtestBuyETHTwoEqualPriceRanges() external{
    LiquidityRange[] memory liquidity = new LiquidityRange[](2);
    LiquidityRange memory range = liquidityRange(4545, 5500, 1 ether, 5000 ether, 5000);
    liquidity[0] = range;
    liquidity[1] = range;

    TestCaseParams memory params = TestCaseParams({
        wethBalance: 1 ether * 2,
        usdcBalance: 5000 ether * 2,
        currentPrice: 5000,
        liquidity: liquidity,
        transferInMintCallback: true,
        transferInSwapCallback: true,
        mintLiqudity: true
    });
    (uint poolBalance0Before, uint poolBalance1Before) = setupTestCase(params);

    uint swapAmount = 42 ether;
    uint expectedAmount = 0.008398516982770993 ether;
    int24 nextTick = 85179;
    uint160 nextPrice = 5603319704133145322707074461607;

    uint userBalance0Before = ERC20(token0).balanceOf(address(this));
    uint userBalance1Before = ERC20(token1).balanceOf(address(this));

    token1.mint(address(this), 42 ether);

    pool.swap(address(this), false, 42 ether, "0x");

    assertSwapState(ExpectedStateAfterSwap({
      pool: pool,
      token0: IERC20(address(token0)),
      token1: IERC20(address(token1)),
      userBalance0: expectedAmount + userBalance0Before,
      userBalance1: userBalance1Before,
      poolBalance0: poolBalance0Before - expectedAmount,
      poolBalance1: poolBalance1Before + swapAmount,
      tick: nextTick,
      price: nextPrice,
      liquidity: params.liquidity[0].amount * 2
    }));
  }

  function testBuyETHTwoConsecutivePriceRanges() external{
    LiquidityRange[] memory liquidity = new LiquidityRange[](2);
    liquidity[0] = liquidityRange(4545, 5500, 1 ether, 5000 ether, 5000);
    liquidity[1] = liquidityRange(5500, 6250, 1 ether, 5000 ether, 5000);

    TestCaseParams memory params = TestCaseParams({
        wethBalance: 1 ether * 2,
        usdcBalance: 5000 ether * 2,
        currentPrice: 5000,
        liquidity: liquidity,
        transferInMintCallback: true,
        transferInSwapCallback: true,
        mintLiqudity: true
    });
    (uint poolBalance0Before, uint poolBalance1Before) = setupTestCase(params);

    uint swapAmount = 9000 ether;
    uint expectedAmount = 1.820694594787485635 ether;
    int24 nextTick = 87173;
    uint160 nextPrice = 6190476002219365604851182401841;

    uint userBalance0Before = ERC20(token0).balanceOf(address(this));
    uint userBalance1Before = ERC20(token1).balanceOf(address(this));

    token1.mint(address(this), swapAmount);

    pool.swap(address(this), false, swapAmount, "0x");

    assertSwapState(ExpectedStateAfterSwap({
      pool: pool,
      token0: IERC20(address(token0)),
      token1: IERC20(address(token1)),
      userBalance0: expectedAmount + userBalance0Before,
      userBalance1: userBalance1Before,
      poolBalance0: poolBalance0Before - expectedAmount,
      poolBalance1: poolBalance1Before + swapAmount,
      tick: nextTick,
      price: nextPrice,
      liquidity: liquidity[1].amount
    }));
  }

  function xtestBuyUSDCOnePriceRange() external{
    LiquidityRange[] memory liquidity = new LiquidityRange[](1);
    liquidity[0] = liquidityRange(4545, 5500, 1 ether, 5000 ether, 5000);
    
    TestCaseParams memory params = TestCaseParams({
        wethBalance: 1 ether,
        usdcBalance: 5000 ether,
        currentPrice: 5000,
        liquidity: liquidity,
        transferInMintCallback: true,
        transferInSwapCallback: true,
        mintLiqudity: true
    });
    
    (uint poolBalance0Before, uint poolBalance1Before) = setupTestCase(params);
    int24 nextTick = 85163;
    uint160 nextPrice = 5598737223630966236662554421688;
    uint swapAmount = 0.01337 ether;
    uint expectedAmount = 66.807123823853842027 ether;

    uint userBalance0Before = ERC20(token0).balanceOf(address(this));
    token0.mint(address(this),  swapAmount);

    uint userBalance1Before = ERC20(token1).balanceOf(address(this));
    pool.swap(address(this), true, swapAmount, "0x");

    assertSwapState(ExpectedStateAfterSwap({
      pool: pool,
      token0: IERC20(address(token0)),
      token1: IERC20(address(token1)),
      userBalance0: userBalance0Before,
      userBalance1: expectedAmount + userBalance1Before,
      poolBalance0: poolBalance0Before + swapAmount,
      poolBalance1: poolBalance1Before - expectedAmount,
      tick: nextTick,
      price: nextPrice,
      liquidity: params.liquidity[0].amount
    }));
  }

  function xtestBuyUSDCTwoEqualPriceRanges() external{
    LiquidityRange[] memory liquidity = new LiquidityRange[](2);
    LiquidityRange memory range = liquidityRange(4545, 5500, 1 ether, 5000 ether, 5000);
    liquidity[0] = range;
    liquidity[1] = range;
    
    TestCaseParams memory params = TestCaseParams({
        wethBalance: 1 ether * 2,
        usdcBalance: 5000 ether * 2,
        currentPrice: 5000,
        liquidity: liquidity,
        transferInMintCallback: true,
        transferInSwapCallback: true,
        mintLiqudity: true
    });
    
    (uint poolBalance0Before, uint poolBalance1Before) = setupTestCase(params);
    int24 nextTick = 85169;
    uint160 nextPrice = 5600479946976371527693873969480;
    uint swapAmount = 0.01337 ether;
    uint expectedAmount = 66.827918929906650442 ether;

    uint userBalance0Before = ERC20(token0).balanceOf(address(this));
    token0.mint(address(this),  swapAmount);

    uint userBalance1Before = ERC20(token1).balanceOf(address(this));
    pool.swap(address(this), true, swapAmount, "0x");

    assertSwapState(ExpectedStateAfterSwap({
      pool: pool,
      token0: IERC20(address(token0)),
      token1: IERC20(address(token1)),
      userBalance0: userBalance0Before,
      userBalance1: expectedAmount + userBalance1Before,
      poolBalance0: poolBalance0Before + swapAmount,
      poolBalance1: poolBalance1Before - expectedAmount,
      tick: nextTick,
      price: nextPrice,
      liquidity: params.liquidity[0].amount * 2
    }));
  }

  function setupTestCase(TestCaseParams memory params) internal returns (uint amount0, uint amount1){
    token0.mint(address(this), params.wethBalance);
    token1.mint(address(this), params.usdcBalance);

    pool = new UniswapV3Pool(
      address(token0),
      address(token1),
      sqrtP(params.currentPrice),
      TickMath.getTickAtSqrtRatio(sqrtP(params.currentPrice))
    ); 

    shouldTransferInMintCallback = params.transferInMintCallback;
    shouldTransferInSwapCallback = params.transferInSwapCallback;
    


    if(params.mintLiqudity){
      for(uint256 i; i < params.liquidity.length; i++){
        (uint256 amount0_, uint256 amount1_) = pool.mint(
          address(this), 
          params.liquidity[i].amount, 
          params.liquidity[i].lowerTick, 
          params.liquidity[i].upperTick, 
          "0x"
        );

        console.log("range", uint24(params.liquidity[i].lowerTick), uint24(params.liquidity[i].upperTick));
        amount0 += amount0_;
        amount1 += amount1_;
      }
    }
  }
}
