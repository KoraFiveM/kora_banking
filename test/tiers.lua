-- Bank tiers (Config.tiers): location normalising, nearest-branch resolution, legacy coords, server-side gating.
local root = debug.getinfo(1, 'S').source:sub(2):match('(.*/)') .. '../'
dofile(root .. 'dates.lua')
local callbacks, threads, noop = {}, {}, function() end
local passed = 0
local function check(value, message) assert(value, message); passed = passed + 1 end

local FLEECA, BIG, LEGACY = { x = 100, y = 100, z = 30 }, { x = 500, y = 500, z = 30 }, { x = 900, y = 900, z = 30 }
local pos = { x = FLEECA.x, y = FLEECA.y, z = FLEECA.z }
local player = { citizenid = 'ABC123', money = { cash = 100000, bank = 1000000 }, charinfo = {} }
local other = { citizenid = 'XYZ789', money = { cash = 0, bank = 0 } }
local used = 0
local onScalar

local function presets()
    return {
        enabled = true, default = 'fleeca',
        list = {
            fleeca = { label = 'Fleeca Bank',
                features = { deposit = true, withdraw = true, transfer = true, sharedAccounts = false, manageMembers = false, orderCard = true },
                limits = { dailyWithdraw = 5000, maxTransfer = 10000 }, blip = { sprite = 108, color = 2 } },
            bigbank = { label = 'Pacific Standard',
                features = { sharedAccounts = true, manageMembers = true },
                limits = { dailyWithdraw = 50000, maxTransfer = 0 }, blip = { sprite = 106, color = 5 } },
        },
    }
end

local env = setmetatable({
    Config = {
        dailyLimit = 100000, useDailyLimit = false, atmDistance = 2, maxAccounts = 2, maxSharedMembers = 10,
        maxSharedMemberBytes = 512, memberRateLimit = { max = 50, window = 10000 },
        locations = {
            { coords = FLEECA, tier = 'fleeca', label = 'Fleeca Bank - Test' },
            { coords = BIG, tier = 'bigbank', label = 'Pacific Standard' },
            LEGACY,
            { coords = { x = 1300, y = 1300, z = 30 }, tier = 'does_not_exist' },
        },
        tiers = presets(),
    },
    Kora = {
        shared = { get = function() return {} end, epoch = function() return 1 end, all = function() return {} end },
        util = { isFiniteNumber = function(n) return type(n) == 'number' and n == n and math.abs(n) < math.huge end,
            cleanText = function(s) return s end },
        callback = { register = function(name, fn) callbacks[name] = fn end },
        sql = { ready = function() return true end, query = function() return {} end, single = function() return nil end,
            insert = function() return 1 end, update = function() return 1 end,
            scalar = function(sql, params) if onScalar then onScalar(sql, params) end return used end },
    },
    exports = setmetatable({ kora_core = {
        createUseable = noop, addCommand = noop,
        getPlayerData = function(_, src, cols) if cols then return player.citizenid end return player end,
        getPlayerByCitizenId = function(_, cid) if cid == 'XYZ789' then return { source = 2 } end end,
        removeMoney = function(_, _, kind, amount) if player.money[kind] < amount then return false end player.money[kind] = player.money[kind] - amount return true end,
        addMoney = function(_, src, kind, amount) local p = src == 1 and player or other; p.money[kind] = p.money[kind] + amount return true end,
        getItemsByName = function() return {} end, getItemByName = function() return nil end,
    } }, { __call = noop }),
    RegisterNetEvent = noop, AddEventHandler = noop, SetTimeout = noop, GetGameTimer = function() return 0 end,
    GetPlayerPed = function() return 1 end, GetEntityCoords = function() return pos end,
    GetPlayerName = function() return 'Tester' end,
    json = { encode = function() return '[]' end, decode = function() return {} end },
    CreateThread = function(fn) threads[#threads + 1] = fn end,
}, { __index = _G })
assert(loadfile(root .. 'tiers.lua', 't', env))()
env.Kora.compat = { provideExport = noop }
assert(loadfile(root .. 'server.lua', 't', env))()
for _, thread in ipairs(threads) do thread() end
local Tiers, Config = env.BankingTiers, env.Config

local function at(where) pos.x, pos.y, pos.z = where.x, where.y, where.z end
local function act(payload, index)
    local snapshot, err = callbacks['qbbanking:open'](1, 'bank', index or 1)
    assert(snapshot, 'branch must open: ' .. tostring(err))
    return callbacks['qbbanking:action'](1, payload)
end
local function reset() player.money.cash, player.money.bank, other.money.bank, used = 100000, 1000000, 0, 0 end

-- Resolution: the tier comes from the location, plain coords use the default tier, unknown names fall back to it.
local info = Tiers.info(1)
check(info.tier == 'fleeca' and info.tierLabel == 'Fleeca Bank' and info.label == 'Fleeca Bank - Test', 'tagged fleeca location')
check(Tiers.info(2).tier == 'bigbank' and Tiers.info(2).tierLabel == 'Pacific Standard', 'tagged bigbank location')
check(Tiers.info(3).tier == 'fleeca' and Tiers.info(3).label == 'Fleeca Bank' and Tiers.info(3).coords == LEGACY, 'legacy plain coords use the default tier')
check(Tiers.info(4).tier == 'fleeca', 'unknown tier names use the default tier')
Config.tiers.default = 'bigbank'
check(Tiers.info(3).tier == 'bigbank', 'Config.tiers.default is honoured for plain coords')
Config.tiers.default = 'nope'
check(Tiers.info(3).tier == 'fleeca', 'an invalid default falls back to fleeca')
Config.tiers.default = 'fleeca'
check(Tiers.info(9) == nil, 'missing locations resolve to nil')
check(Tiers.resolve({ x = 101, y = 100, z = 30 }, 3).index == 1, 'nearest location within range resolves')
check(Tiers.resolve({ x = 300, y = 300, z = 30 }, 3) == nil, 'nothing resolves out of range')
Config.locations[5] = { coords = { x = 102, y = 100, z = 30 }, tier = 'bigbank' }
check(Tiers.resolve({ x = 101.8, y = 100, z = 30 }, 3).index == 5, 'the nearest of two overlapping branches wins')
Config.locations[5] = nil
check(Tiers.entry({ coords = BIG }).tier == nil and Tiers.entry(BIG).coords == BIG, 'entry accepts both shapes')

-- Disabled (the default): nothing is gated, limits are absent, the snapshot carries no branch.
Config.tiers.enabled = false
check(Tiers.info(1).enabled == false and Tiers.info(1).tier == nil, 'disabled tiers report no tier')
check(next(Tiers.gated(Tiers.info(1))) == nil and Tiers.limit(Tiers.info(1), 'maxTransfer') == nil, 'disabled tiers gate nothing')
at(FLEECA); reset()
local result, err = act({ kind = 'transfer', from = 'checking', recipient = 'XYZ789', amount = 20000 })
check(result and result.message, 'a large transfer works with tiers disabled: ' .. tostring(err))
check(result.snapshot.branch == nil and result.snapshot.limits.maxTransfer == nil, 'disabled tiers add nothing to the snapshot')
Config.tiers = nil
check(Tiers.can(Tiers.info(1), 'sharedAccounts') and not Tiers.enabled(), 'a config without Config.tiers behaves as before')
Config.tiers = presets()

-- Enabled at a Fleeca branch.
at(FLEECA); reset()
local snap = callbacks['qbbanking:open'](1, 'bank', 1)
check(snap.branch.tier == 'fleeca' and snap.branch.label == 'Fleeca Bank - Test', 'snapshot names the branch')
check(snap.branch.gated.sharedAccounts == 'Pacific Standard' and snap.branch.gated.manageMembers == 'Pacific Standard', 'snapshot says where gated features live')
check(snap.branch.gated.deposit == nil and snap.limits.maxTransfer == 10000 and snap.limits.counterDaily == 5000, 'snapshot carries the tier limits')
result, err = act({ kind = 'create', name = 'My Club', amount = 10 })
check(result == nil and err == 'Opening a shared account is only available at Pacific Standard.', 'fleeca cannot open shared accounts: ' .. tostring(err))
for _, kind in ipairs({ 'rename', 'delete' }) do
    result, err = act({ kind = kind, account = 'x', name = 'New name' })
    check(result == nil and err:find('only available at Pacific Standard', 1, true), 'fleeca cannot ' .. kind .. ' shared accounts')
end
for _, kind in ipairs({ 'addMember', 'removeMember' }) do
    result, err = act({ kind = kind, account = 'x', citizenid = 'XYZ789' })
    check(result == nil and err == 'Managing account members is only available at Pacific Standard.', 'fleeca cannot manage members: ' .. tostring(err))
end
check(act({ kind = 'deposit', account = 'checking', amount = 50 }), 'fleeca keeps everyday deposits')
check(act({ kind = 'withdraw', account = 'checking', amount = 50 }), 'fleeca keeps everyday withdrawals')
check(act({ kind = 'transfer', from = 'checking', recipient = 'XYZ789', amount = 10000 }), 'fleeca transfers up to the limit')
result, err = act({ kind = 'transfer', from = 'checking', recipient = 'XYZ789', amount = 10001 })
check(result == nil and err == 'Transfers above $10000 are only available at Pacific Standard.', 'fleeca rejects transfers above the limit: ' .. tostring(err))
local before = other.money.bank
used = 4900
result, err = act({ kind = 'withdraw', account = 'checking', amount = 200 })
check(result == nil and err == 'Above the daily withdrawal limit of $5000 at Fleeca Bank - Test.', 'fleeca counter daily limit: ' .. tostring(err))
check(act({ kind = 'withdraw', account = 'checking', amount = 100 }), 'withdrawals within the daily allowance still work')
check(other.money.bank == before, 'rejections move no funds')

-- Feature flags are config-driven and read live.
Config.tiers.list.fleeca.features.withdraw = false
result, err = act({ kind = 'withdraw', account = 'checking', amount = 5 })
check(result == nil and err:find('Withdrawing cash is only available at', 1, true), 'a disabled feature is blocked for withdrawals')
Config.tiers.list.fleeca.features.withdraw = true

-- Enabled at Pacific Standard: shared accounts, members and large transfers pass the tier gate.
at(BIG); reset()
snap = callbacks['qbbanking:open'](1, 'bank', 2)
check(snap.branch.tier == 'bigbank' and next(snap.branch.gated) == nil and snap.limits.maxTransfer == nil, 'bigbank gates nothing and has no transfer cap')
result, err = act({ kind = 'create', name = 'My Club', amount = 10 }, 2)
check(result and result.message == 'Shared account created.', 'bigbank can open shared accounts: ' .. tostring(err))
result, err = act({ kind = 'addMember', account = 'x', citizenid = 'XYZ789' }, 2)
check(err == 'Only the account owner can make that change.', 'bigbank reaches the normal member checks: ' .. tostring(err))
check(act({ kind = 'transfer', from = 'checking', recipient = 'XYZ789', amount = 500000 }, 2), 'bigbank allows large transfers')
used = 49900
result, err = act({ kind = 'withdraw', account = 'checking', amount = 200 }, 2)
check(result == nil and err:find('daily withdrawal limit of $50000', 1, true), 'bigbank has its own higher daily limit')
used = 4900
check(act({ kind = 'withdraw', account = 'checking', amount = 200 }, 2), 'bigbank allows what fleeca would reject')

-- A client cannot choose its tier: the index of a Pacific Standard branch from a Fleeca counter still means Fleeca.
at(FLEECA); reset()
snap = callbacks['qbbanking:open'](1, 'bank', 2)
check(snap.branch.tier == 'fleeca', 'the tier follows the player position, not the client-sent index')
result, err = callbacks['qbbanking:action'](1, { kind = 'create', name = 'Sneaky Club', amount = 10 })
check(result == nil and err:find('only available at Pacific Standard', 1, true), 'spoofing the index does not unlock Pacific Standard features')
-- The tier is re-resolved from the player's position on every action (a stale session tier is never reused).
at(BIG)
result = callbacks['qbbanking:action'](1, { kind = 'transfer', from = 'checking', recipient = 'XYZ789', amount = 50000 })
check(result and result.snapshot.branch.tier == 'bigbank', 'the tier is re-resolved from the current position on each action')
at(FLEECA)
result, err = callbacks['qbbanking:action'](1, { kind = 'transfer', from = 'checking', recipient = 'XYZ789', amount = 50000 })
check(result == nil and err:find('Transfers above $10000', 1, true), 'walking back to Fleeca restores the Fleeca limits')
at({ x = 5000, y = 5000, z = 30 })
check(select(2, callbacks['qbbanking:action'](1, { kind = 'deposit', account = 'checking', amount = 5 })) == 'Your banking session expired.', 'leaving every branch ends the session')
at(LEGACY)
snap = callbacks['qbbanking:open'](1, 'bank', 3)
check(snap.branch.tier == 'fleeca', 'legacy plain-coordinate branches open on the default tier')

-- The counter cap counts withdrawals from every account (shared ones too); the sql flag is 1 only for tier caps.
at(FLEECA); reset()
local capFlags = {}
onScalar = function(sql, params) capFlags[#capFlags + 1] = params[2] end
act({ kind = 'withdraw', account = 'checking', amount = 5 })
check(capFlags[#capFlags] == 1, 'a tier counter cap counts withdrawals from all accounts')
onScalar = nil

-- Overlapping requests from one player are serialised so two withdrawals cannot both pass the same cap.
local nested
callbacks['qbbanking:open'](1, 'bank', 1)
onScalar = function()
    onScalar = nil
    nested = select(2, callbacks['qbbanking:action'](1, { kind = 'withdraw', account = 'checking', amount = 5 }))
end
check(callbacks['qbbanking:action'](1, { kind = 'withdraw', account = 'checking', amount = 5 }), 'the outer request still completes')
check(nested == 'Your previous banking request is still being processed.', 'an overlapping request is rejected: ' .. tostring(nested))
check(act({ kind = 'withdraw', account = 'checking', amount = 5 }), 'the lock is released afterwards')
print(('qbbanking tiers: %d assertions passed'):format(passed))
