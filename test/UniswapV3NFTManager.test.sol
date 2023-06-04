pragma solidity 0.8.14;

import { ERC20Mintable, ERC20 } from "./ERC20Mintable.sol";
import { UniswapV3Factory } from "../src/UniswapV3Factory.sol";
import { UniswapV3Pool, TickMath } from "../src/UniswapV3Pool.sol";
import { UniswapV3NFTManager } from "../src/UniswapV3NFTManager.sol";
import { UniswapV3PoolUtils } from "./UniswapV3Pool.Utils.test.sol";
import "forge-std/console.sol";

contract UniswapV3NFTManagerTest is UniswapV3PoolUtils{
  address USDC;
  address WETH;
  address UNI;

  UniswapV3Factory factory;
  UniswapV3NFTManager manager;

  function setUp() public {
    USDC = address(new ERC20Mintable("US Dollars", "USDC", 18));
    WETH = address(new ERC20Mintable("Ethereum", "Ether", 18));
    UNI = address(new ERC20Mintable("Bitcoin", "UNI", 18));

    factory = new UniswapV3Factory();
    manager = new UniswapV3NFTManager(address(factory));
  }

  function testRender() public {
    address pool = factory.createPool(WETH, USDC, 500);
    UniswapV3Pool(pool).initialize(sqrtP(5000));

    ERC20Mintable(WETH).mint(address(this), 1 ether);
    ERC20Mintable(USDC).mint(address(this), 5000 ether);
    
    ERC20Mintable(WETH).approve(address(manager), type(uint256).max);
    ERC20Mintable(USDC).approve(address(manager), type(uint256).max);

    LiquidityRange memory range = liquidityRange(4545, 5500, 1 ether, 5000 ether, 5000);

    manager.mint(UniswapV3NFTManager.MintParams({
      recipient: address(this),
      tokenA: WETH,
      tokenB: USDC,
      fee: 500,
      lowerTick: range.lowerTick, 
      upperTick: range.upperTick,
      amount0Desired: 1 ether,
      amount1Desired: 5000 ether,
      amount0Min: 0,
      amount1Min: 0
    }));

    string memory uri = manager.tokenURI(0);
    assertTokenURI(uri);
  }

  function assertTokenURI(string memory uri) internal {
    string memory expected = vm.readFile("./test/fixture/tokenuri0");
    assertEq(expected, uri, "Invalid token URI");
  }
}