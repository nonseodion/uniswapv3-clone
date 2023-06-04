pragma solidity ^0.8.14;

import "solmate/tokens/ERC721.sol";
import {PoolAddress} from "./libraries/PoolAddress.sol";
import {IUniswapV3Pool} from "./interfaces/IUniswapV3Pool.sol";
import {LiquidityMath} from "./libraries/LiquidityMath.sol";
import {TickMath} from "./libraries/TickMath.sol";
import { IERC20Minimal as IERC20 } from "./interfaces/IERC20Minimal.sol";
import { NFTRenderer } from "./libraries/NFTRenderer.sol";
import "forge-std/console.sol";

contract UniswapV3NFTManager is ERC721 {
    struct TokenPosition {
        address pool;
        int24 lowerTick;
        int24 upperTick;
    }

    struct MintParams {
        address recipient;
        address tokenA;
        address tokenB;
        uint24 fee;
        int24 lowerTick;
        int24 upperTick;
        uint256 amount0Desired;
        uint256 amount1Desired;
        uint256 amount0Min;
        uint256 amount1Min;
    }

    struct AddLiquidityInternalParams {
        address pool;
        int24 lowerTick;
        int24 upperTick;
        uint256 amount0Desired;
        uint256 amount1Desired;
        uint256 amount0Min;
        uint256 amount1Min;
    }

    struct AddLiquidityExternalParams {
        uint256 tokenId;
        uint256 amount0Desired;
        uint256 amount1Desired;
        uint256 amount0Min;
        uint256 amount1Min;
    }

    struct RemoveLiquidityParams {
        uint256 tokenId;
        uint128 liquidity;
    }

    struct CollectParams {
        uint256 tokenId;
        uint128 amount0;
        uint128 amount1;
    }

    event AddLiquidity(
        uint256 indexed tokenId,
        uint128 liquidity,
        uint256 amount0,
        uint256 amount1
    );

    event RemoveLiquidity(
        uint256 indexed tokenId,
        uint128 liquidity,
        uint256 amount0,
        uint256 amount1
    );

    error WrongToken();
    error UnAuthorised();
    error InsufficientLiquidity();
    error PositionNotCleared();
    error SlippageCheckFailed(uint256 amount0, uint256 amount1);

    modifier isApprovedOrOwner(uint256 id) {
        address owner = ownerOf(id);
        if(owner != msg.sender || !isApprovedForAll[owner][msg.sender] || getApproved[id] != msg.sender){
            revert UnAuthorised();
        }
        _;
    }

    address public immutable factory;
    mapping(uint256 => TokenPosition) positions;
    uint256 nextTokenId;
    uint256 totalSupply;

    constructor(address factory_) ERC721("UniswapV3 NFT Position", "UNIV3") {
        factory = factory_;
    }

    function tokenURI(uint256 id) public view override returns (string memory) {

        TokenPosition memory tokenPosition = positions[id];
        if(tokenPosition.pool == address(0x0)) {
            revert WrongToken();
        }
        console.log(tokenPosition.pool);
        uint24 fee = IUniswapV3Pool(tokenPosition.pool).fee(); 

        return NFTRenderer.render( 
            NFTRenderer.RenderParams({
                pool: tokenPosition.pool,
                fee: fee,
                owner: address(this),
                lowerTick: tokenPosition.lowerTick,
                upperTick: tokenPosition.upperTick
            })
        );
    }

    function mint(MintParams calldata params) public returns (uint256 tokenId) {
        address pool = getPool(params.tokenA, params.tokenB, params.fee);
        (uint128 liquidity, uint256 amount0, uint256 amount1) = _addLiquidity(
            AddLiquidityInternalParams({
                pool: pool,
                lowerTick: params.lowerTick,
                upperTick: params.upperTick,
                amount0Desired: params.amount0Desired,
                amount1Desired: params.amount1Desired,
                amount0Min: params.amount0Min,
                amount1Min: params.amount1Min
            })
        );

        tokenId = nextTokenId++;
        _mint(params.recipient, tokenId);
        totalSupply++;

        positions[tokenId] = TokenPosition(pool, params.lowerTick, params.upperTick);
        emit AddLiquidity(tokenId, liquidity, amount0, amount1);
    }

    function addLiquidity(
        AddLiquidityExternalParams memory params
    ) public returns (uint128 liquidity, uint256 amount0, uint256 amount1) {
        TokenPosition memory position = positions[
            params.tokenId
        ];
        if (position.pool == address(0)) {
            revert WrongToken();
        }

        (liquidity, amount0, amount1) = _addLiquidity(
            AddLiquidityInternalParams({
                pool: position.pool,
                lowerTick: position.lowerTick,
                upperTick: position.upperTick,
                amount0Desired: params.amount0Desired,
                amount1Desired: params.amount1Desired,
                amount0Min: params.amount0Min,
                amount1Min: params.amount1Min
            })
        );

        emit AddLiquidity(params.tokenId, liquidity, amount0, amount1);
    }

    function removeLiquidity(
        RemoveLiquidityParams calldata params
    ) public isApprovedOrOwner(params.tokenId) returns (uint256 amount0, uint256 amount1) {
        TokenPosition memory tokenPosition = positions[params.tokenId];
        if(tokenPosition.pool == address(0x0)) {
            revert WrongToken();
        }

        bytes32 positionId = keccak256(abi.encodePacked(address(this), tokenPosition.lowerTick, tokenPosition.upperTick));

        (uint128 availableLiquidity, , , , ) = IUniswapV3Pool(tokenPosition.pool).positions(positionId);

        if(availableLiquidity < params.liquidity) revert InsufficientLiquidity();

        (amount0, amount1) = IUniswapV3Pool(tokenPosition.pool).burn( 
            params.liquidity,
            tokenPosition.lowerTick, 
            tokenPosition.upperTick
        );

        emit RemoveLiquidity(params.tokenId, params.liquidity, amount0, amount1);
    }

    function collect(
        CollectParams calldata params
    ) public isApprovedOrOwner(params.tokenId) returns(uint256 amount0, uint256 amount1){
        TokenPosition memory tokenPosition = positions[params.tokenId];
        if(tokenPosition.pool == address(0x0)) {
            revert WrongToken();
        }
        
        IUniswapV3Pool pool = IUniswapV3Pool(tokenPosition.pool);

        (amount0, amount1) = pool.collect(
          msg.sender,
          tokenPosition.lowerTick,
          tokenPosition.upperTick,
          params.amount0,
          params.amount1  
        );
    }

    function burn (uint256 tokenId) public isApprovedOrOwner(tokenId) returns(uint256 amount0, uint256 amount1){
        TokenPosition memory tokenPosition = positions[tokenId];
        if(tokenPosition.pool == address(0x0)) {
            revert WrongToken();
        }

        IUniswapV3Pool pool = IUniswapV3Pool(tokenPosition.pool);

        (uint128 liquidity, , , uint256 tokensOwed0, uint256 tokensOwed1) = pool.positions(
            keccak256(abi.encodePacked(address(this), tokenPosition.lowerTick, tokenPosition.upperTick))
        );
        if(liquidity > 0 || tokensOwed0 > 0 ||  tokensOwed1 > 0) revert PositionNotCleared();

        delete positions[tokenId];
        _burn(tokenId);
        totalSupply--;
    }

    function getPool(
        address tokenA,
        address tokenB,
        uint24 fee
    ) private view returns (address pool) {
        return PoolAddress.computeAddress(factory, tokenA, tokenB, fee);
    }

    function _addLiquidity(
        AddLiquidityInternalParams memory params
    ) private returns (uint128 liquidity, uint256 amount0, uint256 amount1) {
      uint160 lowerPrice = TickMath.getSqrtRatioAtTick(params.lowerTick);
      uint160 upperPrice = TickMath.getSqrtRatioAtTick(params.upperTick);
      (uint160 sqrtPriceX96, , , ,  ) = IUniswapV3Pool(params.pool).slot0();
      
      liquidity = LiquidityMath.getLiquidityForAmounts(sqrtPriceX96, lowerPrice, upperPrice, params.amount0Desired, params.amount1Desired);
      bytes memory data = abi.encode(IUniswapV3Pool.MintCallbackData(IUniswapV3Pool(params.pool).token0(), IUniswapV3Pool(params.pool).token1(), msg.sender));

      console.log(uint24(params.lowerTick), uint24(params.upperTick));
      (amount0, amount1) = IUniswapV3Pool(params.pool).mint( 
          address(this),
          liquidity,
          params.lowerTick,
          params.upperTick,
          data
      );

      if (amount0 < params.amount0Min || amount1 < params.amount1Min)
        revert SlippageCheckFailed(amount0, amount1);
    }

  function uniswapV3MintCallback(
      uint256 amount0Owed,
      uint256 amount1Owed,
      bytes calldata data
  ) external {
    IUniswapV3Pool.MintCallbackData memory extra = abi.decode(data, (IUniswapV3Pool.MintCallbackData)); 
    console.log(amount0Owed, amount1Owed);
    IERC20(extra.token0).transferFrom(extra.payer, msg.sender, amount0Owed);
    IERC20(extra.token1).transferFrom(extra.payer, msg.sender, amount1Owed);
  }
}
