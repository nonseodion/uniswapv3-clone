pragma solidity ^0.8.14;

import {UniswapV3Pool} from "./UniswapV3Pool.sol";

contract UniswapV3Factory {
  struct PoolParameters {
    address factory;
    address tokenX;
    address tokenY;
    uint24 tickSpacing;
    uint24 fee;
  }

  PoolParameters public parameters;
  mapping(uint24 => uint24) public fees;
  

  mapping(address => mapping(address => mapping(uint24 => address))) public pools;

  error UnsupportedFee();
  error TokenMustBeDifferent();
  error TokenXCannotBeZero();

  event PoolCreated(address tokenX, address tokenY, uint24 tickSpacing, address pool);

  constructor (){
    fees[500] = 10;
    fees[3000] = 60;
  }

  function createPool(
    address tokenX,
    address tokenY,
    uint24 fee
  ) external returns (address pool){

    if(fees[fee] == 0) revert UnsupportedFee();
    if(tokenX == tokenY) revert TokenMustBeDifferent();

    if(tokenX > tokenY){
      (tokenX, tokenY) = (tokenY, tokenX);
    }
    if(tokenX == address(0)){
      revert TokenXCannotBeZero();
    }

    uint24 tickSpacing = fees[fee];

    parameters = PoolParameters({
      factory: address(this),
      tokenX: tokenX,
      tokenY: tokenY,
      tickSpacing: tickSpacing,
      fee: fee
    }); 

    pool = address(
      new UniswapV3Pool{
        salt: keccak256(abi.encodePacked(tokenX, tokenY, fee))
      }()
    );

    delete parameters;

    pools[tokenX][tokenY][fee] = pool;
    pools[tokenY][tokenX][fee] = pool;

    emit PoolCreated(tokenX, tokenY, fee, pool);
  }
}