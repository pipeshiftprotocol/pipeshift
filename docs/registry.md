# Canonical registry

## Why a shared record

Two venues can list the same underlying under different token addresses. Without a shared
record, a trade matched on one venue and settled against the other's token looks valid to
both and is wrong.

The registry makes the mapping explicit: one canonical id per underlying, one token address
per canonical id, enforced both ways.

## Identity

The id is `keccak256(ticker, isin)`. Both are twelve byte fields, which fits an ISIN exactly
and any listed ticker comfortably.

Deriving identity from the underlying rather than from the token address means a reissued
token keeps the same canonical id. Settlement history remains attributable to the
instrument rather than to whichever wrapper contract was current at the time.

## Listing states

| State | Settleable | Reversible |
|---|---|---|
| `None` | no | never listed |
| `Active` | yes | yes |
| `Halted` | no | back to active |
| `Delisted` | no | terminal |

Halting is for corporate actions and market stops: a security halts, settlement stops
everywhere at once, then resumes. Delisting is terminal, because a delisted instrument that
could be un-delisted would leave open instructions in an ambiguous state.

Both engines check `isSettleable` at settlement time rather than at affirm time. An
instruction affirmed before a halt does not settle during it, which is the correct
behaviour: the halt exists precisely to stop settlement of trades already matched.

## Custodian of record

Each security records a custodian. Today this is informational and attestation happens off
chain. v0.4 adds on chain proof of reserves against this field, with a staleness bound so a
venue can refuse to settle against an attestation older than its risk policy allows.

Reassignment is a single owner call, because a custodian transition is an operational event
that should not require relisting the security and breaking its id.
