pragma solidity ^0.8.14;

library Oracle {
  struct Observation {
    uint32 timestamp;
    int56 tickCummulative;
    bool initialized;
  }

  function initialize (Observation[] memory self, uint32 timestamp) internal returns (uint16 cardinality, uint16 cardinalityNext) {
    self[0] = Observation(
      timestamp,
      0,
      true
    );

    cardinality = 1;
    cardinalityNext = 1;
  }

  function write(
    Observation[] memory self, 
    int24 tick,
    uint16 index,
    uint32 timestamp,
    uint16 cardinality,
    uint16 cardinalityNext
  ) internal pure returns (uint16 indexUpdated, uint16 cardinalityUpdated) {
    Observation memory last = self[index];
    if(last.timestamp >= timestamp){
      return (index, cardinality);
    }

    if(cardinalityNext > cardinality && index == (cardinality - 1)){
      cardinalityUpdated = cardinalityNext;
    }else {
      cardinalityUpdated = cardinality;
    }

    indexUpdated = (index + 1) % cardinalityUpdated;
    self[indexUpdated] = transform(last, timestamp, tick);
  }

  function transform(
    Observation memory last,
    uint32 timestamp,
    int24 tick
  ) internal pure returns (Observation memory) {
    uint56 delta = timestamp - last.timestamp;
    return Observation({
      timestamp: timestamp,
      tickCummulative: last.tickCummulative + int56(tick) * int56(delta),
      initialized: true
    }); 
  }

  function grow(
    Observation[65535] storage self, 
    uint16 next, 
    uint16 current
  ) internal returns (uint16) {
    if(next < current) return current;
    for(uint16 i = current; i < next ; i++){
      self[i].timestamp = 1;
    }
    return next;
  }

  function observe(
    Observation[65535] storage self, 
    uint32[] memory secondsAgos,
    uint32 time,
    uint16 index,
    int24 tick
  ) internal {
    int56[] memory accumulatedTicks = new int56[](secondsAgos.length);

    for(uint i = 0; i < accumulatedTicks.length; i++){
      accumulatedTicks[i] = observeSingle(
        self,
        secondsAgos[i],
        time,
        index,
        tick
      );
    }
  }

  function observeSingle(
    Observation[65535] storage self, 
    uint32 secondsAgo,
    uint32 time,
    uint16 index,
    int24 tick
  ) internal returns (int56 tickCummulative) {
    if(secondsAgo == 0){
      Observation memory last = self[index];
      if(last.timestamp < time) last = transform(last, time, tick);
      return last.tickCummulative;
    }
  }
}

