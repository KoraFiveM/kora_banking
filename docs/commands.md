---
title: Commands
sidebar_position: 4
---

# Commands

kora_banking registers one chat command through kora_core's `addCommand`. It has no key mappings.

## /givecash

```text
/givecash [id] [amount]
```

| Argument | Description |
| --- | --- |
| `id` | Server ID of the receiving player |
| `amount` | Amount of cash. Rounded down, must be 1 to 1,000,000,000 |

- **Permission**: `user` (every player). Both arguments are required.
- **Effect**: moves cash from your cash balance to the target player's cash. The target must be within 5 metres. If crediting the target fails, the money is returned. Both players get a notification ("Gave $X." / "Received $X.").
- **Errors**: invalid player/amount, player not found, too far away, not enough cash.

No bank statement is written, because this is a cash-to-cash handover.

Banking itself is opened through kora_target interactions (branch zones and ATMs) and the `bank_card` item, not through commands.
