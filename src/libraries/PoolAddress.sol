pragma solidity ^0.8.14;

import { UniswapV3Pool } from "../UniswapV3Pool.sol";

library PoolAddress {
  function computeAddress(
    address factory,
    address tokenX,
    address tokenY,
    uint24 fee
  ) internal pure returns(address pool) {
    if(tokenX > tokenY) {
      (tokenX, tokenY) = (tokenY, tokenX);
    }

    bytes32 salt = keccak256(abi.encodePacked(tokenX, tokenY, fee));

    pool = address(uint160(uint256(keccak256(abi.encodePacked(
      uint8(0xff),
      factory,
      salt,
      keccak256(type(UniswapV3Pool).creationCode)
    )))));
  }
}