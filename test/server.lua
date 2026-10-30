local root = debug.getinfo(1, 'S').source:sub(2):match('(.*/)') .. '../'
local api, threads, legacyEvents = {}, {}, {}
local balance, statements = 1000, 0
local statementResult, updateFails
local function noop() end
local env = setmetatable({
    QB = {
        shared = { get = function() return {} end, epoch = function() return 1 end, all = function() return {} end },
        util = {
            isFiniteNumber = function(n) return type(n) == 'number' and n == n and math.abs(n) < math.huge end,
            cleanText = function(s) return s end,
        },
        callback = { register = noop },
        sql = {
            ready = function() return true end,
            query = function() return { { account_name = 'police', account_balance = balance, account_type = 'job' } } end,
            single = function(sql)
                if sql:find('SELECT', 1, true) then
                    return { account_name = 'police', account_balance = balance, account_type = 'job' }
                end
            end,
            update = function(_, params)
                if updateFails then return nil, 'controlled balance update failure' end
                if params[3] and balance < params[3] then return 0 end
                balance = balance + params[1]
                return 1
            end,
            insert = function()
                statements = statements + 1
                return statementResult, statementResult and nil or 'controlled history insert failure'
            end,
        },
    },
    exports = setmetatable({ kora_core = { createUseable = noop, addCommand = noop } }, {
        __call = function(_, name, fn) api[name] = fn end,
    }),
    RegisterNetEvent = noop, AddEventHandler = function(name, fn) legacyEvents[name] = fn end,
    GetGameTimer = function() return 0 end,
    CreateThread = function(fn) threads[#threads + 1] = fn end,
}, { __index = _G })
env.QB.compat = assert(loadfile(root .. '../kora_lib/compat/provider.lua', 't', env))()()
assert(loadfile(root .. 'server.lua', 't', env))()
threads[1]()

local legacyApi = {}
for name, handler in pairs(api) do
    local provide = assert(legacyEvents['__cfx_export_qb-banking_' .. name], 'missing legacy export: ' .. name)
    provide(function(fn) legacyApi[name] = fn end)
    assert(legacyApi[name] == handler, 'legacy callers must reach the same guarded banking operation')
end
assert(legacyApi.AddMoney('police', 25, 'legacy deposit') == true and balance == 1025)
assert(legacyApi.RemoveMoney('police', 25, 'legacy withdrawal') == true and balance == 1000)
assert(legacyApi.AddMoney('police', 0 / 0) == false)
assert(legacyApi.AddMoney('police', math.huge) == false)
assert(legacyApi.AddMoney('missing', 100) == false)
assert(legacyApi.RemoveMoney('police', 1001) == false and balance == 1000)
assert(legacyApi.GetAccountBalance('police') == 1000 and legacyApi.GetAccount('missing') == nil)
statements = 0

-- The history write must not turn a committed balance change into a failed payment.
assert(api.AddMoney('police', 100, 'deposit') == true and balance == 1100,
    'a failed history insert must not report a committed deposit as failed')
assert(api.RemoveMoney('police', 100, 'withdrawal') == true and balance == 1000,
    'a failed history insert must not report a committed withdrawal as failed')
assert(api.GetAccountBalance('police') == balance and statements == 2)
assert(api.AddGangMoney == api.AddMoney and api.RemoveGangMoney == api.RemoveMoney)

statementResult = false
assert(api.AddGangMoney('police', 100) == true and balance == 1100)
assert(api.RemoveGangMoney('police', 100) == true and balance == 1000)
assert(api.CreateBankStatement(0, 'police', 100, 'history only', 'deposit') == false,
    'the standalone statement export must still report its own write failure')

local previousStatements = statements
assert(api.RemoveMoney('police', 1001) == false)
assert(api.AddMoney('missing', 100) == false)
assert(api.AddMoney('police', 0) == false)
assert(api.RemoveMoney('police', -100) == false)
updateFails = true
assert(api.AddMoney('police', 100) == false and api.RemoveMoney('police', 100) == false)
assert(balance == 1000 and statements == previousStatements,
    'rejected balance operations must not change funds or attempt a history write')

updateFails, statementResult = false, 1
assert(api.AddMoney('police', 100) == true and api.RemoveMoney('police', 100) == true)
assert(balance == 1000 and statements == previousStatements + 2)
print('qbbanking server: balance outcomes and history failure regression passed')

local callbacks, created = {}, {}
env.Config = { locations = {} }
env.QB.callback.register = function(name, fn) callbacks[name] = fn end
env.QB.shared.all = function(kind)
    return kind == 'jobs' and { { name = 'unemployed' }, { name = 'police' } }
        or { { name = 'none' }, { name = 'ballas' } }
end
env.QB.sql.query = function() return {} end
env.QB.sql.single = function(sql, params)
    return params and created[params[1]] or nil
end
env.QB.sql.insert = function(_, params)
    local name = params[2]
    created[name] = { account_name = name, account_balance = params[3], account_type = params[4] }
    return 1
end
assert(loadfile(root .. 'server.lua', 't', env))()
threads[#threads]()
assert(created.police and created.police.account_type == 'job' and created.police.account_balance == 0)
assert(created.ballas and created.ballas.account_type == 'gang' and created.ballas.account_balance == 0)
assert(not created.unemployed and not created.none)
local _, openError = callbacks['qbbanking:open'](1, 'bank', 1)
assert(openError == 'Move closer to a bank counter.', 'successful organization bootstrap must reach ready')

local logged = false
env.print = function(message) logged = message:find('account creation failed', 1, true) ~= nil end
env.QB.sql.insert = function() return nil, 'controlled account creation failure' end
assert(loadfile(root .. 'server.lua', 't', env))()
threads[#threads]()
_, openError = callbacks['qbbanking:open'](1, 'bank', 1)
assert(logged and openError == 'Banking is still starting.', 'failed account creation must log and leave banking unready')
print('qbbanking server: fresh organization-account bootstrap regression passed')

-- Statement history UNIONs bank_statements with bank_operation_legs; installs where the legs table kept the
-- server default collation must not raise "Illegal mix of collations", so every string column is pinned.
local function readFile(path)
    local file = assert(io.open(path, 'rb'))
    local text = file:read('a')
    file:close()
    return text
end
local source = readFile(root .. 'server.lua')
local collate = 'COLLATE utf8mb4_unicode_ci'
assert(source:find("local COLLATION = '" .. collate .. "'", 1, true), 'history query must pin one collation')
local legSelects = 0
for select in source:gmatch("UNION ALL SELECT (.-) FROM bank_operation_legs") do
    legSelects = legSelects + 1
    assert(select:find('%%s,citizenid %%s', 1), 'leg select must collate citizenid')
    assert(select:find('reason %%s,direction %%s', 1), 'leg select must collate reason and direction')
end
assert(legSelects == 2, 'both history queries must collate the operation-leg side')
assert(source:find("STATEMENT_COLUMNS = ('id, citizenid %s AS citizenid", 1, true)
    and source:find('reason %s AS reason, statement_type %s AS statement_type', 1, true), 'statement side must be collated too')
assert(readFile(root .. 'sql/002_operation_legs_collation.sql'):find('CONVERT TO CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci', 1, true), 'migration must align bank_operation_legs')
assert(readFile(root .. 'server/finance.lua'):find('002_operation_legs_collation.sql', 1, true), 'migration must be registered')
print('qbbanking server: statement UNION collation regression passed')
