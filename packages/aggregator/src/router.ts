import type { TradingIntent, ExecutionPlan, Address } from "./types";
import type { IntentDomain } from "./intent";
import { requestQuote, pickBestQuote, type MakerEndpoint } from "./rfq";
import { buildUniswapV4FallbackStep, type ReadContractClient } from "./amm/uniswapV4";
import { getLifiQuote } from "./lifi";
import { buildPlan } from "./planBuilder";

export async function routeIntent(args: {
  intent: TradingIntent;
  domain: IntentDomain;
  rfqMakers?: MakerEndpoint[];
  uniswapAdapter: `0x${string}`;
  poolManager: `0x${string}`;
  publicClient: ReadContractClient;
}): Promise<ExecutionPlan> {
  const crossChain = args.intent.sourceChainId !== args.intent.destChainId;
  const quotes = crossChain ? [] : await requestQuote(args.intent, args.rfqMakers ?? []);
  const best = crossChain ? null : await pickBestQuote(args.intent, quotes);

  const lifiQuote = crossChain ? await getLifiQuote(args.intent) : null;
  if (crossChain && !lifiQuote?.transactionRequest) {
    throw new Error("NO_LIFI_ROUTE");
  }
  if (crossChain && lifiQuote?.estimate) {
    const feeTotal = sumCosts(lifiQuote.estimate.feeCosts ?? [], args.intent);
    const gasTotal = sumCosts(lifiQuote.estimate.gasCosts ?? [], args.intent);
    const totalCost = feeTotal + gasTotal;
    if (totalCost > 0n && totalCost * 2n > args.intent.amountIn) {
      throw new Error("INSUFFICIENT_VALUE_FOR_BRIDGE_FEES");
    }
  }

  return buildPlan({
    intent: args.intent,
    domain: args.domain,
    rfqQuote: best,
    buildFallback: crossChain
      ? undefined
      : (intentHash) =>
          buildUniswapV4FallbackStep({
            client: args.publicClient,
            adapter: args.uniswapAdapter,
            poolManager: args.poolManager,
            intentHash,
            intent: args.intent
          }),
    buildLifi:
      crossChain
        ? async () => {
            const approvalAddress =
              lifiQuote?.estimate?.approvalAddress ?? "0x0000000000000000000000000000000000000000";
            const minAmountOut = lifiQuote?.estimate?.toAmountMin ?? "0";
            return {
              lifiDiamond: lifiQuote!.transactionRequest!.to,
              approvalAddress,
              callData: lifiQuote!.transactionRequest!.data,
              value: parseAmount(lifiQuote!.transactionRequest!.value),
              minAmountOut: BigInt(minAmountOut),
              toChainId: args.intent.destChainId
            };
          }
        : undefined
  });
}

function parseAmount(value: string | number | bigint | undefined): bigint {
  if (value === undefined) return 0n;
  if (typeof value === "bigint") return value;
  if (typeof value === "number") return BigInt(value);
  return value.startsWith("0x") ? BigInt(value) : BigInt(value);
}

const ZERO_ADDRESS = "0x0000000000000000000000000000000000000000";
const NATIVE_LIFI = "0xeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee";

function sumCosts(
  costs: Array<{ amount?: string; token?: { address?: Address; chainId?: number } }>,
  intent: TradingIntent
): bigint {
  let total = 0n;
  for (const cost of costs) {
    const amount = cost.amount ? BigInt(cost.amount) : 0n;
    if (amount == 0n) continue;
    const token = cost.token?.address?.toLowerCase();
    const chainId = cost.token?.chainId;
    if (chainId && chainId !== intent.sourceChainId) continue;
    if (!token) continue;
    if (matchesToken(token, intent.inputToken)) {
      total += amount;
    }
  }
  return total;
}

function matchesToken(token: string, inputToken: Address): boolean {
  const input = inputToken.toLowerCase();
  if (token === input) return true;
  return isNativeToken(token) && isNativeToken(input);
}

function isNativeToken(token: string): boolean {
  return token === ZERO_ADDRESS || token === NATIVE_LIFI;
}
