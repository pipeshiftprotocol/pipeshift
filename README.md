<div align="center">

<img src="assets/banner.jpg" alt="Pipeshift" width="100%">

### The settlement layer for tokenized equities on Robinhood Chain

Venues match. Pipeshift settles.

[![License: MIT](https://img.shields.io/badge/license-MIT-0AE8A6.svg?style=flat-square)](LICENSE)
[![Solidity](https://img.shields.io/badge/solidity-0.8.24-0AE8A6.svg?style=flat-square)](contracts/foundry.toml)
[![TypeScript](https://img.shields.io/badge/typescript-5.6-0AE8A6.svg?style=flat-square)](sdk-ts/package.json)
[![Tests](https://img.shields.io/badge/tests-80%20passing-0AE8A6.svg?style=flat-square)](.github/workflows/ci.yml)
[![E2E](https://img.shields.io/badge/e2e-live%20node%20%2B%20chain%20fork-0AE8A6.svg?style=flat-square)](sdk-ts/e2e)
[![Chain](https://img.shields.io/badge/chain-Robinhood%20Chain-221B1D.svg?style=flat-square)](https://pipeshift.trade)

[**What it does**](#what-it-does) ·
[**How it works**](#how-it-works) ·
[**Quickstart**](#quickstart) ·
[**CLI**](#cli) ·
[**Contracts**](#contracts) ·
[**Roadmap**](#roadmap)

</div>

---

## What it does

Trading venues are good at matching. They are not good at settling, and every venue that
builds its own settlement path builds its own way to break.

Pipeshift is the layer underneath. It does three things and nothing else.

**Atomic delivery versus payment.** The security leg and the cash leg move in one
transaction. There is no state in which the shares have moved and the money has not.

**Multilateral netting.** A desk that buys 400 shares and sells 380 in the same session
owes 20. Pipeshift collapses a trade file into one net position per party, so the work
scales with participants rather than with trades.

**One canonical registry.** Every venue settles against the same record of what a token
represents, keyed by ticker and ISIN rather than by token address. A reissued token keeps
its identity and its history.

Pipeshift is not a DEX, not a venue, and not a custodian. It holds no positions between
calls and takes no view on price.

## How it works

```
venue matches a trade
        │
        ├── affirm(instruction) ──────► instruction stored, nothing moves yet
        │                                     │
        │                                     ▼
        │                              settle(id)
        │                                     │
        │                    ┌────────────────┴────────────────┐
        │                    ▼                                 ▼
        │            security leg moves                cash leg moves
        │            seller ──► buyer                  buyer ──► seller
        │                    └────────────────┬────────────────┘
        │                                     ▼
        │                          both legs land, or neither does
        │
        └── many trades ──► netTrades() ──► settleSession(session)
                                                  │
                                                  ▼
                                    one net transfer per party per leg
```

Affirming and settling are separate steps on purpose. A venue affirms as soon as it has a
match, which is cheap and moves nothing. Settlement can then be triggered by anyone,
batched, or deferred until the counterparties have funded, and the deadline on the
instruction bounds how long that can take.

## Quickstart

```bash
git clone --recurse-submodules https://github.com/pipeshiftprotocol/pipeshift.git
cd pipeshift

# contracts
cd contracts
forge test

# sdk and cli
cd ../sdk-ts
npm install
npm test
```

### Run it against a real node

The unit suites prove the logic. These prove the whole thing works end to end: a real
node, a real deployment, real transactions and real receipts.

```bash
cd sdk-ts

# starts anvil, deploys the devnet fixture, settles against it, tears the node down
npm run e2e:full

# same suite against a fork of Robinhood Chain, so the contracts run with the
# chain's own id, gas parameters and EVM revision
npm run e2e:fork
```

Both are green today. The fork run reports `chain id 4663` and settles a matched trade, a
reverting trade and a netting session against forked state.

What the e2e suite asserts, on chain rather than in a harness:

- A matched trade moves both legs, and the SDK computes the same instruction id the contract stores.
- A trade whose cash leg cannot move reverts, and the security leg stays where it was.
- A netting session computed by the SDK settles, and only the net quantity moves.
- An unbalanced session is rejected locally, before it costs gas.
- A client built without a wallet refuses to write at all.

Netting a trade file into the positions that actually have to move:

```ts
import { compressionOf, netTrades, withoutFlatLegs } from "@pipeshift/sdk";

const session = netTrades(security, usdc, trades);
const report = compressionOf(session, trades.length);

console.log(`${report.grossTransfers} transfers gross, ${report.netTransfers} netted`);

await client.settleSession(withoutFlatLegs(session), trades.length);
```

Settling a single matched trade:

```ts
import { PipeshiftClient, validate } from "@pipeshift/sdk";

const client = new PipeshiftClient({ publicClient, walletClient, deployment });

const problems = validate(instruction, now);
if (problems.length > 0) throw new Error(problems.join(", "));

const { id } = await client.affirm(instruction);
await client.settle(id);
```

## CLI

Every command is offline and read only. Nothing in the CLI signs a transaction or touches
a key, so it is safe to point at production data while reasoning about a session.

```bash
$ pipeshift net examples/session.json
security        0x8fa6e2b2d6e2f8f9a1c4d3e5b7a9c1e3f5d7b9a1c3e5f7d9b1a3c5e7f9d1b3a5
cash            0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48
trades in       4
parties         3
parties moving  2
transfers gross 8
transfers net   4
compression     50.00%

party                                      quantity            cash
0x1111111111111111111111111111111111111111  -20000000000000000000       3910000000
0x2222222222222222222222222222222222222222   20000000000000000000      -3910000000
```

| Command | What it does |
|---|---|
| `pipeshift net <file>` | Collapses a trade file into one net position per party |
| `pipeshift id <file>` | Computes the settlement id of an instruction |
| `pipeshift validate <file>` | Checks an instruction against the rules the engine enforces |
| `pipeshift security <ticker> <isin>` | Computes the canonical registry id for an underlying |

Amounts in every input file are decimal strings in base units. A number literal is
rejected rather than parsed, because a float that reaches a settlement amount is a
position break waiting to happen.

## Contracts

| Contract | Responsibility | Tests |
|---|---|---|
| [`SettlementEngine`](contracts/src/SettlementEngine.sol) | Atomic DVP for matched trades, single, batched and partial | 26 |
| [`NettingEngine`](contracts/src/NettingEngine.sol) | Multilateral netting sessions, balance enforced on chain | 11 |
| [`AssetRegistry`](contracts/src/AssetRegistry.sol) | Canonical record per underlying, halt and delist controls | 13 |
| [`SafeTransfer`](contracts/src/libraries/SafeTransfer.sol) | Transfer helpers that tolerate tokens returning no value | covered |
| [`Owned`](contracts/src/libraries/Owned.sol) | Two step ownership, so control cannot be sent to a dead address | covered |

The invariants the test suite exists to defend:

- A failed cash leg leaves the security leg unmoved, and the instruction still affirmed.
- A batch settles fully or reverts fully. No partial batch.
- A netting session that does not sum to zero on both legs is rejected, never partially applied.
- The netting engine holds no residual once a session closes.
- Token supply is conserved across settlement, checked by fuzzing on both engines.
- However an instruction is sliced into fills, the parties end up exactly where a single settlement would have left them.
- A halted security cannot settle, including instructions affirmed before the halt.

## Architecture

```
contracts/
  src/
    SettlementEngine.sol      atomic DVP
    NettingEngine.sol         multilateral netting
    AssetRegistry.sol         canonical registry
    interfaces/               ISettlementEngine, IAssetRegistry, IERC20
    libraries/                SafeTransfer, Owned
  test/                       38 tests including fuzz
  script/Deploy.s.sol         registry first, then both engines

sdk-ts/
  src/
    client.ts                 typed reads and writes over viem
    netting.ts                trade set to net positions
    instruction.ts            id computation and validation
    registry.ts               canonical id helpers
    cli.ts                    offline command line
  test/                       23 tests against the built package
```

| Area | Owner |
|---|---|
| Settlement core, DVP path | [@0xnova](https://github.com/pipeshiftprotocol) |
| Netting, registry, invariants | [@mikrohash](https://github.com/pipeshiftprotocol) |
| SDK, CLI, docs | [@luka](https://github.com/pipeshiftprotocol) |

## Roadmap

| Version | Scope | Status |
|---|---|---|
| v0.1 | Registry, atomic DVP, batch settlement | shipped |
| v0.2 | Multilateral netting, session balance checks | shipped |
| v0.3 | TypeScript SDK, offline CLI, deploy scripts | shipped |
| v0.4 | Proof of reserves attestation per custodian | in progress |
| v0.5 | Partial settlement over several fills | shipped |
| v0.6 | Cross venue session aggregation | planned |

No dates. Follow the commits.

## What is not done

Being explicit about scope is cheaper than being discovered.

- Contracts are unaudited. Do not point real value at them yet.
- Nothing is deployed to Robinhood Chain **mainnet**. The end to end suite deploys to a local node and to a fork of mainnet, which exercises the code but publishes no addresses. Real addresses appear here when they exist.
- Proof of reserves is designed but not implemented, so custodian attestation is off chain today.
- The registry owner is a single key. Multisig handover is a launch requirement, not a code change.

## Contributing

Useful first contributions: an invariant the fuzz tests miss, a token behaviour
`SafeTransfer` does not tolerate, or a netting case that produces a residual.

See [CONTRIBUTING.md](CONTRIBUTING.md). Every pull request needs a test that fails before
the change and passes after.

## License

MIT. See [LICENSE](LICENSE).

<div align="center">

[pipeshift.trade](https://pipeshift.trade) · [@pipeshift_ai](https://x.com/pipeshift_ai)

</div>
