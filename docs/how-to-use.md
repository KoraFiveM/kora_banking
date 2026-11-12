---
title: "How to use"
sidebar_position: 3
---


# How to use

Players use banking at bank counters (full service) and ATMs (cash only, personal account). Other resources read and move money in society, gang and shared accounts through exports, and may run balanced, idempotent multi-account transactions through `ExecuteTransaction`.

## Player walkthrough

1. **Bank counter** — Each entry in `Config.locations` gets a `kora_target` sphere zone (radius 1.2, distance 1.8) labelled `Open bank` (or `Open <label>` when tiers are enabled) and a map blip. Selecting it asks the server to open the bank. The server checks the player's ped is within 3.0 m of a configured location (`BRANCH_RANGE` in `server.lua`) and builds a snapshot.

2. **Accounts and activity** — The `Accounts` view lists every account the player may use: the personal `checking` account (the `bank` value inside `players.money`), shared accounts they own or were added to, and the society or gang account when they are a boss of that job or gang. `Activity` shows the latest 50 statements of the selected account.

3. **Cash and transfers** — `Cash` offers withdraw and deposit. `Transfer` moves money between the player's own accounts, or to another character (by citizen ID or bank card number), or to a shared, society or gang account by name. Recipients may be offline when `Config.Transfers.allowOffline` is true.

4. **Manage** — Open a shared account (funded from the personal balance), rename or close it (balance must be 0), grant or revoke access by citizen ID, and order a bank card with a 4-digit PIN. Only the owner of a shared account may manage it.

5. **ATM** — Targeting an ATM prop (`Config.atmModels`) or a fallback zone (`Config.atmCoords`) shows `Use ATM`. With `Config.requireBankCard` true the client first asks the server whether the player holds a `bank_card` and refuses before any animation if not. A cancellable progress bar (`Config.atmAccessTime`) plays, then the server verifies proximity and opens a locked session. The player enters the 4-digit PIN of one of their own cards. ATMs support withdraw and deposit on the personal account only.

6. **Bank card item** — Using the `bank_card` item from the inventory starts the same ATM flow (`kora_banking:client:useCard`) without aiming at a machine; the position is then found from nearby ATM models or fallback coordinates.

7. **givecash** — `/givecash <id> <amount>` hands cash to a player within 5.0 m. It is a kora_core command and does not touch the bank tables.

## Architecture

- Server (`server.lua`): authority for everything. Holds an in-memory `Accounts` cache keyed by account name (loaded from `bank_accounts` at start and refreshed after each write), a `Sessions` table keyed by player source, validation, the debit/credit logic, statements and the public exports.
- Server durable ledger (`server/finance.lua`): `ExecuteTransaction` and `GetOperation`, receipts in `bank_operations`, legs in `bank_operation_legs`, recovery of interrupted operations.
- Client (`client.lua`): builds the kora_lib AppShell app definition from the latest server snapshot (`Kora.nui.registerApp`, `Kora.nui.openApp`), sends requests, manages targets, blips and the ATM animation and auto-close. It holds no balances of its own and sends no amounts that the server trusts without validation.
- NUI: there is no private page. kora_lib's AppShell renders the app. Form submissions arrive in the client's `onAction` handler, which maps them to `request('pin' | 'action', ...)`.
- Shared: `config.lua` (Config, registered with kora_lib's config system), `tiers.lua` (`BankingTiers`) and `dates.lua` (`BankingDates`).
- Transport: the client sends `kora_banking:server:request` with an incrementing request id and the server answers with `kora_banking:client:response`. This channel is deliberately independent of kora_lib's callback registry. The same handlers are also registered as kora_lib callbacks (`kora_banking:open`, `kora_banking:pin`, `kora_banking:action`) and re-registered if kora_lib restarts. The client waits at most 10 seconds for a reply.

## How money is validated, updated and transferred

There are two distinct paths. Player actions in the UI (`server.lua`) use guarded single-statement updates plus compensating rollbacks. The `ExecuteTransaction` export (`server/finance.lua`) uses one database transaction with a stored receipt.

- Amounts: `roundAmount` accepts a finite number, floors it, and requires 1 to 1,000,000,000. Anything else is rejected. Per-action minimums come from `Config.minAmount`.
- Personal account (`checking`): debited and credited through `exports.kora_core:removeMoney(src, 'bank', ...)` and `addMoney(src, 'bank', ...)` on the online player. A debit first checks `data.money.bank >= amount`.
- Shared, society and gang accounts: `adjustAccount` runs `UPDATE bank_accounts SET account_balance = account_balance + ? ... AND account_balance >= ?` for debits, so an overdraft affects 0 rows and fails. The row count (`applied`) is checked before the cache is refreshed.
- Withdraw: debit the source, then add cash through kora_core. If issuing the cash fails, the source is credited back (`bank withdrawal rollback`). Deposit: remove cash, credit the account, and if crediting fails give the cash back (`bank deposit rollback`).
- Transfers (`transfer` and `moveFunds`): debit the source, then credit the destination. If the credit fails the source is credited back (`transfer rollback`). Offline characters are credited with a guarded `JSON_SET` update on `players.money` that refuses to exceed 9007199254740991. These steps are not wrapped in one database transaction.
- Statements: after a successful move the code writes rows to `bank_statements` (`deposit` or `withdraw`). The return value of that insert is not used to undo the money movement, so a failed history write leaves the balance changed.
- Serialisation: one session per player; while an action runs `current.busy` is set and an overlapping request gets `Your previous banking request is still being processed.`
- Durable path: `ExecuteTransaction` validates balanced debit and credit legs, fences the characters' `money` column with kora_core (`beginPlayerColumnOperation`), then runs all updates, the receipt insert and the leg inserts in a single `Kora.sql.transactionChecked` call.

## Call the exports from your resource

Society, gang and shared accounts are addressed by account name. For job accounts the name is the job name, for gang accounts the gang name.

```lua title="server.lua"
-- Server: charge a society account through the public exports (same pattern kora_bossmenu uses).
local function payFromSociety(job, amount, reason)
    if exports.kora_banking:GetAccountBalance(job) < amount then return false, 'insufficient business funds' end
    if not exports.kora_banking:RemoveMoney(job, amount, reason) then return false, 'could not debit society' end
    return true
end
```
