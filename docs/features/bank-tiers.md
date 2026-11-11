---
title: Bank tiers
sidebar_position: 5
---

# Bank tiers (Fleeca Bank vs Pacific Standard)

Tiers are **off by default**. With `Config.tiers.enabled = false`, every branch offers every service and has no tier limits. Set it to `true` to give branches different services.

## How a branch gets its tier

`Config.locations` entries are plain coordinates or `{ coords, tier, label }` tables:

```lua
locations = {
    vector3(149.05, -1041.3, 29.37),                                                  -- uses Config.tiers.default
    { coords = vector3(247.65, 223.87, 106.29), tier = 'bigbank', label = 'Pacific Standard' },
}
```

- Plain coordinates and unknown tier names use `Config.tiers.default`. If that is not a configured tier, `fleeca` is used when it exists.
- `label` names the branch in the app header, the `Open <label>` target prompt and the map marker. Without it, the tier label is used.
- The shipped config tags Pacific Standard as `bigbank`. The six Fleeca branches and Blaine County Savings (Paleto, with its own label) are `fleeca`.

The server picks the tier from the nearest configured location within 3 m of the player's actual position, never from client data, and re-checks it on every action.

## Tier definition

`Config.tiers.list.<tier>`:

| Option | Meaning |
| --- | --- |
| `label` | Name shown in the header, in "Available at ..." messages and on the map |
| `features.<name>` | `false` blocks the feature at that tier. Unset means allowed. Names: `deposit`, `withdraw`, `transfer`, `sharedAccounts` (open/rename/close shared accounts), `manageMembers` (grant/revoke access), `orderCard` |
| `limits.dailyWithdraw` | Daily withdrawal cap at bank counters of the tier ($, `0` = no limit). ATMs keep `Config.dailyLimit` |
| `limits.maxTransfer` | Largest single transfer at the tier ($, `0` = no limit) |
| `blip` | Optional `sprite`, `color`, `scale` overrides for that tier's map markers |

Default preset:

- **Fleeca Bank** (`fleeca`): deposits, withdrawals, transfers and card orders. Transfers up to $10,000 and a $5,000 daily counter withdrawal cap. No shared accounts or member management.
- **Pacific Standard** (`bigbank`): everything Fleeca offers, plus shared accounts and member management. Transfers up to $250,000 and a $50,000 daily counter withdrawal cap.

You can add your own tiers under `list` and point locations at them.

## In the app

Gated actions are disabled, and the tab shows "Not available at this branch - Available at `<tier label>`". The server message for a blocked action is `<Action> is only available at <tier label>.` In both cases the tier named is the first one (sorted by tier key) that allows the feature. The withdraw and transfer inputs show the remaining counter allowance and the maximum transfer.

## Daily counter cap

`limits.dailyWithdraw` counts all `withdraw` statement rows of the character for the day, on every account they used (personal and shared, and society/gang rows written by that player). The day resets at midnight on the database clock. Because the count reads `bank_statements`, it survives restarts. Outgoing transfers and shared-account opening balances are also `withdraw` rows and count toward the cap. Overlapping requests from one player are processed one at a time, so they cannot slip past the cap together.

## When changes apply

Feature, limit and default-tier changes apply immediately on the server. On the client, map markers and branch target prompts are rebuilt when `tiers.enabled` or `tiers.default` changes through kora_lib's config system (for example `config.local.lua` or the config editor). Other marker changes (per-tier `blip`, `locations`) need a resource restart.
