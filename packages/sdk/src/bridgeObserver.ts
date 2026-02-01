import chalk from "chalk";

interface LifiStatusResponse {
  status?: string;
  substatus?: string;
  substatusMessage?: string;
  receiving?: {
    chainId?: number;
    txHash?: string;
  };
}

export interface BridgeMonitorOptions {
  pollMs?: number;
  apiKey?: string;
  onUpdate?: (status: LifiStatusResponse) => void;
}

export function monitorCrossChainIntent(
  sourceTxHash: string,
  sourceChainId: number,
  opts: BridgeMonitorOptions = {}
): () => void {
  const pollMs = opts.pollMs ?? 15000;
  const apiKey = opts.apiKey ?? process.env.LIFI_API_KEY;
  const headers: Record<string, string> = {};
  if (apiKey) headers["x-lifi-api-key"] = apiKey;

  console.log(chalk.cyan(`\n[BridgeMonitor] Tracking settlement for ${sourceTxHash}...`));

  let stopped = false;
  const checkStatus = async () => {
    if (stopped) return;
    try {
      const params = new URLSearchParams({
        txHash: sourceTxHash,
        fromChain: String(sourceChainId)
      });
      const response = await fetch(`https://li.quest/v1/status?${params.toString()}`, { headers });
      if (!response.ok) return;
      const data = (await response.json()) as LifiStatusResponse;
      opts.onUpdate?.(data);

      const status = data.status?.toUpperCase();
      if (status === "DONE") {
        console.log(chalk.green("\n✔ INTENT SETTLED ON DESTINATION"));
        if (data.receiving?.chainId) console.log(chalk.gray(`Dest Chain: ${data.receiving.chainId}`));
        if (data.receiving?.txHash) console.log(chalk.gray(`Dest Tx: ${data.receiving.txHash}`));
        stop();
        return;
      }
      if (status === "FAILED" || status === "INVALID") {
        const msg = data.substatusMessage ?? data.substatus ?? "Unknown error";
        console.log(chalk.red(`\n✖ BRIDGE FAILED: ${msg}`));
        stop();
        return;
      }

      process.stdout.write(chalk.yellow("."));
    } catch {
      // keep polling on transient errors
    }
  };

  const timer = setInterval(checkStatus, pollMs);
  void checkStatus();

  const stop = () => {
    if (stopped) return;
    stopped = true;
    clearInterval(timer);
  };

  return stop;
}
