local Accounts = {}
local Sessions = {}
local MemberRequests = {}
local ready = false

if not QB.shared.get('items', 'bank_card') then
    local itemRegistered, itemError = QB.shared.register('items', 'bank_card', {
        label = 'Bank Card',
        weight = 0,
        type = 'item',
        image = 'id_card.png',
        unique = true,
        useable = true,
        shouldClose = true,
        description = 'A personal debit card used to access ATMs.',
    })
    if not itemRegistered then
        print(('^1[qbbanking]^7 bank card registration failed: %s'):format(itemError or 'unknown error'))
    end
end

local function roundAmount(value)
    local amount = tonumber(value)
    if not QB.util.isFiniteNumber(amount) then return nil end
    amount = math.floor(amount)
    if amount <= 0 or amount > 1000000000 then return nil end
    return amount
end

local function cleanText(value, fallback, maxLength)
    return QB.util.cleanText(value, {
        maxLength = maxLength or 50,
        controlCharacters = 'preserve',
    }) or fallback
end

local function player(src)
    local data = exports.qbcore:getPlayerData(src)
    if not data then return nil, 'Player data is unavailable.' end
    return data
end

local function boss(record)
    return record and (record.isboss == true or (record.grade and record.grade.isboss == true))
end

local function boundedUsers(value)
    if type(value) == 'string' then
        if #value > Config.maxSharedMemberBytes then return {} end
        local ok, decoded = pcall(json.decode, value)
        value = ok and decoded or nil
    end
    if type(value) ~= 'table' then return {} end

    local result, seen = {}, {}
    for _, citizenid in ipairs(value) do
        if type(citizenid) == 'string' and #citizenid <= 16 and not seen[citizenid] then
            result[#result + 1] = citizenid
            seen[citizenid] = true
            if #result >= Config.maxSharedMembers then break end
        end
    end
    return result
end

local function users(account)
    return boundedUsers(account.users)
end

local function consumeMemberRequest(src)
    local limit = Config.memberRateLimit
    local current = GetGameTimer()
    local cutoff = current - limit.window
    local bucket = MemberRequests[src] or {}
    local retained = {}
    for i = 1, #bucket do
        if bucket[i] > cutoff then retained[#retained + 1] = bucket[i] end
    end
    if #retained >= limit.max then
        MemberRequests[src] = retained
        return false
    end
    retained[#retained + 1] = current
    MemberRequests[src] = retained
    return true
end

local function isMember(account, citizenid)
    if account.citizenid == citizenid then return true end
    for _, member in ipairs(users(account)) do
        if member == citizenid then return true end
    end
    return false
end

local function mayUse(data, account)
    if not account then return false end
    if account.account_type == 'shared' then return isMember(account, data.citizenid) end
    if account.account_type == 'job' then return data.job and data.job.name == account.account_name and boss(data.job) end
    if account.account_type == 'gang' then return data.gang and data.gang.name == account.account_name and boss(data.gang) end
    return false
end

local function mayManage(data, account)
    if account.account_type == 'shared' then return account.citizenid == data.citizenid end
    return mayUse(data, account)
end

local function displayName(data, account)
    if account.account_type == 'job' and data.job and data.job.name == account.account_name then return data.job.label end
    if account.account_type == 'gang' and data.gang and data.gang.name == account.account_name then return data.gang.label end
    return account.account_name:gsub('[_%-]+', ' '):gsub('(%a)([%w]*)', function(a, b) return a:upper() .. b end)
end

local function statement(src, accountName, amount, reason, kind, citizenid)
    citizenid = citizenid or (src and src > 0 and exports.qbcore:getPlayerData(src, { 'citizenid' }) or nil)
    local id = QB.sql.insert(
        'INSERT INTO bank_statements (citizenid, account_name, amount, reason, statement_type) VALUES (?, ?, ?, ?, ?)',
        { citizenid, accountName, amount, cleanText(reason, kind == 'deposit' and 'Deposit' or 'Withdrawal', 50), kind }
    )
    return id ~= nil and id ~= false
end

local function refreshAccount(name)
    local row = QB.sql.single('SELECT * FROM bank_accounts WHERE account_name = ?', { name })
    Accounts[name] = row
    return row
end

local function createAccount(name, balance, kind, citizenid, memberJson)
    if Accounts[name] then return false end
    if kind == 'shared' then
        memberJson = json.encode(boundedUsers(memberJson))
        if #memberJson > Config.maxSharedMemberBytes then return false end
    end
    local id = QB.sql.insert(
        'INSERT INTO bank_accounts (citizenid, account_name, account_balance, account_type, users) VALUES (?, ?, ?, ?, ?)',
        { citizenid, name, balance or 0, kind, memberJson or '[]' }
    )
    if not id then return false end
    refreshAccount(name)
    return id
end

local function ensureOrganizationAccounts(data)
    local job = data.job
    if boss(job) and type(job.name) == 'string' and not Accounts[job.name] then
        createAccount(job.name, 0, 'job')
    end

    local gang = data.gang
    if boss(gang) and type(gang.name) == 'string' and not Accounts[gang.name] then
        createAccount(gang.name, 0, 'gang')
    end
end

local function adjustAccount(name, delta)
    delta = math.floor(tonumber(delta) or 0)
    if delta == 0 or not Accounts[name] then return false end
    local changed
    if delta < 0 then
        changed = QB.sql.update(
            'UPDATE bank_accounts SET account_balance = account_balance + ? WHERE account_name = ? AND account_balance >= ?',
            { delta, name, -delta }
        )
    else
        changed = QB.sql.update('UPDATE bank_accounts SET account_balance = account_balance + ? WHERE account_name = ?', { delta, name })
    end
    if not changed or changed < 1 then return false end
    refreshAccount(name)
    return true
end

local function accountRows(data, mode)
    local rows = {
        {
            name = 'checking', type = 'checking', label = 'Personal bank', owner = 'Only you',
            balance = tonumber(data.money and data.money.bank) or 0, canManage = false,
        },
    }
    if mode == 'atm' then return rows end
    for name, account in pairs(Accounts) do
        if mayUse(data, account) then
            local kind = account.account_type
            rows[#rows + 1] = {
                name = name,
                type = kind,
                label = kind == 'job' and 'Society bank' or kind == 'gang' and 'Gang bank' or 'Shared bank',
                owner = displayName(data, account),
                balance = tonumber(account.account_balance) or 0,
                canManage = mayManage(data, account),
                users = kind == 'shared' and users(account) or nil,
            }
        end
    end
    table.sort(rows, function(a, b)
        local priority = { checking = 1, job = 2, gang = 3, shared = 4 }
        local left, right = priority[a.type] or 9, priority[b.type] or 9
        return left == right and a.owner < b.owner or left < right
    end)
    return rows
end

local function transactionRows(data, accountRowsList)
    local result = {}
    for _, account in ipairs(accountRowsList) do
        local rows
        if account.name == 'checking' then
            rows = QB.sql.query(
                'SELECT id, citizenid, account_name, amount, reason, statement_type, date FROM bank_statements WHERE citizenid = ? AND account_name = ? ORDER BY id DESC LIMIT 50',
                { data.citizenid, 'checking' }
            ) or {}
        else
            rows = QB.sql.query(
                'SELECT id, citizenid, account_name, amount, reason, statement_type, date FROM bank_statements WHERE account_name = ? ORDER BY id DESC LIMIT 50',
                { account.name }
            ) or {}
        end
        result[account.name] = rows
    end
    return result
end

local cardRows
local dailyWithdrawalRemaining

local function snapshot(src, mode, unlocked)
    local data, err = player(src)
    if not data then return nil, err end
    if mode == 'bank' then ensureOrganizationAccounts(data) end
    local list = accountRows(data, mode)
    local info = data.charinfo or {}
    return {
        mode = mode,
        locked = mode == 'atm' and not unlocked,
        profile = {
            name = cleanText(('%s %s'):format(info.firstname or '', info.lastname or ''), GetPlayerName(src), 80),
            accountNumber = data.citizenid,
            cash = tonumber(data.money and data.money.cash) or 0,
            cards = cardRows(src),
        },
        accounts = unlocked == false and {} or list,
        transactions = unlocked == false and {} or transactionRows(data, list),
        limits = { daily = Config.useDailyLimit and dailyWithdrawalRemaining(data) or nil, maxAccounts = Config.maxAccounts },
    }
end

local function nearBranch(src, index)
    local location = Config.locations[tonumber(index)]
    if not location then return false end
    local ped = GetPlayerPed(src)
    if ped == 0 then return false end
    return #(GetEntityCoords(ped) - location) <= 3.0
end

local function nearAtm(src, location)
    if type(location) ~= 'table' then return false end
    local x, y, z = tonumber(location.x), tonumber(location.y), tonumber(location.z)
    if not x or not y or not z then return false end
    if x ~= x or y ~= y or z ~= z or math.abs(x) > 10000 or math.abs(y) > 10000 or math.abs(z) > 2000 then return false end
    local ped = GetPlayerPed(src)
    if ped == 0 then return false end
    return #(GetEntityCoords(ped) - vector3(x, y, z)) <= Config.atmDistance + 1.0
end

local function session(src, mode, unlocked, location)
    Sessions[src] = { mode = mode, unlocked = unlocked == true, location = location, attempts = 0, expires = os.time() + 300 }
end

local function activeSession(src)
    local current = Sessions[src]
    if not current or current.expires < os.time() then Sessions[src] = nil return nil end
    if current.mode == 'bank' and not nearBranch(src, current.location) then Sessions[src] = nil return nil end
    if current.mode == 'atm' and not nearAtm(src, current.location) then Sessions[src] = nil return nil end
    current.expires = os.time() + 300
    return current
end

local function hasBankCard(src)
    return exports.qbcore:getItemByName(src, 'bank_card') ~= nil
end

local function cardPins(src)
    local citizenid = exports.qbcore:getPlayerData(src, { 'citizenid' })
    if not citizenid then return {} end
    local items = exports.qbcore:getItemsByName(src, 'bank_card') or {}
    local pins = {}
    for _, item in pairs(items) do
        local info = item.info
        local pin = info and tonumber(info.cardPin)
        if pin and info.citizenid == citizenid then pins[('%04d'):format(math.floor(pin))] = true end
    end
    return pins
end

cardRows = function(src)
    local rows = {}
    for _, item in pairs(exports.qbcore:getItemsByName(src, 'bank_card') or {}) do
        local info = item.info or {}
        local number = tostring(info.cardNumber or '')
        rows[#rows + 1] = { name = info.name or 'Bank card', number = #number >= 4 and ('**** %s'):format(number:sub(-4)) or 'Issued card' }
    end
    return rows
end

dailyWithdrawalRemaining = function(data)
    local used = QB.sql.scalar(
        "SELECT COALESCE(SUM(amount), 0) FROM bank_statements WHERE citizenid = ? AND account_name = 'checking' AND statement_type = 'withdraw' AND date >= CURRENT_DATE()",
        { data.citizenid }
    ) or 0
    return math.max(0, Config.dailyLimit - (tonumber(used) or 0))
end

local function sourceAccount(data, name)
    if name == 'checking' then return { account_name = 'checking', account_type = 'checking' } end
    local account = Accounts[name]
    if not mayUse(data, account) then return nil end
    return account
end

local function debit(src, data, account, amount, reason)
    if account.account_name == 'checking' then
        if (tonumber(data.money.bank) or 0) < amount then return false end
        return exports.qbcore:removeMoney(src, 'bank', amount, reason, true) == true
    end
    return adjustAccount(account.account_name, -amount)
end

local function credit(src, account, amount, reason)
    if account.account_name == 'checking' then return exports.qbcore:addMoney(src, 'bank', amount, reason, true) == true end
    return adjustAccount(account.account_name, amount)
end

local function transactCash(src, data, current, payload)
    local amount = roundAmount(payload.amount)
    if not amount then return nil, 'Enter a valid amount.' end
    local account = sourceAccount(data, payload.account)
    if not account then return nil, 'You cannot use that account.' end
    if current.mode == 'atm' and account.account_name ~= 'checking' then return nil, 'ATMs only support your personal account.' end
    local reason = cleanText(payload.reason, payload.kind == 'deposit' and 'Cash deposit' or 'Cash withdrawal', 50)

    if payload.kind == 'deposit' then
        if (tonumber(data.money.cash) or 0) < amount then return nil, 'You do not have that much cash.' end
        if not exports.qbcore:removeMoney(src, 'cash', amount, reason, true) then return nil, 'The cash could not be deposited.' end
        if not credit(src, account, amount, reason) then
            exports.qbcore:addMoney(src, 'cash', amount, 'bank deposit rollback', true)
            return nil, 'The account could not be credited.'
        end
        statement(src, account.account_name, amount, reason, 'deposit')
        return ('Deposited $%s.'):format(amount)
    end

    if current.mode == 'atm' and Config.useDailyLimit then
        if amount > dailyWithdrawalRemaining(data) then
            return nil, 'Above the limit of what you may withdraw at this ATM.'
        end
    end
    if not debit(src, data, account, amount, reason) then return nil, 'That account does not have enough money.' end
    if not exports.qbcore:addMoney(src, 'cash', amount, reason, true) then
        credit(src, account, amount, 'bank withdrawal rollback')
        return nil, 'The cash could not be issued.'
    end
    statement(src, account.account_name, amount, reason, 'withdraw')
    return ('Withdrew $%s.'):format(amount)
end

local function transfer(src, data, payload)
    local amount = roundAmount(payload.amount)
    if not amount then return nil, 'Enter a valid amount.' end
    local from = sourceAccount(data, payload.from)
    if not from then return nil, 'You cannot use the source account.' end
    local reason = cleanText(payload.reason, 'Bank transfer', 50)

    if payload.to then
        local destination = sourceAccount(data, payload.to)
        if not destination then return nil, 'You cannot use the destination account.' end
        if destination.account_name == from.account_name then return nil, 'Choose two different accounts.' end
        if not debit(src, data, from, amount, reason) then return nil, 'The source account does not have enough money.' end
        if not credit(src, destination, amount, reason) then
            credit(src, from, amount, 'transfer rollback')
            return nil, 'The destination account could not be credited.'
        end
        statement(src, from.account_name, amount, reason, 'withdraw')
        statement(src, destination.account_name, amount, reason, 'deposit')
        return ('Transferred $%s.'):format(amount)
    end

    local citizenid = cleanText(payload.recipient, nil, 16)
    if not citizenid then return nil, 'Enter an account number.' end
    local recipient = exports.qbcore:getPlayerByCitizenId(citizenid)
    if not recipient or not recipient.source then return nil, 'That account holder must be online.' end
    if citizenid == data.citizenid then return nil, 'Use an internal transfer for your own accounts.' end
    if not debit(src, data, from, amount, reason) then return nil, 'The source account does not have enough money.' end
    if not exports.qbcore:addMoney(recipient.source, 'bank', amount, reason, true) then
        credit(src, from, amount, 'transfer rollback')
        return nil, 'The recipient could not be credited.'
    end
    statement(src, from.account_name, amount, reason, 'withdraw')
    statement(recipient.source, 'checking', amount, reason, 'deposit', citizenid)
    return ('Sent $%s.'):format(amount)
end

local function manage(src, data, payload)
    if payload.kind == 'orderCard' then
        local pin = tostring(payload.pin or '')
        if not pin:match('^%d%d%d%d$') then return nil, 'Choose a 4-digit PIN.' end
        local info = data.charinfo or {}
        local added = exports.qbcore:addItem(src, 'bank_card', 1, nil, {
            citizenid = data.citizenid,
            name = cleanText(('%s %s'):format(info.firstname or '', info.lastname or ''), data.citizenid, 80),
            cardNumber = tostring(math.random(10000000, 99999999)) .. tostring(math.random(10000000, 99999999)),
            cardPin = tonumber(pin),
        }, 'qbbanking:order-card')
        if not added then return nil, 'There is no room for a bank card.' end
        return 'Bank card issued.'
    end

    if payload.kind == 'create' then
        local name = cleanText(payload.name, nil, 40)
        if tonumber(payload.amount) == 0 then return nil, 'You can not open a shared account with $0' end
        local amount = roundAmount(payload.amount)
        if not name or #name < 3 then return nil, 'Account names need at least 3 characters.' end
        if not name:match('^[%w][%w _%-]+$') then return nil, 'Use letters, numbers, spaces, dashes or underscores.' end
        if not amount then return nil, 'Enter an opening balance.' end
        local count = 0
        for _, account in pairs(Accounts) do if account.citizenid == data.citizenid then count = count + 1 end end
        if count >= Config.maxAccounts then return nil, ('You can own up to %d shared accounts.'):format(Config.maxAccounts) end
        if Accounts[name] then return nil, 'That account name is already in use.' end
        if (tonumber(data.money.bank) or 0) < amount then return nil, 'Your personal account does not have enough money.' end
        if not exports.qbcore:removeMoney(src, 'bank', amount, 'Open shared account', true) then return nil, 'The opening balance could not be withdrawn.' end
        if not createAccount(name, amount, 'shared', data.citizenid, '[]') then
            exports.qbcore:addMoney(src, 'bank', amount, 'account creation rollback', true)
            return nil, 'The shared account could not be created.'
        end
        statement(src, 'checking', amount, 'Opened ' .. name, 'withdraw')
        statement(src, name, amount, 'Opening balance', 'deposit')
        return 'Shared account created.'
    end

    local account = Accounts[payload.account]
    if not account or account.account_type ~= 'shared' or account.citizenid ~= data.citizenid then
        return nil, 'Only the account owner can make that change.'
    end
    if payload.kind == 'rename' then
        local name = cleanText(payload.name, nil, 40)
        if not name or #name < 3 or not name:match('^[%w][%w _%-]+$') then return nil, 'Enter a valid account name.' end
        if Accounts[name] then return nil, 'That account name is already in use.' end
        local changed = QB.sql.update('UPDATE bank_accounts SET account_name = ? WHERE account_name = ? AND citizenid = ?', { name, account.account_name, data.citizenid })
        if not changed or changed < 1 then return nil, 'The account could not be renamed.' end
        QB.sql.update('UPDATE bank_statements SET account_name = ? WHERE account_name = ?', { name, account.account_name })
        Accounts[account.account_name] = nil
        refreshAccount(name)
        return 'Shared account renamed.'
    elseif payload.kind == 'delete' then
        if tonumber(account.account_balance) ~= 0 then return nil, 'Move the remaining balance before closing this account.' end
        local changed = QB.sql.update('DELETE FROM bank_accounts WHERE account_name = ? AND citizenid = ?', { account.account_name, data.citizenid })
        if not changed or changed < 1 then return nil, 'The account could not be closed.' end
        Accounts[account.account_name] = nil
        return 'Shared account closed.'
    elseif payload.kind == 'addMember' or payload.kind == 'removeMember' then
        if not consumeMemberRequest(src) then return nil, 'Wait before changing account access again.' end
        local citizenid = cleanText(payload.citizenid, nil, 16)
        if not citizenid then return nil, 'Enter a citizen ID.' end
        local list, found = users(account), false
        for index = #list, 1, -1 do
            if list[index] == citizenid then
                found = true
                if payload.kind == 'removeMember' then table.remove(list, index) end
            end
        end
        if payload.kind == 'addMember' then
            if found then return nil, 'That person already has access.' end
            if #list >= Config.maxSharedMembers then
                return nil, ('Shared accounts support up to %d members.'):format(Config.maxSharedMembers)
            end
            if not QB.sql.scalar('SELECT citizenid FROM players WHERE citizenid = ? LIMIT 1', { citizenid }) then
                return nil, 'No character has that citizen ID.'
            end
            list[#list + 1] = citizenid
        elseif not found then return nil, 'That person does not have access.' end
        local encoded = json.encode(list)
        if #encoded > Config.maxSharedMemberBytes then return nil, 'The account access list is too large.' end
        local changed = QB.sql.update('UPDATE bank_accounts SET users = ? WHERE account_name = ? AND citizenid = ?', { encoded, account.account_name, data.citizenid })
        if not changed or changed < 1 then return nil, 'Account access could not be updated.' end
        account.users = encoded
        return payload.kind == 'addMember' and 'Account access granted.' or 'Account access removed.'
    end
    return nil, 'Unknown account action.'
end

local function openBanking(src, mode, location)
    if not ready then return nil, 'Banking is still starting.' end
    mode = mode == 'atm' and 'atm' or 'bank'
    if mode == 'atm' then
        if not hasBankCard(src) then return nil, 'You need a bank card to use an ATM.' end
        if not nearAtm(src, location) then return nil, 'Move closer to an ATM.' end
        session(src, mode, false, location)
        return snapshot(src, mode, false)
    end
    if not nearBranch(src, location) then return nil, 'Move closer to a bank counter.' end
    session(src, mode, true, location)
    return snapshot(src, mode, true)
end

local function openCallback(src, mode, location)
    local ok, result, err = pcall(openBanking, src, mode, location)
    if ok then return result, err end
    print(('^1[qbbanking]^7 open failed for %s: %s'):format(src, tostring(result)))
    return nil, 'The bank encountered an internal error.'
end

local function pinCallback(src, pin)
    local current = activeSession(src)
    if not current or current.mode ~= 'atm' then return nil, 'Open an ATM first.' end
    if current.lockedUntil and current.lockedUntil > os.time() then return nil, 'Too many attempts. Wait a moment and try again.' end
    if not hasBankCard(src) then return nil, 'You need a bank card to use an ATM.' end
    local value = tostring(pin or '')
    if not value:match('^%d%d%d%d$') or not cardPins(src)[value] then
        current.attempts = current.attempts + 1
        if current.attempts >= 5 then
            current.attempts = 0
            current.lockedUntil = os.time() + 30
            return nil, 'Too many attempts. Wait 30 seconds and try again.'
        end
        return nil, 'Incorrect PIN.'
    end
    current.unlocked = true
    return snapshot(src, 'atm', true)
end

local function actionCallback(src, payload)
    if type(payload) ~= 'table' then return nil, 'Invalid request.' end
    local current = activeSession(src)
    if not current or not current.unlocked then return nil, 'Your banking session expired.' end
    local data, err = player(src)
    if not data then return nil, err end
    local message, actionErr
    if payload.kind == 'deposit' or payload.kind == 'withdraw' then
        message, actionErr = transactCash(src, data, current, payload)
    elseif payload.kind == 'transfer' then
        if current.mode == 'atm' then return nil, 'Transfers are available inside a bank.' end
        message, actionErr = transfer(src, data, payload)
    elseif current.mode == 'bank' then
        message, actionErr = manage(src, data, payload)
    else
        return nil, 'That action is not available at an ATM.'
    end
    if not message then return nil, actionErr end
    return { message = message, snapshot = snapshot(src, current.mode, true) }
end

local function registerCallbacks()
    QB.callback.register('qbbanking:open', openCallback)
    QB.callback.register('qbbanking:pin', pinCallback)
    QB.callback.register('qbbanking:action', actionCallback)
end

registerCallbacks()

-- Banking's own request channel is deliberately independent from qblib's
-- callback registry. A live qblib reload must not make open/PIN/action
-- requests disappear while qbbanking itself remains running.
RegisterNetEvent('qbbanking:server:request', function(requestId, operation, ...)
    local src = source
    if type(requestId) ~= 'number' or requestId % 1 ~= 0 or requestId < 1 then return end

    local handler = operation == 'open' and openCallback
        or operation == 'pin' and pinCallback
        or operation == 'action' and actionCallback
    if not handler then
        return TriggerClientEvent('qbbanking:client:response', src, requestId, nil, 'Invalid banking request.')
    end

    local ok, result, err = pcall(handler, src, ...)
    if not ok then
        print(('^1[qbbanking]^7 %s request failed for %s: %s'):format(operation, src, tostring(result)))
        return TriggerClientEvent('qbbanking:client:response', src, requestId, nil, 'The bank encountered an internal error.')
    end
    TriggerClientEvent('qbbanking:client:response', src, requestId, result, err)
end)

-- qblib owns callback registrations. Reinstall ours after a live qblib
-- restart so bank and ATM requests never point at a cleared registry.
AddEventHandler('onResourceStart', function(resource)
    if resource ~= 'qblib' then return end
    SetTimeout(0, registerCallbacks)
end)

local function createPlayerAccount(playerId, accountName, accountBalance, accountUsers)
    local data = exports.qbcore:getPlayerData(playerId)
    if not data then return false end
    return createAccount(accountName, math.max(0, math.floor(tonumber(accountBalance) or 0)), 'shared', data.citizenid, accountUsers)
end
exports('CreatePlayerAccount', createPlayerAccount)

local function createJobAccount(name, balance) return createAccount(name, balance, 'job') end
local function createGangAccount(name, balance) return createAccount(name, balance, 'gang') end
exports('CreateJobAccount', createJobAccount)
exports('CreateGangAccount', createGangAccount)

local function createBankStatement(playerId, account, amount, reason, kind, accountType)
    if accountType == 'player' then account = 'checking' end
    return statement(playerId, account, math.floor(tonumber(amount) or 0), reason, kind)
end
exports('CreateBankStatement', createBankStatement)

-- qbsql logs history failures; a committed balance change must still report success.
local function addMoney(name, amount, reason)
    amount = roundAmount(amount)
    if not amount or not adjustAccount(name, amount) then return false end
    statement(0, name, amount, reason or 'External deposit', 'deposit', nil)
    return true
end
local function removeMoney(name, amount, reason)
    amount = roundAmount(amount)
    if not amount or not adjustAccount(name, -amount) then return false end
    statement(0, name, amount, reason or 'External withdrawal', 'withdraw', nil)
    return true
end
exports('AddMoney', addMoney)
exports('AddGangMoney', addMoney)
exports('RemoveMoney', removeMoney)
exports('RemoveGangMoney', removeMoney)
exports('GetAccount', function(name) return Accounts[name] end)
exports('GetGangAccount', function(name) return Accounts[name] end)
exports('GetAccountBalance', function(name) return Accounts[name] and tonumber(Accounts[name].account_balance) or 0 end)

exports.qbcore:createUseable('bank_card', function(src)
    if hasBankCard(src) then TriggerClientEvent('qbbanking:client:useCard', src) end
end)

exports.qbcore:addCommand('givecash', 'Give nearby player cash', {
    { name = 'id', help = 'Player ID' }, { name = 'amount', help = 'Amount' },
}, true, function(src, args)
    local target, amount = tonumber(args[1]), roundAmount(args[2])
    if not target or not amount then return QB.notify.send(src, { title = 'Banking', message = 'Enter a valid player and amount.', type = 'error' }) end
    local from, to = player(src), exports.qbcore:getPlayerData(target)
    if not from or not to then return QB.notify.send(src, { title = 'Banking', message = 'Player not found.', type = 'error' }) end
    local a, b = GetEntityCoords(GetPlayerPed(src)), GetEntityCoords(GetPlayerPed(target))
    if #(a - b) > 5.0 then return QB.notify.send(src, { title = 'Banking', message = 'That player is too far away.', type = 'error' }) end
    if not exports.qbcore:removeMoney(src, 'cash', amount, 'cash transfer', true) then return QB.notify.send(src, { title = 'Banking', message = 'You do not have enough cash.', type = 'error' }) end
    if not exports.qbcore:addMoney(target, 'cash', amount, 'cash transfer', true) then
        exports.qbcore:addMoney(src, 'cash', amount, 'cash transfer rollback', true)
        return QB.notify.send(src, { title = 'Banking', message = 'The transfer failed.', type = 'error' })
    end
    QB.notify.send(src, { title = 'Banking', message = ('Gave $%d.'):format(amount), type = 'success' })
    QB.notify.send(target, { title = 'Banking', message = ('Received $%d.'):format(amount), type = 'success' })
end)

RegisterNetEvent('qbbanking:close', function() Sessions[source] = nil end)
AddEventHandler('playerDropped', function()
    Sessions[source] = nil
    MemberRequests[source] = nil
end)

CreateThread(function()
    local available, readyErr = QB.sql.ready(60000)
    if not available then
        print(('^1[qbbanking]^7 database unavailable: %s'):format(readyErr or 'unknown error'))
        return
    end
    local dateColumn = QB.sql.single("SHOW COLUMNS FROM bank_statements WHERE Field = 'date'")
    if dateColumn and type(dateColumn.Extra) == 'string' and dateColumn.Extra:lower():find('on update', 1, true) then
        QB.sql.query('ALTER TABLE bank_statements MODIFY date timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP')
    end
    local rows, loadErr = QB.sql.query('SELECT * FROM bank_accounts')
    if not rows then
        print(('^1[qbbanking]^7 account load failed: %s'):format(loadErr or 'unknown error'))
        return
    end
    for _, account in ipairs(rows) do Accounts[account.account_name] = account end
    local deadline = GetGameTimer() + 5000
    while QB.shared.epoch('jobs') == 0 and GetGameTimer() < deadline do Wait(25) end
    local jobs = QB.shared.all('jobs')
    for _, definition in ipairs(jobs) do
        local name = definition.name
        if name ~= 'unemployed' and not Accounts[name] then CreateJobAccount(name, 0) end
    end
    local gangs = QB.shared.all('gangs')
    for _, definition in ipairs(gangs) do
        local name = definition.name
        if name ~= 'none' and not Accounts[name] then CreateGangAccount(name, 0) end
    end
    ready = true
end)
