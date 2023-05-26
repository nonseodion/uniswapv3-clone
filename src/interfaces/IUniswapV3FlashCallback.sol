// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.14;

interface IUniswapV3FlashCallback {
    function uniswapV3FlashCallback(uint fee0, uint fee1, bytes calldata data) external;
}