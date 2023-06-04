pragma solidity ^0.8.14;

import { Strings } from "openzeppelin-contracts/utils/Strings.sol";
import { IUniswapV3Pool } from "../interfaces/IUniswapV3Pool.sol";
import { IERC20Minimal as IERC20 } from "../interfaces/IERC20Minimal.sol";
import { Base64 } from "openzeppelin-contracts/utils/Base64.sol";

library NFTRenderer {
  using Strings for string;

  struct RenderParams {
    address owner;
    address pool;
    uint24 fee;
    int24 lowerTick;
    int24 upperTick;
  }

  function render(
    RenderParams memory params
  ) internal view returns ( string memory) { 
    string memory symbol0 = IERC20(IUniswapV3Pool(params.pool).token0()).symbol(); 
    string memory symbol1 = IERC20(IUniswapV3Pool(params.pool).token1()).symbol();

    string memory image = string.concat(
      "<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 300 480'>",
      "<style>.tokens {font: bold 30px sans-serif;}",
      ".fee {font: normal 26px sans-serif;}",
      ".tick {font: normal 18px sans-serif;} </style>",
      renderBackground(params.owner, params.lowerTick, params.upperTick),
      renderTop(params.fee, symbol0, symbol1),
      renderBottom(params.lowerTick, params.upperTick)
    );

    string memory description = renderDescription(params.fee, params.lowerTick, params.upperTick, symbol0, symbol1);
    string memory json = string.concat(
      "{ 'name': 'Uniswap V3 Position',",
      "'description': '",
      description,
      "', 'image': 'data:image/svg+xml;base64,",
      Base64.encode(bytes(image)),
      "' }"
    );

    return string.concat(
      "data:application/json;base64,",
      Base64.encode(bytes(json))
    );
  }

  function renderBackground(
    address owner, 
    int24 lowerTick, 
    int24 upperTick
  ) internal pure returns (string memory background){
    bytes32 key = keccak256(abi.encodePacked(owner, lowerTick, upperTick));
    string memory hue = Strings.toString(uint256(key) % 360);
    background = string.concat(
      "<rect width='300' height='480' fill='hsl(",
        hue,
      ",40%,40%)' />",
      "<rect x='30' y='30' width='240' height='420' rx='15' ry='15' fill='hsl(",
        hue,
      ",90%,50%)' stroke='#000' />"
    );
  }

  function renderTop(uint24 fee, string memory symbol0, string memory symbol1) pure internal returns (string memory top){
    top = string.concat(
      "<rect x='30' y='87' width='240' height='42' />",
      "<text x='39' y='120' class='tokens' fill='#fff'>",
      symbol0, "/", symbol1,
      "</text><rect x='30' y='132' width='240' height='30' />",
      "<text x='39' y='120' dy='36' class='fee' fill='#fff'>",
      feeToText(fee),
      "</text>"
    );
  }

  function renderBottom(int24 lowerTick, int24 upperTick) pure internal returns (string memory bottom){


    bottom = string.concat(
      "<rect x='30' y='342' width='240' height='24' />",
      "<text x='39' y='360' class='tick' fill='#fff'>Lower tick: ",
       Strings.toString(lowerTick),
      "</text>",

      "<rect x='30' y='372' width='240' height='24' />",
      "<text x='39' y='360' dy='30' class='tick' fill='#fff'>Upper tick: ",
      Strings.toString(upperTick),
      "</text>"
    );
  }

  function renderDescription (
    uint24 fee,
    int24 lowerTick, 
    int24 upperTick,
    string memory symbol0,
    string memory symbol1
  ) internal pure returns( string memory){
    return string.concat(
      symbol0,
      "/",
      symbol1,
      ", ",
      feeToText(fee),
      ", Lower Tick: ",
      tickToText(lowerTick),
      ", Upper Tick: ",
      tickToText(upperTick)
    );
  }

  function feeToText(uint24 fee) internal pure returns (string memory){
    if(fee == 500)
      return "0.05%";
    else if(fee == 3000)
      return "0.3%";
  }

  function tickToText(int24 tick) internal pure returns (string memory ){
    return string.concat(
      tick < 0 ? "-" : "",
      Strings.toString(tick < 0 ? uint256(uint24(-tick)) : uint256(uint24(tick))) 
    );
  }
}