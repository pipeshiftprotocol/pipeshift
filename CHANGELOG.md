# Changelog

All notable changes to this project are documented here. This project follows
[semantic versioning](https://semver.org).

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
