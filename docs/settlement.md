# Settlement

## The instruction

An instruction is a matched trade with an expiry. It names the security by canonical id,
the cash token, both parties, both amounts, and the venue that matched it.

The id is `keccak256` over all eight fields, computed identically on chain and in the SDK.
Changing any field produces a different instruction, so an amended trade is a new
instruction rather than a mutation of an existing one.

## Lifecycle

```
None ──affirm──► Affirmed ──settle──► Settled
                    │
                    ├──cancel──► Cancelled
                    │
                    └──deadline passes──► unsettleable
```

`Affirmed` is the only state from which settlement is possible. A settled instruction
cannot settle again, which is what makes replay a non-issue: the second call reverts with
the current status attached.

Cancellation is available to the submitting venue and to either party. A counterparty who
no longer wants to settle does not need the venue's cooperation to stop it.

## Atomicity

The property the engine exists for: if the cash leg fails, the security leg does not move.

The status advances to `Settled` before the transfers execute, which looks wrong at first
glance and is the correct order. Both transfers revert on failure, and a revert unwinds the
status change with them. Writing the status first costs nothing and removes any window in
which a reentrant call could see a settled trade as still affirmed.

Batches inherit this. `settleBatch` reverts entirely if any instruction in it fails, so a
venue submitting twenty instructions either gets twenty settlements or gets none and a
clear revert reason.

## Tokens that return nothing

Some tokenized equity wrappers predate the ERC20 return value convention and return no data
at all from `transfer`. Requiring a `bool` from those tokens reverts a transfer that
actually succeeded.

`SafeTransfer` treats an empty return as success and decodes only when there is data. A
return of exactly 32 bytes is decoded as the bool it claims to be; anything else is treated
as a failure rather than optimistically ignored.

## Deadlines

Every instruction carries one. It bounds how long an unfunded trade can sit in the table
and gives the parties a point after which they know it will not settle. The engine checks
the deadline at settlement rather than expiring instructions eagerly, because eager expiry
would need someone to pay gas for the sweep.
