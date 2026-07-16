/** Minimal ABIs for the three deployed contracts. */

export const settlementEngineAbi = [
  {
    type: "function",
    name: "affirm",
    stateMutability: "nonpayable",
    inputs: [
      {
        name: "instruction",
        type: "tuple",
        components: [
          { name: "security", type: "bytes32" },
          { name: "cash", type: "address" },
          { name: "seller", type: "address" },
          { name: "buyer", type: "address" },
          { name: "quantity", type: "uint256" },
          { name: "consideration", type: "uint256" },
          { name: "deadline", type: "uint64" },
          { name: "venue", type: "address" },
        ],
      },
    ],
    outputs: [{ name: "id", type: "bytes32" }],
  },
  {
    type: "function",
    name: "settle",
    stateMutability: "nonpayable",
    inputs: [{ name: "id", type: "bytes32" }],
    outputs: [],
  },
  {
    type: "function",
    name: "settleBatch",
    stateMutability: "nonpayable",
    inputs: [{ name: "ids", type: "bytes32[]" }],
    outputs: [],
  },
  {
    type: "function",
    name: "cancel",
    stateMutability: "nonpayable",
    inputs: [{ name: "id", type: "bytes32" }],
    outputs: [],
  },
  {
    type: "function",
    name: "settledCount",
    stateMutability: "view",
    inputs: [],
    outputs: [{ type: "uint256" }],
  },
  {
    type: "event",
    name: "InstructionSettled",
    inputs: [
      { name: "id", type: "bytes32", indexed: true },
      { name: "seller", type: "address", indexed: true },
      { name: "buyer", type: "address", indexed: true },
    ],
  },
] as const;

export const nettingEngineAbi = [
  {
    type: "function",
    name: "settleSession",
    stateMutability: "nonpayable",
    inputs: [
      {
        name: "session",
        type: "tuple",
        components: [
          { name: "security", type: "bytes32" },
          { name: "cash", type: "address" },
          {
            name: "legs",
            type: "tuple[]",
            components: [
              { name: "party", type: "address" },
              { name: "quantityDelta", type: "int256" },
              { name: "cashDelta", type: "int256" },
            ],
          },
        ],
      },
      { name: "grossTrades", type: "uint256" },
    ],
    outputs: [],
  },
  {
    type: "function",
    name: "sessionCount",
    stateMutability: "view",
    inputs: [],
    outputs: [{ type: "uint256" }],
  },
  {
    type: "function",
    name: "grossTradesNetted",
    stateMutability: "view",
    inputs: [],
    outputs: [{ type: "uint256" }],
  },
] as const;

export const assetRegistryAbi = [
  {
    type: "function",
    name: "securityOf",
    stateMutability: "view",
    inputs: [{ name: "id", type: "bytes32" }],
    outputs: [
      {
        type: "tuple",
        components: [
          { name: "token", type: "address" },
          { name: "ticker", type: "bytes12" },
          { name: "isin", type: "bytes12" },
          { name: "custodian", type: "address" },
          { name: "decimals", type: "uint8" },
          { name: "listing", type: "uint8" },
        ],
      },
    ],
  },
  {
    type: "function",
    name: "isSettleable",
    stateMutability: "view",
    inputs: [{ name: "id", type: "bytes32" }],
    outputs: [{ type: "bool" }],
  },
  {
    type: "function",
    name: "idOfToken",
    stateMutability: "view",
    inputs: [{ name: "token", type: "address" }],
    outputs: [{ type: "bytes32" }],
  },
  {
    type: "function",
    name: "count",
    stateMutability: "view",
    inputs: [],
    outputs: [{ type: "uint256" }],
  },
] as const;
