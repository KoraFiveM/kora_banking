-- Player transfers: lookup by account number, shared/business account name and card number; offline credit via SQL.
local root = debug.getinfo(1, 'S').source:sub(2):match('(.*/)') .. '../'
dofile(root .. 'dates.lua')
local callbacks, threads, noop = {}, {}, function() end
local function check(value, message) assert(value, message) end

local pos = { x = 100, y = 100, z = 30 }
local player = { citizenid = 'ABC123', money = { cash = 0, bank = 5000 }, charinfo = {} }
local online = { citizenid = 'ONL111', money = { bank = 0 } }
local offlineBank = { OFF222 = 0, CARD33 = 0, ABC123 = 0 }
local accounts = { Mechanic = { account_name = 'Mechanic', account_balance = 0, account_type = 'job', users = '[]' },
    ['Fun Club'] = { account_name = 'Fun Club', account_balance = 10, account_type = 'shared', citizenid = 'OFF222', users = '[]' } }
local statements, offlineUpdates = {}, 0
local CARD = '6195897835956877'

local env = setmetatable({
    Config = { dailyLimit = 100000, useDailyLimit = false, atmDistance = 2, maxAccounts = 2, maxSharedMembers = 10,
        maxSharedMemberBytes = 512, memberRateLimit = { max = 50, window = 10000 },
        locations = { { coords = pos } }, Transfers = { allowOffline = true, allowSharedAccounts = true, allowCardNumbers = true } },
    Kora = {
        shared = { get = function() return {} end, epoch = function() return 1 end, all = function() return {} end },
        util = { isFiniteNumber = function(n) return type(n) == 'number' and n == n end, cleanText = function(s) return s end,
            isInteger = function(n) return type(n) == 'number' and n == n and n % 1 == 0 end,
            -- Mirrors this env's own json.decode mock below (same CARD-tagged fixture), since this
            -- closure's lexical environment is the real _G, not the sandboxed env server.lua runs in.
            decodeJson = function(value)
                if type(value) ~= 'string' then return nil, 'invalid_json' end
                if value == 'card' then return { { name = 'bank_card', info = { cardNumber = CARD, citizenid = 'CARD33' } } } end
                return {}
            end,
            nearest = function(list, position, opts)
                local best, bestDistance
                for _, entry in pairs(list) do
                    local coords = opts.coordsOf(entry)
                    local dx, dy, dz = (position.x or 0) - (coords.x or 0), (position.y or 0) - (coords.y or 0), (position.z or 0) - (coords.z or 0)
                    local distance = math.sqrt(dx * dx + dy * dy + dz * dz)
                    if (opts.radius == nil or distance <= opts.radius) and (bestDistance == nil or distance < bestDistance) then
                        best, bestDistance = entry, distance
                    end
                end
                return best, bestDistance
            end,
            rateLimiter = function(max, window)
                local buckets = {}
                local limiter = {}
                function limiter:consume(key, now)
                    local retained = {}
                    for _, t in ipairs(buckets[key] or {}) do if now - t < window then retained[#retained + 1] = t end end
                    if #retained >= max then buckets[key] = retained; return false end
                    retained[#retained + 1] = now
                    buckets[key] = retained
                    return true
                end
                return limiter
            end },
        callback = { register = function(name, fn) callbacks[name] = fn end },
        sql = { ready = function() return true end, ensureTables = function() return { {} } end,
            query = function(sql, params)
                if sql:find('inventory LIKE', 1, true) then
                    if params[1]:find(CARD, 1, true) then return { { citizenid = 'CARD33', inventory = 'card' } } end
                    return {}
                end
                return {}
            end,
            single = function(sql, params)
                if sql:find('FROM bank_accounts', 1, true) then return accounts[params[1]] end
                if sql:find('FROM players', 1, true) then return offlineBank[params[1]] and { citizenid = params[1] } or nil end
            end,
            insert = function(_, params) statements[#statements + 1] = params return #statements end,
            update = function(sql, params)
                if sql:find('UPDATE players', 1, true) then
                    if offlineBank[params[2]] == nil then return 0 end
                    offlineBank[params[2]] = offlineBank[params[2]] + params[1]; offlineUpdates = offlineUpdates + 1
                    return 1
                end
                local account = accounts[params[2]]
                if not account then return 0 end
                account.account_balance = account.account_balance + params[1]
                return 1
            end,
            scalar = function() return 0 end },
    },
    exports = setmetatable({ kora_core = {
        createUseable = noop, addCommand = noop,
        getPlayerData = function(_, src, cols) if cols then return player.citizenid end return player end,
        getPlayerByCitizenId = function(_, cid) if cid == 'ONL111' then return { source = 2 } end end,
        removeMoney = function(_, _, kind, amount) if player.money[kind] < amount then return false end player.money[kind] = player.money[kind] - amount return true end,
        addMoney = function(_, src, kind, amount) online.money[kind] = online.money[kind] + amount return true end,
        getItemsByName = function() return {} end, getItemByName = function() return nil end,
    } }, { __call = noop }),
    RegisterNetEvent = noop, AddEventHandler = noop, SetTimeout = noop, GetGameTimer = function() return 0 end,
    GetPlayerPed = function() return 1 end, GetEntityCoords = function() return pos end, GetPlayerName = function() return 'Tester' end,
    json = { encode = function() return '[]' end,
        decode = function(s) if s == 'card' then return { { name = 'bank_card', info = { cardNumber = CARD, citizenid = 'CARD33' } } } end return {} end },
    CreateThread = function(fn) threads[#threads + 1] = fn end,
}, { __index = _G })
assert(loadfile(root .. 'tiers.lua', 't', env))()
env.Kora.compat = { provideExport = noop }
assert(loadfile(root .. 'server.lua', 't', env))()
for _, thread in ipairs(threads) do thread() end

local function send(recipient, amount)
    assert(callbacks['kora_banking:open'](1, 'bank', 1))
    return callbacks['kora_banking:action'](1, { kind = 'transfer', from = 'checking', recipient = recipient, amount = amount })
end
local function lastStatements(n) local out = {} for i = #statements - n + 1, #statements do out[#out + 1] = statements[i] end return out end

local result, err = send('ONL111', 100)
check(result and online.money.bank == 100 and offlineUpdates == 0, 'online recipient is credited through the player object: ' .. tostring(err))

result, err = send('OFF222', 200)
check(result and offlineBank.OFF222 == 200 and offlineUpdates == 1, 'offline recipient is credited in the database: ' .. tostring(err))
local rows = lastStatements(2)
check(rows[1][1] == 'ABC123' and rows[1][5] == 'withdraw' and rows[2][1] == 'OFF222' and rows[2][2] == 'checking' and rows[2][5] == 'deposit', 'both sides are logged')
check(player.money.bank == 4700, 'sender is debited once')

result, err = send('Mechanic', 300)
check(result and accounts.Mechanic.account_balance == 300, 'society account is credited by name: ' .. tostring(err))
rows = lastStatements(2)
check(rows[2][2] == 'Mechanic' and rows[2][5] == 'deposit', 'society deposit is logged against the account')
result, err = send('Fun Club', 50)
check(result and accounts['Fun Club'].account_balance == 60, 'shared account is credited by name: ' .. tostring(err))

result, err = send(CARD, 400)
check(result and offlineBank.CARD33 == 400, 'card number resolves to the issuing character: ' .. tostring(err))
result, err = send('6195 8978 3595 6877', 10)
check(result and offlineBank.CARD33 == 410, 'a card number typed in groups of four resolves too')

result, err = send('NOPE999', 10)
check(not result and err == 'No account was found with that number.', 'unknown numbers report not found: ' .. tostring(err))
result, err = send('ABC123', 10)
check(not result and err == 'Use an internal transfer for your own accounts.', 'cannot send to yourself')
local before = player.money.bank
result = send('9999999999999999', 10)
check(not result and player.money.bank == before, 'unknown card does not debit')

local cfg = env.Config.Transfers
cfg.allowOffline = false
result, err = send('OFF222', 10)
check(not result and err == 'That account holder must be online.' and offlineBank.OFF222 == 200, 'allowOffline=false keeps the online-only behaviour')
check(send('ONL111', 10), 'allowOffline=false still pays online players')
cfg.allowOffline = true
cfg.allowSharedAccounts = false
result = send('Mechanic', 10)
check(not result and accounts.Mechanic.account_balance == 300, 'allowSharedAccounts=false blocks account names')
cfg.allowSharedAccounts, cfg.allowCardNumbers = true, false
result = send(CARD, 10)
check(not result and offlineBank.CARD33 == 410, 'allowCardNumbers=false blocks card numbers')
print('transfers: ok')
