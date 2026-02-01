export const PYTH_HERMES_URL = "https://hermes.pyth.network";
export const PYTH_ETH_USD_PRICE_ID =
  "0xff61491a931112ddf1bd8147cd1b641375f79f5825126d665480874634fd0ace";

export interface PythPrice {
  price: number;
  conf: number;
  publishTime: number;
}

export interface PythPriceResult {
  status: "ok" | "error";
  data?: PythPrice;
}

export async function fetchPythPrice(
  priceId: string = PYTH_ETH_USD_PRICE_ID,
  hermesUrl: string = PYTH_HERMES_URL
): Promise<PythPriceResult> {
  try {
    const url = `${hermesUrl}/v2/updates/price/latest?ids[]=${priceId}`;
    const res = await fetch(url);
    if (!res.ok) return { status: "error" };
    const payload = await res.json();
    const parsed = payload?.parsed?.[0];
    const priceData = parsed?.price;
    if (!priceData) return { status: "error" };

    const expo = Number(priceData.expo);
    const price = Number(priceData.price) * 10 ** expo;
    const conf = Number(priceData.conf) * 10 ** expo;
    const publishTime = Number(priceData.publish_time);

    return { status: "ok", data: { price, conf, publishTime } };
  } catch {
    return { status: "error" };
  }
}
