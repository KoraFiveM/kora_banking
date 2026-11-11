---
title: Exports
sidebar_position: 5
---

# Exports

All exports are **server-side**. kora_banking has no client exports.

The account exports below are also published under the `qb-banking` resource name through `Kora.compat.provideExport`. Legacy calls such as `exports['qb-banking']:AddMoney(...)` therefore keep working. `ExecuteTransaction` and `GetOperation` are only available as `exports.kora_banking`.

Named accounts are rows in `bank_accounts` (shared, job and gang accounts). The account exports work on that in-memory cache. They do **not** touch a character's personal bank balance, which belongs to kora_core money.

## CreatePlayerAccount

```lua
exports.kora_banking:CreatePlayerAccount(playerId, accountName, accountBalance, accountUsers)
```

Creates a **shared** account owned by the online player's character.

| Param | Type | Description |
| --- | --- | --- |
| `playerId` | number | Server ID of the owner |
| `accountName` | string | Unique account name (max 50 characters in the database). This export does not apply the UI name rules |
| `accountBalance` | number | Opening balance (floored, minimum 0). Not deducted from the player |
| `accountUsers` | table or JSON string | Optional member citizen IDs. The list is bounded by `maxSharedMembers` / `maxSharedMemberBytes` |

**Returns**: the new row ID, or `false` (player offline, the name already exists, the member list is too large, or the insert failed).

## CreateJobAccount / CreateGangAccount

```lua
exports.kora_banking:CreateJobAccount(name, balance)
exports.kora_banking:CreateGangAccount(name, balance)
```

Creates a `job` or `gang` account named `name` with `balance` (default 0). **Returns** the row ID, or `false` if the account already exists or the insert failed.

## AddMoney / AddGangMoney

```lua
local ok = exports.kora_banking:AddMoney(accountName, amount, reason)
```

Credits an existing named account. `amount` is floored and must be 1 to 1,000,000,000. A `deposit` statement is written with `reason` (default `External deposit`). **Returns** `true` or `false`. `AddGangMoney` is an alias.

## RemoveMoney / RemoveGangMoney

```lua
local ok = exports.kora_banking:RemoveMoney(accountName, amount, reason)
```

Debits an existing named account only if the balance covers the amount. A `withdraw` statement is written with `reason` (default `External withdrawal`). **Returns** `true` or `false`. `RemoveGangMoney` is an alias.

## GetAccount / GetGangAccount

```lua
local account = exports.kora_banking:GetAccount(accountName)
```

**Returns** the cached `bank_accounts` row (`id`, `citizenid`, `account_name`, `account_balance`, `account_type`, `users`), or `nil`. `GetGangAccount` is an alias.

## GetAccountBalance

```lua
local balance = exports.kora_banking:GetAccountBalance(accountName)
```

**Returns** the balance as a number, or `0` if the account does not exist.

## CreateBankStatement

```lua
exports.kora_banking:CreateBankStatement(playerId, account, amount, reason, statementType, accountType)
```

Inserts a `bank_statements` row so external money movements show up in the Activity tab.

| Param | Type | Description |
| --- | --- | --- |
| `playerId` | number | Source whose citizen ID is stored. Pass `0` for none |
| `account` | string | Account name. Ignored when `accountType` is `'player'` |
| `amount` | number | Floored amount |
| `reason` | string | Reference (max 50 characters). Defaults to `Deposit` or `Withdrawal` |
| `statementType` | `'deposit'` or `'withdraw'` | Row type |
| `accountType` | string | `'player'` writes to the personal account (`checking`) |

**Returns** `true` if the row was inserted.

## ExecuteTransaction / GetOperation

```lua
local receipt, code, message = exports.kora_banking:ExecuteTransaction(operationKey, request)
local receipt, code, message = exports.kora_banking:GetOperation(operationKey)
```

These are restricted to resources in `Config.transactionCallers`. See [Durable transactions](./features/durable-transactions.md) for the request format, receipts and error codes.

## Example

```lua
-- Pay a job's society account and log it
if exports.kora_banking:AddMoney('police', 500, 'Fine payment') then
    print(exports.kora_banking:GetAccountBalance('police'))
end
```
