pragma solidity ^0.8.14;

import { ERC20Mintable } from "../test/ERC20Mintable.sol";
import { UniswapV3Pool } from "../src/UniswapV3Pool.sol";
import { UniswapV3Manager } from "../src/UniswapV3Manager.sol";
import { UniswapV3Factory } from "../src/UniswapV3Factory.sol";
import "forge-std/Script.sol";

contract DeployDevelopment is Script {
  uint256 wethBalance = 1 ether;
  uint256 usdcBalance = 5042 ether;
  int24 currentTick = 85176;
  uint160 currentSqrtP = 5602277097478614198912276234240;
  
  function run() public{
    vm.startBroadcast();
    ERC20Mintable token0 = new ERC20Mintable("Ethereum", "ETH", 18);
    ERC20Mintable token1 = new ERC20Mintable("USDC", "USDC", 18);
    // UniswapV3Pool pool = new UniswapV3Pool(address(token0), address(token1), currentSqrtP, currentTick);
    UniswapV3Factory factory = new UniswapV3Factory();
    UniswapV3Manager manager = new UniswapV3Manager(address(factory));

    token0.mint(msg.sender, 1 ether);
    token1.mint(msg.sender, 5042 ether);
    vm.stopBroadcast();

    console.log("Manager: ", address(manager));    
    // console.log("Pool: ", address(pool));    
    console.log("Token0: ", address(token0));
    console.log("Token1: ", address(token1));
  }
}