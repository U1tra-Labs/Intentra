import type { TradingIntent, Quote, ExecutionPlan, RfqStep, AmmStep, LifiStep, Address, Hex } from "./types";
import type { IntentDomain } from "./intent";
import { hashIntent } from "./intent";

const ZERO_ADDRESS = "0x0000000000000000000000000000000000000000" as Address;
const ZERO_BYTES32 = ("0x" + "00".repeat(32)) as Hex;
const ZERO_BYTES = "0x" as Hex;

export async function buildPlan(args: {
  intent: TradingIntent;
  domain: IntentDomain;
  rfqQuote: Quote | null;
  buildFallback?: (intentHash: Hex) => Promise<AmmStep> | AmmStep;
  buildLifi?: (intentHash: Hex) => Promise<LifiStep | null> | LifiStep | null;
}): Promise<ExecutionPlan> {
  const intentHash = hashIntent(args.intent, args.domain);
  const ammFallback: AmmStep = args.buildFallback
    ? await args.buildFallback(intentHash)
    : {
        poolManager: ZERO_ADDRESS,
        adapter: ZERO_ADDRESS,
        fallbackData: ZERO_BYTES
      };
  const lifiFallback = args.buildLifi ? await args.buildLifi(intentHash) : null;

  const lifi: LifiStep = lifiFallback ?? {
    lifiDiamond: ZERO_ADDRESS,
    approvalAddress: ZERO_ADDRESS,
    callData: ZERO_BYTES,
    value: 0n,
    minAmountOut: 0n,
    toChainId: 0
  };
  const primary: RfqStep = args.rfqQuote
    ? {
        makerFill: args.rfqQuote.makerFill,
        maker: args.rfqQuote.maker,
        amountOut: args.rfqQuote.amountOut,
        expiry: args.rfqQuote.expiry,
        makerSig: args.rfqQuote.makerSig
      }
    : {
        makerFill: ZERO_ADDRESS,
        maker: ZERO_ADDRESS,
        amountOut: 0n,
        expiry: 0,
        makerSig: ZERO_BYTES32
      };

  return {
    intentHash,
    primary,
    amm: ammFallback,
    lifi,
    deadline: args.intent.deadline
  };
}

export { hashIntent };
