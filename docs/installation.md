---
title: "Installation"
sidebar_position: 2
---


# Installation

Kora Banking is the bank, ATM and account ledger for the Kora stack: personal (checking), shared, society (job) and gang accounts, bank cards with PINs, optional bank tiers and a durable, idempotent transaction export for other resources. There is nothing to import by hand: the tables are created on boot and the `bank_card` item registers itself.

## Install Kora Banking

1. **Add the folder** — Place `kora_banking` in your resources directory (on the Kora recipe it is `resources/[kora]/kora_banking`). Keep the folder name unchanged: `kora_core` only treats the resource named exactly `kora_banking` as a durable provider for its player column fences, and other resources call `exports.kora_banking`.

2. **Have the dependencies running** — The manifest declares `kora_theme`, `kora_lib`, `kora_sql`, `kora_core`, `kora_target` and `kora_inventory` as dependencies. The UI is drawn by kora_lib's AppShell (`Kora.nui`), the database layer is `Kora.sql`, players, money and items come from kora_core exports, and the ATM and bank prompts are `kora_target` zones and model targets. kora_core also needs a working `players` table (the banking code reads and writes `players.money` and `players.inventory`).

3. **Start it after its dependencies** — Add it after the six dependencies. Resources that call its exports (for example `kora_bossmenu`, which declares `dependency 'kora_banking'`) must start after it.

   ```bash title="server.cfg" {7}
   ensure kora_theme
   ensure kora_lib
   ensure kora_sql
   ensure kora_inventory
   ensure kora_core
   ensure kora_target
   ensure kora_banking
   # resources that call exports.kora_banking (for example kora_bossmenu) start after it
   ensure kora_bossmenu
   ```

4. **Tables are created automatically** — On start, `server/schema.lua` defines `KoraBankingSchema` and both `server.lua` and `server/finance.lua` apply it with `Kora.sql.ensureTables`. It is additive only: it creates missing tables and columns and never alters existing ones. Four tables are used: `bank_accounts`, `bank_statements`, `bank_operations`, `bank_operation_legs`. No SQL file has to be run.

5. **The bank_card item** — If the shared item `bank_card` is not already defined, `server.lua` registers it with `Kora.shared.register('items', 'bank_card', ...)`: label `Bank Card`, weight 0, `unique = true`, `useable = true`, image `id_card.png`. If you define the item yourself beforehand, yours is kept. Using the item (through kora_core `createUseable`) starts the ATM flow on the client when the player holds a card.

6. **Job and gang accounts** — Once the database is ready, the server waits up to 5 seconds for `Kora.shared` jobs to load, then creates a `job` account for every shared job except `unemployed` and a `gang` account for every shared gang except `none`, if one does not exist. A boss who opens a bank counter also triggers creation of their own job or gang account. There is nothing to configure per job.

7. **Review the config** — Open `config.lua`. The defaults give two Fleeca ATMs and eight bank branches, a daily ATM allowance of $5000, bank cards required at ATMs, two shared accounts per character, and bank tiers off. See the Configuration page for every option.

## Manifest reference

How the resource is wired. `provide 'qb-banking'` lets legacy resources keep resolving the old name. `server/schema.lua` loads first so `KoraBankingSchema` exists for `server.lua` and `server/finance.lua`.

```lua title="fxmanifest.lua"
fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'kora_banking'
provide 'qb-banking'

dependency 'kora_theme'
dependency 'kora_lib'
dependency 'kora_sql'
dependency 'kora_core'
dependency 'kora_target'
dependency 'kora_inventory'

shared_scripts {
    '@kora_lib/init.lua',
    '@kora_sql/init.lua',
    '@kora_core/init.lua',
    'config.lua',
    'dates.lua',
    'tiers.lua',
}

client_scripts { 'client.lua' }
server_scripts { 'server/schema.lua', 'server.lua', 'server/finance.lua' }
```

- `locales/*.lua` (en, de, es, it, nl) and the `web/` React project are not referenced by the manifest, and no `ui_page` is declared. The interface is drawn entirely through kora_lib's AppShell. Treat both as unused by the running resource.
- `config.lua`, `dates.lua` and `tiers.lua` are shared scripts, so the `Config`, `BankingDates` and `BankingTiers` globals exist on both client and server.

## Compatibility names and tax

- Every public export is registered on `exports.kora_banking` and also provided as `qb-banking` through `Kora.compat.provideExport('qb-banking', name, handler)` (`bankingExport` in `server.lua`).
- kora_core's optional transaction tax (`Config.money.tax`, off by default) deposits into the account named by `Config.money.tax.account` through the provider `qb-banking`, calling the export names `AddMoney`, `GetAccount` and `CreateJobAccount`. Those exist here with the same names.
- kora_core's `Config.dependencySupervisor.map` (off by default) lists `qb-banking` as a resource to restart when kora_inventory, kora_target or kora_core restart. Whether a restart issued under that name reaches `kora_banking` is not verified in the source I read; if you enable the supervisor, test it.

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

## Further reading

For the table layout see [Database](./database.md); for the `bank_card` item see [Items](./items.md); for every option see [Configuration](./api/configuration.md).
