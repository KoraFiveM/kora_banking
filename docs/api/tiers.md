---
title: "Bank tiers"
sidebar_position: 4
---


# Bank tiers

Optional branch classes. With `Config.tiers.enabled = true` each location uses the features, limits and blip of its tier. Defaults: `fleeca` (deposit, withdraw, transfer, orderCard; no shared accounts or member management; $5000 daily counter withdrawal and $10000 largest transfer) and `bigbank` (Pacific Standard: everything; $50000 and $250000).

Namespace: `BankingTiers` · Source: `tiers.lua, server.lua (branchAt, tierBlocks), client.lua (blipOptions, appDefinition)`

## How it works

Enforcement is on the server: `branchAt` resolves the real branch from the player's ped, `tierBlocks` rejects gated features with `<what> is only available at <label>.`, and `maxTransfer` and `dailyWithdraw` are checked in `transfer` and `transactCash`. The client only disables controls and shows `Available at ...`. ATMs are never tier-restricted and always use the ATM allowance.

## Terms used on this page

| Term | Meaning |
| --- | --- |
| Feature | A gated capability: `deposit`, `withdraw`, `transfer`, `sharedAccounts` (create, rename, close), `manageMembers` (add or remove), `orderCard`. |
| Limit | `dailyWithdraw` (counter withdrawals per day across all accounts) and `maxTransfer` (single transfer). |

## Functions

`BankingTiers` is a global shared by client and server scripts of this resource. It is not exported to other resources.

### `BankingTiers.enabled()`

True when `Config.tiers.enabled == true`.

**Parameters**



**Returns**

- **`boolean`.**

**Example**

```lua
if BankingTiers.enabled() then print('tiers on') end
```

**Representative console output**

```text
Global table in `tiers.lua`, not an export. Only usable inside this resource.
```

### `BankingTiers.resolve(position, range)`

Finds the nearest `Config.locations` entry within `range` of a position and returns its info table.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `position` | table \| vector3 \| vector4 | Needs numeric x, y, z. |
| `range` | number | Search radius (the server uses 3.0). |

**Returns**

- **`table | nil`** — `{ index, coords, label, enabled, tier?, tierLabel?, features?, limits?, blip? }`.

**Example**

```lua
local info = BankingTiers.resolve(GetEntityCoords(GetPlayerPed(src)), 3.0)
```

**Representative console output**

```text
Never trusts client-sent tiers. When tiers are disabled the info has only `index`, `coords`, `label`, `enabled`.
```

### `BankingTiers.can(info, feature)`

True unless tiers are on and the tier sets the feature to false.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `info` | table \| nil | Result of `info` or `resolve`. |
| `feature` | string | One of `deposit`, `withdraw`, `transfer`, `sharedAccounts`, `manageMembers`, `orderCard`. |

**Returns**

- **`boolean`.**

**Example**

```lua
if not BankingTiers.can(info, 'transfer') then return end
```

**Representative console output**

```text
Nil info means allowed.
```

### `BankingTiers.limit(info, key)`

Positive limit of the tier for `dailyWithdraw` or `maxTransfer`.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `info` | table \| nil | Branch info. |
| `key` | string | Limit name. |

**Returns**

- **`integer | nil`** — floored positive number, or nil for no limit.

**Example**

```lua
local cap = BankingTiers.limit(info, 'maxTransfer')
```

**Representative console output**

```text
0, negative or missing values mean no limit.
```

### `BankingTiers.info(index)`

Other helpers: `info(index)` describes one location; `get(name)` returns a tier; `entry(raw)` normalizes a location entry; `defaultName()` picks the default tier (falls back to `fleeca` when present); `availableAt(feature)` gives the label of the first tier, sorted by name, that allows a feature; `gated(info)` lists blocked features with that label; `higherLimitAt(key, current)` returns the first tier whose limit is higher.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `index` | number | Index into `Config.locations`. |

**Returns**

- **`table | nil`.**

**Example**

```lua
local info = BankingTiers.info(1)
```

**Representative console output**

```text
All of them read `Config` at call time.
```

## Limits and related APIs

Helpers return nil or no restriction when `Config` is missing or malformed. Tier names used by locations that do not exist fall back to `Config.tiers.default`.

## Related guides

- [Configuration](./configuration.md)

## Branch tiers in practice

### How a branch gets its tier

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


### Tier definition

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


### In the app

Gated actions are disabled, and the tab shows "Not available at this branch - Available at `<tier label>`". The server message for a blocked action is `<Action> is only available at <tier label>.` In both cases the tier named is the first one (sorted by tier key) that allows the feature. The withdraw and transfer inputs show the remaining counter allowance and the maximum transfer.


### Daily counter cap

`limits.dailyWithdraw` counts all `withdraw` statement rows of the character for the day, on every account they used (personal and shared, and society/gang rows written by that player). The day resets at midnight on the database clock. Because the count reads `bank_statements`, it survives restarts. Outgoing transfers and shared-account opening balances are also `withdraw` rows and count toward the cap. Overlapping requests from one player are processed one at a time, so they cannot slip past the cap together.


### When changes apply

Feature, limit and default-tier changes apply immediately on the server. On the client, map markers and branch target prompts are rebuilt when `tiers.enabled` or `tiers.default` changes through kora_lib's config system (for example `config.local.lua` or the config editor). Other marker changes (per-tier `blip`, `locations`) need a resource restart.

