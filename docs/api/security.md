---
title: "Security and integrity"
sidebar_position: 5
---


# Security and integrity

What the resource protects, where, and what you must still do in your own scripts.

Namespace: `kora_banking` · Source: `server.lua, server/finance.lua, tiers.lua, client.lua`

## How it works

The client is presentation only. Everything that moves money runs on the server in the active session of the player, after permission, proximity and tier checks.

## Built-in protections

Where each one is implemented.

| Option | Type | Description |
| --- | --- | --- |
| `Server authority` | protection | Balances, account permissions, branch and tier all come from the server (`player`, `mayUse`, `branchAt`, `server.lua`). The client's `Config.locations` index only has to name a real entry. |
| `Proximity` | protection | Bank: the ped must be within 3.0 m of a configured location (`branchAt`). ATM: within `atmDistance + atmTolerance` of the sent coordinates (`nearAtm`). Both are rechecked on every action in `activeSession`; coordinates beyond sane bounds are rejected. |
| `Account access` | protection | `mayUse` allows shared members and owners, and only the boss (`isboss`) of the matching job or gang. `mayManage` restricts shared-account management to the owner. ATM sessions can only use `checking`. |
| `Amount validation` | protection | `roundAmount` requires a finite number, floored, 1 to 1,000,000,000. `Config.minAmount` applies per kind. |
| `Overdraft protection` | protection | Account debits use `account_balance >= ?` in the UPDATE. Character legs in `ExecuteTransaction` use the same guard and a 9007199254740991 ceiling. |
| `Per-player serialisation` | protection | `current.busy` blocks overlapping action requests of one session, so two requests cannot both pass the same daily cap. |
| `PIN throttling` | protection | 4-digit PIN, five failures lock the session for 30 seconds. Cards must belong to the player (`info.citizenid`). |
| `Rate limit` | protection | Member management uses `Kora.util.rateLimiter(Config.memberRateLimit.max, window)` per source. |
| `Input cleaning` | protection | Text goes through `Kora.util.cleanText` (50 characters; account names 3 to 40 with a strict pattern), and SQL uses bound parameters everywhere. |
| `Caller allow-list` | protection | `ExecuteTransaction` and `GetOperation` only answer resources listed in `Config.transactionCallers`, identified by `GetInvokingResource()`. |
| `Idempotency` | protection | Durable operations are keyed by (resource, key) with a request fingerprint and a receipt; a repeat returns the receipt instead of paying twice. |
| `Session lifetime` | protection | Sessions last 300 seconds of inactivity, end on `kora_banking:close` and `playerDropped`. |

### Developer responsibilities

Not enforced by the bank.

| Option | Type | Description |
| --- | --- | --- |
| `Never trust client amounts for your own exports` | responsibility | `AddMoney`, `RemoveMoney`, `CreateBankStatement`, `CreateJobAccount`, `CreatePlayerAccount` have no caller check and no player context. Call them only from server code that has already authorized the action. Never wire them to a client net event. |
| `Check results` | responsibility | `RemoveMoney` and `AddMoney` return false on failure. Only deliver goods after a true result and refund if a later step fails. |
| `Duplicate payments` | responsibility | The simple exports are not idempotent. Calling `AddMoney` twice credits twice. For one-time payments use `ExecuteTransaction` with a stable key and persist your own record. |
| `Races` | responsibility | Reading a balance and then removing is not atomic across calls. Rely on the return value of `RemoveMoney`, not on a prior `GetAccountBalance`. |
| `Keep transactionCallers minimal` | responsibility | Only list resources you trust: they can move any character's bank balance. |
| `Cache freshness` | responsibility | If you change `bank_accounts` with SQL, trigger `kora_banking:refreshAccount`. |

### Known limits of the integrity model

Observed in the source.

| Option | Type | Description |
| --- | --- | --- |
| `No single transaction for UI actions` | limit | Deposit, withdraw and transfers are sequences of separate updates with compensating rollbacks. The code has no recovery for a server crash between the two steps. |
| `Statements can fail silently` | limit | The statement insert after a successful move is not checked, so history can miss a move. |
| `PIN counter reset` | limit | Corrected: the attempt counter and the 30-second lock are kept per player in `PinGuards` (`server.lua:708`), not in the session, so closing and reopening the ATM does not reset them. They are cleared on a correct PIN and on `playerDropped`, so a player who reconnects starts with a fresh counter. |
| `Card numbers` | limit | Generated with `math.random` and not checked for uniqueness. Transfers by card number scan persisted `players.inventory`. |
| `Transfers to any named account` | limit | A transfer by account name to a shared, job or gang account does not require access to the destination. |
| `Member lists` | limit | Lowering `maxSharedMembers` or `maxSharedMemberBytes` silently shortens or empties lists when read. |

## Functions

Protections and responsibilities.

## Limits and related APIs

This page reflects the code of `kora_banking` only. The safety of `players.money` writes by the online player path depends on kora_core's `addMoney` and `removeMoney`, which this resource calls but which were not audited here.

## Related guides

- [Public exports](./exports.md)
- [Configuration](./configuration.md)
