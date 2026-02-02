import { encodeAbiParameters, keccak256, toHex } from "viem";

export type Hex = `0x${string}`;

const COMMITMENT_TYPEHASH = keccak256(
  toHex("Commitment(bytes32 intentHash,bytes32 planHash,uint256 notBefore,bytes32 salt)")
);

export function hashCommitment(params: {
  intentHash: Hex;
  planHash: Hex;
  notBefore: bigint;
  salt: Hex;
}): Hex {
  return keccak256(
    encodeAbiParameters(
      [
        { name: "typeHash", type: "bytes32" },
        { name: "intentHash", type: "bytes32" },
        { name: "planHash", type: "bytes32" },
        { name: "notBefore", type: "uint256" },
        { name: "salt", type: "bytes32" }
      ],
      [COMMITMENT_TYPEHASH, params.intentHash, params.planHash, params.notBefore, params.salt]
    )
  );
}

export interface CommitmentRecord {
  commitment: Hex;
  intentHash: Hex;
  planHash: Hex;
  salt: Hex;
  notBefore: bigint;
  status: "pending" | "revealed" | "executed" | "cancelled" | "refunded";
}
