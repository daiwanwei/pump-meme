// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

library CurveMath {
    function computeSwap(uint256 _coinReserve, uint256 _amountIn, bool buyOrSell)
        public
        pure
        returns (uint256 amountOut)
    {
        /// FIXME: correct the formula
        if (buyOrSell) {
            amountOut = _amountIn;
        } else {
            amountOut = _amountIn;
        }
    }
}
