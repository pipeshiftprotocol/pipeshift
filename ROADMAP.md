# Roadmap

No dates. The commit log is the schedule.

## Shipped

**v0.1 Registry and atomic DVP.** One canonical record per underlying keyed by ticker and
ISIN. Atomic delivery versus payment for a matched trade, single and batched, with batches
reverting fully rather than partially.

**v0.2 Multilateral netting.** Sessions that collapse many trades into one net position per
party, with balance enforced on chain. A session that does not sum to zero on both legs is
rejected rather than partially applied.

**v0.3 Client surface.** TypeScript SDK over viem, offline CLI, deploy scripts.

**v0.5 Partial settlement.** An instruction can be closed over several fills. Each fill is
atomic across both legs, and the fill that closes the instruction takes the remaining
consideration rather than a rounded share, so slicing never changes the outcome.

**v0.6 Cross venue sessions.** A session can cover several venues at once, so desks that trade
the same name on more than one venue net across all of them before anything settles.

## In progress

**v0.4 Proof of reserves.** Per custodian attestation that the underlying backing a listed
security is held, published on chain and checkable before settlement. The registry already
records a custodian per security. This adds the attestation and a staleness bound, so a
venue can refuse to settle against an attestation older than its own risk policy allows.

## Planned

## Not planned

**Matching.** Pipeshift settles what venues match. Adding an order book would put us in
competition with the venues we are supposed to serve.

**Custody.** The registry records who custodies. It does not custody.

**Pricing.** No oracle, no mark, no view on value. The consideration is whatever the venue
matched at.
