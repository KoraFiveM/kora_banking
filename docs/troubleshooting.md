---
title: Troubleshooting
sidebar_position: 10
---

# Troubleshooting

| Symptom | Cause / fix |
| --- | --- |
| "Banking is still starting." | The startup thread has not finished. Check the server console for `[kora_banking] database unavailable`, `schema setup failed`, `account load failed`, or `job/gang account creation failed`. Any of these stops startup until the resource restarts. |
| "Move closer to a bank counter." | The server only accepts branch sessions within 3 m of a `Config.locations` entry. Make sure the coordinates match the counter. |
| "Move closer to an ATM." on a wall ATM | Raise `Config.atmTolerance`. For ATMs the target does not detect, add the position to `Config.atmCoords`. |
| No `Use ATM` option | The prop is not in `Config.atmModels`, or `Config.atmAlwaysShowTarget = false` and the player has no card. |
| "You need a bank card to use an ATM." | Order a card at a branch (Manage → Bank card), or set `Config.requireBankCard = false`. |
| "Incorrect PIN." with a card in the inventory | The card was issued to another character. Only cards whose `citizenid` matches the current character unlock. |
| "Too many attempts..." | 5 wrong PINs cause a 30-second lockout for that player. Reopening the ATM does not reset it. |
| A society account is missing from the list | Society/gang accounts are only visible to bosses of the player's current job or gang. |
| A card-number transfer says no account was found | The recipient's inventory has not been saved since the card was ordered, or `Config.Transfers.allowCardNumbers` is off. |
| "That account holder must be online." | `Config.Transfers.allowOffline` is `false`. |
| Durable transactions return `unavailable` | Durable startup has not completed. Check the console for `durable banking schema setup failed` and consider `Config.migrationRetrySeconds`. |
| A balance changed in SQL is not shown | Account rows are cached. Trigger `kora_banking:refreshAccount` with the account name (server). See [Events](./events.md). |
| Tier markers do not change after editing `blip` or `locations` | Restart `kora_banking`. Only `tiers.enabled` / `tiers.default` changes rebuild markers live. |
