-- Server-authoritative minimum withdraw/deposit/transfer amounts (Config.minAmount).
local root = debug.getinfo(1, 'S').source:sub(2):match('(.*/)') .. '../'
local callbacks, threads, noop = {}, {}, function() end
local vec = {}
vec.__index = vec
vec.__sub = function(a, b) return setmetatable({ d = math.abs((a.x or 0) - (b.x or 0)) }, vec) end
vec.__len = function(a) return a.d or 0 end
local here = setmetatable({ x = 0 }, vec)
local player = { citizenid = 'ABC123', money = { cash = 100, bank = 1000 }, charinfo = {} }
local other = { citizenid = 'XYZ789', money = { cash = 0, bank = 0 } }
local function purse(src) return src == 1 and player or other end
local passed = 0
local function check(value, message) assert(value, message); passed = passed + 1 end

local env = setmetatable({
    Config = { locations = { here }, dailyLimit = 100000, useDailyLimit = false, atmDistance = 2 },
    QB = {
        shared = { get = function() return {} end, epoch = function() return 1 end, all = function() return {} end },
        util = { isFiniteNumber = function(n) return type(n) == 'number' and n == n and math.abs(n) < math.huge end,
            cleanText = function(s) return s end },
        callback = { register = function(name, fn) callbacks[name] = fn end },
        sql = { ready = function() return true end, query = function() return {} end, single = function() return nil end,
            insert = function() return 1 end, update = function() return 1 end, scalar = function() return 0 end },
    },
    exports = setmetatable({ kora_core = {
        createUseable = noop, addCommand = noop,
        getPlayerData = function(_, src, cols)
            if cols then return purse(src).citizenid end
            return purse(src)
        end,
        getPlayerByCitizenId = function(_, cid) if cid == 'XYZ789' then return { source = 2 } end end,
        removeMoney = function(_, src, kind, amount) local p = purse(src); if p.money[kind] < amount then return false end p.money[kind] = p.money[kind] - amount return true end,
        addMoney = function(_, src, kind, amount) local p = purse(src); p.money[kind] = p.money[kind] + amount return true end,
        getItemsByName = function() return {} end, getItemByName = function() return nil end,
    } }, { __call = noop }),
    RegisterNetEvent = noop, AddEventHandler = noop, SetTimeout = noop, GetGameTimer = function() return 0 end,
    GetPlayerPed = function() return 1 end, GetEntityCoords = function() return here end,
    GetPlayerName = function() return 'Tester' end,
    CreateThread = function(fn) threads[#threads + 1] = fn end,
    vector3 = function(x) return setmetatable({ x = x }, vec) end,
}, { __index = _G })
-- exports.kora_core:fn(...) passes the table as first argument; mimic with colon-call semantics
for _, fn in pairs(env.exports.kora_core) do assert(type(fn) == 'function') end
env.QB.compat = { provideExport = noop }
assert(loadfile(root .. 'server.lua', 't', env))()
for _, thread in ipairs(threads) do thread() end

local function act(payload)
    assert(callbacks['qbbanking:open'](1, 'bank', 1), 'branch must open')
    local result, err = callbacks['qbbanking:action'](1, payload)
    return result, err
end
local function reset() player.money.cash, player.money.bank, other.money.bank = 100, 1000, 0 end

local kinds = {
    withdraw = { payload = function(a) return { kind = 'withdraw', account = 'checking', amount = a } end, word = 'withdrawal' },
    deposit = { payload = function(a) return { kind = 'deposit', account = 'checking', amount = a } end, word = 'deposit' },
    transfer = { payload = function(a) return { kind = 'transfer', from = 'checking', recipient = 'XYZ789', amount = a } end, word = 'transfer' },
}

-- Defaults (minAmount = 1 or absent) behave as before: $1 works, $0 is the generic invalid-amount error.
for name, kind in pairs(kinds) do
    for _, config in ipairs({ { withdraw = 1, deposit = 1, transfer = 1 }, false }) do
        env.Config.minAmount = config or nil
        reset()
        local result = act(kind.payload(1))
        check(result and result.message, name .. ' of $1 must work with default minimum')
        local failed, err = act(kind.payload(0))
        check(failed == nil and err == 'Enter a valid amount.', name .. ' of $0 keeps the generic invalid-amount message')
    end
end

-- Minimum 5: below rejected with message and no funds moved, at and above accepted.
env.Config.minAmount = { withdraw = 5, deposit = 5, transfer = 5 }
for name, kind in pairs(kinds) do
    reset()
    local cash, bank = player.money.cash, player.money.bank
    for _, amount in ipairs({ 1, 4, 4.9 }) do
        local failed, err = act(kind.payload(amount))
        check(failed == nil and err == ('Minimum %s is $5.'):format(kind.word), name .. ' of $' .. amount .. ' must be rejected: ' .. tostring(err))
    end
    check(player.money.cash == cash and player.money.bank == bank and other.money.bank == 0, name .. ' rejection must not move funds')
    for _, amount in ipairs({ 5, 6 }) do
        local result, err = act(kind.payload(amount))
        check(result and result.message, name .. ' of $' .. amount .. ' must be accepted: ' .. tostring(err))
    end
end

-- Each kind reads its own key, live.
env.Config.minAmount = { withdraw = 5, deposit = 1, transfer = 1 }
reset()
check(act(kinds.deposit.payload(1)), 'deposit unaffected by the withdrawal minimum')
check(act(kinds.transfer.payload(1)), 'transfer unaffected by the withdrawal minimum')
check(select(2, act(kinds.withdraw.payload(4))) == 'Minimum withdrawal is $5.', 'withdrawal minimum still applies')
env.Config.minAmount.withdraw = 10
check(select(2, act(kinds.withdraw.payload(9))) == 'Minimum withdrawal is $10.', 'minimum is read at use time')

-- Internal transfers are covered too, and the snapshot exposes the minimums to the client.
env.Config.minAmount = { withdraw = 5, deposit = 6, transfer = 7 }
check(select(2, act({ kind = 'transfer', from = 'checking', to = 'club', amount = 3 })) == 'Minimum transfer is $7.', 'internal transfer minimum')
local snap = callbacks['qbbanking:open'](1, 'bank', 1)
check(snap.limits.min.withdraw == 5 and snap.limits.min.deposit == 6 and snap.limits.min.transfer == 7, 'snapshot carries the minimums')
env.Config.minAmount = { withdraw = 'junk', deposit = -3, transfer = 0 }
snap = callbacks['qbbanking:open'](1, 'bank', 1)
check(snap.limits.min.withdraw == 1 and snap.limits.min.deposit == 1 and snap.limits.min.transfer == 1, 'invalid minimums fall back to 1')
print(('qbbanking minimum amounts: %d assertions passed'):format(passed))
