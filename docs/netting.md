# Netting

## The problem with gross

Gross settlement moves value once per trade, twice counting both legs. A session with
twelve thousand trades between forty desks moves twenty four thousand times.

Most of that movement cancels. A desk that buys 400 shares and sells 380 in the same
session owes 20 shares. The other 380 were a round trip through its own book.

## What a session is

A session is one security, one cash token, and one net position per party. Deltas are
signed: negative means the party delivers, positive means the party receives.

The engine requires both legs to sum to zero. A session that does not is rejected with the
residual attached, because applying it would create or destroy value.

## Order of operations

Collection first, payout second.

```
for each party with a negative delta:  transfer in
for each party with a positive delta:  transfer out
```

The reverse order would have the engine paying out before it is funded, which works only if
someone else's balance happens to cover the gap. Collecting first means a short collection
reverts the whole session and the engine never operates on credit.

## Flat parties

A party whose net position is zero on both legs moves nothing. The SDK drops those legs
before submission with `withoutFlatLegs`, so a desk that traded all session and ended flat
costs no gas at settlement.

This is the interesting case in practice. In a busy session the majority of participants
end close to flat, and the transfers that remain are a small fraction of the trades that
produced them.

## Reproducibility

`netTrades` sorts legs by party address, so the same trade set always produces the same
session regardless of the order trades arrived in. Two venues computing the same session
independently get byte identical results, which matters once sessions are aggregated across
venues in v0.6.

## What netting does not change

Netting is a compression of movement, not of obligation. Every party ends with exactly the
position gross settlement would have given them. If that is not true, the session did not
sum to zero and the engine rejected it.
