pragma solidity ^0.8.14;

import {UniswapV3Pool} from "./UniswapV3Pool.sol";
import {PoolAddress} from "./libraries/PoolAddress.sol";
import {TickMath} from "./libraries/TickMath.sol";
import {Path} from "./libraries/Path.sol";

contract Quoter {
    using Path for bytes;

    struct QuoteSingleParameters {
        address tokenIn;
        address tokenOut;
        uint256 amountIn;
        uint160 sqrtPriceLimitX96;
        uint24 tickSpacing;
    }

    struct QuoteParameters {
        uint amountIn;
        uint minAmountOut;
        bytes path;
    }

    address immutable factory;

    constructor(address factory_) {
        factory = factory_;
    }

    function quoteSingle(
        QuoteSingleParameters memory params
    ) public returns (uint256 amountOut, uint160 sqrtPriceAfter, int24 tick) {
        bool zeroForOne = params.tokenIn < params.tokenOut;
        address pool = PoolAddress.computeAddress(
            factory,
            params.tokenIn,
            params.tokenOut,
            params.tickSpacing
        );

        try
            UniswapV3Pool(pool).swap(
                address(this),
                zeroForOne,
                params.amountIn,
                params.sqrtPriceLimitX96 == 0
                  ? (
                      zeroForOne
                          ? TickMath.MIN_SQRT_RATIO + 1
                          : TickMath.MAX_SQRT_RATIO - 1
                  )
                  : params.sqrtPriceLimitX96,
                abi.encode(pool)
            )
        {} catch (bytes memory reason) {
            (amountOut, sqrtPriceAfter, tick) = abi.decode(
                reason,
                (uint256, uint160, int24)
            );
        }
    }

    function quote(
        QuoteParameters memory params
    )
        public
        returns (
            uint256[] memory amountsOut,
            uint160[] memory sqrtPricesAfterX96,
            int24[] memory ticksAfterSwaps
        )
    {
        uint256 length = params.path.numPools();
        amountsOut = new uint256[](length);
        sqrtPricesAfterX96 = new uint160[](length);
        ticksAfterSwaps = new int24[](length); 

        while (true) {
            (address tokenIn, address tokenOut, uint24 tickSpacing) = params
                .path
                .getFirstPool()
                .decodeFirstPool();

            (
                uint256 amountOut,
                uint160 sqrtPriceAfterX96,
                int24 tick
            ) = quoteSingle(
                  QuoteSingleParameters({
                      tokenIn: tokenIn,
                      tokenOut: tokenOut,
                      amountIn: params.amountIn,
                      sqrtPriceLimitX96: 0,
                      tickSpacing: tickSpacing
                  })
                );

            amountsOut[--length] = amountOut;
            sqrtPricesAfterX96[length] = sqrtPriceAfterX96;
            ticksAfterSwaps[length] = tick;

            if (params.path.hasMultiplePools()) {
                params.path = params.path.skipToken();
                params.amountIn = amountOut;
            } else {
                break;
            }
        }
    }

    function getPool(
        address tokenIn,
        address tokenOut,
        uint24 tickSpacing
    ) public view returns (address pool) {
        (tokenIn, tokenOut) = tokenIn > tokenOut
            ? (tokenOut, tokenIn)
            : (tokenIn, tokenOut);

        pool = PoolAddress.computeAddress(
            factory,
            tokenIn,
            tokenOut,
            tickSpacing
        );
    }

    function uniswapV3SwapCallback(
        int256 amount0Delta,
        int256 amount1Delta,
        bytes calldata data
    ) external {
        uint256 amountOut = amount0Delta > 0
            ? uint256(-amount1Delta)
            : uint256(-amount0Delta);

        address pool = abi.decode(data, (address));
        (uint160 slot, int24 tick) = UniswapV3Pool(pool).slot0();

        assembly {
            let freeMemoryPointer := mload(0x40)
            mstore(freeMemoryPointer, amountOut)
            mstore(add(freeMemoryPointer, 0x20), slot)
            mstore(add(freeMemoryPointer, 0x40), tick)
            revert(freeMemoryPointer, 0x60)
        }
    }
}
