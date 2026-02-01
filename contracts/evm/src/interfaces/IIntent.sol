// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IIntent {
  struct TradingIntent {
    address trader;
    address inputToken;
    address outputToken;
    uint256 amountIn;
    uint256 minOut;
    uint256 deadline;
    uint256 nonce;
    uint256 sourceChainId;
    uint256 destChainId;
  }

  struct RfqStep {
    address makerFill; // contract that executes fill
    address maker;     // maker address (for signature/identity)
    uint256 amountOut; // quoted out
    uint256 expiry;
    bytes makerSig;    // EIP-712 quote sig
  }

  struct AmmStep {
    address poolManager;
    address adapter;      // optional provenance helper
    bytes fallbackData;   // abi.encode(PoolKey, SwapParams, hookData)
  }

  struct LifiStep {
    address lifiDiamond;
    address approvalAddress;
    bytes callData;
    uint256 value;
    uint256 minAmountOut;
    uint256 toChainId;
  }

  struct ExecutionPlan {
    bytes32 intentHash;
    RfqStep primary;
    AmmStep amm;
    LifiStep lifi;
    uint256 deadline;
  }
}
