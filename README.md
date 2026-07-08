<div align="center">

# Pipeshift

### The settlement layer for tokenized equities on Robinhood Chain

Venues match. Pipeshift settles.

[![License: MIT](https://img.shields.io/badge/license-MIT-0AE8A6.svg?style=flat-square)](LICENSE)
[![Solidity](https://img.shields.io/badge/solidity-0.8.24-0AE8A6.svg?style=flat-square)](contracts/foundry.toml)
[![TypeScript](https://img.shields.io/badge/typescript-5.6-0AE8A6.svg?style=flat-square)](sdk-ts/package.json)
[![Tests](https://img.shields.io/badge/tests-61%20passing-0AE8A6.svg?style=flat-square)](.github/workflows/ci.yml)
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
git clone https://github.com/pipeshiftprotocol/pipeshift.git
cd pipeshift

# contracts
cd contracts
forge install
forge test

# sdk and cli
cd ../sdk-ts
npm install
npm test
```

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
