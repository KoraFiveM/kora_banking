# qbbanking

## Features
- React banking interface using qblib's shared theme tokens
- Clearly separated personal, society, gang, and shared balances
- Full branch services: cash, transfers, transaction history, shared accounts, and bank cards
- Compact ATM interface with server-side PIN checks and attempt throttling
- Targetable world ATMs with card animation, owner-bound cards, proximity checks, and configurable daily limits
- qblib callbacks, notifications, interactions, and theme integration
- qbcore flat exports for players, money, inventory, commands, jobs, and gangs
- Compatible `AddMoney`, `RemoveMoney`, and account exports for job resources

## Requirements

- `qblib`
- `qbsql`
- `qbcore`
- `qbtarget`
- `qbinventory`

Run `pnpm install` and `pnpm build` from `web/` after changing the interface.

ATMs are available on the models in `Config.atmModels`. Players can order a bank card and choose its PIN at a branch, then target an ATM or use the card while standing beside one. `Config.atmDistance`, `Config.atmAccessTime`, `Config.useDailyLimit`, and `Config.dailyLimit` control the ATM flow.

The resource name is `qbbanking`. It provides the legacy `qb-banking` identity and card-use event so existing job resources can migrate without breaking.

# License

    QBCore Framework
    Copyright (C) 2021 Joshua Eger

    This program is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with this program.  If not, see <https://www.gnu.org/licenses/>
