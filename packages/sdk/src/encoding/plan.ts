import { encodeAbiParameters, keccak256 } from "viem";

export type Address = `0x${string}`;
export type Hex = `0x${string}`;

export interface RfqStep {
  makerFill: Address;
  maker: Address;
  amountOut: bigint;
  expiry: number;
  makerSig: Hex;
}

export interface AmmStep {
  poolManager: Address;
  adapter: Address;
  fallbackData: Hex;
}

export interface LifiStep {
  lifiDiamond: Address;
  approvalAddress: Address;
  callData: Hex;
  value: bigint;
  minAmountOut: bigint;
  toChainId: number;
}

export interface ExecutionPlan {
  intentHash: Hex;
  primary: RfqStep;
  amm: AmmStep;
  lifi: LifiStep;
  deadline: number;
}

const PLAN_ABI = [
  {
    name: "plan",
    type: "tuple",
    components: [
      { name: "intentHash", type: "bytes32" },
      {
        name: "primary",
        type: "tuple",
        components: [
          { name: "makerFill", type: "address" },
          { name: "maker", type: "address" },
          { name: "amountOut", type: "uint256" },
          { name: "expiry", type: "uint256" },
          { name: "makerSig", type: "bytes" }
        ]
      },
      {
        name: "amm",
        type: "tuple",
        components: [
          { name: "poolManager", type: "address" },
          { name: "adapter", type: "address" },
          { name: "fallbackData", type: "bytes" }
        ]
      },
      {
        name: "lifi",
        type: "tuple",
        components: [
          { name: "lifiDiamond", type: "address" },
          { name: "approvalAddress", type: "address" },
          { name: "callData", type: "bytes" },
          { name: "value", type: "uint256" },
          { name: "minAmountOut", type: "uint256" },
          { name: "toChainId", type: "uint256" }
        ]
      },
      { name: "deadline", type: "uint256" }
    ]
  }
] as const;

export function hashExecutionPlan(plan: ExecutionPlan): Hex {
  const encoded = encodeAbiParameters(PLAN_ABI, [plan]);
  return keccak256(encoded);
}
