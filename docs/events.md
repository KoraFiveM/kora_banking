---
title: Events
sidebar_position: 7
---

# Events

## Public events

| Event | Side | Type | Payload | Description |
| --- | --- | --- | --- | --- |
| `kora_banking:client:useCard` | client | net event | none | Starts the ATM access flow at the nearest ATM in reach. Triggered by the server when a player uses a `bank_card` they hold. |
| `qb-banking:client:useCard` | client | net event | none | Legacy alias of `kora_banking:client:useCard`. |
| `kora_banking:refreshAccount` | server | local event | `accountName` (string) | Reloads one row from `bank_accounts` into the in-memory cache (or removes it if the row is gone). Trigger it with `TriggerEvent` after changing `bank_accounts` directly in SQL. |
| `kora_banking:durableReady` | server | local event | none | Fired once durable transactions are ready after startup recovery. Listen with `AddEventHandler`. |

```lua
-- server: after a direct SQL change to a society balance
TriggerEvent('kora_banking:refreshAccount', 'mechanic')
```

## Internal events and callbacks

These events and callbacks carry the banking UI's traffic. Every request is validated server-side (session, proximity, card, PIN, access, amounts). Do not trigger them from other resources.

| Name | Side | Description |
| --- | --- | --- |
| `kora_banking:server:request` | server net event | Request channel: `requestId, operation, ...` where `operation` is `open`, `atmCard`, `pin` or `action`. |
| `kora_banking:client:response` | client net event | Reply to a request: `requestId, result, error`. |
| `kora_banking:close` | server net event | Ends the caller's banking session. |
| `kora_banking:open`, `kora_banking:pin`, `kora_banking:action` | kora_lib callbacks (server) | The same handlers registered with `Kora.callback`. They are re-registered when kora_lib restarts. |

## Events consumed

| Event | Side | Purpose |
| --- | --- | --- |
| `onResourceStart` (`kora_lib`) | server | Re-register the callbacks. |
| `onClientResourceStart` / `onClientResourceStop` (`kora_target`) | client | Re-register ATM and branch targets after a kora_target restart. |
| `playerDropped` | server | Clear the banking session and PIN attempt state. |
