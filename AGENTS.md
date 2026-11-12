# kora_banking agent guide

kora_banking is the Kora FiveM banking resource: personal, shared, society and gang accounts, bank branches and ATMs rendered through the kora_lib AppShell, plus legacy `qb-banking` exports and a durable transaction API. Layout: `config.lua` (shared Config and kora_lib config registration), `tiers.lua` and `dates.lua` (shared helpers), `client.lua` (app, targets, blips, ATM flow), `server.lua` (sessions, accounts, transfers, exports, command), `server/finance.lua` (durable transactions), `server/schema.lua` (database schema), `test/` (Lua tests, run with `test/run.sh`), `tests/` (kora_qa scenarios).

## Documentation

User-facing documentation lives in `docs/` (Markdown, published via the Kora Docusaurus site, kora_docs_next). Read `docs/index.md` first; it has the documentation map. Layout: `index.md` (overview and map), `installation.md` (setup, manifest, requirements), `how-to-use.md` (player walkthrough, architecture, money validation), `commands.md` (`/givecash`), `api/` (`exports.md` public exports, `configuration.md` every `Config` option, `tiers.md` bank tiers and `BankingTiers` helpers, `security.md` protections and limits), `features/` (branches, accounts, ATMs, transfers, durable transactions), and topic pages `events.md`, `database.md`, `items.md`, `compatibility.md`, `troubleshooting.md`. Change the page that owns the topic: exports and their errors in `api/exports.md`, options and defaults in `api/configuration.md`.

When you add, change, or remove a feature, config option, command, export, event, item, permission, or database table/column, update the matching page in `docs/` in the same change. Keep docs accurate to the code; do not document behaviour that does not exist.

Docs rules: plain Markdown with `title`/`sidebar_position` front matter (no `id`/`slug`), relative links only between docs pages, assets inside `docs/`, fenced code blocks with a language, and no raw `<`, `>`, `{`, `}` outside code (pages are parsed as MDX). The release version comes from `fxmanifest.lua`'s `version` field.

## Shared contribution standards

Read [CONTRIBUTING.md](CONTRIBUTING.md) before editing. Humans and agents follow
the same Kora standards and self-contained local Lua checks. Preserve the domain
constraints above and in module guides; record policy conflicts explicitly.
