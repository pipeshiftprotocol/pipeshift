# Changelog

All notable changes to this project are documented here. This project follows
[semantic versioning](https://semver.org).

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
