import type { Address, AmmStep, TradingIntent, Hex } from "../types";

export interface ReadContractClient {
  readContract: (args: {
    address: Address;
    abi: unknown[];
    functionName: string;
    args: readonly unknown[];
  }) => Promise<Hex>;
}

const ADAPTER_ABI = [
  {
    type: "function",
    name: "buildFallbackData",
    stateMutability: "view",
    inputs: [
      { name: "intentHash", type: "bytes32" },
      { name: "inputToken", type: "address" },
      { name: "outputToken", type: "address" },
      { name: "amountIn", type: "uint256" },
      { name: "minOut", type: "uint256" },
      { name: "deadline", type: "uint256" }
    ],
    outputs: [{ name: "fallbackData", type: "bytes" }]
  }
] as const;

export async function buildUniswapV4FallbackStep(args: {
  client: ReadContractClient;
  adapter: Address;
  poolManager: Address;
  intentHash: Hex;
  intent: TradingIntent;
}): Promise<AmmStep> {
  const fallbackData = await args.client.readContract({
    address: args.adapter,
    abi: ADAPTER_ABI,
    functionName: "buildFallbackData",
    args: [
      args.intentHash,
      args.intent.inputToken,
      args.intent.outputToken,
      args.intent.amountIn,
      args.intent.minOut,
      args.intent.deadline
    ]
  });

  return {
    poolManager: args.poolManager,
    adapter: args.adapter,
    fallbackData
  };
}
