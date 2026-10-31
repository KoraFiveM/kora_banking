local ready, busy, recoveryTimer = false, {}, nil

local function caller()
    local resource = GetInvokingResource()
    if resource and Config.transactionCallers and Config.transactionCallers[resource] == true then return resource end
end

local function operationId(resource, key) return resource .. ':' .. key end

local function canonical(value, depth)
    if depth > 24 then error('Request is too deeply nested.') end
    if type(value) == 'table' then
        local keys, parts = {}, {}
        for key in pairs(value) do
            if type(key) ~= 'string' and type(key) ~= 'number' then error('Invalid request key.') end
            keys[#keys + 1] = key
        end
        table.sort(keys, function(a, b) return type(a) .. tostring(a) < type(b) .. tostring(b) end)
        for _, key in ipairs(keys) do parts[#parts + 1] = json.encode(type(key) .. ':' .. tostring(key)) .. ':' .. canonical(value[key], depth + 1) end
        return '{' .. table.concat(parts, ',') .. '}'
    end
    if value ~= nil and type(value) ~= 'string' and type(value) ~= 'number' and type(value) ~= 'boolean' then error('Invalid request value.') end
    if type(value) == 'number' and (value ~= value or math.abs(value) == math.huge) then error('Invalid request number.') end
    return json.encode(value)
end

local function decode(value)
    local ok, result = pcall(json.decode, value or '')
    return ok and type(result) == 'table' and result or nil
end

local function playerValues(ids)
    local result = {}
    if #ids == 0 then return result end
    local placeholders = {}
    for i = 1, #ids do placeholders[i] = '?' end
    local rows, err = Kora.sql.query('SELECT `citizenid`,`money` FROM `players` WHERE `deleted_at` IS NULL AND `citizenid` IN (' .. table.concat(placeholders, ',') .. ')', ids)
    if not rows then return nil, err end
    for _, row in ipairs(rows) do
        local money = decode(row.money)
        if not money then return nil, 'Stored money is invalid.' end
        result[row.citizenid] = { money = money }
    end
    for _, cid in ipairs(ids) do if not result[cid] then return nil, 'A character no longer exists.' end end
    return result
end

local function synchronize(resource, key)
    local operationKey = operationId(resource, key)
    for _, operation in ipairs(exports.kora_core:getPlayerColumnOperations()) do
        if operation.operationKey == operationKey then
            local values, err = playerValues(operation.citizenids)
            if not values then return false, err end
            return exports.kora_core:finishPlayerColumnOperation(operation.token, values)
        end
    end
    return true
end

local function receipt(resource, key, expectedRequest)
    -- A stopped caller can leave its old driver worker running before it has
    -- acquired the receipt row. Join it before treating an absent receipt as safe.
    local settled, waitErr = Kora.sql.awaitCheckedOperation('qbbanking:' .. operationId(resource, key), expectedRequest)
    if not settled then return nil, 'unavailable', waitErr end
    if settled.active and settled.result and settled.result.code == 'indeterminate' then
        return nil, 'indeterminate', settled.result.message
    end
    -- A locking read also waits for a receipt INSERT left at the database by
    -- a restarted SQL host, whose in-memory worker registry no longer exists.
    local read, err = Kora.sql.transactionChecked({ { query = 'SELECT `request`,`receipt` FROM `bank_operations` WHERE `resource`=? AND `operation_key`=? FOR UPDATE', values = { resource, key } } })
    if not read or not read.success or not read.results or type(read.results[1]) ~= 'table' then return nil, 'unavailable', err or 'Banking receipt lookup could not be confirmed.' end
    local row = read.results[1][1]
    if not row then return nil, 'not_found' end
    if expectedRequest and row.request ~= expectedRequest then return nil, 'conflict', 'Operation key has different transaction terms.' end
    local value = decode(row.receipt)
    if not value then return nil, 'unavailable', 'Stored banking receipt is invalid.' end
    local synced, syncErr = synchronize(resource, key)
    if not synced then return nil, 'pending', syncErr or 'Committed funds are awaiting player synchronization.' end
    for _, account in ipairs(value.accounts or {}) do TriggerEvent('qbbanking:refreshAccount', account) end
    return value
end

local function prepare(request)
    if type(request) ~= 'table' then return nil, 'Invalid financial request.' end
    local accounts, ids, seen, legs = {}, {}, {}, {}
    local totals = { debits = 0, credits = 0 }
    for _, direction in ipairs({ 'debits', 'credits' }) do
        local entries = request[direction] or {}
        if type(entries) ~= 'table' or #entries > 128 then return nil, 'Invalid transaction legs.' end
        for _, entry in ipairs(entries) do
            if type(entry) ~= 'table' then return nil, 'Invalid transaction leg.' end
            local amount = entry.amount
            if type(amount) ~= 'number' or amount % 1 ~= 0 or amount < 1 or amount > 1000000000 then return nil, 'Amounts must be positive whole currency units.' end
            local cid, account = entry.citizenid, entry.account
            if (cid == nil) == (account == nil) then return nil, 'Choose one character or named account per leg.' end
            local name = cid or account
            if type(name) ~= 'string' or #name < 1 or #name > 50 then return nil, 'Invalid financial account.' end
            local identity = (cid and 'character:' or 'account:') .. name
            accounts[identity] = accounts[identity] or { citizenid = cid, account = account, debits = 0, credits = 0 }
            accounts[identity][direction] = accounts[identity][direction] + amount
            totals[direction] = totals[direction] + amount
            legs[#legs + 1] = { citizenid = cid, account = account, amount = amount, direction = direction == 'debits' and 'withdraw' or 'deposit' }
            if cid and not seen[cid] then ids[#ids + 1], seen[cid] = cid, true end
        end
    end
    if totals.debits < 1 or totals.debits ~= totals.credits then return nil, 'Financial legs must balance.' end
    if request.statements ~= nil and (type(request.statements) ~= 'table' or #request.statements > 256) then return nil, 'Invalid domain transaction.' end
    for _, statement in ipairs(request.statements or {}) do
        if type(statement) ~= 'table' or type(statement.query) ~= 'string' or #statement.query > 20000 then return nil, 'Invalid domain statement.' end
    end
    table.sort(ids)
    return { accounts = accounts, ids = ids, legs = legs, amount = totals.debits }
end

local function execute(resource, key, request, fingerprint)
    local existing, code, err = receipt(resource, key, fingerprint)
    if existing or code ~= 'not_found' then return existing, code, err end
    local prepared, validationErr = prepare(request)
    if not prepared then return nil, 'rejected', validationErr end
    local token, lockCode, lockErr = exports.kora_core:beginPlayerColumnOperation(operationId(resource, key), prepared.ids, { 'money' })
    if not token then return nil, lockCode, lockErr end
    local values, loadErr = playerValues(prepared.ids)
    if not values then
        if lockCode ~= 'resumed' then
            local released, releaseErr = exports.kora_core:abortPlayerColumnOperation(token)
            if not released then return nil, 'pending', releaseErr end
        end
        return nil, 'unavailable', loadErr
    end
    local names = {}
    for _, account in pairs(prepared.accounts) do if account.account then names[#names + 1] = account.account end end
    table.sort(names)
    local value = { operationKey = key, resource = resource, status = 'completed', timestamp = os.time(), amount = prepared.amount, accounts = names }
    local statements = { { query = 'INSERT INTO `bank_operations` (`resource`,`operation_key`,`request`,`receipt`) VALUES (?,?,?,?)',
        values = { resource, key, fingerprint, json.encode(value) }, expectedRows = 1 } }
    local accountKeys = {}
    for identity in pairs(prepared.accounts) do accountKeys[#accountKeys + 1] = identity end
    table.sort(accountKeys)
    for _, identity in ipairs(accountKeys) do
        local account = prepared.accounts[identity]
        local delta = account.credits - account.debits
        if account.citizenid then
            statements[#statements + 1] = {
                query = [[UPDATE `players` SET `money`=JSON_SET(`money`,'$.bank',COALESCE(JSON_EXTRACT(`money`,'$.bank'),0)+?)
                    WHERE `citizenid`=? AND `deleted_at` IS NULL AND (?=0 OR COALESCE(JSON_EXTRACT(`money`,'$.bank'),0)>=?)
                    AND COALESCE(JSON_EXTRACT(`money`,'$.bank'),0)+?<=9007199254740991]],
                values = { delta, account.citizenid, account.debits, account.debits, delta }, expectedRows = 1,
                failureCode = account.debits > 0 and 'insufficient_funds' or 'conflict',
            }
        else
            statements[#statements + 1] = {
                query = [[UPDATE `bank_accounts` SET `account_balance`=`account_balance`+? WHERE `account_name`=?
                    AND (?=0 OR `account_balance`>=?) AND `account_balance`+?<=2147483647]],
                values = { delta, account.account, account.debits, account.debits, delta }, expectedRows = 1,
                failureCode = account.debits > 0 and 'insufficient_funds' or 'conflict',
            }
        end
    end
    for index, leg in ipairs(prepared.legs) do
        statements[#statements + 1] = { query = [[INSERT INTO `bank_operation_legs`
            (`resource`,`operation_key`,`leg`,`citizenid`,`account_name`,`direction`,`amount`,`reason`) VALUES (?,?,?,?,?,?,?,?)]],
            values = { resource, key, index, leg.citizenid or Kora.sql.NULL, leg.account or Kora.sql.NULL, leg.direction, leg.amount,
                type(request.reason) == 'string' and request.reason:sub(1, 50) or 'Housing transaction' }, expectedRows = 1 }
    end
    for _, statement in ipairs(request.statements or {}) do statements[#statements + 1] = statement end
    local outcome, transactionErr = Kora.sql.transactionChecked(statements, { key = 'qbbanking:' .. operationId(resource, key), fingerprint = fingerprint, citizenids = prepared.ids })
    if not outcome or not outcome.success then
        if outcome and outcome.code ~= 'indeterminate' then
            local found, foundCode, foundErr = receipt(resource, key, fingerprint)
            if found or foundCode ~= 'not_found' then return found, foundCode, foundErr end
            local released, releaseErr = exports.kora_core:abortPlayerColumnOperation(token)
            if not released then return nil, 'pending', releaseErr end
        end
        return nil, outcome and outcome.code or 'indeterminate', outcome and outcome.message or transactionErr
    end
    return receipt(resource, key, fingerprint)
end

exports('ExecuteTransaction', function(key, request)
    local resource = caller()
    if not resource then return nil, 'rejected', 'This resource cannot execute durable banking operations.' end
    if not ready then return nil, 'unavailable', 'Durable banking is not ready.' end
    if type(key) ~= 'string' or #key < 1 or #key > 128 then return nil, 'rejected', 'Invalid operation key.' end
    local encoded, fingerprint = pcall(canonical, request, 0)
    if not encoded or #fingerprint > 524288 then return nil, 'rejected', 'Invalid or oversized financial request.' end
    local identity = operationId(resource, key)
    if busy[identity] then return nil, 'pending', 'This banking operation is pending.' end
    busy[identity] = true
    local result = table.pack(pcall(execute, resource, key, request, fingerprint))
    busy[identity] = nil
    if not result[1] then
        print(('[qbbanking] durable operation failed for %s: %s'):format(resource, tostring(result[2])))
        return nil, 'indeterminate', 'The transaction needs receipt reconciliation.'
    end
    return table.unpack(result, 2, result.n)
end)

exports('GetOperation', function(key)
    local resource = caller()
    if not resource then return nil, 'rejected', 'This resource cannot read banking operations.' end
    if not ready then return nil, 'unavailable', 'Durable banking is not ready.' end
    if type(key) ~= 'string' or #key < 1 or #key > 128 then return nil, 'rejected', 'Invalid operation key.' end
    local result = table.pack(pcall(receipt, resource, key))
    if not result[1] then return nil, 'unavailable', 'Banking receipt lookup failed.' end
    return table.unpack(result, 2, result.n)
end)

local function recoverOperations()
    recoveryTimer = nil
    local called, operations = pcall(function() return exports.kora_core:getPlayerColumnOperations() end)
    local pending = not called
    if called then
        for _, operation in ipairs(operations) do
            local identity = operation.operationKey
            if busy[identity] or operation.preparing then pending = true
            else
                busy[identity] = true
                local recovered, ok = pcall(function()
                    local resource, key = identity:match('^([^:]+):(.+)$')
                    if not resource then return false end
                    local value, code = receipt(resource, key)
                    if value then return true end
                    if code ~= 'not_found' then return false end
                    -- No worker remains and no receipt exists: no financial
                    -- mutation committed, so an orphaned preparation can release.
                    return exports.kora_core:abortPlayerColumnOperation(operation.token)
                end)
                busy[identity] = nil
                if not recovered or not ok then pending = true end
            end
        end
    end
    if pending and not recoveryTimer then recoveryTimer = Kora.timers.setTimeout(recoverOperations, 30000) end
end

local LEGS_TABLE, LEGS_COLLATION = 'bank_operation_legs', 'utf8mb4_unicode_ci'

-- kora_sql only accepts CREATE TABLE IF NOT EXISTS / ALTER ... ADD IF NOT EXISTS in migration files, so the
-- idempotent collation conversion lives here, guarded by information_schema (runs every boot, no-op once aligned).
local function alignLegsCollation()
    local mismatched, err = Kora.sql.scalar([[SELECT
        (SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = DATABASE() AND table_name = ? AND table_collation <> ?)
        + (SELECT COUNT(*) FROM information_schema.columns WHERE table_schema = DATABASE() AND table_name = ? AND collation_name IS NOT NULL AND collation_name <> ?)]],
        { LEGS_TABLE, LEGS_COLLATION, LEGS_TABLE, LEGS_COLLATION })
    if mismatched == nil then return false, err or 'collation check returned no result' end
    if (tonumber(mismatched) or 0) == 0 then return true end
    local _, alterErr = Kora.sql.execute(('ALTER TABLE `%s` CONVERT TO CHARACTER SET utf8mb4 COLLATE %s'):format(LEGS_TABLE, LEGS_COLLATION))
    if alterErr then return false, alterErr end
    print(('[qbbanking] converted %s to %s'):format(LEGS_TABLE, LEGS_COLLATION))
    return true
end

local function bootstrap()
    local available = Kora.sql.ready(60000)
    if not available then Kora.timers.setTimeout(bootstrap, 30000); return end
    local migrated, err = Kora.sql.migrateFiles(GetCurrentResourceName(), {
        { version = 1, name = 'durable_operations', file = 'sql/001_durable_operations.sql' },
        { version = 2, name = 'operation_legs_collation', file = 'sql/002_operation_legs_collation.sql' },
    })
    if not migrated then
        print(('[qbbanking] durable banking migration failed: %s. Durable transactions and durable history stay disabled until it succeeds.'):format(tostring(err)))
        local retry = tonumber(Config.migrationRetrySeconds) or 0
        if retry > 0 then Kora.timers.setTimeout(bootstrap, retry * 1000) end
        return
    end
    local aligned, alignErr = alignLegsCollation()
    if not aligned then
        -- History queries pin the collation per column, so a failed conversion is not fatal.
        print(('[qbbanking] could not align %s collation (continuing): %s'):format(LEGS_TABLE, tostring(alignErr)))
    end
    local settled, waitErr = Kora.sql.awaitCheckedOperations('qbcore:fence:qbbanking:')
    if not settled then
        print(('[qbbanking] player operation recovery deferred: %s'):format(tostring(waitErr)))
        Kora.timers.setTimeout(bootstrap, 30000)
        return
    end
    recoverOperations()
    ready = true
    TriggerEvent('qbbanking:durableReady')
end

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() and recoveryTimer then Kora.timers.clearTimeout(recoveryTimer) end
end)

CreateThread(bootstrap)
