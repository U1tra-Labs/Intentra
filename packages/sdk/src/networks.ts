export type NetworkName = "Ethereum" | "Base" | "Arbitrum" | "Optimism";

export interface NetworkInfo {
  name: NetworkName;
  chainId: number;
  nativeSymbol: string;
}

export const NETWORKS: Record<NetworkName, NetworkInfo> = {
  Ethereum: { name: "Ethereum", chainId: 1, nativeSymbol: "ETH" },
  Base: { name: "Base", chainId: 8453, nativeSymbol: "ETH" },
  Arbitrum: { name: "Arbitrum", chainId: 42161, nativeSymbol: "ETH" },
  Optimism: { name: "Optimism", chainId: 10, nativeSymbol: "ETH" }
};

export function getNetwork(name: string): NetworkInfo | undefined {
  const key = name as NetworkName;
  return NETWORKS[key];
}

export function getNetworkByChainId(chainId: number): NetworkInfo | undefined {
  return Object.values(NETWORKS).find((net) => net.chainId === chainId);
}
