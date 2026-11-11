---
title: Compatibility
sidebar_position: 9
---

# Compatibility

kora_banking declares `provide 'qb-banking'` in `fxmanifest.lua`, so resources that depend on `qb-banking` start against it.

| Legacy surface | kora_banking behaviour |
| --- | --- |
| `exports['qb-banking']:CreatePlayerAccount`, `CreateJobAccount`, `CreateGangAccount`, `CreateBankStatement`, `AddMoney`, `AddGangMoney`, `RemoveMoney`, `RemoveGangMoney`, `GetAccount`, `GetGangAccount`, `GetAccountBalance` | Same handlers as the `kora_banking` exports (published through `Kora.compat.provideExport`). See [Exports](./exports.md). |
| `qb-banking:client:useCard` | Client net event, same as `kora_banking:client:useCard`. |
| `bank_accounts` / `bank_statements` table names and columns | Kept, so existing data and SQL keep working. |

`ExecuteTransaction` and `GetOperation` are kora_banking-only APIs and are not published under `qb-banking`.
