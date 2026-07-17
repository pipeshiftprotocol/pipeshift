# @pipeshift/sdk

Settlement SDK for tokenized equities on Robinhood Chain: atomic delivery versus payment,
multilateral netting, canonical asset registry.

```bash
npm install @pipeshift/sdk
```

## Netting

```ts
import { compressionOf, netTrades, withoutFlatLegs } from "@pipeshift/sdk";

const session = netTrades(security, usdc, trades);
const report = compressionOf(session, trades.length);

console.log(`${report.grossTransfers} gross, ${report.netTransfers} netted`);
console.log(`${report.flatParties} desks ended flat`);

await client.settleSession(withoutFlatLegs(session), trades.length);
```

`netTrades` sorts legs by party address, so the same trade set always produces the same
session regardless of the order trades arrived in. It throws `NettingImbalanceError` with
the residual attached if the result would not sum to zero, which turns a reverted
transaction into a local error.

## Settlement

```ts
import { PipeshiftClient, instructionId, validate } from "@pipeshift/sdk";

const client = new PipeshiftClient({ publicClient, walletClient, deployment });

const problems = validate(instruction, now);
if (problems.length > 0) throw new Error(problems.join(", "));

const { id } = await client.affirm(instruction);
await client.settle(id);
```

`validate` returns every problem rather than the first, so a venue can fix a whole batch in
one pass instead of discovering issues one revert at a time. `instructionId` computes the
same id the contract does, so a trade can be referenced before it is submitted.

## Read only clients

A client constructed without a `walletClient` can read everything and write nothing. Write
calls throw `ReadOnlyClientError` instead of failing at the RPC layer.

```ts
const reader = new PipeshiftClient({ publicClient, deployment });

await reader.settledCount();      // works
await reader.grossTradesNetted(); // works
await reader.settle(id);          // throws ReadOnlyClientError
```

## Amounts

Every amount is `bigint` in base units. The SDK never accepts a `number` for an amount and
the CLI rejects number literals in input files, because a float that reaches a settlement
amount is a position break waiting to happen.

## CLI

The package ships a `pipeshift` binary. Every command is offline and read only.

```bash
pipeshift net session.json
pipeshift validate instruction.json
pipeshift security AAPL US0378331005
```

## License

MIT
