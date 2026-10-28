# kora_banking

## Features
- kora_lib AppShell banking interface, shared with the administration menu
- Clearly separated personal, society, gang, and shared balances
- Full branch services: cash, transfers, transaction history, shared accounts, and bank cards
- Compact ATM interface with server-side PIN checks and attempt throttling
- Targetable world ATMs with card animation, owner-bound cards, proximity checks, and configurable daily limits
- Grouped `Bank` map markers created and cleaned up through kora_lib
- kora_lib callbacks, notifications and interactions
- kora_core flat exports for players, money, inventory, commands, jobs, and gangs
- Compatible `AddMoney`, `RemoveMoney`, and account exports for job resources

## Requirements

- `kora_lib`
- `kora_sql`
- `kora_core`
- `kora_target`
- `kora_inventory`

ATMs are available on the models in `Config.atmModels`. Players can order a bank card and choose its PIN at a branch, then target an ATM or use the card while standing beside one. `Config.atmDistance`, `Config.atmAccessTime`, `Config.useDailyLimit`, and `Config.dailyLimit` control the ATM flow.

The resource name is `kora_banking`. It provides the legacy `qb-banking` identity and card-use event so existing job resources can migrate without breaking.

## Durable resource transactions

`Config.transactionCallers` authorizes server resources (default `kora_housing`).
`ExecuteTransaction(operationKey, request)` returns a confirmed receipt, or
`nil, code, message`. `GetOperation(operationKey)` reads only the caller's receipt
and completes any pending player/cache synchronization. Both yield.

```lua
local receipt, code, message = exports.kora_banking:ExecuteTransaction('sale:123', {
    debits = { { citizenid = buyerCitizenId, amount = 1000 } },
    credits = { { citizenid = sellerCitizenId, amount = 940 },
                { account = 'realestate', amount = 60 } },
    reason = 'Property purchase',
    statements = { { query = 'UPDATE properties SET owner=? WHERE id=? AND owner=?',
        values = { buyerCitizenId, propertyId, sellerCitizenId }, expectedRows = 1 } },
})
```

Legs must balance in positive whole currency units. Each leg identifies one
character's bank balance or one existing named bank account. Debit checks use the
gross debit even when the same account is also credited, and never use core
negative-balance allowances. Account creation remains an explicit existing API.
The caller supplies trusted server SQL; validate every domain precondition using
`expectedRows` and transactional tables. Do not accept SQL or prices from clients.

The exact request is immutable per resource/key. Its unique receipt, ledger legs,
balances and supplied domain statements commit together. The receipt has
`operationKey`, `resource`, `status='completed'`, `timestamp`, `amount`, `accounts`.
Repeating the same request returns its original receipt; changed terms conflict.
Keep prepared requests durably so retries after restart use identical terms.

`insufficient_funds` is a confirmed debit precondition failure; `unavailable` is
storage failure, `conflict` is changed terms/domain state, and `rejected` is invalid
input or an unauthorized caller. `pending` and `indeterminate` retain fences and
require receipt reconciliation or an identical retry. `GetOperation` can return
`not_found` after waiting for an old driver worker; it does not execute a new debit.
Never issue compensating money changes after an ambiguous reply.

Deploy updated kora_sql (including its built bundle), kora_core and kora_banking together.
Core migration 10 records player-column locks; kora_banking migration 1 adds durable
receipts and a separate ledger supporting 50-character citizen IDs. Existing bank
exports keep their signatures. The new ledger is included in transaction history.
Bank startup reconciles its own retained player fences: confirmed receipts publish
committed balances, and a confirmed absent preparation releases without a debit.
Receipt lookup uses a locking read to wait for server-side work after a SQL-host
restart. Failed reconciliation retries only while known operations remain pending.
An unresolved persistent lock deliberately refuses money/item writes and character
login until its owning provider reconciles; retain the receipt/lock tables when
restarting resources. Direct third-party SQL writes to player JSON bypass core
coordination and are outside this guarantee.

# License

    QBCore Framework
    Copyright (C) 2021 Joshua Eger

    This program is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with this program.  If not, see <https://www.gnu.org/licenses/>
