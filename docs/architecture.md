# Architecture

Three contracts, one shared record, no state held between calls.

## Components

**AssetRegistry** is the only place that knows what a token represents. Ids are derived
from ticker and ISIN, so the id survives a token reissue and settlement history stays
continuous across it. The registry also owns the halt switch: a security under a corporate
action stops settling everywhere at once, including instructions affirmed before the halt.

**SettlementEngine** turns a matched trade into a movement of value. It stores instructions
on affirm, moves both legs on settle, and holds nothing in between. The security leg moves
first and the cash leg second, which is an implementation detail rather than a guarantee:
the guarantee is that a failure on either leg reverts both.

**NettingEngine** takes a session, verifies it sums to zero on both legs, collects from
every party in deficit, then pays out every party in surplus. Collection precedes payout so
the contract is funded before it owes anyone, and a short collection reverts the session
rather than leaving a partial one behind.

## Why affirm and settle are separate

A venue knows a trade is matched immediately. It does not know when both counterparties
will be funded. Collapsing affirm and settle into one call would force the venue to wait
for funding before recording the match, which pushes the record of truth off chain into
whatever the venue happens to be running.

Splitting them means the match is recorded cheaply and immediately, and settlement is a
separate permissionless call that anyone can trigger once funding is in place. The deadline
on the instruction bounds how long that can hang.

## Trust assumptions

The registry owner can list, halt and delist securities. That key decides what is
settleable, which makes it the most sensitive object in the system. It is a single key in
the current code and must be a multisig before anything real settles.

Venues are allowlisted. A venue can affirm instructions naming any two parties, but it
cannot move value: settlement still requires both parties to have approved the engine. The
worst a malicious venue can do is fill the instruction table with entries that will never
settle, which is bounded by their deadlines.

Anyone can call settle. This is deliberate. Settlement is not a privilege, and letting the
counterparties or a third party push it through removes the venue as a liveness dependency.

## What the engines never do

They never hold positions between calls, never take custody, never quote a price, and never
net across securities. A session is scoped to one security and one cash token, because
netting across securities would require a price to be correct, and pricing is not our job.
