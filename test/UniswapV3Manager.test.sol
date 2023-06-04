pragma solidity ^0.8.14;

import { TestUtils } from "./TestUtils.sol";
import { UniswapV3PoolUtils } from "./UniswapV3Pool.Utils.test.sol";
import { UniswapV3Pool } from "../src/UniswapV3Pool.sol";
import { UniswapV3Factory } from "../src/UniswapV3Factory.sol";
import { UniswapV3Manager } from "../src/UniswapV3Manager.sol";
import { ERC20Mintable, ERC20 } from "./ERC20Mintable.sol";
import { ABDKMath64x64 } from "../lib/abdk-libraries-solidity/ABDKMath64x64.sol";
import { LiquidityMath } from "../src/libraries/LiquidityMath.sol";
import { TickMath } from "../src/libraries/TickMath.sol";
import "forge-std/Test.sol";

contract UniswapV3ManagerTest is UniswapV3PoolUtils{
  struct TokenTestProps {
    uint256 mintAmount;
    uint160 sqrtPriceX96;
    uint160 lowerPrice;
    uint160 upperPrice;
  }

  struct ManagerTestParams {
    address token0;
    address token1;
    uint256 token0Balance;
    uint256 token1Balance;
    uint160 currentPrice;
    LiquidityRange[] liquidity;
    bool mintLiqudity;
    uint24 fee;
  }

  UniswapV3Factory factory;
  UniswapV3Manager manager;
  address WETH;
  address USDC;
  address UNI;

  mapping(uint => mapping(address => TokenTestProps)) tokenProps;

  ManagerTestParams params;

  function setUp() public{
    USDC = address(new ERC20Mintable("US Dollars", "USDC", 18));
    WETH = address(new ERC20Mintable("Ethereum", "Ether", 18));
    UNI = address(new ERC20Mintable("Bitcoin", "UNI", 18));

    factory = new UniswapV3Factory();
    manager = new UniswapV3Manager(address(factory));

    ERC20(USDC).approve(address(manager), type(uint256).max);
    ERC20(WETH).approve(address(manager), type(uint256).max);
    ERC20(UNI).approve(address(manager), type(uint256).max);

    tokenProps[0][WETH] = TokenTestProps({
      mintAmount: 1 ether,
      sqrtPriceX96: sqrtP(5000),
      lowerPrice: sqrtP(4545),
      upperPrice: sqrtP(5500)
    });
    tokenProps[0][USDC] = TokenTestProps({
      mintAmount: 5000 ether,
      sqrtPriceX96: sqrtP(1, 5000),
      lowerPrice: sqrtP(1, 5500),
      upperPrice: sqrtP(1, 4545)
    });

    tokenProps[1][UNI] = TokenTestProps({
      mintAmount: 100 ether,
      sqrtPriceX96: sqrtP(1, 10),
      lowerPrice: sqrtP(1, 13),
      upperPrice: sqrtP(1, 7)
    });
    tokenProps[1][WETH] = TokenTestProps({
      mintAmount: 10 ether,
      sqrtPriceX96: sqrtP(10),
      lowerPrice: sqrtP(7),
      upperPrice: sqrtP(13)
    }); 

  }

  // @dev swap ETH for UNI ETH=>USDC->UNI
  function testMultiPoolSwap() public {
    address[2][2] memory pools = [
      WETH < USDC ? [WETH, USDC] : [USDC, WETH], 
      WETH < UNI ? [WETH, UNI] : [UNI, WETH]
    ];

    for(uint i = 0; i < 2; i++ ){
      LiquidityRange[] memory liquidity = new LiquidityRange[](1);
      liquidity[0] = liquidityRange_(
        tokenProps[i][pools[i][0]].lowerPrice,
        tokenProps[i][pools[i][0]].upperPrice,
        tokenProps[i][pools[i][0]].mintAmount, 
        tokenProps[i][pools[i][1]].mintAmount, 
        tokenProps[i][pools[i][0]].sqrtPriceX96
      );
       

      params.token0 = pools[i][0];
      params.token1 = pools[i][1];
      params.token0Balance = tokenProps[i][pools[i][0]].mintAmount;
      params.token1Balance = tokenProps[i][pools[i][1]].mintAmount;
      params.currentPrice = tokenProps[i][pools[i][0]].sqrtPriceX96;
      params.liquidity.push(liquidity[0]);
      params.mintLiqudity = true;
      params.fee = 500; 

      setupTestCase();
      delete(params.liquidity);
    }

    ERC20Mintable(UNI).mint(address(this), 2.5 ether);

    manager.swap(UniswapV3Manager.SwapParams({
      path: abi.encodePacked(UNI, uint24(60), WETH, uint24(60), USDC),
      recipient: address(this),
      amountIn: 2.5 ether,
      minAmountOut: 0
    }));
  }

  function setupTestCase() internal returns (uint256 amount0, uint256 amount1){
      ERC20Mintable(params.token0).mint(address(this), params.token0Balance);
      ERC20Mintable(params.token1).mint(address(this), params.token1Balance);

      UniswapV3Pool pool = UniswapV3Pool(factory.createPool(address(params.token0), address(params.token1), params.fee));
      pool.initialize(params.currentPrice);

      if(params.mintLiqudity){
        for(uint256 i; i < params.liquidity.length; i++){
          (uint256 amount0_, uint256 amount1_) = manager.mint(
            address(pool), 
            address(this),
            params.liquidity[i].lowerTick, 
            params.liquidity[i].upperTick, 
            params.token0Balance,
            params.token1Balance,
            0,
            0,
            UniswapV3Manager.MintCallbackData(
              params.token0, params.token1, address(this)
            )
          );

          amount0 += amount0_;
          amount1 += amount1_;
        }
      }
  }

  function sqrtP(int128 x, int128 y) pure internal returns (uint128 price) {
    int128 priceX64 = ABDKMath64x64.div(x, y);
    // 96 - 64 = 32
    price = uint128(ABDKMath64x64.sqrt(priceX64) << 32);
  }

  function liquidityRange_(
    uint160 lowerPrice,
    uint160 upperPrice,
    uint256 amount0,
    uint256 amount1,
    uint160 currentPrice
  ) internal returns (LiquidityRange memory range){
    range.lowerTick = TickMath.getTickAtSqrtRatio(lowerPrice);
    range.upperTick = TickMath.getTickAtSqrtRatio(upperPrice);
    range.amount = LiquidityMath.getLiquidityForAmounts(
      currentPrice, 
      lowerPrice, 
      upperPrice, 
      amount0, 
      amount1
    );
  }
}