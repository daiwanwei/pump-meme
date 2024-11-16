// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {CurrencyLibrary, Currency} from "v4-core/src/types/Currency.sol";
import {PoolSwapTest} from "v4-core/src/test/PoolSwapTest.sol";
import {PumpMemeHook} from "../src/PumpMemeHook.sol";
import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";

import {LiquidityAmounts} from "v4-core/test/utils/LiquidityAmounts.sol";
import {IPositionManager} from "v4-periphery/src/interfaces/IPositionManager.sol";
import {EasyPosm} from "./utils/EasyPosm.sol";
import {Fixtures} from "./utils/Fixtures.sol";
import {IUniswapV2Factory} from "../src/interfaces/uniswapV2/IUniswapV2Factory.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {IPumpMemeHook} from "../src/interfaces/IPumpMemeHook.sol";

contract PumpMemeHookTest is Test, Fixtures {
    using EasyPosm for IPositionManager;
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;
    using StateLibrary for IPoolManager;

    PumpMemeHook hook;
    PoolId poolId;

    uint256 tokenId;
    int24 tickLower;
    int24 tickUpper;

    Currency weth;
    Currency memeCoin;

    /// This is the address of the Uniswap V2 factory contract on the Ethereum mainnet.
    IUniswapV2Factory uniswapV2Factory = IUniswapV2Factory(0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f);

    function setUp() public {
        // creates the pool manager, utility routers, and test tokens
        deployFreshManagerAndRouters();
        (weth, memeCoin) = deployMintAndApprove2Currencies();

        deployAndApprovePosm(manager);

        // Deploy the hook to an address with the correct flags
        address flags = address(
            uint160(Hooks.AFTER_SWAP_FLAG) ^ (0x4444 << 144) // Namespace the hook to avoid collisions
        );
        bytes memory constructorArgs = abi.encode(manager, uniswapV2Factory, weth); //Add all the necessary constructor arguments from the hook
        deployCodeTo("PumpMemeHook.sol:PumpMemeHook", constructorArgs, flags);
        hook = PumpMemeHook(flags);

        // Create the pool
        key = PoolKey(currency0, currency1, 3000, 60, IHooks(hook));
        poolId = key.toId();
        manager.initialize(key, SQRT_PRICE_1_1);

        setupLabel();

        // Provide full-range liquidity to the pool
        tickLower = TickMath.minUsableTick(key.tickSpacing);
        tickUpper = TickMath.maxUsableTick(key.tickSpacing);

        uint128 liquidityAmount = 100e18;

        (uint256 amount0Expected, uint256 amount1Expected) = LiquidityAmounts.getAmountsForLiquidity(
            SQRT_PRICE_1_1,
            TickMath.getSqrtPriceAtTick(tickLower),
            TickMath.getSqrtPriceAtTick(tickUpper),
            liquidityAmount
        );

        (tokenId,) = posm.mint(
            key,
            tickLower,
            tickUpper,
            liquidityAmount,
            amount0Expected + 1,
            amount1Expected + 1,
            address(this),
            block.timestamp,
            ZERO_BYTES
        );
    }

    function testPumpMemeHooks() public {
        // positions were created in setup()
        address meme = Currency.unwrap(memeCoin);
        assertEq(hook.hits(poolId, meme), 0);

        // Perform a test swap //
        bool zeroForOne = true;
        int256 amountSpecified = -1e18; // negative number indicates exact input swap!
        bytes memory hookData = abi.encode(IPumpMemeHook.CallbackData(meme));
        BalanceDelta swapDelta = swap(key, zeroForOne, amountSpecified, hookData);
        // ------------------- //

        assertEq(int256(swapDelta.amount0()), amountSpecified);

        assertEq(hook.hits(poolId, meme), 1);
    }

    function test_preLaunch() public {
        uint256 depositAmount = 10 ether;
        uint256 pumpCap = 100000000;
        assertEq(preLaunch(depositAmount, pumpCap), true);
    }

    function test_buy() public {
        uint256 depositAmount = 10 ether;
        uint256 pumpCap = 100000000;
        assertEq(preLaunch(depositAmount, pumpCap), true);

        uint256 buyAmount = 10000000000;
        assertEq(buy(buyAmount), true);
    }

    function test_sell() public {
        uint256 depositAmount = 10 ether;
        uint256 pumpCap = 100000000;
        assertEq(preLaunch(depositAmount, pumpCap), true);

        uint256 buyAmount = 10000000000;
        assertEq(buy(buyAmount), true);

        uint256 sellAmount = 1000000;
        assertEq(sell(sellAmount), true);
    }

    function test_pump() public {
        uint256 depositAmount = 10 ether;
        uint256 pumpCap = 100000000;
        assertEq(preLaunch(depositAmount, pumpCap), true);

        uint256 buyAmount = 10000000000;
        assertEq(buy(buyAmount), true);

        assertEq(pump(), true);
    }

    function preLaunch(uint256 depositAmount, uint256 pumpCap) private returns (bool) {
        IERC20 coin = IERC20(Currency.unwrap(memeCoin));
        assertEq(coin.approve(address(hook), depositAmount), true);

        PoolKey[] memory poolKeys = new PoolKey[](1);
        poolKeys[0] = key;

        IPumpMemeHook.PreLaunchParams memory params =
            IPumpMemeHook.PreLaunchParams({coin: coin, coinReserve: depositAmount, startBlock: 0, pumpCap: pumpCap});
        assertEq(hook.preLaunch(params, poolKeys), true);
        return true;
    }

    function buy(uint256 amount) private returns (bool) {
        IERC20 coin = IERC20(Currency.unwrap(memeCoin));
        IERC20 wethCoin = IERC20(Currency.unwrap(weth));

        assertEq(wethCoin.approve(address(hook), amount), true);
        assertEq(hook.buy(coin, amount), true);
        return true;
    }

    function sell(uint256 amount) private returns (bool) {
        IERC20 coin = IERC20(Currency.unwrap(memeCoin));
        assertEq(coin.approve(address(hook), amount), true);
        assertEq(hook.sell(coin, amount), true);
        return true;
    }

    function pump() private returns (bool) {
        IERC20 coin = IERC20(Currency.unwrap(memeCoin));
        assertEq(hook.pump(coin), true);
        return true;
    }

    function setupLabel() public {
        vm.label(address(hook), "PumpMemeHook");
        vm.label(Currency.unwrap(weth), "WETH");
        vm.label(Currency.unwrap(memeCoin), "MEME Coin");
        vm.label(address(uniswapV2Factory), "UniswapV2Factory");
    }
}
