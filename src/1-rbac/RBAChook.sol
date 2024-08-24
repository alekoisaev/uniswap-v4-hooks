// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BaseHook} from "v4-periphery/base/hooks/BaseHook.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {IERC1155} from "openzeppelin-contracts/contracts/token/ERC1155/IERC1155.sol";

contract RBACHook is BaseHook {
    /// @dev Thrown when trying to perform a modifyPosition operation without the proper credential
    error MissingAmulet();
    /// @dev Thrown when trying to perform a swap operation without the proper credential
    error MissingPirateCredential();
    /// @dev Thrown when the lock acquirer does not match the allowed pool operator
    error NotPoolOperator();

    /// @dev IERC1155 Multi Token Standard contract that contains the credentials to operate with this pool
    IERC1155 immutable pirateChest;
    /// @dev Only our specific pool operator may engage with pool to swap or modifyPosition and thus, with these hooks.
    address allowedPoolOperator;

    /// @dev ID for the credential necessary to perform modifyPosition operations
    uint256 public constant AMULET = 1;
    /// @dev ID for the credential necessary to perform swap operations
    uint256 public constant PIRATE_CREDENTIAL = 2;

    /// keccak(DeltaUnspecified) - 1
    bytes32 constant DELTA_UNSPECIFIED_SLOT = 0x2e5feb220472ad9c92768617797b419bfabdc71375060ca8a1052c1ad7a5383b;

    constructor(IPoolManager _poolManager, address _pirateChest, address _allowedPoolOperator) BaseHook(_poolManager) {
        allowedPoolOperator = _allowedPoolOperator;
        pirateChest = IERC1155(_pirateChest);
    }

    modifier poolOperatorOnly(address sender) {
        if (sender != address(allowedPoolOperator)) revert NotPoolOperator();
        _;
    }

    /// @dev Lists the callbacks this hook implements.
    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: false,
            afterInitialize: false,
            beforeAddLiquidity: true,
            afterAddLiquidity: false,
            beforeRemoveLiquidity: true,
            afterRemoveLiquidity: false,
            beforeSwap: true,
            afterSwap: false,
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: false,
            afterSwapReturnDelta: false,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }

    ////////////////////////////////
    ////// Action Callbacks ////////
    ////////////////////////////////
    function beforeSwap(
        address sender,
        PoolKey calldata,
        IPoolManager.SwapParams calldata,
        bytes calldata hookData
    ) external view override poolOperatorOnly(sender) returns (bytes4) {
        address user = _getUserAddress(hookData);

        if (pirateChest.balanceOf(user, PIRATE_CREDENTIAL) == 0) {
            revert MissingPirateCredential();
        }

        return BaseHook.beforeSwap.selector;
    }

    function beforeAddLiquidity(
        address sender,
        PoolKey calldata,
        IPoolManager.ModifyLiquidityParams calldata,
        bytes calldata hookData
    ) external view override poolOperatorOnly(sender) returns (bytes4) {
        address user = _getUserAddress(hookData);

        if (pirateChest.balanceOf(user, AMULET) == 0) {
            revert MissingAmulet();
        }

        return BaseHook.beforeAddLiquidity.selector;
    }

    function beforeRemoveLiquidity(
        address sender,
        PoolKey calldata,
        IPoolManager.ModifyLiquidityParams calldata,
        bytes calldata hookData
    ) external view override poolOperatorOnly(sender) returns (bytes4) {
        address user = _getUserAddress(hookData);

        if (pirateChest.balanceOf(user, AMULET) == 0) {
            revert MissingAmulet();
        }

        return BaseHook.beforeRemoveLiquidity.selector;
    }

    //////////////////////////////////
    ////// Internal Functions ////////
    //////////////////////////////////

    function _getUserAddress(bytes calldata hookData) internal pure returns (address user) {
        user = abi.decode(hookData, (address));
    }
}
