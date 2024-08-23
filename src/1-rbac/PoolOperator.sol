// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IUnlockCallback} from "v4-core/interfaces/callback/IUnlockCallback.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {BalanceDelta} from "v4-core/types/BalanceDelta.sol";
import {Currency, CurrencyLibrary} from "v4-core/types/Currency.sol";
import {CurrencySettler} from "./utils/CurrencySettler.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

contract PoolOperator is IUnlockCallback {
    using CurrencyLibrary for Currency;
    using CurrencySettler for Currency;

    /// @dev Thrown when msg.sender is not the pool operator (this contract)
    error NotPoolOperator();
    /// @dev Thrown when msg.sender is not the Uniswap V4 Pool Manager contract
    error NotPoolManager();
    /// @dev Thrown when actions performed while the lock has been acquired fail
    error LockFailure();

    /// @dev Uniswap V4 pool manager
    IPoolManager public immutable poolManager;

    constructor(IPoolManager _poolManager) {
        poolManager = _poolManager;
    }

    /// @dev Only the pool manager may call this function
    modifier poolManagerOnly() {
        if (msg.sender != address(poolManager)) revert NotPoolManager();
        _;
    }

    /// @dev Only the pool operator itself may call this function
    modifier poolOperatorOnly() {
        if (msg.sender != address(this)) revert NotPoolOperator();
        _;
    }

    ///////////////////////
    ////// Actions ////////
    ///////////////////////

    /// @notice Performs a swap operation
    /// @dev Requests a unlock from the pool manager and when acquired, it performs the swap on the callback
    /// @param key Uniquely identifies the pool to use for the swap
    /// @param params Describes the swap operation
    function unlockSwap(PoolKey memory key, IPoolManager.SwapParams memory params) public {
        poolManager.unlock(abi.encodeCall(this.performSwap, (key, params, msg.sender)));
    }

    /// @notice Modifies a liquidity position
    /// @dev Requests a unlock from the pool manager and when acquired, it performs a modifyPosition operation on the callback
    /// @param key Uniquely identifies the pool to use for the swap
    /// @param params Describes the modifyPosition operation
    function unlockModifyLiquidity(PoolKey memory key, IPoolManager.ModifyLiquidityParams memory params) external {
        poolManager.unlock(abi.encodeCall(this.performModifyLiquidity, (key, params, msg.sender)));
    }

    ///////////////////////////////////////
    ////// Unlock Callback ////////
    //////////////////////////////////////

    function unlockCallback(bytes calldata data) external virtual poolManagerOnly returns (bytes memory) {
        (bool success, bytes memory returnData) = address(this).call(data);
        if (success) return returnData;
        if (returnData.length == 0) revert LockFailure();
        // If the call failed, bubble up the reason
        assembly ("memory-safe") {
            revert(add(returnData, 32), mload(returnData))
        }
    }

    ///////////////////////
    ////// Handlers ///////
    ///////////////////////
    function performSwap(
        PoolKey memory key,
        IPoolManager.SwapParams memory params,
        address user
    ) external poolOperatorOnly returns (BalanceDelta delta) {
        // Call `swap` with the user address encoded as `hookData`
        poolManager.swap(key, params, abi.encode(user));
    }

    function performModifyLiquidity(
        PoolKey memory key,
        IPoolManager.ModifyLiquidityParams memory params,
        address user
    ) external poolOperatorOnly returns (BalanceDelta delta) {
        // Call `modifyLiquidity` with the user address as `hookData`
        (delta,) = poolManager.modifyLiquidity(key, params, abi.encode(user));
        // At this point, the `beforeModifyLiquidity` in our hook contract has already been executed

        int256 delta0 = delta.amount0();
        int256 delta1 = delta.amount1();

        if (delta0 < 0) key.currency0.settle(poolManager, user, uint256(-delta0), false);
        if (delta1 < 0) key.currency1.settle(poolManager, user, uint256(-delta1), false);
        if (delta0 > 0) key.currency0.take(poolManager, user, uint256(delta0), false);
        if (delta1 > 0) key.currency1.take(poolManager, user, uint256(delta1), false);
    }
}
