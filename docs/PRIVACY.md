# Privacy Features

## Overview
Intentra supports three privacy-enhancing mechanisms:

1. Private intent submission: commitments hide trade details until execution.
2. Maker quote privacy: sealed bids prevent quote sniping.
3. Time-delayed batching: aligned execution reduces adverse selection.

## Flow Diagram

[User] -> commit(hash) -> [IntentChannel]
         (wait for notBefore)
[Maker] -> sealed quote -> [Yellow Network]
         (batch window closes)
[Executor] -> reveal + execute -> [Hook validates] -> [Uniswap v4]

## Commitment Format
Commitment is a keccak256 hash of a typed payload:

Commitment(bytes32 intentHash, bytes32 planHash, uint256 notBefore, bytes32 salt)

## Commitment Authorization (EIP-712)
Relayer submissions use a typed signature so the relayer cannot alter escrow parameters.

Primary type:
CommitmentAuthorization(
  bytes32 commitment,
  address trader,
  address inputToken,
  uint256 amountIn,
  uint256 deadline,
  uint256 notBefore
)

Domain:
- name: IntentChannel
- version: 1
- chainId: current chain id
- verifyingContract: IntentChannel address

## Configuration
- minDelay: minimum time between commit and reveal (e.g., 30s)
- batchWindow: batch alignment period (e.g., 5 minutes)
- Setting both to 0 disables batching (instant private execution)

## Security Considerations
- Salt must be cryptographically random (use generateSalt()).
- notBefore prevents timing attacks and enforces batching.
- Commitments are collision-resistant.
- Unrevealed commitments can be refunded after deadline.
- Private commits currently expect ERC20 input tokens (wrap native if needed).
