// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {BaseHook} from "v4-periphery/src/base/hooks/BaseHook.sol";

import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "v4-core/src/types/BeforeSwapDelta.sol";
import {IUniswapV2Factory} from "./interfaces/uniswapV2/IUniswapV2Factory.sol";
import {IUniswapV2Pair} from "./interfaces/uniswapV2/IUniswapV2Pair.sol";
import {IPumpMemeHook} from "./interfaces/IPumpMemeHook.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {CurveMath} from "./libraries/CurveMath.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {CurrencySettler} from "v4-core/test/utils/CurrencySettler.sol";
import {TransientStateLibrary} from "v4-core/src/libraries/TransientStateLibrary.sol";

contract PumpMemeHook is BaseHook, IPumpMemeHook {
    using PoolIdLibrary for PoolKey;
    using CurrencySettler for Currency;
    using TransientStateLibrary for IPoolManager;

    // struct
    struct LaunchConfig {
        uint256 startBlock;
        uint256 pumpCap;
        uint256 wethReserve;
        uint256 coinReserve;
        uint24 poolNums;
        bool launched;
    }

    // NOTE: ---------------------------------------------------------
    // state variables should typically be unique to a pool
    // a single hook contract should be able to service multiple pools
    // ---------------------------------------------------------------

    // states
    IERC20 public immutable weth;

    IUniswapV2Factory public immutable uniswapV2Factory;

    mapping(address => LaunchConfig) public launchConfigs;
    mapping(address => mapping(uint24 => PoolKey)) public validPoolKeys;

    mapping(PoolId => mapping(address => uint256)) public hits;

    constructor(IPoolManager _poolManager, IUniswapV2Factory _uniswapV2Factory, IERC20 _weth) BaseHook(_poolManager) {
        weth = _weth;
        uniswapV2Factory = _uniswapV2Factory;
    }

    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: false,
            afterInitialize: false,
            beforeAddLiquidity: false,
            afterAddLiquidity: false,
            beforeRemoveLiquidity: false,
            afterRemoveLiquidity: false,
            beforeSwap: false,
            afterSwap: true,
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: false,
            afterSwapReturnDelta: false,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }

    // -----------------------------------------------
    // NOTE: see IHooks.sol for function documentation
    // -----------------------------------------------

    function afterSwap(
        address,
        PoolKey calldata key,
        IPoolManager.SwapParams calldata,
        BalanceDelta,
        bytes calldata hookData
    ) external override returns (bytes4, int128) {
        if (hookData.length == 0) {
            return (BaseHook.afterSwap.selector, 0);
        }
        CallbackData memory data = abi.decode(hookData, (CallbackData));
        hits[key.toId()][data.coin]++;

        emit Hited(key, data.coin, hits[key.toId()][data.coin]);

        return (BaseHook.afterSwap.selector, 0);
    }

    // IPumpMemeHook
    function preLaunch(PreLaunchParams memory _params, PoolKey[] calldata _poolKeys) external returns (bool) {
        if (launchConfigs[address(_params.coin)].launched) {
            return false;
        }

        if (!_params.coin.transferFrom(msg.sender, address(this), _params.coinReserve)) {
            revert FailToDepoistCoin(msg.sender, _params.coinReserve);
        }

        LaunchConfig memory config = LaunchConfig({
            startBlock: _params.startBlock,
            wethReserve: 0,
            coinReserve: _params.coinReserve,
            pumpCap: _params.pumpCap,
            poolNums: uint24(_poolKeys.length),
            launched: true
        });

        for (uint24 i = 0; i < _poolKeys.length; i++) {
            zeroIsWeth(_poolKeys[i]);
            validPoolKeys[address(_params.coin)][i] = _poolKeys[i];
            hits[_poolKeys[i].toId()][address(_params.coin)] = 0;
        }

        launchConfigs[address(_params.coin)] = config;

        emit PreLaunched(msg.sender, address(_params.coin));

        return true;
    }

    function buy(IERC20 _coin, uint256 _amount) external returns (bool) {
        LaunchConfig storage config = launchConfigs[address(_coin)];

        uint256 amountOut = CurveMath.computeSwap(config.coinReserve, _amount, true);

        uint256 newWethReserve = config.wethReserve + _amount;
        uint256 newCoinReserve = config.coinReserve - amountOut;

        if (!weth.transferFrom(msg.sender, address(this), _amount)) {
            revert FailToPay(msg.sender, _amount);
        }

        if (!_coin.transfer(msg.sender, amountOut)) {
            revert FailToBuyCoin(msg.sender, amountOut);
        }

        config.wethReserve = newWethReserve;
        config.coinReserve = newCoinReserve;

        emit Bought(msg.sender, address(_coin), amountOut);

        return true;
    }

    function sell(IERC20 _coin, uint256 _amount) external returns (bool) {
        LaunchConfig storage config = launchConfigs[address(_coin)];

        uint256 amountOut = CurveMath.computeSwap(config.coinReserve, _amount, false);

        uint256 newCoinReserve = config.coinReserve + _amount;
        uint256 newWethReserve = config.wethReserve - amountOut;

        if (!_coin.transferFrom(msg.sender, address(this), _amount)) {
            revert FailToPay(msg.sender, _amount);
        }

        if (!weth.transfer(msg.sender, amountOut)) {
            revert FailToSellCoin(msg.sender, amountOut);
        }

        config.wethReserve = newWethReserve;
        config.coinReserve = newCoinReserve;

        emit Sold(msg.sender, address(_coin), _amount);

        return true;
    }

    function pump(IERC20 _coin) external returns (bool) {
        LaunchConfig storage config = launchConfigs[address(_coin)];

        // check if the pump cap is reached
        if (config.wethReserve < config.pumpCap) {
            revert UnderPumpCap(config.pumpCap, config.wethReserve);
        }

        (uint256 donateAmount, uint256 pumpAmount) = calculateDistribution(config.wethReserve);

        /// Donate To No.1 Pool
        PoolKey memory key = getFirstPoolKey(address(_coin));
        donateWethToV4Pool(key, address(_coin), donateAmount);

        /// Pump
        /// 1. create a new pool if not exists
        address pair = createV2Pool(address(weth), address(_coin));
        /// 2. add liquidity to the pool and burn the liquidity
        /// TODO: correct deposit amount
        uint256 liquidity = addAndBurnV2PoolLiquidity(address(weth), address(_coin), pumpAmount, config.coinReserve);
        emit Pumped(key, address(_coin), liquidity);

        return true;
    }

    function donateWethToV4Pool(PoolKey memory _key, address _coin, uint256 _amount) internal returns (bool) {
        poolManager.unlock(abi.encodeCall(this.unlockCallbackDonate, (_key, _coin, _amount)));
        return true;
    }

    function _donateWethToV4Pool(PoolKey calldata key, uint256 amount) internal returns (bool) {
        bool isZero = zeroIsWeth(key);
        uint256 amount0 = isZero ? amount : 0;
        uint256 amount1 = isZero ? 0 : amount;
        poolManager.donate(key, amount0, amount1, new bytes(0));
        int256 delta0 = poolManager.currencyDelta(address(this), key.currency0);
        int256 delta1 = poolManager.currencyDelta(address(this), key.currency1);
        key.currency0.settle(poolManager, address(this), uint256(-delta0), false);
        key.currency1.settle(poolManager, address(this), uint256(-delta1), false);
        return true;
    }

    function createV2Pool(address _weth, address _coin) internal returns (address) {
        if (uniswapV2Factory.getPair(_weth, _coin) != address(0)) {
            return uniswapV2Factory.getPair(_weth, _coin);
        }
        address pool = uniswapV2Factory.createPair(_weth, _coin);
        emit CreatedV2Pool(_weth, _coin, pool);
        return pool;
    }

    function addAndBurnV2PoolLiquidity(address _weth, address _coin, uint256 _wethAmount, uint256 _coinAmount)
        internal
        returns (uint256 liquidity)
    {
        address pool = uniswapV2Factory.getPair(_weth, _coin);
        if (pool == address(0)) {
            revert V2PoolNotExists(_weth, _coin);
        }
        IUniswapV2Pair uniswapV2Pair = IUniswapV2Pair(pool);
        if (!IERC20(weth).transfer(pool, _wethAmount)) {
            revert InsufficientWethReserve(_wethAmount);
        }
        if (!IERC20(_coin).transfer(pool, _coinAmount)) {
            revert InsufficientCoinReserve(_coinAmount);
        }
        uint256 liquidity = uniswapV2Pair.mint(address(this));
        emit AddedLiquidityToV2Pool(_weth, _coin, _wethAmount, _coinAmount, liquidity);

        // Burn Liquidity(transferred to 0x0)
        if (!uniswapV2Pair.transfer(address(0), liquidity)) {
            revert FailToBurnLiquidity(pool, liquidity);
        }
        emit BurnV2PoolLiquidity(_weth, _coin, liquidity);
        return liquidity;
    }

    function isValidPoolKey(PoolKey memory _poolKey, address _coin) public view returns (bool) {
        LaunchConfig memory config = launchConfigs[_coin];

        for (uint24 i = 0; i < config.poolNums; i++) {
            if (PoolId.unwrap(_poolKey.toId()) == PoolId.unwrap(validPoolKeys[_coin][i].toId())) {
                return true;
            }
        }
        return false;
    }

    // unlock callback
    function unlockCallbackDonate(PoolKey calldata key, address _coin, uint256 donateAmount) external selfOnly {
        _donateWethToV4Pool(key, donateAmount);
        emit DonatedToV4Pool(key, _coin, donateAmount);
    }

    function getFirstPoolKey(address _coin) public view returns (PoolKey memory) {
        uint256 maxHits = 0;
        uint24 maxHitsPoolId = 0;
        for (uint24 i = 0; i < launchConfigs[_coin].poolNums; i++) {
            uint256 hit = hits[validPoolKeys[_coin][i].toId()][_coin];
            if (hit > maxHits) {
                maxHits = hit;
                maxHitsPoolId = i;
            }
        }
        return validPoolKeys[_coin][maxHitsPoolId];
    }

    function zeroIsWeth(PoolKey calldata _poolKey) public view returns (bool) {
        if (Currency.unwrap(_poolKey.currency0) == address(weth)) {
            return true;
        }
        if (Currency.unwrap(_poolKey.currency1) == address(weth)) {
            return false;
        }

        revert InvalidPoolCurrency(_poolKey, address(weth));
    }

    function calculateDistribution(uint256 amount) public pure returns (uint256 donateAmount, uint256 pumpAmount) {
        uint256 bps = 100;
        donateAmount = (amount * bps) / 1000000;
        pumpAmount = amount - donateAmount;
    }
}
