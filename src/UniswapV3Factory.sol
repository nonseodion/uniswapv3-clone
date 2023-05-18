pragma solidity ^0.8.14;

import {UniswapV3Pool} from "./UniswapV3Pool.sol";

contract UniswapV3Factory {
  struct PoolParameters {
    address factory;
    address tokenX;
    address tokenY;
    uint24 tickSpacing;
  }

  PoolParameters public parameters;
  mapping(uint24 => bool) public tickSpacings;
  

  mapping(address => mapping(address => mapping(uint24 => address))) public pools;

  error UnsupportedTickSpacing();
  error TokenMustBeDifferent();
  error TokenXCannotBeZero();

  event PoolCreated(address tokenX, address tokenY, uint24 tickSpacing, address pool);

  constructor (){
    tickSpacings[60] = true;
  }

  function createPool(
    address tokenX,
    address tokenY,
    uint24 tickSpacing
  ) external returns (address pool){

    if(!tickSpacings[tickSpacing]) revert UnsupportedTickSpacing();
    if(tokenX == tokenY) revert TokenMustBeDifferent();

    if(tokenX > tokenY){
      (tokenX, tokenY) = (tokenY, tokenX);
    }
    if(tokenX == address(0)){
      revert TokenXCannotBeZero();
    }

    parameters = PoolParameters({
      factory: address(this),
      tokenX: tokenX,
      tokenY: tokenY,
      tickSpacing: tickSpacing
    }); 

    pool = address(
      new UniswapV3Pool{
        salt: keccak256(abi.encodePacked(tokenX, tokenY, tickSpacing))
      }()
    );

    delete parameters;

    pools[tokenX][tokenY][tickSpacing] = pool;
    pools[tokenY][tokenX][tickSpacing] = pool;

    emit PoolCreated(tokenX, tokenY, tickSpacing, pool);
  }
}