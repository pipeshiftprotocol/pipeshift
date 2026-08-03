# Changelog

All notable changes to this project are documented here. This project follows
[semantic versioning](https://semver.org).

## [0.5.0] - 2026-08-03

### Added
- `settlePartial(id, quantity)`: an instruction can now be closed over several fills, because
  real inventory arrives late and in pieces. Each fill is atomic across both legs, exactly like
  a full settlement.
- `fillOf(id)` reports how much of an instruction has been delivered and what is outstanding.
- `InstructionFilled` event carrying the filled quantity, the cash paid and what remains.
- 12 contract tests and one end to end test covering partial settlement, including a fuzz test
  asserting that any slicing of an instruction leaves the parties exactly where a single
  settlement would have.
- SDK support: `client.settlePartial()` and `client.fillOf()`.

### Changed
- `settle` is now expressed through the same routine as a partial fill, so there is one
  settlement path to reason about rather than two. It closes whatever is outstanding, which for
  an untouched instruction is the entire quantity.

### Notes
- The cash owed for a partial fill is its pro rata share rounded down, except for the fill that
  closes the instruction, which takes whatever consideration is left. Rounding therefore cannot
  leak value in either direction however the caller slices the instruction.

## [0.4.0] - 2026-07-30

### Added
- End to end suite that runs against a real node: deploys the contracts, affirms and settles
  a matched trade, checks that a failing cash leg leaves the security leg unmoved, and settles
  a netting session computed by the SDK.
- `e2e:full` starts anvil, deploys the devnet fixture and tears the node down afterwards.
- `e2e:fork` runs the same suite against a fork of Robinhood Chain, so the contracts execute
  with the chain's own id, gas parameters and EVM revision. Reports `chain id 4663`.
- `script/Devnet.s.sol`: a complete working deployment for local runs, with demo tokens, a
  listed security, a registered venue and funded parties.
- CI jobs for both, with the fork job allowed to fail so a public endpoint's bad day does not
  block a merge.

### Fixed
- The devnet fixture funded only the two sides of the first trade. A netting session moves
  value in both directions for every participant, so every role is now funded on both legs.

## [0.3.0] - 2026-07-29

### Added
- TypeScript SDK with typed clients over the settlement engine, netting engine and registry.
- Offline CLI with `net`, `id`, `validate` and `security` commands.
- Deploy script that wires the registry first, then both engines.
- 23 SDK tests running against the built package rather than source.

### Changed
- Amounts in CLI input files must be decimal strings. Number literals are rejected instead
  of parsed, because a float that reaches a settlement amount is a position break.
- `Status` and `Listing` are const objects rather than TypeScript enums, so the package runs
  unmodified under Node type stripping.

## [0.2.0] - 2026-07-16

### Added
- `NettingEngine` with multilateral netting sessions.
- On chain balance enforcement: a session that does not sum to zero on both legs reverts.
- Collection before payout inside a session, so the engine is funded before it pays anyone.
- `transfersSaved` for reporting compression against gross settlement.
- Fuzz test asserting supply conservation and zero residual across sessions.

### Fixed
- Duplicate parties in a session are rejected. Previously the second leg silently overwrote
  the first when a venue submitted the same desk twice.

## [0.1.0] - 2026-06-26

### Added
- `SettlementEngine` with atomic delivery versus payment for matched trades.
- `AssetRegistry` with one canonical record per underlying, keyed by ticker and ISIN.
- Batch settlement that reverts fully rather than partially.
- `SafeTransfer`, tolerating tokenized equity wrappers that return no value from transfer.
- `Owned` with two step ownership transfer.
- Venue allowlist and cash token allowlist.
