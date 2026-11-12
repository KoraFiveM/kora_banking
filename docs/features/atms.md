---
title: ATMs and bank cards
sidebar_position: 3
---

# ATMs and bank cards

ATMs give quick access to the **personal account only**. They support cash withdrawal and deposit. Transfers, shared accounts and account management are only available at a branch. ATMs have no [tier](../api/tiers.md).

## Finding an ATM

- **Model target**: `Use ATM` on every prop in `Config.atmModels` (interaction distance `Config.atmDistance`).
- **Fallback zones**: a `Use ATM` sphere of `Config.atmZoneRadius` at each `Config.atmCoords` entry, for ATMs that are part of the map. A zone hides its option while the aimed entity is already an `atmModels` prop, so one machine never shows two options.
- **Using the card**: using the `bank_card` item from the inventory starts the same flow at the nearest ATM in reach.

Reach is `Config.atmDistance + Config.atmTolerance` from the ATM's position, on both client and server.

With `Config.atmAlwaysShowTarget = false` (and cards required), the option only appears for players the server last reported as holding a card. The client refreshes this answer at most every 5 seconds while aiming.

## Access flow

1. With `Config.atmCloseInVehicle` (default), the ATM is refused if the player is in a vehicle (`Config.atmVehicleMessage`).
2. The client asks the server (`atmCard`) whether the player holds a bank card and is near the ATM. If not, only a notification is shown, with no animation.
3. A cancellable "Accessing ATM..." progress bar runs for `Config.atmAccessTime` ms with a card prop and animation. Movement is handled per `Config.atmAccessMovement`.
4. The client sends `open` with the ATM position. The server re-checks the card and distance.
5. With `Config.requireBankCard = true`, the app opens in the compact layout on a PIN keypad. With `false`, it opens unlocked.

## PIN check

- The PIN must match `cardPin` of a `bank_card` item in the player's inventory whose `citizenid` is the current character. Holding someone else's card is enough to pass the card check, but not to unlock with their PIN.
- After 5 wrong PINs the player is locked out for 30 seconds. Attempts and the lockout are tracked per player, not per ATM session, so closing and reopening the ATM does not reset them. They clear on a correct PIN or when the player disconnects.

## Session

- The ATM session expires after 5 minutes of inactivity. Every action re-checks that the player is still within reach of the ATM.
- The client closes the ATM when the player moves further than `Config.atmCloseDistance` metres (default 3, `0` disables) or enters a vehicle (with `Config.atmCloseInVehicle`).

## Daily allowance

With `Config.useDailyLimit` (default `true`), ATM withdrawals are capped at `Config.dailyLimit` (default $5,000) per character per day. The day resets at midnight on the database clock (`CURRENT_DATE()`).

The used amount is the sum of `withdraw` rows in `bank_statements` for the character on account `checking` since midnight. That includes bank-counter withdrawals, and also outgoing transfers and shared-account opening balances from the personal account, because those write `withdraw` rows on `checking` too. Transactions made through the durable ledger (`bank_operation_legs`) are not counted.

The ATM shows the remaining allowance. The withdraw button is disabled when the balance or remaining allowance is below the minimum withdrawal.

## Bank cards

See [Items](../items.md) for the item definition and [Bank branches](./bank-branches.md#ordering-a-bank-card) for ordering.
