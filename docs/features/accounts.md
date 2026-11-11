---
title: Shared, society and gang accounts
sidebar_position: 2
---

# Shared, society and gang accounts

## Account types

| Type | Name in the app | Storage | Who can use it |
| --- | --- | --- | --- |
| `checking` | Personal bank | kora_core player money `bank` | The character |
| `job` | Society bank | `bank_accounts` row, `account_name` = job name | Players whose current job matches and who are a boss (`isboss` on the job or its grade) |
| `gang` | Gang bank | `bank_accounts` row, `account_name` = gang name | Players whose current gang matches and who are a boss |
| `shared` | Shared bank | `bank_accounts` row owned by a citizen ID with a JSON `users` list | The owner and listed members |

Accounts are listed in this order: personal, society, gang, shared. Within a type, they are sorted by owner name. Society and gang accounts show the job or gang label. Other accounts show the account name in title case.

Anyone who can use an account can deposit into it, withdraw from it and transfer from it at a branch. Only the owner of a shared account can manage it.

## Society and gang accounts

- At startup the resource loads all `bank_accounts` rows into memory. It then creates a zero-balance `job` account for every job in kora_core shared jobs (except `unemployed`) and a `gang` account for every gang (except `none`) that has no account yet.
- When a boss opens a branch, a missing account for their current job or gang is created on the fly.
- Other resources can create accounts with `CreateJobAccount` / `CreateGangAccount` and move money with `AddMoney` / `RemoveMoney`. See [Exports](../exports.md).

## Shared accounts

All shared-account actions are in the branch app under **Manage**. With tiers enabled, they need the `sharedAccounts` feature (create, rename, close) or the `manageMembers` feature (grant, revoke).

### Create

- Name: 3 to 40 characters. It must start with a letter or digit, followed by letters, digits, spaces, dashes or underscores. Names are unique across all bank accounts, including job and gang accounts.
- Opening balance: must be at least $1. It is withdrawn from your personal account. The form defaults to 0, but the server rejects $0 with "You can not open a shared account with $0".
- A character can own at most `Config.maxAccounts` shared accounts.
- Two statement rows are written: a withdrawal `Opened <name>` on `checking` and a deposit `Opening balance` on the new account.

### Rename

Owner only. The new name follows the same rules and must be unused. Existing `bank_statements` rows are renamed as well.

### Close

Owner only. The balance must be exactly 0 ("Move the remaining balance before closing this account.").

### Grant and revoke access

Owner only. Enter a citizen ID (max 16 characters).

- Grant: the citizen ID must exist in `players`, must not already be a member, and the list must be below `Config.maxSharedMembers`. The encoded list must fit in `Config.maxSharedMemberBytes`.
- Revoke: removes the citizen ID from the list.
- Requests are rate-limited per player by `Config.memberRateLimit` (default 5 per 10 seconds).

Members see the account in their list and can use its money, but cannot rename, close or change access.
