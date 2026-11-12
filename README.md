> [!WARNING]
> **Kora Framework is in alpha and actively being developed.**
>
> This resource is a work in progress. Features may be incomplete or unstable,
> and APIs, configuration, and behavior may change. It is not ready for production use.
>
> **Help shape Kora:** try it out, share feedback, report bugs through this
> repository’s Issues, and contribute improvements through pull requests.

# kora_banking

## Features
- kora_lib AppShell banking interface, shared with the administration menu
- Clearly separated personal, society, gang, and shared balances
- Full branch services: cash, transfers, transaction history, shared accounts, and bank cards
- Compact ATM interface with server-side PIN checks and attempt throttling
- Targetable world ATMs with card animation, owner-bound cards, proximity checks, and configurable daily limits
- Grouped `Bank` map markers created and cleaned up through kora_lib
- Optional bank tiers: Fleeca Bank branches for everyday cash, Pacific Standard (Big Bank) for shared accounts and larger limits
- kora_lib callbacks, notifications and interactions
- kora_core flat exports for players, money, inventory, commands, jobs, and gangs
- Compatible `AddMoney`, `RemoveMoney`, and account exports for job resources

## Requirements

- `kora_lib`
- `kora_sql`
- `kora_core`
- `kora_target`
- `kora_inventory`

ATMs are available on the models in `Config.atmModels`. ATMs baked into the map, or whose prop the targeting ray does not resolve, can be listed in `Config.atmCoords` (vector3 per machine; default: the two Fleeca ATMs in front of the Legion Square bank); each gets a `Use ATM` target zone of `Config.atmZoneRadius` metres (default `1.2`) that hides itself while the aimed prop is already an `atmModels` entry. `Config.atmAlwaysShowTarget` (default `true`) keeps `Use ATM` visible to players without a bank card, who then get `Config.atmNoCardMessage`; `false` shows the target only to players the server reports as holding a card. Players can order a bank card and choose its PIN at a branch, then target an ATM or use the card while standing beside one. `Config.atmDistance`, `Config.atmTolerance` (extra metres for wide wall ATMs, default `1.0`), `Config.atmCloseDistance` (metres from the machine at which an open ATM closes, default `3.0`, `0` disables), `Config.atmCloseInVehicle` (default `true`; ATMs cannot be opened from a vehicle and close when the player enters one) with `Config.atmVehicleMessage`, `Config.atmAccessTime`, `Config.atmAccessMovement` (default `'controls'`: walk and sprint keys are ignored during the access bar, so the player slows to a natural stop and is never frozen in place or mid-air; `'freeze'` restores the old freeze in place), `Config.requireBankCard` (default `true`; the server checks for a bank card before the animation and progress bar start, so a player without one only sees the error notification; `false` lets ATMs open without a card or PIN), `Config.useDailyLimit`, and `Config.dailyLimit` control the ATM flow.

## Bank tiers (Fleeca Bank vs Pacific Standard)

Off by default: with `Config.tiers.enabled = false` every branch behaves exactly as before. Set it to `true` to give
branches different services.

`Config.locations` entries are either plain coordinates (still valid; they use `Config.tiers.default`) or a table:

```lua
locations = {
    vector3(149.05, -1041.3, 29.37),                                                  -- legacy: default tier
    { coords = vector3(247.65, 223.87, 106.29), tier = 'bigbank', label = 'Pacific Standard' },
}
```

`label` names the branch in the app header, the target prompt and the map marker; without it the tier label is used.
The shipped locations are tagged: Pacific Standard (Vinewood/Alta) is `bigbank`, the six Fleeca branches are `fleeca`, and
Blaine County Savings (Paleto) is `fleeca` with its own label.

`Config.tiers.list.<tier>` defines each tier:

| Option | Meaning |
| --- | --- |
| `label` | Name shown in the header, in "Available at ..." messages and on the map |
| `features.<name>` | `false` blocks the feature at that tier (unset = allowed). Names: `deposit`, `withdraw`, `transfer`, `sharedAccounts` (open/rename/close shared accounts), `manageMembers` (grant/revoke access), `orderCard` |
| `limits.dailyWithdraw` | Daily withdrawal cap at bank counters of the tier ($, `0` = no limit). ATMs keep `Config.dailyLimit` |
| `limits.maxTransfer` | Largest single transfer at the tier ($, `0` = no limit) |
| `blip` | Optional `sprite`, `color`, `scale` overrides for that tier's map markers |

Default preset: Fleeca = cash, deposits, withdrawals and transfers up to `$10,000` with a `$5,000` daily withdrawal cap;
Pacific Standard = everything Fleeca offers plus shared accounts and member management, transfers up to `$250,000`
and a `$50,000` daily withdrawal cap. You can add your own tiers under `list` and point locations at them.

The server picks the tier from the nearest configured location to the player's real position (within 3 m), never from
anything the client sends, and re-checks it on every action. The UI disables gated actions and says
"Available at Pacific Standard". The daily withdrawal cap counts all of the character's bank-account withdrawals of the day
(the same statement table the ATM allowance uses). Feature, limit and default-tier changes apply immediately; map marker
changes need a resource restart. A per-day transfer total is not tracked.

The counter cap counts withdrawals from every account the character used that day (personal and shared); the day
resets at midnight on the database clock and is stored in `bank_statements`, so it survives restarts. Overlapping
requests from one player are processed one at a time so they cannot slip past a cap together.

ATMs are not branches and have no tier: they serve the personal account only (no transfers, shared accounts or member
management) and keep the `Config.useDailyLimit` / `Config.dailyLimit` allowance. Client-side map markers and the
"Open <branch>" prompts are rebuilt when the server config arrives, so enabling tiers in `config.local.lua` shows the
Fleeca / Pacific Standard markers without editing `config.lua`.

The resource name is `kora_banking`. It provides the legacy `qb-banking` identity and card-use event so existing job resources can migrate without breaking.

## Durable resource transactions

`Config.transactionCallers` authorizes server resources (default `kora_housing`).
`ExecuteTransaction(operationKey, request)` returns a confirmed receipt, or
`false, code, message` (not `nil`: a leading nil would drop the code and message
across the export boundary). `GetOperation(operationKey)` reads only the caller's receipt
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
Startup creates the player-column lock table (kora_core) and kora_banking's durable
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

## Player transfers

The "Another player" transfer accepts a character account number (citizen ID), a shared / society (job) / gang account
name, or the number of an issued bank card (spaces or dashes between groups of four are ignored). Offline characters are
credited directly in the database; the sender and the recipient both get a statement row. Tier limits (`maxTransfer`,
the `transfer` feature) still apply.

| Option | Default | Effect |
|---|---|---|
| `Config.Transfers.allowOffline` | `true` | `false` = the recipient must be online (previous behaviour) |
| `Config.Transfers.allowSharedAccounts` | `true` | allow shared, society and gang account names |
| `Config.Transfers.allowCardNumbers` | `true` | allow a bank card number; it resolves to the character the card was issued to |

Card numbers are looked up in stored inventories, so a card that was only just ordered resolves after the issuing
character's inventory has been saved.

Full documentation: see [docs/](docs/index.md).
