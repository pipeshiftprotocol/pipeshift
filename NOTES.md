# Notes

Working through the settlement model before writing contracts.

- gross settlement moves value twice per trade. wrong unit of work.
- netting needs a shared record of what a token is, otherwise two venues net
  against different tokens for the same underlying.
- registry id from ticker + isin, not token address. survives reissue.
- affirm and settle must be separate. venue knows the match immediately, funding
  arrives later.
- open question: partial settlement. probably not v0.1.
