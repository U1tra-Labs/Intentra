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
    name: "IntentCommittedPrivate",
    inputs: [
      { name: "commitment", type: "bytes32", indexed: true },
      { name: "trader", type: "address", indexed: true },
      { name: "inputToken", type: "address", indexed: false },
      { name: "amountIn", type: "uint256", indexed: false },
      { name: "notBefore", type: "uint256", indexed: false },
      { name: "deadline", type: "uint256", indexed: false }
    ]
  },
  {
    type: "event",
    name: "IntentRevealed",
    inputs: [
      { name: "commitment", type: "bytes32", indexed: true },
      { name: "intentHash", type: "bytes32", indexed: true },
      { name: "planHash", type: "bytes32", indexed: true },
      { name: "trader", type: "address", indexed: false }
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
    type: "event",
    name: "CommitmentCancelled",
    inputs: [
      { name: "commitment", type: "bytes32", indexed: true },
      { name: "trader", type: "address", indexed: true },
      { name: "refundAmount", type: "uint256", indexed: false }
    ]
  },
  {
    type: "event",
    name: "BatchWindowUpdated",
    inputs: [
      { name: "oldWindow", type: "uint256", indexed: false },
      { name: "newWindow", type: "uint256", indexed: false }
    ]
  },
  {
    type: "event",
    name: "MinDelayUpdated",
    inputs: [
      { name: "oldDelay", type: "uint256", indexed: false },
      { name: "newDelay", type: "uint256", indexed: false }
    ]
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
  },
  {
    type: "function",
    name: "notBeforeOf",
    stateMutability: "view",
    inputs: [{ name: "intentHash", type: "bytes32" }],
    outputs: [{ name: "", type: "uint256" }]
  }
] as const;
