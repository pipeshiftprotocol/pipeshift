# Deployment

## Order

The registry deploys first. Both engines take its address as an immutable constructor
argument, so it cannot be swapped later. That is intentional: an engine that could be
repointed at a different registry could be repointed at one that lists an attacker's token
under a real ticker.

```bash
export PIPESHIFT_OWNER=0x...        # multisig, not an EOA
export PIPESHIFT_RPC_URL=https://...

cd contracts
forge script script/Deploy.s.sol \
  --rpc-url "$PIPESHIFT_RPC_URL" \
  --broadcast \
  --verify
```

The script prints all three addresses. Record them, they are the deployment.

## After deploying

Order matters here too, because each step widens what is possible.

1. Verify the registry owner is the multisig, not the deploying key.
2. List securities. Nothing settles until an underlying is listed and active.
3. Accept cash tokens on the settlement engine. An unlisted cash token cannot be affirmed against.
4. Register venues. This is the last step because a registered venue with nothing listed can do nothing.

## Checklist before real value

- [ ] Owner is a multisig on both engines and the registry
- [ ] Contracts audited, report published
- [ ] Cash token allowlist reviewed, no test tokens remaining
- [ ] Venue allowlist reviewed, every entry attributable to a real operator
- [ ] Custodian addresses confirmed with each custodian directly
- [ ] Deployment addresses published in the README and on pipeshift.trade

## Current status

Nothing is deployed to Robinhood Chain mainnet. When it is, addresses appear in the README
and in the release notes for that version. If you find addresses for Pipeshift anywhere
else, they are not ours.
