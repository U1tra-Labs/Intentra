import type { Address, Hex, TradingIntent } from "./types";

export interface LifiQuote {
  transactionRequest?: {
    to: Address;
    data: Hex;
    value: string;
  };
  estimate?: {
    toAmountMin?: string;
    approvalAddress?: Address;
    feeCosts?: Array<{
      amount?: string;
      token?: {
        address?: Address;
        chainId?: number;
      };
    }>;
    gasCosts?: Array<{
      amount?: string;
      token?: {
        address?: Address;
        chainId?: number;
      };
    }>;
  };
}

export async function getLifiQuote(intent: TradingIntent): Promise<LifiQuote | null> {
  const params = new URLSearchParams({
    fromChain: String(intent.sourceChainId),
    toChain: String(intent.destChainId),
    fromToken: intent.inputToken,
    toToken: intent.outputToken,
    fromAmount: intent.amountIn.toString(),
    fromAddress: intent.trader,
    toAddress: intent.trader
  });

  const url = `https://li.quest/v1/quote?${params.toString()}`;
  const headers: Record<string, string> = {};
  const apiKey = process.env.LIFI_API_KEY;
  if (apiKey) headers["x-lifi-api-key"] = apiKey;

  try {
    const response = await fetch(url, { headers });
    if (!response.ok) return null;
    return (await response.json()) as LifiQuote;
  } catch {
    return null;
  }
}
