---
title: Bank branches
sidebar_position: 1
---

# Bank branches

Every entry in `Config.locations` gets a kora_target sphere zone (radius 1.2 m, interaction distance 1.8 m) and a map marker. The target option reads `Open bank`. When [tiers](./bank-tiers.md) are enabled, it reads `Open <label>` (for example `Open Pacific Standard`).

## Opening a branch

Selecting the target sends an `open` request to the server with the location index. The server:

1. Refuses while banking is still starting ("Banking is still starting.").
2. Resolves the nearest configured location within **3 metres** of the player's real position ("Move closer to a bank counter." otherwise). The client-sent index only has to name a real location. The tier is never taken from the client.
3. Creates a bank session that expires after 5 minutes of inactivity. Each action re-checks that the player is still within 3 m of a branch.
4. Creates a missing society or gang account if the player is a job or gang boss.
5. Returns a snapshot with profile (name, account number = citizen ID, cash, issued cards), accessible accounts, the last 50 transactions per account, date settings, limits and (with tiers enabled) branch information.

The app (kora_lib AppShell id `kora_banking:bank`) opens in the standard layout. Its header shows the branch label when tiers are enabled, and `Kora Bank` otherwise.

## App sections

| View | Tab | What it does |
| --- | --- | --- |
| Accounts | Summary | Cash on hand, selected balance, branch (with tiers), and a searchable list of accessible accounts. Selecting a card changes the selected account. |
| Accounts | Activity | Table of recent transactions for the selected account: type, amount, reference, date. |
| Cash | Withdraw | Withdraw from any usable account. Has $50/$100/$250/$500 presets and an optional reference (max 50 chars). |
| Cash | Deposit | Deposit cash into any usable account. |
| Transfer | My accounts | Move money between two of your accessible accounts. |
| Transfer | Another player | Send to a citizen ID, an account name or a card number. See [Transfers](./transfers.md). |
| Manage | Shared accounts | Lists your owned shared accounts and lets you create one. See [Accounts](./accounts.md). |
| Manage | Bank card | Lists issued cards (masked as `**** 1234`) and issues a new card with a chosen 4-digit PIN. |
| Manage | Account access | Rename, grant access, revoke access, close a shared account (owners only). |

## Rules enforced by the server

- Amounts are rounded down to whole dollars and must be at least the `Config.minAmount` value for the action, and at most 1,000,000,000.
- Deposits require enough cash. Withdrawals require enough balance in the chosen account.
- If a step fails after money has moved, the server rolls it back (for example cash is returned if the account cannot be credited).
- Every successful deposit, withdrawal and transfer writes rows to `bank_statements`.
- One player's actions are processed one at a time. An overlapping request gets "Your previous banking request is still being processed."
- With tiers enabled, the tier's feature gates, the daily counter withdrawal cap and the maximum transfer apply. See [Bank tiers](./bank-tiers.md).

## Ordering a bank card

`Manage → Bank card → Issue bank card` asks for a 4-digit PIN and adds one `bank_card` item with this metadata:

| Field | Value |
| --- | --- |
| `citizenid` | The ordering character |
| `name` | Character first and last name |
| `cardNumber` | Random 16-digit number |
| `cardPin` | The chosen PIN (number) |

Cards are free, and there is no limit on how many a character can order. If the inventory has no room, the order fails with "There is no room for a bank card." The tier feature `orderCard` can block ordering.

## Map markers

Markers are created with `Kora.blips.create` using `Config.blipInfo` (category `Bank`). With tiers enabled, each marker uses its tier's `sprite`/`color`/`scale` overrides and the location label as its name. Markers and branch targets are rebuilt when `tiers.enabled` or `tiers.default` changes through the kora_lib config system.
