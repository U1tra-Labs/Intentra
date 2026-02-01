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

export interface Quote {
  makerFill: Address;
  maker: Address;
  amountOut: bigint;
  expiry: number;
  makerSig: Hex;
}
