---
title: "Public exports"
sidebar_position: 2
---


# Public exports

Server exports for reading and changing the balances of shared, society (job) and gang accounts, creating accounts and writing statements. Each is registered under `kora_banking` and also provided as `qb-banking`. Everything else in `server.lua` is a local function.

Namespace: `exports.kora_banking` · Source: `server.lua (bankingExport), fxmanifest.lua`

## How it works

The functions work on the in-memory `Accounts` cache that is loaded at start. `AddMoney`, `RemoveMoney`, `GetAccount` and `GetAccountBalance` return `false`, `nil` or `0` for an account that is not in the cache. There is no export for personal (`checking`) balances: use kora_core's `getPlayerData`, `addMoney` and `removeMoney` for those, or `ExecuteTransaction` for balanced multi-party changes.

## Charge a society account safely

1. **Read the balance if you need to display it** — `GetAccountBalance(name)` returns 0 for an unknown account.
2. **Debit first, then give the goods** — Call `RemoveMoney` and only proceed when it returns true. It is atomic, so it already refuses an overdraft.
3. **Refund if your later step fails** — If something after the debit fails, call `AddMoney` with a refund reason and check its result too (kora_bossmenu does this).
4. **Use ExecuteTransaction when several parties must change together** — These exports are independent single updates. They are not atomic across accounts.

## Terms used on this page

| Term | Meaning |
| --- | --- |
| Account name | The key of an account: the job name, gang name, shared account name. The personal account is the literal `checking` and is not stored in `bank_accounts`. |
| Cache | The `Accounts` table in `server.lua`, loaded once from `bank_accounts` and refreshed after this resource's own writes. |

## Functions

Eleven exports. The `Gang` variants are aliases of the generic ones.

### `exports.kora_banking:AddMoney(name, amount, reason?)`

Credits a shared, society or gang account and writes a `deposit` statement with no character attached.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `name` | string | Required. Account name: for job and gang accounts the job or gang name, for shared accounts the shared account name. |
| `amount` | number | Required. Floored to an integer; must be between 1 and 1,000,000,000 after flooring and finite. |
| `reason?` | string | Optional text stored in `bank_statements.reason`. Cleaned and cut to 50 characters. Default `External deposit` / `External withdrawal`. |

**Returns**

- **`boolean`** — `true` when the balance was updated. `false` when the amount is invalid, the account is not in the in-memory cache, or the UPDATE affected no row.

**Example**

```lua
local ok = exports.kora_banking:AddMoney('police', 500, 'evidence-fine')
if not ok then print('police account was not credited') end
```

**Representative console output**

```text
Adds 500 to `bank_accounts.account_balance` for `police` and inserts a statement row (`citizenid` NULL, type `deposit`). The statement insert result is not checked: the call still returns true if the history row failed. There is no overflow guard on this UPDATE other than the column type (`int(11)`).
```

### `exports.kora_banking:AddGangMoney(name, amount, reason?)`

Alias of `AddMoney`: the same function is registered under both names, so it works on any account type.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `name` | string | Required. Account name: for job and gang accounts the job or gang name, for shared accounts the shared account name. |
| `amount` | number | Required. Floored to an integer; must be between 1 and 1,000,000,000 after flooring and finite. |
| `reason?` | string | Optional text stored in `bank_statements.reason`. Cleaned and cut to 50 characters. Default `External deposit` / `External withdrawal`. |

**Returns**

- **`boolean`** — same as `AddMoney`.

**Example**

```lua
exports.kora_banking:AddGangMoney('ballas', 1200, 'turf-income')
```

**Representative console output**

```text
Behaves exactly like `AddMoney`.
```

### `exports.kora_banking:RemoveMoney(name, amount, reason?)`

Debits a shared, society or gang account if it holds enough, and writes a `withdraw` statement.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `name` | string | Required. Account name: for job and gang accounts the job or gang name, for shared accounts the shared account name. |
| `amount` | number | Required. Floored to an integer; must be between 1 and 1,000,000,000 after flooring and finite. |
| `reason?` | string | Optional text stored in `bank_statements.reason`. Cleaned and cut to 50 characters. Default `External deposit` / `External withdrawal`. |

**Returns**

- **`boolean`** — `true` on success. `false` for an invalid amount, an unknown account, or insufficient funds (the guarded UPDATE `... AND account_balance >= ?` matched no row).

**Example**

```lua
if not exports.kora_banking:RemoveMoney('ambulance', 300, 'supplies') then
    return false, 'insufficient business funds'
end
```

**Representative console output**

```text
The balance is lowered atomically in one UPDATE, so two concurrent callers cannot both spend the same money. The statement insert is separate and its failure is ignored.
```

### `exports.kora_banking:RemoveGangMoney(name, amount, reason?)`

Alias of `RemoveMoney`.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `name` | string | Required. Account name: for job and gang accounts the job or gang name, for shared accounts the shared account name. |
| `amount` | number | Required. Floored to an integer; must be between 1 and 1,000,000,000 after flooring and finite. |
| `reason?` | string | Optional text stored in `bank_statements.reason`. Cleaned and cut to 50 characters. Default `External deposit` / `External withdrawal`. |

**Returns**

- **`boolean`** — same as `RemoveMoney`.

**Example**

```lua
exports.kora_banking:RemoveGangMoney('ballas', 200, 'bribe')
```

**Representative console output**

```text
Behaves exactly like `RemoveMoney`.
```

### `exports.kora_banking:GetAccount(name)`

Returns the cached account row.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `name` | string | Required. Account name: for job and gang accounts the job or gang name, for shared accounts the shared account name. |

**Returns**

- **`table | nil`** — the `bank_accounts` row `{ id, citizenid, account_name, account_balance, account_type, users }` (`users` is a JSON string of citizen IDs), or `nil` when the account is not in the cache. Exports return a copy to other resources, but inside this resource the cached table is shared.

**Example**

```lua
local account = exports.kora_banking:GetAccount('police')
if account then print(account.account_type, account.account_balance) end
```

**Representative console output**

```text
Prints for example `job 4200`. The cache is only refreshed by this resource's own writes, so manual SQL edits are not visible until a refresh.
```

### `exports.kora_banking:GetGangAccount(name)`

Alias of `GetAccount`.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `name` | string | Required. Account name: for job and gang accounts the job or gang name, for shared accounts the shared account name. |

**Returns**

- **`table | nil`** — same as `GetAccount`.

**Example**

```lua
local gang = exports.kora_banking:GetGangAccount('ballas')
```

**Representative console output**

```text
Works for any account name, not only gangs.
```

### `exports.kora_banking:GetAccountBalance(name)`

Returns the balance of a cached account.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `name` | string | Required. Account name: for job and gang accounts the job or gang name, for shared accounts the shared account name. |

**Returns**

- **`number`** — `account_balance`, or `0` when the account is missing or the value is not numeric. A missing account and an empty account are indistinguishable; use `GetAccount` to tell them apart.

**Example**

```lua
local funds = exports.kora_banking:GetAccountBalance('police')
```

**Representative console output**

```text
Used by kora_bossmenu to show a society balance.
```

### `exports.kora_banking:CreatePlayerAccount(playerId, accountName, accountBalance?, accountUsers?)`

Creates a `shared` account owned by the character of an online player.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `playerId` | number | Required. Server ID of an online player; the account `citizenid` is that player's character. |
| `accountName` | string | Required. Unique account name. This export does not apply the 3 to 40 character name rule of the UI. |
| `accountBalance?` | number | Optional starting balance, floored and clamped to at least 0 (default 0). The amount is not taken from anyone: it is created from nothing. |
| `accountUsers?` | table \| string | Optional member list: an array of citizen ID strings or a JSON string of one. Entries longer than 16 characters or duplicated are dropped, and the list is cut at `Config.maxSharedMembers`. |

**Returns**

- **`number | false`** — the new row id, or `false` if the player is unknown, the name already exists in the cache, the encoded member list exceeds `Config.maxSharedMemberBytes`, or the insert failed.

**Example**

```lua
local id = exports.kora_banking:CreatePlayerAccount(src, 'smith_family', 0, { 'ABC12345' })
if not id then print('account not created') end
```

**Representative console output**

```text
Inserts into `bank_accounts` and refreshes the cache. It does not enforce `Config.maxAccounts`; that limit only applies to the UI.
```

### `exports.kora_banking:CreateJobAccount(name, balance?)`

Creates a `job` account with no owner.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `name` | string | Required. The job name (accounts are matched to the player's job by this exact name). |
| `balance?` | number | Optional starting balance. Passed to the insert as given (default 0), without flooring or validation. |

**Returns**

- **`number | false`** — the new row id, or `false` when an account with that name is already cached or the insert failed.

**Example**

```lua
exports.kora_banking:CreateJobAccount('mechanic', 0)
```

**Representative console output**

```text
Job accounts for all shared jobs are already created at startup, so you normally only call this for dynamically created jobs. kora_core's tax module also calls it through the `qb-banking` provider.
```

### `exports.kora_banking:CreateGangAccount(name, balance?)`

Creates a `gang` account with no owner.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `name` | string | Required. The gang name. |
| `balance?` | number | Optional starting balance, passed as given (default 0). |

**Returns**

- **`number | false`** — the new row id, or `false` when it already exists or the insert failed.

**Example**

```lua
exports.kora_banking:CreateGangAccount('newgang', 0)
```

**Representative console output**

```text
Same behavior as `CreateJobAccount` with `account_type = 'gang'`.
```

### `exports.kora_banking:CreateBankStatement(playerId, account, amount, reason, kind, accountType?)`

Writes a history row only. It does not move any money.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `playerId` | number | Server ID. When greater than 0 the statement's `citizenid` is that online player's character; otherwise `citizenid` is NULL. |
| `account` | string | Account name stored in `bank_statements.account_name`. |
| `amount` | number | Floored to an integer (not range checked). |
| `reason` | string | Cleaned and cut to 50 characters. Default `Deposit` or `Withdrawal` depending on kind. |
| `kind` | string | Must be `deposit` or `withdraw` (the column is an enum). Any other value makes the insert fail. |
| `accountType?` | string | When `player`, the account name is replaced by `checking`. |

**Returns**

- **`boolean`** — `true` when the row was inserted, `false` otherwise.

**Example**

```lua
exports.kora_banking:CreateBankStatement(src, 'checking', 250, 'Rent', 'withdraw', 'player')
```

**Representative console output**

```text
Inserts one `bank_statements` row. Because a statement does not change a balance, a statement for money that was never moved will still appear in the player's Activity.
```

## Limits and related APIs

Server only. Unknown accounts fail silently with false, nil or 0. The export statements are inserted without checking the insert result. Amounts above 1,000,000,000 or below 1 are rejected by `AddMoney` and `RemoveMoney`; `CreateJobAccount`, `CreateGangAccount` and `CreateBankStatement` do not range check.

## Related guides

- [Security and integrity](./security.md)

## Additional details (from the code)

- The account exports are also published under the `qb-banking` resource name through `Kora.compat.provideExport`, so legacy calls such as `exports['qb-banking']:AddMoney(...)` keep working. `ExecuteTransaction` and `GetOperation` exist only on `exports.kora_banking`. See [Compatibility](../compatibility.md).
- Named accounts are rows in `bank_accounts` (shared, job and gang accounts). The account exports do not touch a character's personal bank balance, which belongs to kora_core money.

### ExecuteTransaction and GetOperation

```lua
local receipt, code, message = exports.kora_banking:ExecuteTransaction(operationKey, request)
local receipt, code, message = exports.kora_banking:GetOperation(operationKey)
```

These are restricted to resources in `Config.transactionCallers`. See [Durable transactions](../features/durable-transactions.md) for the request format, receipts and error codes.

