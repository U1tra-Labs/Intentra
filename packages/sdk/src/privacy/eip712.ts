import { hashTypedData } from "viem";

export type Address = `0x${string}`;
export type Hex = `0x${string}`;

export interface TradingIntent {
  trader: Address;
  inputToken: Address;
  outputToken: Address;
  amountIn: bigint;
  minOut: bigint;
  deadline: number;
  nonce: bigint;
  sourceChainId: number;
  destChainId: number;
}

export interface MakerQuote {
  intentHash: Hex;
  inputToken: Address;
  outputToken: Address;
  amountIn: bigint;
  amountOut: bigint;
  expiry: number;
}

export interface CommitmentAuthorization {
  commitment: Hex;
  trader: Address;
  inputToken: Address;
  amountIn: bigint;
  deadline: number;
  notBefore: number;
}

export interface EIP712Signer {
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
}

export const INTENT_TYPES = {
  TradingIntent: [
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
} as const;

export const QUOTE_TYPES = {
  MakerQuote: [
    { name: "intentHash", type: "bytes32" },
    { name: "inputToken", type: "address" },
    { name: "outputToken", type: "address" },
    { name: "amountIn", type: "uint256" },
    { name: "amountOut", type: "uint256" },
    { name: "expiry", type: "uint256" }
  ]
} as const;

export const COMMITMENT_AUTH_TYPES = {
  CommitmentAuthorization: [
    { name: "commitment", type: "bytes32" },
    { name: "trader", type: "address" },
    { name: "inputToken", type: "address" },
    { name: "amountIn", type: "uint256" },
    { name: "deadline", type: "uint256" },
    { name: "notBefore", type: "uint256" }
  ]
} as const;

export function hashIntent(intent: TradingIntent, domain: { chainId: number; verifyingContract: Address; name?: string; version?: string }): Hex {
  return hashTypedData({
    domain: {
      name: domain.name ?? "IntentChannel",
      version: domain.version ?? "1",
      chainId: domain.chainId,
      verifyingContract: domain.verifyingContract
    },
    types: INTENT_TYPES,
    primaryType: "TradingIntent",
    message: intent
  });
}

export async function signIntent(
  intent: TradingIntent,
  signer: EIP712Signer,
  domain: { chainId: number; verifyingContract: Address; name?: string; version?: string }
): Promise<Hex> {
  return signer.signTypedData({
    domain: {
      name: domain.name ?? "IntentChannel",
      version: domain.version ?? "1",
      chainId: domain.chainId,
      verifyingContract: domain.verifyingContract
    },
    types: INTENT_TYPES,
    primaryType: "TradingIntent",
    message: intent
  });
}

export function hashMakerQuote(
  quote: MakerQuote,
  domain: { chainId: number; verifyingContract: Address; name?: string; version?: string }
): Hex {
  return hashTypedData({
    domain: {
      name: domain.name ?? "MakerFill",
      version: domain.version ?? "1",
      chainId: domain.chainId,
      verifyingContract: domain.verifyingContract
    },
    types: QUOTE_TYPES,
    primaryType: "MakerQuote",
    message: quote
  });
}

export async function signMakerQuote(
  quote: MakerQuote,
  signer: EIP712Signer,
  domain: { chainId: number; verifyingContract: Address; name?: string; version?: string }
): Promise<Hex> {
  return signer.signTypedData({
    domain: {
      name: domain.name ?? "MakerFill",
      version: domain.version ?? "1",
      chainId: domain.chainId,
      verifyingContract: domain.verifyingContract
    },
    types: QUOTE_TYPES,
    primaryType: "MakerQuote",
    message: quote
  });
}

export function hashCommitmentAuthorization(
  authorization: CommitmentAuthorization,
  domain: { chainId: number; verifyingContract: Address; name?: string; version?: string }
): Hex {
  return hashTypedData({
    domain: {
      name: domain.name ?? "IntentChannel",
      version: domain.version ?? "1",
      chainId: domain.chainId,
      verifyingContract: domain.verifyingContract
    },
    types: COMMITMENT_AUTH_TYPES,
    primaryType: "CommitmentAuthorization",
    message: authorization
  });
}

export async function signCommitmentAuthorization(
  authorization: CommitmentAuthorization,
  signer: EIP712Signer,
  domain: { chainId: number; verifyingContract: Address; name?: string; version?: string }
): Promise<Hex> {
  return signer.signTypedData({
    domain: {
      name: domain.name ?? "IntentChannel",
      version: domain.version ?? "1",
      chainId: domain.chainId,
      verifyingContract: domain.verifyingContract
    },
    types: COMMITMENT_AUTH_TYPES,
    primaryType: "CommitmentAuthorization",
    message: authorization
  });
}
