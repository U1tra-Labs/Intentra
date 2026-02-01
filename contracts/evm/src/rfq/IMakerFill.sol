// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IMakerFill {
  function fill(
    bytes32 intentHash,
    address inputToken,
    address outputToken,
    uint256 amountIn,
    uint256 minOut,
    bytes calldata makerPayload
  ) external returns (uint256 amountOut);
}
