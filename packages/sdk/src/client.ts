import type { TradingIntent } from "./privacy/eip712";
import { signIntent } from "./privacy/eip712";
import { hashExecutionPlan } from "./encoding/plan";
import { routeIntent } from "../../aggregator/src/router";
import type { MakerEndpoint } from "../../aggregator/src/rfq";
import type { ExecutionPlan } from "../../aggregator/src/types";

export type Address = `0x${string}`;
export type Hex = `0x${string}`;

export interface PublicClient {
  readContract: (args: {
    address: Address;
    abi: unknown[];
    functionName: string;
    args: readonly unknown[];
  }) => Promise<any>;
}

export interface WalletClient {
  signTypedData: (args: {
    domain: {
      name: string;
      version: string;
      chainId: number;
      verifyingContract: Address;
    };
    types: Record<string, Array<{ name: string; type: string }>>;
    primaryType: string;
    message: Record<string, unknown>;
  }) => Promise<Hex>;
  writeContract: (args: {
    address: Address;
    abi: unknown[];
    functionName: string;
    args: readonly unknown[];
    value?: bigint;
  }) => Promise<string>;
}

const INTENT_CHANNEL_ABI = [
  {
    type: "function",
    name: "commitIntent",
    stateMutability: "nonpayable",
    inputs: [
      {
        name: "intent",
        type: "tuple",
        components: [
          { name: "trader", type: "address" },
          { name: "inputToken", type: "address" },
          { name: "outputToken", type: "address" },
          { name: "amountIn", type: "uint256" },
          { name: "minOut", type: "uint256" },
          { name: "deadline", type: "uint256" },
          { name: "nonce", type: "uint256" },
          { name: "sourceChainId", type: "uint256" },
          { name: "destChainId", type: "uint256" }
        ]
      },
      { name: "traderSig", type: "bytes" },
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
    ],
    outputs: [
      { name: "intentHash", type: "bytes32" },
      { name: "planHash", type: "bytes32" }
    ]
  },
  {
    type: "function",
    name: "commitIntentPrivate",
    stateMutability: "payable",
    inputs: [
      { name: "commitment", type: "bytes32" },
      { name: "inputToken", type: "address" },
      { name: "amountIn", type: "uint256" },
      { name: "deadline", type: "uint256" },
      { name: "notBefore", type: "uint256" },
      { name: "trader", type: "address" },
      { name: "traderSig", type: "bytes" }
    ],
    outputs: []
  },
  {
    type: "function",
    name: "revealIntent",
    stateMutability: "nonpayable",
    inputs: [
      { name: "commitment", type: "bytes32" },
      {
        name: "intent",
        type: "tuple",
        components: [
          { name: "trader", type: "address" },
          { name: "inputToken", type: "address" },
          { name: "outputToken", type: "address" },
          { name: "amountIn", type: "uint256" },
          { name: "minOut", type: "uint256" },
          { name: "deadline", type: "uint256" },
          { name: "nonce", type: "uint256" },
          { name: "sourceChainId", type: "uint256" },
          { name: "destChainId", type: "uint256" }
        ]
      },
      { name: "traderSig", type: "bytes" },
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
      },
      { name: "salt", type: "bytes32" }
    ],
    outputs: [
      { name: "intentHash", type: "bytes32" },
      { name: "planHash", type: "bytes32" }
    ]
  }
] as const;

const EXECUTION_COMMITTER_ABI = [
  {
    type: "function",
    name: "execute",
    stateMutability: "nonpayable",
    inputs: [
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
    ],
    outputs: [
      { name: "amountOut", type: "uint256" },
      { name: "usedFallback", type: "bool" }
    ]
  },
  {
    type: "function",
    name: "executeWithReveal",
    stateMutability: "nonpayable",
    inputs: [
      { name: "commitment", type: "bytes32" },
      {
        name: "intent",
        type: "tuple",
        components: [
          { name: "trader", type: "address" },
          { name: "inputToken", type: "address" },
          { name: "outputToken", type: "address" },
          { name: "amountIn", type: "uint256" },
          { name: "minOut", type: "uint256" },
          { name: "deadline", type: "uint256" },
          { name: "nonce", type: "uint256" },
          { name: "sourceChainId", type: "uint256" },
          { name: "destChainId", type: "uint256" }
        ]
      },
      { name: "traderSig", type: "bytes" },
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
      },
      { name: "salt", type: "bytes32" }
    ],
    outputs: [
      { name: "amountOut", type: "uint256" },
      { name: "usedFallback", type: "bool" }
    ]
  }
] as const;

export class DemoClient {
  constructor(
    readonly cfg: {
      intentChannel: Address;
      executionCommitter: Address;
      uniswapAdapter: Address;
      poolManager: Address;
      chainId: number;
      publicClient: PublicClient;
      walletClient: WalletClient;
      rfqMakers?: MakerEndpoint[];
    }
  ) {}

  async demoTrade(intent: TradingIntent): Promise<{
    intentHash: Hex;
    planHash: Hex;
    commitTx: string;
    execTx: string;
  }> {
    const traderSig = await signIntent(intent, this.cfg.walletClient, {
      chainId: this.cfg.chainId,
      verifyingContract: this.cfg.intentChannel
    });

    const plan = await routeIntent({
      intent,
      domain: {
        chainId: this.cfg.chainId,
        verifyingContract: this.cfg.intentChannel
      },
      rfqMakers: this.cfg.rfqMakers,
      uniswapAdapter: this.cfg.uniswapAdapter,
      poolManager: this.cfg.poolManager,
      publicClient: this.cfg.publicClient
    });

    const planHash = hashExecutionPlan(plan);

    const commitTx = await this.cfg.walletClient.writeContract({
      address: this.cfg.intentChannel,
      abi: INTENT_CHANNEL_ABI,
      functionName: "commitIntent",
      args: [intent, traderSig, plan]
    });

    const execTx = await this.cfg.walletClient.writeContract({
      address: this.cfg.executionCommitter,
      abi: EXECUTION_COMMITTER_ABI,
      functionName: "execute",
      args: [plan]
    });

    return {
      intentHash: plan.intentHash,
      planHash,
      commitTx,
      execTx
    };
  }

  async commitPrivateIntent(args: {
    commitment: Hex;
    inputToken: Address;
    amountIn: bigint;
    deadline: number;
    notBefore: number;
    trader: Address;
    traderSig?: Hex;
    value?: bigint;
  }): Promise<string> {
    return this.cfg.walletClient.writeContract({
      address: this.cfg.intentChannel,
      abi: INTENT_CHANNEL_ABI,
      functionName: "commitIntentPrivate",
      args: [
        args.commitment,
        args.inputToken,
        args.amountIn,
        args.deadline,
        args.notBefore,
        args.trader,
        args.traderSig ?? "0x"
      ],
      value: args.value
    });
  }

  async revealIntent(args: {
    commitment: Hex;
    intent: TradingIntent;
    traderSig: Hex;
    plan: ExecutionPlan;
    salt: Hex;
  }): Promise<string> {
    return this.cfg.walletClient.writeContract({
      address: this.cfg.intentChannel,
      abi: INTENT_CHANNEL_ABI,
      functionName: "revealIntent",
      args: [args.commitment, args.intent, args.traderSig, args.plan, args.salt]
    });
  }

  async executeWithReveal(args: {
    commitment: Hex;
    intent: TradingIntent;
    traderSig: Hex;
    plan: ExecutionPlan;
    salt: Hex;
  }): Promise<string> {
    return this.cfg.walletClient.writeContract({
      address: this.cfg.executionCommitter,
      abi: EXECUTION_COMMITTER_ABI,
      functionName: "executeWithReveal",
      args: [args.commitment, args.intent, args.traderSig, args.plan, args.salt]
    });
  }
}
