// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IntentChannel} from "../channels/IntentChannel.sol";
import {BaseHook} from "v4-periphery/src/utils/BaseHook.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {SwapParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "@uniswap/v4-core/src/types/BeforeSwapDelta.sol";

contract YellowClearingHook is BaseHook {
  // forge-lint: disable-next-line(screaming-snake-case-immutable)
  IntentChannel public immutable channel;
  // forge-lint: disable-next-line(screaming-snake-case-immutable)
  address public immutable committer;

  constructor(IPoolManager poolManager_, IntentChannel channel_, address committer_) BaseHook(poolManager_) {
    channel = channel_;
    committer = committer_;
  }
  // Demo-only: bypass hook address validation to allow standard deployment.
  // Remove this override for production (hooks should be deployed at permission-encoded addresses).
  function validateHookAddress(BaseHook) internal pure override {}



  function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
    return Hooks.Permissions({
      beforeInitialize: false,
      afterInitialize: false,
      beforeAddLiquidity: false,
      afterAddLiquidity: false,
      beforeRemoveLiquidity: false,
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

  function _beforeSwap(
    address sender,
    PoolKey calldata,
    SwapParams calldata,
    bytes calldata hookData
  ) internal view override returns (bytes4, BeforeSwapDelta, uint24) {
    require(sender == committer, "NOT_COMMITTER");

    (bytes32 intentHash, uint256 minOut, uint256 deadline) = abi.decode(
      hookData,
      (bytes32, uint256, uint256)
    );

    require(channel.planHashOf(intentHash) != bytes32(0), "INTENT_NOT_COMMITTED");
    require(channel.status(intentHash) == IntentChannel.IntentStatus.Released, "NOT_RELEASED");
    require(block.timestamp >= channel.notBeforeOf(intentHash), "BATCH_NOT_READY");
    require(block.timestamp <= deadline, "HOOK_DEADLINE");
    require(block.timestamp <= channel.deadlineOf(intentHash), "INTENT_DEADLINE");
    require(minOut == channel.minOutOf(intentHash), "MIN_OUT_MISMATCH");

    return (BaseHook.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);
  }
}
