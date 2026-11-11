---
title: Configuration
sidebar_position: 2
---

# Configuration

All options live in `config.lua` in the global `Config` table, which is shared by client and server. Most options are also registered with kora_lib's config editor (`Kora.config`). Changes saved there go to `config.local.lua`, which is git-ignored. The "Applies" column shows when a change takes effect. For options with editor metadata it is the value declared there; options without metadata (`transactionCallers`, `ui.accent`, `atmCloseDistance`, `atmCloseInVehicle`, `atmVehicleMessage`) are read when they are used. Options marked "restart" need `restart kora_banking`.

## General

| Key | Type | Default | Applies | Description |
| --- | --- | --- | --- | --- |
| `transactionCallers` | table (resource name to `true`) | `{ kora_housing = true }` | immediately | Server resources allowed to call `ExecuteTransaction` / `GetOperation`. See [Durable transactions](./features/durable-transactions.md). |
| `ui.accent` | string or nil | `nil` | next open | Optional accent colour passed to the kora_lib AppShell. |
| `migrationRetrySeconds` | integer (0 to 3600) | `0` | next failure | If the durable schema setup fails at startup, retry after this many seconds. `0` logs once and leaves durable transactions and durable history disabled until restart. |

## ATMs

| Key | Type | Default | Applies | Description |
| --- | --- | --- | --- | --- |
| `atmModels` | list of model names | `prop_atm_01`, `prop_atm_02`, `prop_atm_03`, `prop_fleeca_atm`, `gabz_sm_pb_atmframe`, `v_5_b_atm1`, `v_5_b_atm2` | restart | Props that get the `Use ATM` target and are found by the nearby-ATM lookup. |
| `atmCoords` | list of `vector3` | two Legion Square Fleeca ATMs: `vector3(147.4, -1035.8, 29.3)`, `vector3(145.9, -1035.2, 29.3)` | restart | Fallback ATMs for machines baked into the map or not resolved by the target ray. Each gets a `Use ATM` sphere zone, which is hidden while the aimed entity is already an `atmModels` prop. |
| `atmZoneRadius` | number (0.3 to 5.0) | `1.2` | restart | Radius of each `atmCoords` zone. |
| `atmDistance` | number | `1.8` | restart | Target interaction distance and base ATM reach. |
| `atmTolerance` | number | `1.0` | restart | Extra metres on top of `atmDistance` for the client lookup and the server proximity check. Raise it for wide wall ATMs. |
| `atmCloseDistance` | number | `3.0` | next ATM open | An open ATM closes when the player is further than this from the machine. `0` disables the check. |
| `atmCloseInVehicle` | boolean | `true` | immediately | ATMs cannot be opened from a vehicle, and an open ATM closes when the player enters one. |
| `atmVehicleMessage` | string | `'You cannot use an ATM from a vehicle.'` | immediately | Notification for the vehicle block. |
| `atmAccessTime` | integer (ms) | `1500` | restart | Duration of the cancellable "Accessing ATM..." progress bar. |
| `atmAccessMovement` | `'controls'` or `'freeze'` | `'controls'` | immediately | `controls` ignores walk/sprint keys during the bar, so the ped is never frozen. `freeze` freezes the ped in place (legacy behaviour). |
| `requireBankCard` | boolean | `true` | immediately | `true`: an ATM needs a `bank_card` in the inventory and its PIN, and the server checks for the card before the animation starts. `false`: ATMs open without a card or PIN. |
| `atmAlwaysShowTarget` | boolean | `true` | immediately | `true`: `Use ATM` always shows, and players without a card get `atmNoCardMessage`. `false`: the option only shows for players the server reports as holding a card (re-checked at most every 5 seconds while aiming). |
| `atmNoCardMessage` | string | `'You need a bank card to use an ATM.'` | immediately | Notification shown when the card is missing. |
| `useDailyLimit` | boolean | `true` | restart | Enforce the daily ATM withdrawal allowance. |
| `dailyLimit` | integer | `5000` | restart | ATM allowance per character per day, counted since midnight on the database clock. See [ATMs](./features/atms.md#daily-allowance) for what counts. |

## Amounts and dates

| Key | Type | Default | Applies | Description |
| --- | --- | --- | --- | --- |
| `minAmount.withdraw` | integer (min 1) | `1` | immediately | Smallest withdrawal (counter and ATM). Set it to `5` for a $5 minimum. |
| `minAmount.deposit` | integer (min 1) | `1` | immediately | Smallest deposit (counter and ATM). |
| `minAmount.transfer` | integer (min 1) | `1` | immediately | Smallest transfer (internal and to others). |
| `dateFormat` | `'locale'`, `'DD/MM/YYYY'`, `'MM/DD/YYYY'`, `'YYYY-MM-DD'` | `'locale'` | next Activity view | `locale` follows the client `locale` convar: English US/CA/PH (or plain `en`) use `MM/DD/YYYY` with a 12-hour clock, `ja`/`zh`/`ko`/`hu`/`sv`/`lt` use `YYYY-MM-DD`, and all others use `DD/MM/YYYY`. |
| `showTime` | boolean | `true` | next Activity view | Append hour and minute to activity dates. |
| `dateTimezone` | `'player'` or `'server'` | `'player'` | next Activity view | `player` shows dates in the player machine's time zone. `server` shows UTC to everyone. The legacy values `local` and `utc` are mapped to `player` and `server`. |

All amounts are rounded down to whole dollars and must be between 1 and 1,000,000,000.

## Transfers

| Key | Type | Default | Applies | Description |
| --- | --- | --- | --- | --- |
| `Transfers.allowOffline` | boolean | `true` | immediately | Credit offline characters directly in the `players` table. `false` requires the recipient to be online. |
| `Transfers.allowSharedAccounts` | boolean | `true` | immediately | Allow a shared, society or gang account name as the recipient. |
| `Transfers.allowCardNumbers` | boolean | `true` | immediately | Allow a bank card number as the recipient. |

## Shared accounts

| Key | Type | Default | Applies | Description |
| --- | --- | --- | --- | --- |
| `maxAccounts` | integer | `2` | restart | Shared accounts a character may own. |
| `maxSharedMembers` | integer | `10` | restart | Additional members per shared account. Lowering it truncates stored member lists when they are read. |
| `maxSharedMemberBytes` | integer | `512` | restart | Maximum JSON size of a member list. Oversized stored lists are read as empty, and oversized updates are rejected. |
| `memberRateLimit.max` | integer | `5` | restart | Member-management requests per player per window. |
| `memberRateLimit.window` | integer (ms) | `10000` | restart | Rolling window for `memberRateLimit.max`. |

## Map markers

| Key | Type | Default | Applies | Description |
| --- | --- | --- | --- | --- |
| `blipInfo.category` | string | `'Bank'` | restart | kora_lib map-legend category. |
| `blipInfo.sprite` | integer | `108` | restart | Blip sprite. |
| `blipInfo.color` | integer | `2` | restart | Blip colour. |
| `blipInfo.scale` | number | `0.55` | restart | Blip scale. |
| `blipInfo.shortRange` | boolean | `true` | restart | Show markers on the minimap only when nearby. |

## Locations

`locations` is a list (editor: restart to apply). Each entry is either plain coordinates or a table with `coords`, `tier` and `label`:

```lua
locations = {
    vector3(149.05, -1041.3, 29.37), -- plain: uses Config.tiers.default when tiers are enabled
    { coords = vector3(247.65, 223.87, 106.29), tier = 'bigbank', label = 'Pacific Standard' },
}
```

Shipped locations:

| Label | Tier |
| --- | --- |
| Fleeca Bank - Legion Square | `fleeca` |
| Fleeca Bank - Alta | `fleeca` |
| Fleeca Bank - Burton | `fleeca` |
| Fleeca Bank - Rockford Plaza | `fleeca` |
| Fleeca Bank - Great Ocean Highway | `fleeca` |
| Fleeca Bank - Harmony | `fleeca` |
| Pacific Standard | `bigbank` |
| Blaine County Savings | `fleeca` |

Each location gets a target sphere (radius 1.2, interaction distance 1.8) and a map marker. The server only accepts a bank session when the player stands within 3 metres of a configured location.

## Bank tiers

| Key | Type | Default | Applies | Description |
| --- | --- | --- | --- | --- |
| `tiers.enabled` | boolean | `false` | immediately (server checks); markers and prompts are rebuilt when the client receives the change | Turn tiers on. |
| `tiers.default` | tier name | `'fleeca'` | immediately | Tier for plain-coordinate locations and unknown tier names. |
| `tiers.list.<tier>.label` | string | `'Fleeca Bank'` / `'Pacific Standard'` | next open | Tier name shown in the header, in "Available at ..." messages and on the map. |
| `tiers.list.<tier>.features.<feature>` | boolean | see below | immediately | `false` blocks the feature at that tier. If the key is unset, the feature is allowed. Features: `deposit`, `withdraw`, `transfer`, `sharedAccounts`, `manageMembers`, `orderCard`. |
| `tiers.list.<tier>.limits.dailyWithdraw` | integer | `5000` / `50000` | immediately | Daily counter withdrawal cap. `0` means no limit. |
| `tiers.list.<tier>.limits.maxTransfer` | integer | `10000` / `250000` | immediately | Largest single transfer. `0` means no limit. |
| `tiers.list.<tier>.blip` | table | `{ sprite = 108, color = 2 }` / `{ sprite = 106, color = 5 }` | marker rebuild | Optional `sprite`, `color`, `scale` overrides. |

Default presets:

```lua
fleeca = {
    label = 'Fleeca Bank',
    features = { deposit = true, withdraw = true, transfer = true, sharedAccounts = false, manageMembers = false, orderCard = true },
    limits = { dailyWithdraw = 5000, maxTransfer = 10000 },
    blip = { sprite = 108, color = 2 },
},
bigbank = {
    label = 'Pacific Standard',
    features = { deposit = true, withdraw = true, transfer = true, sharedAccounts = true, manageMembers = true, orderCard = true },
    limits = { dailyWithdraw = 50000, maxTransfer = 250000 },
    blip = { sprite = 106, color = 5 },
},
```

You can add your own tiers under `list` and reference them from `locations`. See [Bank tiers](./features/bank-tiers.md).
