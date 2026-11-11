---
title: kora_banking
sidebar_position: 1
---

# kora_banking

kora_banking is the Kora banking resource. It gives every character a personal bank account (stored as the `bank` money type in kora_core), plus shared, society (job) and gang accounts stored in its own tables. Players use bank counters at the configured branch locations and targetable ATMs (with an owner-bound bank card and PIN). The interface is rendered by kora_lib's AppShell. The server checks every balance, card, distance, tier and access rule. Other server resources can call legacy-compatible account exports (it provides `qb-banking`). Authorized resources such as kora_housing can also run durable, idempotent multi-party transactions.

## Features

- **Bank branches**: a target zone at each entry in `Config.locations` opens the full banking app. It has these tabs: Accounts (summary and activity), Cash (withdraw/deposit), Transfer (between your own accounts or to someone else) and Manage (shared accounts, bank card, account access). See [Bank branches](./features/bank-branches.md).
- **Account types**: personal account (`checking`, the character's kora_core bank balance), shared accounts owned by one character with up to `Config.maxSharedMembers` members, society accounts for job bosses and gang accounts for gang bosses. See [Shared, society and gang accounts](./features/accounts.md).
- **ATMs**: model targets on `Config.atmModels`, fallback sphere zones at `Config.atmCoords`, a card animation and progress bar, a 4-digit PIN keypad with lockout, and an optional daily allowance. ATMs serve the personal account only. See [ATMs and bank cards](./features/atms.md).
- **Bank cards**: the `bank_card` item is issued at a branch and bound to the character who ordered it. Using the item opens a nearby ATM. See [Items](./items.md).
- **Transfers**: transfers between your own accounts, and transfers to a citizen ID (online or offline), to a shared/society/gang account name or to a bank card number. See [Transfers](./features/transfers.md).
- **Bank tiers (optional)**: Fleeca Bank and Pacific Standard presets with per-tier feature gates, a daily counter withdrawal cap and a maximum single transfer. They are off by default. See [Bank tiers](./features/bank-tiers.md).
- **Transaction history**: the last 50 rows per account from `bank_statements` and from the durable ledger. Date format, time display and time zone are configurable.
- **Map markers**: grouped `Bank` blips created through kora_lib, with optional per-tier icons.
- **Durable resource transactions**: `ExecuteTransaction` / `GetOperation` for allow-listed server resources. They provide balanced debit/credit legs, caller-supplied SQL in the same database transaction, and idempotent receipts. See [Durable transactions](./features/durable-transactions.md).
- **`/givecash` command**: hand cash to a nearby player. See [Commands](./commands.md).
- **Legacy compatibility**: it provides `qb-banking`, the `qb-banking` export names and the `qb-banking:client:useCard` event. See [Compatibility](./compatibility.md).

## Requirements

Declared in `fxmanifest.lua`:

| Resource | Used for |
| --- | --- |
| [kora_theme](https://github.com/KoraFiveM/kora_theme) | Shared palette consumed by the kora_lib AppShell frame (must start first) |
| [kora_lib](https://github.com/KoraFiveM/kora_lib) | AppShell UI, callbacks, notifications, progress bar, blips, config editor, timers, utilities |
| [kora_sql](https://github.com/KoraFiveM/kora_sql) | Database access, schema creation (`Kora.sql.ensureTables`), checked transactions |
| [kora_core](https://github.com/KoraFiveM/kora_core) | Player data, money, items, useable items, commands, jobs/gangs, player-column operation locks |
| [kora_target](https://github.com/KoraFiveM/kora_target) | Branch sphere zones, ATM model targets and ATM fallback zones |
| [kora_inventory](https://github.com/KoraFiveM/kora_inventory) | Holds the `bank_card` item |

The durable transaction API needs kora_sql, kora_core and kora_banking versions that match each other. Deploy them together.

## Installation

1. Put `kora_banking` in your resources folder.
2. Ensure it after its dependencies in `server.cfg`:

   ```cfg
   ensure kora_theme
   ensure kora_lib
   ensure kora_sql
   ensure kora_core
   ensure kora_target
   ensure kora_inventory
   ensure kora_banking
   ```

3. **SQL**: nothing to import by hand. On start the resource creates or extends `bank_accounts`, `bank_statements`, `bank_operations` and `bank_operation_legs` through `Kora.sql.ensureTables`. See [Database](./database.md).
4. **Items**: the `bank_card` item is registered at runtime in kora_core's shared items if it does not already exist. You only need an `id_card.png` image in your inventory images. See [Items](./items.md).
5. Society accounts are created at startup for every job (except `unemployed`), and gang accounts for every gang (except `none`).

## Documentation

- [Configuration](./configuration.md)
- Features: [Bank branches](./features/bank-branches.md), [Accounts](./features/accounts.md), [ATMs and bank cards](./features/atms.md), [Transfers](./features/transfers.md), [Bank tiers](./features/bank-tiers.md), [Durable transactions](./features/durable-transactions.md)
- [Commands](./commands.md)
- [Exports](./exports.md)
- [Events](./events.md)
- [Database](./database.md)
- [Items](./items.md)
- [Compatibility](./compatibility.md)
- [Troubleshooting](./troubleshooting.md)
