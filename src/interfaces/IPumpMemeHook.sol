// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";

interface IPumpMemeHook {
    struct PreLaunchParams {
        IERC20 coin;
        uint256 pumpCap;
        uint256 coinReserve;
        uint256 startBlock;
    }

    struct CallbackData {
        address coin;
    }

    error InvalidPoolCurrency(PoolKey poolKey, address weth);
    error FailToDepoistCoin(address sender, uint256 amount);
    error FailToPay(address sender, uint256 amount);
    error FailToBuyCoin(address receiver, uint256 amount);
    error FailToSellCoin(address receiver, uint256 amount);
    error InsufficientWethReserve(uint256 wethReserve);
    error InsufficientCoinReserve(uint256 coinReserve);
    error UnderPumpCap(uint256 pumpCap, uint256 wethReserve);
    error FailToBurnLiquidity(address coin, uint256 liquidity);
    error V2PoolNotExists(address weth, address coin);

    event PreLaunched(address indexed sender, address coin);
    event Bought(address indexed receiver, address coin, uint256 amount);
    event Sold(address indexed receiver, address coin, uint256 amount);
    event Pumped(PoolKey poolKey, address coin, uint256 liquidity);

    event Hited(PoolKey poolKey, address coin, uint256 count);
    event DonatedToV4Pool(PoolKey poolKey, address coin, uint256 donateAmount);
    event CreatedV2Pool(address weth, address coin, address pool);
    event AddedLiquidityToV2Pool(address weth, address coin, uint256 wethAmount, uint256 coinAmount, uint256 liquidity);
    event BurnV2PoolLiquidity(address weth, address coin, uint256 liquidity);

    function preLaunch(PreLaunchParams memory params, PoolKey[] memory poolkeys) external returns (bool);

    function buy(IERC20 coin, uint256 amount) external returns (bool);

    function sell(IERC20 coin, uint256 amount) external returns (bool);

    function pump(IERC20 coin) external returns (bool);
}
