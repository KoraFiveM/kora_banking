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
- **Bank tiers (optional)**: Fleeca Bank and Pacific Standard presets with per-tier feature gates, a daily counter withdrawal cap and a maximum single transfer. They are off by default. See [Bank tiers](./api/tiers.md).
- **Transaction history**: the last 50 rows per account from `bank_statements` and from the durable ledger. Date format, time display and time zone are configurable.
- **Map markers**: grouped `Bank` blips created through kora_lib, with optional per-tier icons.
- **Durable resource transactions**: `ExecuteTransaction` / `GetOperation` for allow-listed server resources. They provide balanced debit/credit legs, caller-supplied SQL in the same database transaction, and idempotent receipts. See [Durable transactions](./features/durable-transactions.md).
- **`/givecash` command**: hand cash to a nearby player. See [Commands](./commands.md).
- **Legacy compatibility**: it provides `qb-banking`, the `qb-banking` export names and the `qb-banking:client:useCard` event. See [Compatibility](./compatibility.md).

## Requirements and installation

The resource needs kora_theme, kora_lib, kora_sql, kora_core, kora_target and kora_inventory. See [Installation](./installation.md) for the requirements table, `server.cfg` order and first-start behaviour.

## Documentation map

- [Installation](./installation.md): setup steps, manifest reference and requirements
- [How to use](./how-to-use.md): player walkthrough, architecture and how money is validated
- [Commands](./commands.md): `/givecash`
- API reference: [overview](./api/index.md), [Public exports](./api/exports.md), [Configuration](./api/configuration.md), [Bank tiers](./api/tiers.md), [Security and integrity](./api/security.md)
- Features: [Bank branches](./features/bank-branches.md), [Accounts](./features/accounts.md), [ATMs and bank cards](./features/atms.md), [Transfers](./features/transfers.md), [Durable transactions](./features/durable-transactions.md)
- [Events](./events.md)
- [Database](./database.md)
- [Items](./items.md)
- [Compatibility](./compatibility.md)
- [Troubleshooting](./troubleshooting.md)
