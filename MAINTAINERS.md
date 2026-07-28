# Maintainers

| Handle | Area | Review required for |
|---|---|---|
| `@pipeshiftprotocol` | Everything, release management | Any change to `.github/`, releases, deploy scripts |
| `@0xnova` | Settlement core, DVP path | `contracts/src/SettlementEngine.sol`, `contracts/src/libraries/` |
| `@mikrohash` | Netting, registry, invariants | `contracts/src/NettingEngine.sol`, `contracts/src/AssetRegistry.sol`, `contracts/test/` |
| `@luka` | SDK, CLI, documentation | `sdk-ts/`, `docs/` |

## Review policy

Anything under `contracts/src` needs one contracts owner, no matter how small the diff. A
one line change on the settlement path is exactly where a break hides.

Anything that touches an invariant listed in the README needs two approvals, and the pull
request must name the test that covers it.

Documentation and tooling changes need one approval from any maintainer.

## Release policy

Versions in `contracts/` and `sdk-ts/` move together. A release requires:

- Both suites green on `main`.
- CHANGELOG entry describing behaviour changes, not commits.
- A "what is not done" section in the release notes.

We do not publish release notes that omit known gaps.
