---
title: "Configuration"
sidebar_position: 3
---


# Configuration

`config.lua` is a shared script, so `Config` exists on client and server. When kora_lib's `Kora.config.adopt` is available the file registers the typed values with kora_lib (labels, limits, advanced flags) and wraps `Config` with `Kora.config.adopt`. The client script runs before kora_lib delivers the server's config snapshot, and rebuilds blips and zones when `tiers.enabled` or `tiers.default` change.

Namespace: `Config` · Source: `config.lua`

## All options

Every key of `Config` in `config.lua`. Anything under `tiers.list` is open-ended: you may add your own tier names.

| Key | Type | Default | Controls | Applies |
| --- | --- | --- | --- | --- |
| transactionCallers | table&lt;string, true> | &#123; kora_housing = true &#125; | Resources allowed to call `ExecuteTransaction` and `GetOperation`. Read at call time. |  |
| ui.accent | string \| nil | nil | Accent colour passed to the AppShell definition when it is a string. | Not registered with kora_lib's config editor. |
| atmModels | string[] | prop_atm_01, prop_atm_02, prop_atm_03, prop_fleeca_atm, gabz_sm_pb_atmframe, v_5_b_atm1, v_5_b_atm2 | Model names targeted as ATMs and searched for nearby (client). | Restart. |
| atmCoords | vector3[] | two Fleeca ATMs at Legion Square | Fallback `Use ATM` sphere zones for map-baked ATMs. | Restart. |
| atmZoneRadius | number | 1.2 | Radius of each fallback zone (0.3 to 5.0). | Restart. |
| atmDistance | number | 1.8 | Interaction distance for ATMs. The server allows `atmTolerance` extra. | Restart. |
| atmTolerance | number | 1.0 | Extra metres added to atmDistance for the client lookup and the server proximity check. | Restart. |
| atmCloseDistance | number | 3.0 | An open ATM closes when the player is further than this from the machine (0 = never). Client-side only; the server also drops the session when out of range. | Not in the kora_lib config list. |
| atmCloseInVehicle | boolean | true | Blocks ATM use from a vehicle and closes an open ATM when entering one. | Not in the kora_lib config list. |
| atmVehicleMessage | string | You cannot use an ATM from a vehicle. | Notification for the vehicle block. |  |
| atmAccessTime | integer (ms) | 1500 | Duration of the cancellable access progress bar. | Restart. |
| atmAccessMovement | 'controls' \| 'freeze' | 'controls' | `controls` ignores movement keys during the bar; `freeze` freezes the ped. | Immediately. |
| requireBankCard | boolean | true | ATMs need a bank card in the inventory and its PIN. When false the ATM opens unlocked. | Immediately. |
| atmAlwaysShowTarget | boolean | true | Show `Use ATM` for everyone. When false, shown only to players the server reports as holding a card (checked every 5 seconds while aiming). | Immediately. |
| atmNoCardMessage | string | You need a bank card to use an ATM. | Message when a card is required but missing. | Immediately. |
| dateFormat | 'locale' \| 'DD/MM/YYYY' \| 'MM/DD/YYYY' \| 'YYYY-MM-DD' | 'locale' | Activity date order. | Next time Activity opens. |
| showTime | boolean | true | Append hour and minute to Activity dates. | Next time Activity opens. |
| dateTimezone | 'player' \| 'server' | 'player' | Time zone for Activity dates. `local` and `utc` are older aliases for `player` and `server`. | Next time Activity opens. |
| useDailyLimit | boolean | true | Enforce the daily ATM withdrawal allowance. | Restart. |
| dailyLimit | integer | 5000 | Daily ATM allowance per character for the `checking` account (from midnight on the database clock). | Restart. |
| minAmount.withdraw / deposit / transfer | integer (min 1) | 1 / 1 / 1 | Minimum amount per action, enforced on the server and shown in the form. | Immediately. |
| Transfers.allowOffline | boolean | true | Credit offline characters directly in `players.money`. False requires the recipient to be online. | Immediately. |
| Transfers.allowSharedAccounts | boolean | true | Allow shared, society and gang account names as recipients. | Immediately. |
| Transfers.allowCardNumbers | boolean | true | Allow a bank card number as recipient. | Immediately. |
| migrationRetrySeconds | integer (0 to 3600) | 0 | Retry the durable schema setup after this many seconds when it fails. 0 = log once and stay disabled until restart. | Next failure. |
| maxAccounts | integer | 2 | Shared accounts a character may own via the UI (job and gang accounts do not count). | Restart. |
| maxSharedMembers | integer | 10 | Additional members per shared account. Lowering it truncates loaded lists. | Restart. |
| maxSharedMemberBytes | integer | 512 | Maximum JSON size of a member list. Oversized stored lists read as empty. | Restart. |
| memberRateLimit.max | integer | 5 | Member requests per window per player. | Restart. |
| memberRateLimit.window | integer (ms, min 1) | 10000 | Rolling window of the member rate limiter. | Restart. |
| blipInfo.category | string | 'Bank' | kora_lib map legend category. | Restart. |
| blipInfo.sprite / color / scale / shortRange | integer / integer / number / boolean | 108 / 2 / 0.55 / true | Default bank blip (tier blips override sprite, color, scale). | Restart. |
| locations | table[] | 8 branches | Each entry is plain coordinates or `{ coords, tier, label }`. | Restart. |
| tiers.enabled | boolean | false | Turn bank tiers on. | Server checks immediately; restart for blips. |
| tiers.default | string | 'fleeca' | Tier for plain-coordinate or unknown-tier locations. | Immediately. |
| tiers.list.&lt;name>.label | string | 'Fleeca Bank' / 'Pacific Standard' | Display name of the tier. | Next time the bank opens. |
| tiers.list.&lt;name>.features.&lt;feature> | boolean | see Bank tiers | Set false to block `deposit`, `withdraw`, `transfer`, `sharedAccounts`, `manageMembers` or `orderCard`. Unset means allowed. | Immediately. |
| tiers.list.&lt;name>.limits.dailyWithdraw / maxTransfer | integer (0 = none) | 5000 / 10000 (fleeca), 50000 / 250000 (bigbank) | Counter daily withdrawal cap and largest single transfer. | Immediately. |
| tiers.list.&lt;name>.blip | table | &#123; sprite = 108, color = 2 &#125; / &#123; sprite = 106, color = 5 &#125; | Per-tier blip overrides (sprite, color, scale). | Restart. |

## How it works

Values flagged Restart are read once at start or captured into zones and the member rate limiter. Values flagged Immediately are read at use time, on the server for security checks. The registered ranges (for example `minAmount` at least 1, `memberRateLimit.window` at least 1, `migrationRetrySeconds` 0 to 3600) come from the `config.*` registrations at the bottom of `config.lua`. How kora_lib stores or overrides saved values is not documented here.

## Options

Pass an options table as the final argument to a play function. Omit the table or any field to use its default.

| Option | Type | Description |
| --- | --- | --- |
| `transactionCallers` | table&lt;string, true> | Default &#123; kora_housing = true &#125;. Resources allowed to call `ExecuteTransaction` and `GetOperation`. Read at call time. |
| `ui.accent` | string \| nil | Default nil. Accent colour passed to the AppShell definition when it is a string. Applies: Not registered with kora_lib's config editor. |
| `atmModels` | string[] | Default prop_atm_01, prop_atm_02, prop_atm_03, prop_fleeca_atm, gabz_sm_pb_atmframe, v_5_b_atm1, v_5_b_atm2. Model names targeted as ATMs and searched for nearby (client). Applies: Restart. |
| `atmCoords` | vector3[] | Default two Fleeca ATMs at Legion Square. Fallback `Use ATM` sphere zones for map-baked ATMs. Applies: Restart. |
| `atmZoneRadius` | number | Default 1.2. Radius of each fallback zone (0.3 to 5.0). Applies: Restart. |
| `atmDistance` | number | Default 1.8. Interaction distance for ATMs. The server allows `atmTolerance` extra. Applies: Restart. |
| `atmTolerance` | number | Default 1.0. Extra metres added to atmDistance for the client lookup and the server proximity check. Applies: Restart. |
| `atmCloseDistance` | number | Default 3.0. An open ATM closes when the player is further than this from the machine (0 = never). Client-side only; the server also drops the session when out of range. Applies: Not in the kora_lib config list. |
| `atmCloseInVehicle` | boolean | Default true. Blocks ATM use from a vehicle and closes an open ATM when entering one. Applies: Not in the kora_lib config list. |
| `atmVehicleMessage` | string | Default You cannot use an ATM from a vehicle.. Notification for the vehicle block. |
| `atmAccessTime` | integer (ms) | Default 1500. Duration of the cancellable access progress bar. Applies: Restart. |
| `atmAccessMovement` | 'controls' \| 'freeze' | Default 'controls'. `controls` ignores movement keys during the bar; `freeze` freezes the ped. Applies: Immediately. |
| `requireBankCard` | boolean | Default true. ATMs need a bank card in the inventory and its PIN. When false the ATM opens unlocked. Applies: Immediately. |
| `atmAlwaysShowTarget` | boolean | Default true. Show `Use ATM` for everyone. When false, shown only to players the server reports as holding a card (checked every 5 seconds while aiming). Applies: Immediately. |
| `atmNoCardMessage` | string | Default You need a bank card to use an ATM.. Message when a card is required but missing. Applies: Immediately. |
| `dateFormat` | 'locale' \| 'DD/MM/YYYY' \| 'MM/DD/YYYY' \| 'YYYY-MM-DD' | Default 'locale'. Activity date order. Applies: Next time Activity opens. |
| `showTime` | boolean | Default true. Append hour and minute to Activity dates. Applies: Next time Activity opens. |
| `dateTimezone` | 'player' \| 'server' | Default 'player'. Time zone for Activity dates. `local` and `utc` are older aliases for `player` and `server`. Applies: Next time Activity opens. |
| `useDailyLimit` | boolean | Default true. Enforce the daily ATM withdrawal allowance. Applies: Restart. |
| `dailyLimit` | integer | Default 5000. Daily ATM allowance per character for the `checking` account (from midnight on the database clock). Applies: Restart. |
| `minAmount.withdraw / deposit / transfer` | integer (min 1) | Default 1 / 1 / 1. Minimum amount per action, enforced on the server and shown in the form. Applies: Immediately. |
| `Transfers.allowOffline` | boolean | Default true. Credit offline characters directly in `players.money`. False requires the recipient to be online. Applies: Immediately. |
| `Transfers.allowSharedAccounts` | boolean | Default true. Allow shared, society and gang account names as recipients. Applies: Immediately. |
| `Transfers.allowCardNumbers` | boolean | Default true. Allow a bank card number as recipient. Applies: Immediately. |
| `migrationRetrySeconds` | integer (0 to 3600) | Default 0. Retry the durable schema setup after this many seconds when it fails. 0 = log once and stay disabled until restart. Applies: Next failure. |
| `maxAccounts` | integer | Default 2. Shared accounts a character may own via the UI (job and gang accounts do not count). Applies: Restart. |
| `maxSharedMembers` | integer | Default 10. Additional members per shared account. Lowering it truncates loaded lists. Applies: Restart. |
| `maxSharedMemberBytes` | integer | Default 512. Maximum JSON size of a member list. Oversized stored lists read as empty. Applies: Restart. |
| `memberRateLimit.max` | integer | Default 5. Member requests per window per player. Applies: Restart. |
| `memberRateLimit.window` | integer (ms, min 1) | Default 10000. Rolling window of the member rate limiter. Applies: Restart. |
| `blipInfo.category` | string | Default 'Bank'. kora_lib map legend category. Applies: Restart. |
| `blipInfo.sprite / color / scale / shortRange` | integer / integer / number / boolean | Default 108 / 2 / 0.55 / true. Default bank blip (tier blips override sprite, color, scale). Applies: Restart. |
| `locations` | table[] | Default 8 branches. Each entry is plain coordinates or `{ coords, tier, label }`. Applies: Restart. |
| `tiers.enabled` | boolean | Default false. Turn bank tiers on. Applies: Server checks immediately; restart for blips. |
| `tiers.default` | string | Default 'fleeca'. Tier for plain-coordinate or unknown-tier locations. Applies: Immediately. |
| `tiers.list.<name>.label` | string | Default 'Fleeca Bank' / 'Pacific Standard'. Display name of the tier. Applies: Next time the bank opens. |
| `tiers.list.<name>.features.<feature>` | boolean | Default see Bank tiers. Set false to block `deposit`, `withdraw`, `transfer`, `sharedAccounts`, `manageMembers` or `orderCard`. Unset means allowed. Applies: Immediately. |
| `tiers.list.<name>.limits.dailyWithdraw / maxTransfer` | integer (0 = none) | Default 5000 / 10000 (fleeca), 50000 / 250000 (bigbank). Counter daily withdrawal cap and largest single transfer. Applies: Immediately. |
| `tiers.list.<name>.blip` | table | Default &#123; sprite = 108, color = 2 &#125; / &#123; sprite = 106, color = 5 &#125;. Per-tier blip overrides (sprite, color, scale). Applies: Restart. |

## Safe defaults

The shipped defaults keep tiers off, require bank cards, enable a $5000 daily ATM allowance and allow offline, shared-account and card-number transfers.

## Not registered with the config editor

`transactionCallers`, `ui.accent`, `atmCloseDistance`, `atmCloseInVehicle` and `atmVehicleMessage` are read straight from `Config`; edit `config.lua` for those that have no registration.

## Limits and related APIs

Lowering `maxSharedMembers` truncates member lists when they are read, which can remove access without any message. `Config.locations` indexes are sent by the client as plain numbers, so reordering the list while players have a bank open can make that index point at a different branch.

## Related guides

- [Bank tiers](./tiers.md)
- [Security and integrity](./security.md)

## Additional details (from the code)

These notes complement the option table above.

### Date format and time zone

- `dateFormat = 'locale'` follows the client `locale` convar: English US/CA/PH (or plain `en`) use `MM/DD/YYYY` with a 12-hour clock, `ja`/`zh`/`ko`/`hu`/`sv`/`lt` use `YYYY-MM-DD`, and all others use `DD/MM/YYYY`.
- `dateTimezone = 'player'` shows dates in the player machine's time zone, `'server'` shows UTC to everyone.

All amounts are rounded down to whole dollars and must be between 1 and 1,000,000,000.

### Locations

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


### Default tier presets

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

You can add your own tiers under `list` and reference them from `locations`. See [Bank tiers](./tiers.md).
