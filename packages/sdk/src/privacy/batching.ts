export function alignToBatchWindow(timestamp: bigint, batchWindow: bigint): bigint {
  if (batchWindow === 0n) return timestamp;
  const rounded = (timestamp / batchWindow) * batchWindow;
  if (timestamp % batchWindow === 0n) return timestamp;
  return rounded + batchWindow;
}

export function calculateNotBefore(minDelay: bigint, batchWindow: bigint, desiredTime?: bigint): bigint {
  const now = BigInt(Math.floor(Date.now() / 1000));
  const earliest = now + minDelay;
  const proposed = desiredTime ?? earliest;
  const normalized = proposed < earliest ? earliest : proposed;
  return alignToBatchWindow(normalized, batchWindow);
}
