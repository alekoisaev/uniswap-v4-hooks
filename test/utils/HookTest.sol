// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";

import {PoolManager} from "v4-core/PoolManager.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {PoolModifyLiquidityTest} from "v4-core/test/PoolModifyLiquidityTest.sol";
import {PoolSwapTest} from "v4-core/test/PoolSwapTest.sol";
import {PoolDonateTest} from "v4-core/test/PoolDonateTest.sol";

import {TestERC20} from "v4-core/test/TestERC20.sol";
import {TickMath} from "v4-core/libraries/TickMath.sol";

/// @notice Contract to initialize some test helpers
/// @dev Minimal initialization. Inheriting contract should set up pools and provision liquidity
contract HookTest is Test {
    PoolManager manager_;
    PoolModifyLiquidityTest modifyPositionRouter;
    PoolSwapTest swapRouter_;
    PoolDonateTest donateRouter_;
    TestERC20 token0;
    TestERC20 token1;

    // uint160 public constant MIN_PRICE_LIMIT = TickMath.MIN_SQRT_RATIO + 1;
    // uint160 public constant MAX_PRICE_LIMIT = TickMath.MAX_SQRT_RATIO - 1;

    function initHookTestEnv() public {
        uint256 amount = 2 ** 128;
        TestERC20 _tokenA = new TestERC20(amount);
        TestERC20 _tokenB = new TestERC20(amount);

        // pools alphabetically sort tokens by address
        // so align `token0` with `pool.token0` for consistency
        if (address(_tokenA) < address(_tokenB)) {
            token0 = _tokenA;
            token1 = _tokenB;
        } else {
            token0 = _tokenB;
            token1 = _tokenA;
        }
        manager_ = new PoolManager(500000);

        // Helpers for interacting with the pool
        modifyPositionRouter = new PoolModifyLiquidityTest(IPoolManager(address(manager_)));
        swapRouter_ = new PoolSwapTest(IPoolManager(address(manager_)));
        donateRouter_ = new PoolDonateTest(IPoolManager(address(manager_)));

        // Approve for liquidity provision
        token0.approve(address(modifyPositionRouter), amount);
        token1.approve(address(modifyPositionRouter), amount);

        // Approve for swapping
        token0.approve(address(swapRouter_), amount);
        token1.approve(address(swapRouter_), amount);
    }

    function swap(PoolKey memory key, int256 amountSpecified, bool zeroForOne, bytes memory hookData) internal {
        IPoolManager.SwapParams memory params = IPoolManager.SwapParams({
            zeroForOne: zeroForOne,
            amountSpecified: amountSpecified,
            sqrtPriceLimitX96: zeroForOne ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1 // unlimited impact
        });

        PoolSwapTest.TestSettings memory testSettings =
            PoolSwapTest.TestSettings({withdrawTokens: true, settleUsingTransfer: true});

        swapRouter_.swap(key, params, testSettings, hookData);
    }
}
