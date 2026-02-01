// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {SwapParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";

contract UniswapV4Adapter {
  // forge-lint: disable-next-line(screaming-snake-case-immutable)
  address public immutable poolManager;
  // forge-lint: disable-next-line(screaming-snake-case-immutable)
  address public immutable hook;
  // forge-lint: disable-next-line(screaming-snake-case-immutable)
  uint24 public immutable fee;
  // forge-lint: disable-next-line(screaming-snake-case-immutable)
  int24 public immutable tickSpacing;

  constructor(address poolManager_, address hook_, uint24 fee_, int24 tickSpacing_) {
    poolManager = poolManager_;
    hook = hook_;
    fee = fee_;
    tickSpacing = tickSpacing_;
  }

  function buildFallbackData(
    bytes32 intentHash,
    address inputToken,
    address outputToken,
    uint256 amountIn,
    uint256 minOut,
    uint256 deadline
  ) external view returns (bytes memory fallbackData) {
    Currency currencyIn = Currency.wrap(inputToken);
    Currency currencyOut = Currency.wrap(outputToken);
    bool zeroForOne = Currency.unwrap(currencyIn) < Currency.unwrap(currencyOut);

    PoolKey memory key = PoolKey({
      currency0: zeroForOne ? currencyIn : currencyOut,
      currency1: zeroForOne ? currencyOut : currencyIn,
      fee: fee,
      tickSpacing: tickSpacing,
      hooks: IHooks(hook)
    });

    uint160 sqrtPriceLimitX96 = zeroForOne
      ? TickMath.MIN_SQRT_PRICE + 1
      : TickMath.MAX_SQRT_PRICE - 1;

    SwapParams memory params = SwapParams({
      zeroForOne: zeroForOne,
      // forge-lint: disable-next-line(unsafe-typecast)
      amountSpecified: -int256(amountIn),
      sqrtPriceLimitX96: sqrtPriceLimitX96
    });

    bytes memory hookData = abi.encode(intentHash, minOut, deadline);
    fallbackData = abi.encode(key, params, hookData);
  }
}
