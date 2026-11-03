-- Schema regressions and the guarded collation step.
local assertions = 0
local function check(value, message) assert(value, message); assertions = assertions + 1 end
local function readFile(path)
    local file = assert(io.open(path, 'rb')); local text = file:read('a'); file:close(); return text
end

-- Schema regressions: the Lua table declaration replaces the SQL files.
local function loadSchema()
    local env = { Kora = { sql = { NULL = { null = true } } } }
    assert(loadfile('server/schema.lua', 't', env))()
    local byName = {}
    for _, spec in ipairs(env.QBBankingSchema) do byName[spec.name] = spec end
    return env.QBBankingSchema, byName, env.Kora.sql.NULL
end
local list, byName, NULL = loadSchema()
check(#list == 4, 'schema declares four tables')
for _, name in ipairs({ 'bank_accounts', 'bank_statements', 'bank_operations', 'bank_operation_legs' }) do check(byName[name], name .. ' is declared') end
check(byName.bank_accounts.collate == 'utf8mb4_unicode_ci' and byName.bank_statements.collate == 'utf8mb4_unicode_ci', 'legacy tables keep unicode collation')
check(byName.bank_operations.collate == nil, 'bank_operations has no explicit collation')
check(byName.bank_operation_legs.collate == 'utf8mb4_unicode_ci', 'bank_operation_legs pins the collation')
check(table.concat(byName.bank_operations.primary, ',') == 'resource,operation_key', 'operations primary key')
check(table.concat(byName.bank_operation_legs.primary, ',') == 'id', 'legs primary key')
local legUnique
for _, index in ipairs(byName.bank_operation_legs.indexes) do if index.name == 'uk_bank_operation_leg' then legUnique = index end end
check(legUnique and legUnique.unique and table.concat(legUnique.columns, ',') == 'resource,operation_key,leg', 'legs unique key')
check(byName.bank_accounts.indexes[1].unique and byName.bank_accounts.indexes[1].name == 'account_name', 'account_name is unique')
local function column(spec, name) for _, c in ipairs(spec.columns) do if c.name == name then return c end end end
check(column(byName.bank_accounts, 'citizenid').null and column(byName.bank_accounts, 'citizenid').default == NULL, 'citizenid is nullable default NULL')
check(column(byName.bank_accounts, 'users').default == '[]', 'users defaults to []')
check(column(byName.bank_operation_legs, 'amount').unsigned and column(byName.bank_operation_legs, 'amount').type == 'bigint', 'leg amount is bigint unsigned')

-- Guarded step + bootstrap behaviour.
local function boot(opts)
    local printed, threads, calls = {}, {}, { execute = {}, ensure = 0, ready = false }
    local sql = { ready = function() return true end, awaitCheckedOperations = function() return { settled = 0 } end }
    function sql.ensureTables(specs)
        calls.ensure = calls.ensure + 1; calls.specs = specs
        if opts.migrateError then return nil, opts.migrateError end
        return { ran = 1 }
    end
    function sql.scalar(query, params) calls.query, calls.params = query, params; if calls.scalarAt == nil then calls.scalarAt = calls.ensure or 0 end; return opts.mismatched, opts.scalarError end
    function sql.execute(query) calls.execute[#calls.execute + 1] = query; return nil, opts.alterError end
    local timers = { delays = {} }
    local api = { sql = sql, timers = { setTimeout = function(fn, ms) threads[#threads + 1] = fn; timers.delays[#timers.delays + 1] = ms; return #threads end, clearTimeout = function() end } }
    local env = {}
    for key, value in pairs(_G) do env[key] = value end
    env.QBBankingSchema = { { name = 'bank_operation_legs' } }
    env.Kora, env.QB, env.Config = api, api, { transactionCallers = {}, migrationRetrySeconds = opts.retry }
    env.print = function(text) printed[#printed + 1] = text end
    env.exports = setmetatable({ kora_core = {} }, { __call = function() end })
    env.GetInvokingResource = function() return 'kora_housing' end
    env.GetCurrentResourceName = function() return 'kora_banking' end
    env.CreateThread = function(fn) threads[#threads + 1] = fn end
    env.AddEventHandler = function() end
    env.TriggerEvent = function(name) if name == 'qbbanking:durableReady' then calls.ready = true end end
    assert(loadfile('server/finance.lua', 't', env))()
    threads[1]()
    return calls, printed, timers
end

local calls = boot({ mismatched = 3 })
check(calls.ensure == 1 and calls.specs[1].name == 'bank_operation_legs', 'bootstrap applies the schema via ensureTables')
check(#calls.execute == 1 and calls.execute[1]:find('CONVERT TO CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci', 1, true), 'mismatched collation converts')
check(calls.ready, 'durable banking enables after conversion')
check(calls.scalarAt == 0, 'collation is aligned before ensureTables so the handler sees no collation drift')
calls = boot({ mismatched = '0' })
check(#calls.execute == 0 and calls.ready, 'already aligned: no ALTER, durable enabled')
calls = boot({ mismatched = 0 })
check(calls.params[1] == 'bank_operation_legs' and calls.params[2] == 'utf8mb4_unicode_ci', 'guard checks the legs table and target collation')
local printed
calls, printed = boot({ alterError = 'denied' })
check(calls.ready and printed[1]:find('collation check returned no result', 1, true), 'a failed guard check is logged but does not disable durable banking')
calls, printed = boot({ mismatched = 2, alterError = 'denied' })
check(calls.ready and printed[1]:find('could not align', 1, true), 'a failed conversion is logged but does not disable durable banking')
local timers
calls, printed, timers = boot({ mismatched = 0, migrateError = 'boom' })
check(not calls.ready and printed[1]:find('stay disabled', 1, true) and #timers.delays == 0, 'schema failure is logged clearly; no retry by default')
calls, printed, timers = boot({ mismatched = 0, migrateError = 'boom', retry = 120 })
check(not calls.ready and timers.delays[1] == 120000, 'migrationRetrySeconds schedules a retry')
print(('qbbanking migrations: %d assertions passed; Lua schema, guarded collation conversion, failure handling'):format(assertions))
