-- Migration regressions: kora_sql's retry-safety rule against our SQL files, and the guarded collation step.
local assertions = 0
local function check(value, message) assert(value, message); assertions = assertions + 1 end
local function readFile(path)
    local file = assert(io.open(path, 'rb')); local text = file:read('a'); file:close(); return text
end

-- Port of kora_sql server/js/migrate.js splitStatements + retry-safety check (statement level).
local function split(sql)
    local out, buf, inS, inD, inB, inC = {}, '', false, false, false, false
    local i = 1
    while i <= #sql do
        local c, nxt = sql:sub(i, i), sql:sub(i + 1, i + 1)
        if inC then
            if c == '\n' then inC = false end
            buf = buf .. c
        elseif not inS and not inD and not inB and c == '-' and nxt == '-' then inC = true; buf = buf .. c
        else
            if c == "'" and not inD and not inB then inS = not inS
            elseif c == '"' and not inS and not inB then inD = not inD
            elseif c == '`' and not inS and not inD then inB = not inB end
            if c == ';' and not inS and not inD and not inB then out[#out + 1] = buf; buf = '' else buf = buf .. c end
        end
        i = i + 1
    end
    if buf:match('%S') then out[#out + 1] = buf end
    return out
end
local function count(text, pattern) local n = 0; for _ in text:gmatch(pattern) do n = n + 1 end; return n end
local function retrySafe(sql)
    for _, stmt in ipairs(split(sql)) do
        if stmt:match('%S') then
            local body = stmt
            repeat local stripped = body:gsub('^%s*%-%-[^\n]*\n', ''); local changed = stripped ~= body; body = stripped until not changed
            body = body:gsub('^%s+', '')
            local upper = body:upper():gsub('%s+', ' ')
            local safeCreate = upper:find('^CREATE TABLE IF NOT EXISTS ') ~= nil
            local adds, safeAdds = count(upper, '%f[%w]ADD%f[%W]'), count(upper, 'ADD COLUMN IF NOT EXISTS') + count(upper, 'ADD INDEX IF NOT EXISTS') + count(upper, 'ADD UNIQUE INDEX IF NOT EXISTS')
            local drops, safeDrops = count(upper, '%f[%w]DROP%f[%W]'), count(upper, 'DROP INDEX IF EXISTS')
            local safeAlter = upper:find('^ALTER TABLE ') ~= nil and adds > 0 and adds == safeAdds and drops == safeDrops
            if not safeCreate and not safeAlter then return false end
        end
    end
    return true
end

-- The checker port must reject the original v2 and accept the shipped files.
check(not retrySafe('ALTER TABLE `t` CONVERT TO CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;'), 'original v2 form must be rejected by the port')
check(retrySafe('-- c\nALTER TABLE `t` ADD COLUMN IF NOT EXISTS `a` INT;'), 'port accepts guarded ADD')
for _, file in ipairs({ 'sql/001_durable_operations.sql', 'sql/002_operation_legs_collation.sql' }) do
    check(retrySafe(readFile(file)), file .. ' must pass the kora_sql retry-safety rule')
end
check(readFile('sql/002_operation_legs_collation.sql'):find('COLLATE=utf8mb4_unicode_ci', 1, true), 'v2 pins the collation')

-- Guarded step + bootstrap behaviour.
local function boot(opts)
    local printed, threads, calls = {}, {}, { execute = {}, migrate = 0, ready = false }
    local sql = { ready = function() return true end, awaitCheckedOperations = function() return { settled = 0 } end }
    function sql.migrateFiles(_, list)
        calls.migrate = calls.migrate + 1; calls.list = list
        if opts.migrateError then return nil, opts.migrateError end
        return { ran = 1 }
    end
    function sql.scalar(query, params) calls.query, calls.params = query, params; return opts.mismatched, opts.scalarError end
    function sql.execute(query) calls.execute[#calls.execute + 1] = query; return nil, opts.alterError end
    local timers = { delays = {} }
    local api = { sql = sql, timers = { setTimeout = function(fn, ms) threads[#threads + 1] = fn; timers.delays[#timers.delays + 1] = ms; return #threads end, clearTimeout = function() end } }
    local env = {}
    for key, value in pairs(_G) do env[key] = value end
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
check(calls.list[1].version == 1 and calls.list[2].version == 2 and calls.list[2].name == 'operation_legs_collation', 'version numbering is kept')
check(#calls.execute == 1 and calls.execute[1]:find('CONVERT TO CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci', 1, true), 'mismatched collation converts')
check(calls.ready, 'durable banking enables after conversion')
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
calls, printed, timers = boot({ migrateError = 'boom' })
check(not calls.ready and printed[1]:find('stay disabled', 1, true) and #timers.delays == 0, 'migration failure is logged clearly; no retry by default')
calls, printed, timers = boot({ migrateError = 'boom', retry = 120 })
check(not calls.ready and timers.delays[1] == 120000, 'migrationRetrySeconds schedules a retry')
print(('qbbanking migrations: %d assertions passed; retry-safe SQL, guarded collation conversion, failure handling'):format(assertions))
