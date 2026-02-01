export const IntentChannelAbi = [
  {
    type: "event",
    name: "IntentCommitted",
    inputs: [
      { name: "intentHash", type: "bytes32", indexed: true },
      { name: "trader", type: "address", indexed: true },
      { name: "planHash", type: "bytes32", indexed: false },
      { name: "amountIn", type: "uint256", indexed: false },
      { name: "minOut", type: "uint256", indexed: false },
      { name: "deadline", type: "uint256", indexed: false }
    ]
  },
  {
    type: "event",
    name: "IntentReleased",
    inputs: [
      { name: "intentHash", type: "bytes32", indexed: true },
      { name: "to", type: "address", indexed: true },
      { name: "amountIn", type: "uint256", indexed: false }
    ]
  },
  {
    type: "event",
    name: "IntentExecuted",
    inputs: [
      { name: "intentHash", type: "bytes32", indexed: true },
      { name: "usedFallback", type: "bool", indexed: false },
      { name: "amountOut", type: "uint256", indexed: false }
    ]
  },
  {
    type: "event",
    name: "IntentCancelled",
    inputs: [{ name: "intentHash", type: "bytes32", indexed: true }]
  },
  {
    type: "event",
    name: "IntentRefunded",
    inputs: [{ name: "intentHash", type: "bytes32", indexed: true }]
  },
  {
    type: "function",
    name: "status",
    stateMutability: "view",
    inputs: [{ name: "intentHash", type: "bytes32" }],
    outputs: [{ name: "", type: "uint8" }]
  },
  {
    type: "function",
    name: "destChainIdOf",
    stateMutability: "view",
    inputs: [{ name: "intentHash", type: "bytes32" }],
    outputs: [{ name: "", type: "uint256" }]
  }
] as const;
