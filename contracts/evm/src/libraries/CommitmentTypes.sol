// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

library CommitmentTypes {
  // keccak256("Commitment(bytes32 intentHash,bytes32 planHash,uint256 notBefore,bytes32 salt)")
  bytes32 internal constant COMMITMENT_TYPEHASH =
    0xa72657cc1df3ea2c1c6383385c4ff188673e234f04b7f455097ee261abb3a95c;

  function hash(
    bytes32 intentHash,
    bytes32 planHash,
    uint256 notBefore,
    bytes32 salt
  ) internal pure returns (bytes32) {
    return keccak256(abi.encode(COMMITMENT_TYPEHASH, intentHash, planHash, notBefore, salt));
  }

  function verify(
    bytes32 commitment,
    bytes32 intentHash,
    bytes32 planHash,
    uint256 notBefore,
    bytes32 salt
  ) internal pure returns (bool) {
    return commitment == hash(intentHash, planHash, notBefore, salt);
  }
}
