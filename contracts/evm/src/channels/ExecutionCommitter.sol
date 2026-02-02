// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IIntent} from "../interfaces/IIntent.sol";
import {IntentChannel} from "./IntentChannel.sol";
import {IMakerFill} from "../rfq/IMakerFill.sol";
import {SafeTransferLib, IERC20} from "../utils/SafeTransferLib.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {SwapParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {IUnlockCallback} from "@uniswap/v4-core/src/interfaces/callback/IUnlockCallback.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {BalanceDelta, BalanceDeltaLibrary} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {Currency, CurrencyLibrary} from "@uniswap/v4-core/src/types/Currency.sol";

contract ExecutionCommitter is IUnlockCallback {
  using SafeTransferLib for IERC20;
  using BalanceDeltaLibrary for BalanceDelta;
  using CurrencyLibrary for Currency;

  error SwapFailed(bytes reason);


  // forge-lint: disable-next-line(screaming-snake-case-immutable)
  IntentChannel public immutable channel;
  // forge-lint: disable-next-line(screaming-snake-case-immutable)
  IPoolManager public immutable poolManager;

  bool private inUnlock;

  event Executed(bytes32 indexed intentHash, uint256 amountOut, bool usedFallback);

  constructor(IntentChannel channel_, IPoolManager poolManager_) {
    channel = channel_;
    poolManager = poolManager_;
  }

  function executeWithReveal(
    bytes32 commitment,
    IIntent.TradingIntent calldata intent,
    bytes calldata traderSig,
    IIntent.ExecutionPlan calldata plan,
    bytes32 salt
  ) external returns (uint256 amountOut, bool usedFallback) {
    channel.revealIntent(commitment, intent, traderSig, plan, salt);
    return execute(plan);
  }

  function execute(IIntent.ExecutionPlan calldata plan) public returns (uint256 amountOut, bool usedFallback) {
    // forge-lint: disable-next-line(asm-keccak256)
    bytes32 planHash = keccak256(abi.encode(plan));
    require(channel.planHashOf(plan.intentHash) == planHash, "PLAN_HASH_MISMATCH");
    require(block.timestamp <= plan.deadline, "PLAN_EXPIRED");

    (
      address trader,
      address inputToken,
      address outputToken,
      uint256 amountIn,
      uint256 minOut,
      uint256 intentDeadline,
      uint256 destChainId
    ) = channel.getIntentData(plan.intentHash);

    require(trader != address(0), "INTENT_NOT_FOUND");
    require(block.timestamp <= intentDeadline, "INTENT_EXPIRED");

    uint256 pulled = channel.takeInputForExecution(plan.intentHash, address(this));
    require(pulled == amountIn && pulled > 0, "BAD_INPUT_AMOUNT");

    bool rfqSuccess = false;
    bool usedLifi = false;
    if (plan.primary.makerFill != address(0) && plan.primary.expiry >= block.timestamp) {
      _safeApprove(inputToken, plan.primary.makerFill, amountIn);
      (bool ok, bytes memory data) = plan.primary.makerFill.call(
        abi.encodeWithSelector(
          IMakerFill.fill.selector,
          plan.intentHash,
          inputToken,
          outputToken,
          amountIn,
          minOut,
          abi.encode(plan.primary)
        )
      );
      if (ok) {
        require(data.length >= 32, "RFQ_BAD_RETURN");
        amountOut = abi.decode(data, (uint256));
        if (amountOut < minOut) revert("RFQ_TOO_LOW");
        rfqSuccess = true;
      }
    }

    if (!rfqSuccess) {
      usedFallback = true;
      if (plan.lifi.lifiDiamond != address(0)) {
        usedLifi = true;
        require(plan.lifi.toChainId == destChainId, "LIFI_DEST_MISMATCH");
        amountOut = _executeLifi(plan, inputToken, amountIn, minOut);
      } else {
        amountOut = _executeV4Fallback(plan);
      }
    }

    require(amountOut >= minOut, "INSUFFICIENT_OUT");
    if (!usedLifi) {
      _payout(outputToken, trader, amountOut);
    }

    channel.markExecuted(plan.intentHash, amountOut, usedFallback);
    emit Executed(plan.intentHash, amountOut, usedFallback);
  }

  function _executeV4Fallback(IIntent.ExecutionPlan calldata plan) internal returns (uint256 amountOut) {
    require(plan.amm.poolManager == address(poolManager), "POOL_MANAGER_MISMATCH");
    require(plan.amm.fallbackData.length > 0, "NO_FALLBACK");

    bytes memory result = poolManager.unlock(plan.amm.fallbackData);
    amountOut = abi.decode(result, (uint256));
  }

  function _executeLifi(
    IIntent.ExecutionPlan calldata plan,
    address inputToken,
    uint256 amountIn,
    uint256 minOut
  ) internal returns (uint256 amountOut) {
    require(plan.lifi.callData.length > 0, "NO_LIFI_CALLDATA");
    require(plan.lifi.minAmountOut >= minOut, "LIFI_MIN_OUT");

    if (inputToken == address(0)) {
      require(plan.lifi.value >= amountIn, "LIFI_VALUE_LOW");
    } else if (plan.lifi.approvalAddress != address(0)) {
      _safeApprove(inputToken, plan.lifi.approvalAddress, amountIn);
    }

    (bool ok, ) = plan.lifi.lifiDiamond.call{value: plan.lifi.value}(plan.lifi.callData);
    require(ok, "LIFI_CALL_FAILED");

    amountOut = plan.lifi.minAmountOut;
  }

  function unlockCallback(bytes calldata data) external returns (bytes memory result) {
    require(msg.sender == address(poolManager), "NOT_POOL_MANAGER");
    require(!inUnlock, "REENTRANCY");
    inUnlock = true;

    (PoolKey memory key, SwapParams memory params, bytes memory hookData) = abi.decode(
      data,
      (PoolKey, SwapParams, bytes)
    );
    require(params.amountSpecified < 0, "NOT_EXACT_INPUT");

    BalanceDelta swapDelta;
    try poolManager.swap(key, params, hookData) returns (BalanceDelta delta) {
      swapDelta = delta;
    } catch (bytes memory reason) {
      inUnlock = false;
      revert SwapFailed(reason);
    }
    uint256 amountOut = _settleSwap(key, params, swapDelta);

    inUnlock = false;
    result = abi.encode(amountOut);
  }

  function _settleSwap(
    PoolKey memory key,
    SwapParams memory params,
    BalanceDelta delta
  ) internal returns (uint256 amountOut) {
    int128 amount0 = delta.amount0();
    int128 amount1 = delta.amount1();

    // forge-lint: disable-next-line(unsafe-typecast)
    if (amount0 < 0) _settleCurrency(key.currency0, uint256(uint128(-amount0)));
    // forge-lint: disable-next-line(unsafe-typecast)
    if (amount1 < 0) _settleCurrency(key.currency1, uint256(uint128(-amount1)));
    // forge-lint: disable-next-line(unsafe-typecast)
    if (amount0 > 0) _takeCurrency(key.currency0, uint256(uint128(amount0)));
    // forge-lint: disable-next-line(unsafe-typecast)
    if (amount1 > 0) _takeCurrency(key.currency1, uint256(uint128(amount1)));

    if (params.zeroForOne) {
      // forge-lint: disable-next-line(unsafe-typecast)
      amountOut = amount1 > 0 ? uint256(uint128(amount1)) : 0;
    } else {
      // forge-lint: disable-next-line(unsafe-typecast)
      amountOut = amount0 > 0 ? uint256(uint128(amount0)) : 0;
    }

    require(amountOut > 0, "NO_OUTPUT");
  }

  function _settleCurrency(Currency currency, uint256 amount) internal {
    if (amount == 0) return;
    if (currency.isAddressZero()) {
      poolManager.settle{value: amount}();
      return;
    }

    poolManager.sync(currency);
    IERC20(Currency.unwrap(currency)).safeTransfer(address(poolManager), amount);
    poolManager.settle();
  }

  function _takeCurrency(Currency currency, uint256 amount) internal {
    if (amount == 0) return;
    poolManager.take(currency, address(this), amount);
  }

  function _payout(address outputToken, address trader, uint256 amountOut) internal {
    if (outputToken == address(0)) {
      (bool ok, ) = trader.call{value: amountOut}("");
      require(ok, "NATIVE_PAYOUT_FAILED");
    } else {
      IERC20(outputToken).safeTransfer(trader, amountOut);
    }
  }

  function _safeApprove(address token, address spender, uint256 amount) internal {
    (bool ok, bytes memory data) = token.call(abi.encodeWithSignature("approve(address,uint256)", spender, amount));
    require(ok && (data.length == 0 || abi.decode(data, (bool))), "APPROVE_FAILED");
  }

  receive() external payable {}
}
