pragma solidity ^0.8.14;

library Path {
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
    
  }
}