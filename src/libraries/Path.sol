pragma solidity ^0.8.14;

import { BytesLib } from "../../lib/solidity-bytes-utils/contracts/BytesLib.sol";

library Path {
  using BytesLib for bytes;
  using { toUint24 } for bytes;

  // @dev the byte-length of an address in the path
  uint private constant ADDRESS_SIZE = 20;
  // @dev the byte-length of a tick spacing in the path
  uint private constant TICKSPACING_SIZE = 3;
  // @dev the byte-length of an address and tickspacing in the path
  uint private constant NEXT_OFFSET_SIZE = ADDRESS_SIZE + TICKSPACING_SIZE;
  // @dev the byte-length of an encoded pool key (address + tickSpacing + address)
  uint private constant POP_SIZE = NEXT_OFFSET_SIZE + ADDRESS_SIZE;
  // @dev the minimum length for a path with 2 or more pools
  uint private constant MULTIPLE_POOLS_MIN_LENGTH = POP_SIZE + NEXT_OFFSET_SIZE;

  function numPools(bytes memory path) pure internal returns(uint256) {
    return (path.length - ADDRESS_SIZE) / NEXT_OFFSET_SIZE;
  }

  function hasMultiplePools(bytes memory path) pure internal returns(bool) {
    return path.length >= MULTIPLE_POOLS_MIN_LENGTH;
  }

  function getFirstPool(bytes memory path) pure internal returns(bytes memory pool) {
    return path.slice(0, POP_SIZE);
  }

  function skipToken(bytes memory path) pure internal returns(bytes memory pool) {
    return path.slice(NEXT_OFFSET_SIZE, path.length - NEXT_OFFSET_SIZE);
  }

  function decodeFirstPool(bytes memory path) pure internal returns(address tokenIn, address tokenOut, uint24 tickSpacing){
    tokenIn = path.toAddress(0);
    tokenOut = path.toAddress(POP_SIZE);
    tickSpacing = path.toUint24(ADDRESS_SIZE);
  }

  function toUint24(bytes memory _bytes, uint256 _start) pure internal returns(uint24){
    require(_bytes.length >= _start+3, "toUint24_outOfBounds");
    uint24 tempUint;

    assembly {
      tempUint := mload(add(add( _bytes, 0x3 ), _start))
    }

    return tempUint;
  }
}
