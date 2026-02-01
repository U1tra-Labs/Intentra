import type { Quote, TradingIntent, Address } from "./types";

export interface MakerEndpoint {
  maker: Address;
  makerFill: Address;
  url: string;
}

export const DEFAULT_MAKERS: MakerEndpoint[] = [];

export async function requestQuote(intent: TradingIntent, makers: MakerEndpoint[] = DEFAULT_MAKERS): Promise<Quote[]> {
  if (makers.length === 0) return [];

  const requests = makers.map(async (maker) => {
    try {
      const res = await fetch(maker.url, {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ intent })
      });
      if (!res.ok) return null;
      const data = await res.json();
      return {
        maker: maker.maker,
        makerFill: maker.makerFill,
        amountOut: BigInt(data.amountOut ?? 0),
        expiry: Number(data.expiry ?? 0),
        makerSig: data.makerSig as `0x${string}`
      } as Quote;
    } catch {
      return null;
    }
  });

  const results = await Promise.all(requests);
  return results.filter((q): q is Quote => q !== null);
}

export async function pickBestQuote(intent: TradingIntent, quotes: Quote[]): Promise<Quote | null> {
  const now = Math.floor(Date.now() / 1000);
  const valid = quotes.filter((q) => q.expiry >= now && q.amountOut >= intent.minOut);
  if (valid.length === 0) return null;
  return valid.reduce((best, q) => (q.amountOut > best.amountOut ? q : best), valid[0]);
}
