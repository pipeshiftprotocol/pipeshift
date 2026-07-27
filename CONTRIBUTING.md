# Contributing

Pipeshift settles other people's trades. A bug here is a position break, not a rendering
glitch, so the bar for changes to the settlement path is deliberately high.

## The rule that matters

Every pull request that changes behaviour needs a test that fails before the change and
passes after. If you cannot write that test, say so in the description and explain why.

## What we want

- Invariants the fuzz suite misses. Especially anything that lets supply change across a settle.
- Token behaviours `SafeTransfer` does not tolerate. Fee on transfer, rebasing, missing return values.
- Netting cases that leave a residual in the engine.
- Gas reductions on the settle path that do not weaken an invariant.
- Documentation that corrects something wrong, rather than adding words around it.

## What we do not want

- Reformatting unrelated files.
- New dependencies on the settlement path. The contracts have no external imports and that is intentional.
- Features that make the engine hold positions between calls.
- Anything that turns Pipeshift into a venue. Matching is out of scope by design.

## Local checks

Run both suites before opening a pull request. CI runs the same commands.

```bash
cd contracts && forge fmt --check && forge build && forge test
cd ../sdk-ts && npm ci && npm run typecheck && npm test
```

## Commit messages

Conventional prefixes, scope in parentheses, imperative mood.

```
feat(netting): reject sessions with a duplicate party
fix(settlement): keep status affirmed when the cash leg reverts
test(registry): cover delist as a terminal state
docs(readme): correct the compression example
```

## Review

Paths map to owners in [.github/CODEOWNERS](.github/CODEOWNERS). Changes under
`contracts/src` need review from a contracts owner regardless of size.
