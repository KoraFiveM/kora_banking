local root = debug.getinfo(1, 'S').source:sub(2):match('(.*/)') .. '../'
local api, threads = {}, {}
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
    exports = setmetatable({ qbcore = { createUseable = noop, addCommand = noop } }, {
        __call = function(_, name, fn) api[name] = fn end,
    }),
    RegisterNetEvent = noop, AddEventHandler = noop,
    GetGameTimer = function() return 0 end,
    CreateThread = function(fn) threads[#threads + 1] = fn end,
}, { __index = _G })
assert(loadfile(root .. 'server.lua', 't', env))()
threads[1]()

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
