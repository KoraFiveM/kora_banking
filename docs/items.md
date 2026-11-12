---
title: Items
sidebar_position: 9
---

# Items

## bank_card

At startup the server registers this item in kora_core's shared items, unless an item named `bank_card` already exists:

```lua
bank_card = {
    label = 'Bank Card',
    weight = 0,
    type = 'item',
    image = 'id_card.png',
    unique = true,
    useable = true,
    shouldClose = true,
    description = 'A personal debit card used to access ATMs.',
}
```

If you define `bank_card` yourself, keep it `unique` and `useable`.

### Metadata

Cards issued at a branch (`Manage → Bank card`) carry this metadata:

| Key | Description |
| --- | --- |
| `citizenid` | Character the card was issued to. PIN checks and card-number transfers use it |
| `name` | Cardholder name |
| `cardNumber` | 16-digit number (string) |
| `cardPin` | 4-digit PIN (number) |

### Use

Using the item (kora_core `createUseable`) triggers `kora_banking:client:useCard` for the player. This starts the ATM flow at the nearest ATM within reach, or shows "Move closer to an ATM." See [ATMs and bank cards](./features/atms.md).

Any `bank_card` passes the "has a card" check. Unlocking requires the PIN of a card issued to the current character.
