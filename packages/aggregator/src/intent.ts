import { hashTypedData } from "viem";
import type { Address, Hex, TradingIntent } from "./types";

export interface IntentDomain {
  chainId: number;
  verifyingContract: Address;
  name?: string;
  version?: string;
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
    primaryType: "TradingIntent";
    message: TradingIntent;
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

export function buildIntentDomain(domain: IntentDomain) {
  return {
    name: domain.name ?? "IntentChannel",
    version: domain.version ?? "1",
    chainId: domain.chainId,
    verifyingContract: domain.verifyingContract
  };
}

export function hashIntent(intent: TradingIntent, domain: IntentDomain): Hex {
  return hashTypedData({
    domain: buildIntentDomain(domain),
    types: INTENT_TYPES,
    primaryType: "TradingIntent",
    message: intent
  });
}

export async function signIntent(
  intent: TradingIntent,
  signer: EIP712Signer,
  domain: IntentDomain
): Promise<Hex> {
  return signer.signTypedData({
    domain: buildIntentDomain(domain),
    types: INTENT_TYPES,
    primaryType: "TradingIntent",
    message: intent
  });
}
