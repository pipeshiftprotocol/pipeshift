## What this changes

<!-- One or two sentences. What behaviour is different after this lands. -->

## Why

<!-- The problem. If this fixes a bug, describe the failure, not the patch. -->

## Test that proves it

<!-- Name the test that fails before this change and passes after. -->

## Checklist

- [ ] `forge fmt --check` and `forge test` pass in `contracts/`
- [ ] `npm run typecheck` and `npm test` pass in `sdk-ts/`
- [ ] A test covers the changed behaviour
- [ ] No new dependency on the settlement path
- [ ] CHANGELOG updated if behaviour changed
