#!/usr/bin/env node
import { watchIntentChannel } from "../logReader.js";
import { monitorCrossChainIntent } from "../bridgeObserver.js";

function getArg(name: string, args: string[]): string | undefined {
  const idx = args.indexOf(`--${name}`);
  if (idx === -1) return undefined;
  return args[idx + 1];
}

function usage(): void {
  process.stdout.write(
    "Usage: yellow-watch --rpc <url> --channel <address> [--from-block <number>]\n" +
      "Examples:\n" +
      "  yellow-watch --rpc https://... --channel 0x...\n" +
      "  RPC_URL=... INTENT_CHANNEL=0x... yellow-watch\n"
  );
}

async function main() {
  const args = process.argv.slice(2);
  const rpc = getArg("rpc", args) ?? process.env.RPC_URL;
  const channel = getArg("channel", args) ?? process.env.INTENT_CHANNEL;
  const fromBlockRaw = getArg("from-block", args);

  if (!rpc || !channel) {
    usage();
    process.exit(1);
  }

  const fromBlock = fromBlockRaw ? BigInt(fromBlockRaw) : undefined;
  const monitors = new Set<string>();

  process.stdout.write(`Watching IntentChannel: ${channel}\n`);
  const stop = await watchIntentChannel(
    {
      rpcUrl: rpc,
      intentChannel: channel as `0x${string}`,
      fromBlock
    },
    (event) => {
      if (!event.usedFallback) return;
      if (event.destChainId === undefined) return;
      if (event.destChainId === event.chainId) return;
      if (monitors.has(event.txHash)) return;
      monitors.add(event.txHash);
      monitorCrossChainIntent(event.txHash, event.chainId);
    }
  );

  process.on("SIGINT", () => {
    stop();
    process.stdout.write("\nStopped.\n");
    process.exit(0);
  });
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
