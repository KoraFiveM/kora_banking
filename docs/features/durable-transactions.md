---
title: Durable transactions
sidebar_position: 6
---

# Durable resource transactions

`ExecuteTransaction` and `GetOperation` let trusted **server** resources move money between character bank balances and named bank accounts atomically. The money moves in the same database transaction as their own SQL statements, and an idempotent receipt is stored. kora_housing uses this API for property sales.

## Authorization

Only resources listed in `Config.transactionCallers` with the value `true` may call these exports (default `{ kora_housing = true }`). The caller is detected with `GetInvokingResource()`. Any other caller gets `false, 'rejected', ...`. Both exports yield, so call them from a thread.

## ExecuteTransaction

```lua
local receipt, code, message = exports.kora_banking:ExecuteTransaction('sale:123', {
    debits = { { citizenid = buyerCitizenId, amount = 1000 } },
    credits = {
        { citizenid = sellerCitizenId, amount = 940 },
        { account = 'realestate', amount = 60 },
    },
    reason = 'Property purchase',
    statements = {
        { query = 'UPDATE properties SET owner=? WHERE id=? AND owner=?',
          values = { buyerCitizenId, propertyId, sellerCitizenId }, expectedRows = 1 },
    },
})
```

| Parameter | Description |
| --- | --- |
| `operationKey` | String, 1 to 128 characters. Unique per caller resource. |
| `request.debits` / `request.credits` | Up to 128 legs each. Each leg has exactly one of `citizenid` (character bank balance) or `account` (existing named bank account), each 1 to 50 characters. `amount` is a whole number from 1 to 1,000,000,000. Total debits must equal total credits. |
| `request.reason` | Optional string, truncated to 50 characters. Stored on each ledger leg (default `Housing transaction`). |
| `request.statements` | Optional, up to 256 kora_sql checked-transaction statements (`query` up to 20,000 characters, `values`, `expectedRows`). They run in the same transaction. |

The canonical encoded request must not exceed 512 KB.

Behaviour:

- Debit checks use the gross debit for each account, even when the same account is also credited. They never use kora_core negative-balance allowances.
- Character balances are updated in `players.money` (`$.bank`) under a kora_core player-column lock (`money`). Named accounts are updated in `bank_accounts`. Accounts are never created by this API, so create them first with the existing exports.
- The receipt (`bank_operations`), balance updates, ledger legs (`bank_operation_legs`) and your statements commit together or not at all.
- The caller supplies trusted server SQL. Validate every domain precondition with `expectedRows` and transactional tables. Never accept SQL or prices from clients.

### Return values

On success the export returns a receipt table:

| Field | Description |
| --- | --- |
| `operationKey` | The key you passed |
| `resource` | Calling resource |
| `status` | `'completed'` |
| `timestamp` | `os.time()` at execution |
| `amount` | Total debited |
| `accounts` | Sorted list of named accounts touched |

On refusal it returns `false, code, message` (not `nil`, because a leading `nil` would drop the code and message across the export boundary).

| Code | Meaning |
| --- | --- |
| `rejected` | Invalid input, unbalanced legs, or an unauthorized caller |
| `unavailable` | Storage failure, or durable banking is not ready yet |
| `insufficient_funds` | A debited balance was too low (confirmed: nothing committed) |
| `conflict` | Same key with different terms, a credit target that could not be updated, or a failed domain statement |
| `pending` | The operation is in progress or awaiting player synchronization. Reconcile or retry identically |
| `indeterminate` | The outcome is unknown. Reconcile with `GetOperation` or retry identically |

Other codes from kora_core's player-column lock may also be passed through.

### Idempotency

The exact request is immutable per resource and key. Repeating the same request returns the original receipt. Changing the terms returns `conflict`. Store prepared requests durably so that retries after a restart use identical terms. **Never issue compensating money changes after an ambiguous reply** (`pending`, `indeterminate`, `unavailable`).

## GetOperation

```lua
local receipt, code, message = exports.kora_banking:GetOperation('sale:123')
```

This export reads only the calling resource's receipt and completes any pending player/cache synchronization. It returns the receipt, or `false, code, message`. It can return `not_found` after waiting for an old driver worker. It never executes a new debit.

## Startup and recovery

- On start the resource waits for the database, ensures its schema, waits for its own retained player-operation fences, and reconciles them. A confirmed receipt publishes the committed balances. A confirmed absent preparation is released without a debit. Unresolved operations are retried every 30 seconds.
- Until this finishes, the exports return `unavailable`. When it finishes, the local event `kora_banking:durableReady` fires, and branch/ATM history starts including ledger legs.
- If schema setup fails, durable features stay disabled. With `Config.migrationRetrySeconds` above 0, setup is retried after that many seconds.
- An unresolved persistent lock deliberately refuses money/item writes and character login for the affected characters until it is reconciled. Keep the `bank_operations` / `bank_operation_legs` tables (and kora_core's lock table) when restarting resources.
- Direct third-party SQL writes to the player money JSON bypass kora_core coordination and are outside this guarantee.
