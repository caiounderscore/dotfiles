---
name: igaming-correctness
description: Correctness and latency checklist for money-moving and high-concurrency paths in iGaming and sports-betting systems, such as bets, wallets, settlements, payouts, and provider callbacks. Use when a change touches balances, transactions, settlement, retries, or the hot path during peak events.
---

# iGaming correctness

## Money

- Amounts are integer minor units or fixed-point decimals with an explicit currency, never floats. Rounding rules
  are explicit and tested.
- Every balance change is an append-only ledger entry with a reason and a reference, and balances reconcile against
  the ledger.

## Exactly-once effects

- Every externally triggered operation (bet placement, settlement, payout, provider callback) carries an idempotency
  key, and a retry returns the first result.
- A check-then-write on a balance runs in one transaction with a row lock or a conditional update
  (`... WHERE balance >= ?`). Test two concurrent requests against it.
- Publish events through an outbox in the same transaction as the state change. Consumers are idempotent and
  tolerate duplicates and reordering.

## Peak load

- Every call on the hot path has a timeout. Retries use capped exponential backoff with jitter, and only on
  retryable errors.
- No unbounded queries, lists, or queues: paginate, and set backpressure limits.
- State the p99 latency budget the change must meet and how it was measured.

## Release

- A change to money flow ships behind a flag or a kill switch, with a rollback that needs no data fix.
- Name the metrics and alerts that show it working and failing, such as error rate, settlement lag, and the
  ledger reconciliation difference.
