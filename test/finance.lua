-- Real provider code against a transactional, rollback-capable SQL fixture.
local tools = dofile('../kora_core/test/mocks.lua')
local json = { encode = tools.stableEncode, decode = tools.simpleDecode }
local function copy(value) return json.decode(json.encode(value)) end
local database = { players = { BUYER = { cash = 0, bank = 10000 }, SELLER = { cash = 0, bank = 0 } },
    accounts = { society = 0, escrow = 0 }, receipts = {}, ledger = {}, owner = 'SELLER' }
local locks, memory, cache = {}, {}, {}
local caller = 'kora_housing'
local commits, attempts, assertions = 0, 0, 0
local function check(value, message) assert(value, message); assertions = assertions + 1 end
local function boot()
    local api, threads, f = {}, {}, {}
    local core = {}
    function core.beginPlayerColumnOperation(_, key, ids)
        local token = 'qbbanking:' .. key
        local resumed = locks[token] ~= nil
        locks[token] = locks[token] or { token = token, operationKey = key, citizenids = copy(ids) }
        return token, resumed and 'resumed' or nil
    end
    function core.getPlayerColumnOperations()
        local result = {}
        for _, operation in pairs(locks) do result[#result + 1] = copy(operation) end
        return result
    end
    function core.finishPlayerColumnOperation(_, token, values)
        if f.failFinish then return false, 'controlled publication failure' end
        for cid, data in pairs(values) do memory[cid] = copy(data.money) end
        locks[token] = nil
        return true
    end
    function core.abortPlayerColumnOperation(_, token) locks[token] = nil; return true end
    local sql = { NULL = '\0qbsql:null\0', ready = function() return true end, ensureTables = function() return { {} } end }
    function sql.awaitCheckedOperation() return { active = false } end
    function sql.scalar() return 0 end
    function sql.awaitCheckedOperations() return { settled = 0 } end
    function sql.single(_, params)
        if f.outage then return nil, 'controlled database outage' end
        return copy(database.receipts[params[1] .. ':' .. params[2]])
    end
    function sql.query(_, ids)
        if f.outage then return nil, 'controlled database outage' end
        local rows = {}
        for _, cid in ipairs(ids) do
            if database.players[cid] then rows[#rows + 1] = { citizenid = cid, money = json.encode(database.players[cid]) } end
        end
        return rows
    end
    function sql.transactionChecked(statements)
        if statements[1].query:find('SELECT `request`,`receipt`', 1, true) then
            if f.outage then return { success = false, code = 'unavailable' } end
            local p = statements[1].values
            local row = database.receipts[p[1] .. ':' .. p[2]]
            return { success = true, results = { row and { copy(row) } or {} } }
        end
        attempts = attempts + 1
        local staged = copy(database)
        for index, statement in ipairs(statements) do
            if f.failAt == index then return { success = false, code = 'unavailable', message = 'controlled query failure' } end
            local query, p, affected = statement.query, statement.values, 1
            if query:find('INSERT INTO `bank_operations`', 1, true) then
                local identity = p[1] .. ':' .. p[2]
                if staged.receipts[identity] then return { success = false, code = 'duplicate' } end
                staged.receipts[identity] = { request = p[3], receipt = p[4] }
            elseif query:find('UPDATE `players`', 1, true) then
                local money = staged.players[p[2]]
                if not money or p[3] > 0 and money.bank < p[3] then affected = 0 else money.bank = money.bank + p[1] end
            elseif query:find('UPDATE `bank_accounts`', 1, true) then
                local balance = staged.accounts[p[2]]
                if not balance or p[3] > 0 and balance < p[3] or balance + p[1] > 2147483647 then affected = 0 else staged.accounts[p[2]] = balance + p[1] end
            elseif query:find('INSERT INTO `bank_operation_legs`', 1, true) then
                staged.ledger[#staged.ledger + 1] = copy(p)
            elseif query == 'UPDATE property owner' then
                if staged.owner ~= p[2] then affected = 0 else staged.owner = p[1] end
            else error('Unexpected financial statement: ' .. query) end
            if statement.expectedRows and affected ~= statement.expectedRows then
                return { success = false, code = statement.failureCode or 'conflict', statement = index }
            end
        end
        database, commits = staged, commits + 1
        if f.loseCommitReply then f.loseCommitReply = false; return { success = false, code = 'indeterminate' } end
        return { success = true }
    end
    local env = {}
    for key, value in pairs(_G) do env[key] = value end
    env.json, env.Config, env.Kora = json, { transactionCallers = { kora_housing = true, other = true } }, { sql = sql, timers = { setTimeout = function(fn) threads[#threads + 1] = fn; return #threads end, clearTimeout = function() end } }
    env.exports = setmetatable({ kora_core = core }, { __call = function(_, name, fn) api[name] = fn end })
    env.GetInvokingResource = function() return caller end
    env.GetCurrentResourceName = function() return 'kora_banking' end
    env.CreateThread = function(fn) threads[#threads + 1] = fn end
    env.AddEventHandler = function() end
    env.TriggerEvent = function(name, account) if name == 'qbbanking:refreshAccount' then cache[account] = database.accounts[account] end end
    assert(loadfile('server/finance.lua', 't', env))()
    threads[1]()
    return api, f
end

locks['qbbanking:kora_housing:orphan'] = { token = 'qbbanking:kora_housing:orphan', operationKey = 'kora_housing:orphan', citizenids = { 'BUYER' } }
local api, f = boot()
check(next(locks) == nil and commits == 0, 'Startup releases a confirmed absent preparation without creating a financial mutation')
local sale = { debits = { { citizenid = 'BUYER', amount = 1000 } }, credits = {
    { citizenid = 'SELLER', amount = 940 }, { account = 'society', amount = 60 } }, reason = 'Property sale',
    statements = { { query = 'UPDATE property owner', values = { 'BUYER', 'SELLER' }, expectedRows = 1 } } }
local receipt, code = api.ExecuteTransaction('sale:one', sale)
check(receipt and receipt.status == 'completed' and receipt.operationKey == 'sale:one', code)
check(database.players.BUYER.bank == 9000 and database.players.SELLER.bank == 940 and database.accounts.society == 60, 'All financial legs must commit')
check(database.owner == 'BUYER' and cache.society == 60 and memory.BUYER.bank == 9000, 'Ownership, caches and money must agree')
check(#database.ledger == 3 and commits == 1, 'One durable operation and each leg once')
local previousAttempts = attempts
receipt = api.ExecuteTransaction('sale:one', copy(sale))
check(receipt and attempts == previousAttempts and commits == 1, 'An identical retry must not execute again')
local changed = copy(sale); changed.reason = 'Different immutable terms'
receipt, code = api.ExecuteTransaction('sale:one', changed)
check(not receipt and code == 'conflict' and commits == 1, 'A changed retry must conflict')
caller = 'other'
receipt, code = api.GetOperation('sale:one')
check(not receipt and code == 'not_found', 'Another resource must not read the receipt')
caller = 'untrusted'
check(api.ExecuteTransaction('forged', sale) == nil, 'Untrusted callers cannot execute')
caller = 'kora_housing'

local rent = { debits = { { citizenid = 'BUYER', amount = 10000 } }, credits = { { citizenid = 'SELLER', amount = 10000 } } }
receipt, code = api.ExecuteTransaction('rent:insufficient', rent)
check(not receipt and code == 'insufficient_funds', 'Core overdraft policy must not fund rent')
check(database.players.BUYER.bank == 9000 and commits == 1 and next(locks) == nil, 'Insufficient funds must roll back and release')

local invalidSale = copy(sale); invalidSale.statements[1].values[2] = 'OLD_OWNER'
receipt, code = api.ExecuteTransaction('sale:stale', invalidSale)
check(not receipt and code == 'conflict', 'A changed domain precondition must refuse settlement')
check(database.players.BUYER.bank == 9000 and database.owner == 'BUYER' and commits == 1, 'Domain failure must roll back funds and receipt')
f.failAt = 3
receipt, code = api.ExecuteTransaction('sale:sql-failure', sale)
check(not receipt and code == 'unavailable' and database.players.BUYER.bank == 9000, 'Query failure must not partially debit')
f.failAt = nil

local reserve = { debits = { { citizenid = 'BUYER', amount = 500 } }, credits = { { account = 'escrow', amount = 500 } } }
f.loseCommitReply = true
receipt, code = api.ExecuteTransaction('deposit:reserve', reserve)
check(not receipt and code == 'indeterminate' and database.accounts.escrow == 500, 'A lost commit reply must remain indeterminate')
check(next(locks) ~= nil, 'Ambiguous commit keeps the player fence')
api, f = boot()
check(next(locks) == nil and memory.BUYER.bank == 8500, 'Bank startup alone recovers a committed receipt even when housing has no pending row')
receipt = api.GetOperation('deposit:reserve')
check(receipt and receipt.status == 'completed' and next(locks) == nil, 'Provider restart must recover the original receipt and fence')
check(memory.BUYER.bank == 8500 and cache.escrow == 500, 'Receipt recovery publishes committed balances')
previousAttempts = attempts
check(api.ExecuteTransaction('deposit:reserve', copy(reserve)) ~= nil and attempts == previousAttempts, 'Restarted duplicate must not reserve twice')
local refund = { debits = { { account = 'escrow', amount = 500 } }, credits = { { citizenid = 'BUYER', amount = 500 } } }
check(api.ExecuteTransaction('deposit:refund', refund) ~= nil, 'Escrow refund must settle')
check(database.accounts.escrow == 0 and database.players.BUYER.bank == 9000, 'Escrow refund must conserve funds')
f.failFinish = true
receipt, code = api.ExecuteTransaction('publish:pending', reserve)
check(not receipt and code == 'pending' and next(locks) ~= nil, 'Confirmed commit with failed publication must remain pending')
f.failFinish = false
check(api.GetOperation('publish:pending') ~= nil and next(locks) == nil, 'Receipt retry must release only after publication succeeds')
local netted = { debits = { { citizenid = 'BUYER', amount = 1000000 } }, credits = { { citizenid = 'BUYER', amount = 1000000 } } }
receipt, code = api.ExecuteTransaction('gross:not-net', netted)
check(not receipt and code == 'insufficient_funds', 'A same-account credit cannot net away the required gross debit')
database.players.SELLER.bank = -100
local income = { debits = { { citizenid = 'BUYER', amount = 20 } }, credits = { { citizenid = 'SELLER', amount = 20 } } }
check(api.ExecuteTransaction('credit:negative-recipient', income) ~= nil and database.players.SELLER.bank == -80, 'Credit-only legs still pay a recipient with an existing allowed negative balance')
f.outage = true
receipt, code = api.ExecuteTransaction('rent:outage', reserve)
check(not receipt and code == 'unavailable', 'An outage cannot be classified as insufficient funds')
print(('qbbanking durable finance: %d assertions passed; atomic commit, rollback, escrow, receipt/restart recovery'):format(assertions))
