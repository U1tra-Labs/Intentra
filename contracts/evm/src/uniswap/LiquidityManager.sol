// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {ModifyLiquidityParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {IUnlockCallback} from "@uniswap/v4-core/src/interfaces/callback/IUnlockCallback.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {BalanceDelta, BalanceDeltaLibrary} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {Currency, CurrencyLibrary} from "@uniswap/v4-core/src/types/Currency.sol";

interface IERC20Minimal {
  function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

contract LiquidityManager is IUnlockCallback {
  using BalanceDeltaLibrary for BalanceDelta;
  using CurrencyLibrary for Currency;

  struct CallbackData {
    PoolKey key;
    ModifyLiquidityParams params;
    bytes hookData;
    address payer;
  }

  // forge-lint: disable-next-line(screaming-snake-case-immutable)
  IPoolManager public immutable poolManager;

  constructor(IPoolManager poolManager_) {
    poolManager = poolManager_;
  }

  function initializePool(PoolKey calldata key, uint160 sqrtPriceX96) external {
    poolManager.initialize(key, sqrtPriceX96);
  }

  function modifyLiquidity(
    PoolKey calldata key,
    ModifyLiquidityParams calldata params,
    bytes calldata hookData,
    address payer
  ) external returns (BalanceDelta callerDelta) {
    bytes memory result = poolManager.unlock(abi.encode(CallbackData({
      key: key,
      params: params,
      hookData: hookData,
      payer: payer
    })));

    callerDelta = abi.decode(result, (BalanceDelta));
  }

  function unlockCallback(bytes calldata data) external returns (bytes memory result) {
    require(msg.sender == address(poolManager), "NOT_POOL_MANAGER");

    CallbackData memory decoded = abi.decode(data, (CallbackData));
    (BalanceDelta callerDelta, ) = poolManager.modifyLiquidity(decoded.key, decoded.params, decoded.hookData);

    _settleLiquidity(decoded.key, callerDelta, decoded.payer);
    result = abi.encode(callerDelta);
  }

  function _settleLiquidity(PoolKey memory key, BalanceDelta delta, address payer) internal {
    int128 amount0 = delta.amount0();
    int128 amount1 = delta.amount1();

    // forge-lint: disable-next-line(unsafe-typecast)
    if (amount0 < 0) _settleCurrencyFrom(key.currency0, payer, uint256(uint128(-amount0)));
    // forge-lint: disable-next-line(unsafe-typecast)
    if (amount1 < 0) _settleCurrencyFrom(key.currency1, payer, uint256(uint128(-amount1)));
    // forge-lint: disable-next-line(unsafe-typecast)
    if (amount0 > 0) poolManager.take(key.currency0, payer, uint256(uint128(amount0)));
    // forge-lint: disable-next-line(unsafe-typecast)
    if (amount1 > 0) poolManager.take(key.currency1, payer, uint256(uint128(amount1)));
  }

  function _settleCurrencyFrom(Currency currency, address payer, uint256 amount) internal {
    if (amount == 0) return;
    require(!currency.isAddressZero(), "NATIVE_NOT_SUPPORTED");

    poolManager.sync(currency);
    bool ok = IERC20Minimal(Currency.unwrap(currency)).transferFrom(payer, address(poolManager), amount);
    require(ok, "TRANSFER_FROM_FAILED");
    poolManager.settle();
  }
}
