pragma solidity ^0.8.14;

library Position {
  struct Info {
    uint128 liquidity;
  }

  function update(Info storage self, uint128 amount) internal {
    self.liquidity += amount;
  }

  function get(
    mapping(bytes32 => Info) storage positions, 
    address owner, 
    int24 lowerTick, 
    int24 upperTick
  ) view public returns (Info storage) {
    return positions[keccak256(abi.encodePacked(owner, lowerTick, upperTick))];
  }
}