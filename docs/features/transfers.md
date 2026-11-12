---
title: Transfers
sidebar_position: 4
---

# Transfers

Transfers are only available at a bank branch. ATMs refuse them with "Transfers are available inside a bank."

## Between my accounts

Pick a source and a destination from your accessible accounts (personal, shared, and society/gang if you are a boss). They must be different. The source is debited and the destination credited. If crediting fails, the debit is rolled back. A `withdraw` row is written for the source and a `deposit` row for the destination.

## To another player or account

The **Another player** tab takes a free-text recipient. Leading and trailing spaces are trimmed. A 16-digit number written in groups of four separated by spaces or dashes is joined into one number. The server resolves the recipient in this order:

1. **Online character** whose citizen ID equals the text.
2. **Named account** (shared, society or gang) with that `account_name`, if `Config.Transfers.allowSharedAccounts` is on. The name is looked up in the cache, then in the database.
3. **Character by citizen ID** in the `players` table (not soft-deleted), online or offline.
4. **Bank card number** (12 to 19 digits), if `Config.Transfers.allowCardNumbers` is on. The server searches stored inventories in `players.inventory` for a card with that `cardNumber` and resolves the issuing character (`citizenid` in the card metadata).

Then:

- Sending to your own citizen ID is refused ("Use an internal transfer for your own accounts.").
- An online recipient is credited through kora_core `addMoney` (bank).
- An offline recipient is credited directly in `players.money` (JSON `$.bank`) when `Config.Transfers.allowOffline` is on. Otherwise the transfer is refused with "That account holder must be online."
- Sender and recipient both get a statement row (`withdraw` on the source, `deposit` on the recipient's `checking` or on the named account).

Card numbers are looked up in saved inventories. A card that was just ordered only resolves after the issuing character's inventory has been saved.

## Limits

- `Config.minAmount.transfer` (default 1).
- With tiers enabled, the `transfer` feature gate and the tier's `limits.maxTransfer` apply. If the amount is too large, the error names the first tier (alphabetical by tier key) with a higher limit.
- No per-day transfer total is tracked. Outgoing transfers from the personal account do count toward the ATM daily allowance and the tier counter cap, because they are recorded as `withdraw` statements. See [Bank tiers](../api/tiers.md#daily-counter-cap).
