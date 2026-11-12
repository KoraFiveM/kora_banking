---
title: Database
sidebar_position: 8
---

# Database

The schema is declared in `server/schema.lua` and applied at startup with `Kora.sql.ensureTables`. This is additive only: missing tables, columns and keys are created, and existing ones are never altered. No SQL file needs to be imported.

## bank_accounts

Named accounts (shared, society and gang). Collation `utf8mb4_unicode_ci`.

| Column | Type | Notes |
| --- | --- | --- |
| `id` | `int(11)` auto increment | Primary key |
| `citizenid` | `varchar(11)` null | Owner of a shared account. `NULL` for job/gang accounts |
| `account_name` | `varchar(50)` null | Unique |
| `account_balance` | `int(11)` default 0 | |
| `account_type` | `enum('shared','job','gang')` | |
| `users` | `longtext` default `'[]'` | JSON array of member citizen IDs (shared accounts) |

## bank_statements

Transaction history shown in the Activity tab. It is also the source for the ATM daily allowance and the tier counter cap. Collation `utf8mb4_unicode_ci`.

| Column | Type | Notes |
| --- | --- | --- |
| `id` | `int(11)` auto increment | Primary key |
| `citizenid` | `varchar(11)` null | Acting character (indexed). `NULL` for export-driven rows |
| `account_name` | `varchar(50)` default `'checking'` | `checking` = personal account |
| `amount` | `int(11)` null | |
| `reason` | `varchar(50)` null | Reference |
| `statement_type` | `enum('deposit','withdraw')` null | |
| `date` | `timestamp` default `CURRENT_TIMESTAMP` | |

## bank_operations

Durable transaction receipts.

| Column | Type | Notes |
| --- | --- | --- |
| `resource` | `varchar(64)` | Primary key part |
| `operation_key` | `varchar(128)` | Primary key part |
| `request` | `longtext` | Canonical request fingerprint |
| `receipt` | `longtext` | JSON receipt |
| `created_at` | `timestamp` default `CURRENT_TIMESTAMP` | |

## bank_operation_legs

Durable ledger legs. They are included in the Activity history once durable banking is ready. Collation `utf8mb4_unicode_ci`.

| Column | Type | Notes |
| --- | --- | --- |
| `id` | `bigint unsigned` auto increment | Primary key |
| `resource` | `varchar(64)` | |
| `operation_key` | `varchar(128)` | |
| `leg` | `smallint unsigned` | Unique with `resource`, `operation_key` |
| `citizenid` | `varchar(50)` null | Character leg (index with `created_at`) |
| `account_name` | `varchar(50)` null | Named-account leg (index with `created_at`) |
| `direction` | `varchar(8)` | `withdraw` or `deposit` |
| `amount` | `bigint unsigned` | |
| `reason` | `varchar(50)` | |
| `created_at` | `timestamp` default `CURRENT_TIMESTAMP` | |

## Other tables used

| Table | Usage |
| --- | --- |
| `players` (kora_core) | `citizenid`/`deleted_at` to validate recipients and new members. `money` JSON (`$.bank`) for offline transfer credits and durable transactions. `inventory` JSON to resolve bank card numbers. |
| kora_core player-column lock table | Created by kora_core. Used by durable transactions through `beginPlayerColumnOperation` and related functions. |

## History query

For each account, the Activity tab shows the 50 newest rows. These come from `bank_statements` and, when durable banking is ready, `bank_operation_legs` combined with `UNION ALL`. Dates are returned as Unix milliseconds. Personal-account history uses `bank_statements` rows with the character's `citizenid` and `account_name = 'checking'`, plus ledger legs with the same `citizenid`.
