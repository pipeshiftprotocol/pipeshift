# Changelog

All notable changes to this project are documented here. This project follows
[semantic versioning](https://semver.org).

## [0.1.0] - 2026-06-26

### Added
- `SettlementEngine` with atomic delivery versus payment for matched trades.
- `AssetRegistry` with one canonical record per underlying, keyed by ticker and ISIN.
- Batch settlement that reverts fully rather than partially.
- `SafeTransfer`, tolerating tokenized equity wrappers that return no value from transfer.
- `Owned` with two step ownership transfer.
- Venue allowlist and cash token allowlist.
