import { createPublicClient, http } from "viem";
import type { Address } from "viem";
import chalk from "chalk";
import { IntentChannelAbi } from "./abi/IntentChannel.js";

export interface LogReaderConfig {
  rpcUrl: string;
  intentChannel: `0x${string}`;
  fromBlock?: bigint;
}

export interface ExecutionEvent {
  txHash: `0x${string}`;
  intentHash: `0x${string}`;
  usedFallback: boolean;
  chainId: number;
  destChainId?: number;
  blockNumber: bigint;
}

type EventLog = {
  eventName: string;
  args: Record<string, unknown>;
  blockNumber: bigint;
  transactionHash: `0x${string}`;
  logIndex: number | bigint;
};

function shortHex(value: string): string {
  if (value.length <= 10) return value;
  return `${value.slice(0, 6)}…${value.slice(-4)}`;
}

function toStringValue(value: unknown): string {
  if (typeof value === "bigint") return value.toString();
  if (typeof value === "boolean") return value ? "true" : "false";
  if (typeof value === "string") return value;
  return JSON.stringify(value);
}

function colorEvent(name: string, usedFallback?: boolean): string {
  if (name === "IntentCommitted") return chalk.cyan(name);
  if (name === "IntentReleased") return chalk.blue(name);
  if (name === "IntentCancelled" || name === "IntentRefunded") return chalk.red(name);
  if (name === "IntentExecuted") {
    return usedFallback ? chalk.yellow("IntentExecuted(AMM)") : chalk.green("IntentExecuted(RFQ)");
  }
  return name;
}

export async function watchIntentChannel(
  cfg: LogReaderConfig,
  onExecution?: (event: ExecutionEvent) => void
): Promise<() => void> {
  const client = createPublicClient({
    transport: http(cfg.rpcUrl)
  });
  const chainId = await client.getChainId();

  const seen = new Set<string>();

  const unwatch = client.watchContractEvent({
    address: cfg.intentChannel as Address,
    abi: IntentChannelAbi,
    fromBlock: cfg.fromBlock,
    onLogs: async (logs) => {
      for (const log of logs as unknown as EventLog[]) {
        const key = `${log.transactionHash}:${String(log.logIndex)}`;
        if (seen.has(key)) continue;
        seen.add(key);

        const name = log.eventName;
        const intentHashFull = String((log.args as any).intentHash ?? "") as `0x${string}`;
        const intentHash = shortHex(intentHashFull);
        const usedFallback = name === "IntentExecuted" ? Boolean((log.args as any).usedFallback) : undefined;
        const eventLabel = colorEvent(name, usedFallback);

        const fields: string[] = [];
        if (name === "IntentCommitted") {
          fields.push(`trader=${shortHex(String((log.args as any).trader))}`);
          fields.push(`amountIn=${toStringValue((log.args as any).amountIn)}`);
          fields.push(`minOut=${toStringValue((log.args as any).minOut)}`);
          fields.push(`dl=${toStringValue((log.args as any).deadline)}`);
        } else if (name === "IntentReleased") {
          fields.push(`to=${shortHex(String((log.args as any).to))}`);
          fields.push(`amountIn=${toStringValue((log.args as any).amountIn)}`);
        } else if (name === "IntentExecuted") {
          fields.push(`amountOut=${toStringValue((log.args as any).amountOut)}`);
          if (onExecution) {
            let destChainId: number | undefined;
            try {
              const value = await client.readContract({
                address: cfg.intentChannel as Address,
                abi: IntentChannelAbi,
                functionName: "destChainIdOf",
                args: [intentHashFull]
              });
              destChainId = Number(value);
            } catch {
              destChainId = undefined;
            }

            onExecution({
              txHash: log.transactionHash,
              intentHash: intentHashFull,
              usedFallback: Boolean(usedFallback),
              chainId,
              destChainId,
              blockNumber: log.blockNumber
            });
          }
        }

        const meta = `chain=${chainId} tx=${shortHex(log.transactionHash)}`;
        const line = `#${log.blockNumber.toString()} ${intentHash} ${eventLabel} ${meta}`;
        const extra = fields.length ? " " + fields.join(" ") : "";
        process.stdout.write(line + extra + "\n");
      }
    }
  });

  return () => unwatch();
}
