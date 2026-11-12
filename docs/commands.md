---
title: "Commands"
sidebar_position: 4
---


# Commands

Kora Banking adds one chat command, registered through kora_core's command system.

## Built-in commands

### `/givecash <id> <amount>`

Moves cash from your character to the player with that server ID. The target must be within 5.0 metres. Cash is removed from the sender first and added to the target; if adding fails, the sender is refunded (`cash transfer rollback`).

| Field | Details |
| --- | --- |
| Context | In-game · server command (kora_core) |
| Arguments | id — required, the target's server ID (number). amount — required, whole amount between 1 and 1,000,000,000 (decimals are floored). |
| Access | Registered with `argsRequired = true` and no permission argument, which kora_core defaults to `user`: every player can use it. This command never touches `bank_accounts` or `bank_statements`. |

**Example**

```text
/givecash 12 250
```

**Result**

Sender sees `Gave $250.` and the target `Received $250.` as Banking notifications. Errors shown: `Enter a valid player and amount.`, `Player not found.`, `That player is too far away.`, `You do not have enough cash.`, `The transfer failed.`

## No banking admin commands

The resource registers no admin command for editing balances. Use the exports from another resource or edit the database yourself; if you edit `bank_accounts` directly, restart `kora_banking` or trigger `kora_banking:refreshAccount` so the in-memory cache is reloaded.

## Additional details (from the code)

- Banking itself is opened through kora_target interactions (branch zones and ATMs) and the `bank_card` item, not through commands. There are no key mappings.
- See [Items](./items.md) for the card and [Bank branches](./features/bank-branches.md) for the counters.
