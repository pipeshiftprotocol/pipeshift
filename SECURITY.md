# Security

## Status

The contracts in this repository are **unaudited** and nothing is deployed to Robinhood
Chain mainnet. Do not point real value at them.

## Reporting

Report vulnerabilities to **security@pipeshift.trade**. Include the affected file, a
description of the impact, and a reproduction if you have one. A Foundry test that
demonstrates the issue is the fastest path to a fix.

Do not open a public issue for anything that lets an attacker move value.

We aim to acknowledge within 48 hours and to ship a fix or a written explanation within
14 days.

## In scope

- Any path that lets one leg of a settlement move without the other.
- Any path that lets a netting session change total supply.
- Any path that lets a non-venue affirm, or lets a settled instruction settle twice.
- Any path that lets the registry map one token to two canonical ids.
- Griefing that permanently blocks settlement of a valid affirmed instruction.

## Out of scope

- Gas optimisation without a security impact.
- Behaviour of third party tokenized equity tokens themselves.
- Anything requiring the registry owner key, which is trusted by design.
- Front running of settlement, which is permissionless on purpose.

## Disclosure

We will credit reporters in the release notes unless asked otherwise.
