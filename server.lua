local Accounts = {}
local Sessions = {}
local ready = false
local durableHistory = false
AddEventHandler('kora_banking:durableReady', function() durableHistory = true end)

if not Kora.shared.get('items', 'bank_card') then
    local itemRegistered, itemError = Kora.shared.register('items', 'bank_card', {
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
        print(('^1[kora_banking]^7 bank card registration failed: %s'):format(itemError or 'unknown error'))
    end
end

local function roundAmount(value)
    local amount = tonumber(value)
    if not Kora.util.isFiniteNumber(amount) then return nil end
    amount = math.floor(amount)
    if amount <= 0 or amount > 1000000000 then return nil end
    return amount
end

-- Kora.sql.update returns the affected row count, or false/nil on failure -- this is "did it actually change anything".
local function applied(changed)
    return type(changed) == 'number' and changed >= 1
end

local MIN_LABELS = { withdraw = 'withdrawal', deposit = 'deposit', transfer = 'transfer' }

-- Read at use time so live config changes apply immediately; anything invalid falls back to 1.
local function minimumAmount(kind)
    local value = type(Config.minAmount) == 'table' and tonumber(Config.minAmount[kind]) or 1
    if not value or value ~= value or value < 1 then return 1 end
    return math.floor(value)
end

local function belowMinimum(kind, amount)
    local minimum = minimumAmount(kind)
    if amount < minimum then return ('Minimum %s is $%d.'):format(MIN_LABELS[kind], minimum) end
end

local function cleanText(value, fallback, maxLength)
    return Kora.util.cleanText(value, {
        maxLength = maxLength or 50,
        controlCharacters = 'preserve',
    }) or fallback
end

local function validAccountName(raw)
    local name = cleanText(raw, nil, 40)
    if not name or #name < 3 then return nil, 'Account names need at least 3 characters.' end
    if not name:match('^[%w][%w _%-]+$') then return nil, 'Use letters, numbers, spaces, dashes or underscores.' end
    return name
end

local function player(src)
    local data = exports.kora_core:getPlayerData(src)
    if not data then return nil, 'Player data is unavailable.' end
    return data
end

local function boss(record)
    return record and (record.isboss == true or (record.grade and record.grade.isboss == true))
end

local function boundedUsers(value)
    if type(value) == 'string' then
        if #value > Config.maxSharedMemberBytes then return {} end
        value = Kora.util.decodeJson(value)
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

-- Config.memberRateLimit requires a restart to change (see config.lua), so building the limiter once on first
-- use -- rather than at module load, before Config is necessarily populated -- is safe.
local memberRequestLimiter

local function consumeMemberRequest(src)
    if not memberRequestLimiter then
        memberRequestLimiter = Kora.util.rateLimiter(Config.memberRateLimit.max, Config.memberRateLimit.window)
    end
    return memberRequestLimiter:consume(src, GetGameTimer())
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
    citizenid = citizenid or (src and src > 0 and exports.kora_core:getPlayerData(src, { 'citizenid' }) or nil)
    local id = Kora.sql.insert(
        'INSERT INTO bank_statements (citizenid, account_name, amount, reason, statement_type) VALUES (?, ?, ?, ?, ?)',
        { citizenid, accountName, amount, cleanText(reason, kind == 'deposit' and 'Deposit' or 'Withdrawal', 50), kind }
    )
    return id ~= nil and id ~= false
end

local function refreshAccount(name)
    local row = Kora.sql.single('SELECT * FROM bank_accounts WHERE account_name = ?', { name })
    Accounts[name] = row
    return row
end

AddEventHandler('kora_banking:refreshAccount', refreshAccount)

local function createAccount(name, balance, kind, citizenid, memberJson)
    if Accounts[name] then return false end
    if kind == 'shared' then
        memberJson = json.encode(boundedUsers(memberJson))
        if #memberJson > Config.maxSharedMemberBytes then return false end
    end
    local id = Kora.sql.insert(
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
        changed = Kora.sql.update(
            'UPDATE bank_accounts SET account_balance = account_balance + ? WHERE account_name = ? AND account_balance >= ?',
            { delta, name, -delta }
        )
    else
        changed = Kora.sql.update('UPDATE bank_accounts SET account_balance = account_balance + ? WHERE account_name = ?', { delta, name })
    end
    if not applied(changed) then return false end
    refreshAccount(name)
    return true
end

local ACCOUNT_TYPE_PRIORITY = { checking = 1, job = 2, gang = 3, shared = 4 }

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
        local left, right = ACCOUNT_TYPE_PRIORITY[a.type] or 9, ACCOUNT_TYPE_PRIORITY[b.type] or 9
        return left == right and a.owner < b.owner or left < right
    end)
    return rows
end

-- Both halves of the UNION select the date as UNIX_TIMESTAMP(...)*1000 so the column type no longer depends on
-- bank_statements (timestamp) versus bank_operation_legs (datetime) or on how the SQL driver returns dates.
-- Both sides of the UNION pin the same collation: installs where bank_operation_legs was created
-- with the server default (not the schema's utf8mb4_unicode_ci) otherwise fail with "Illegal mix of collations".
local COLLATION = 'COLLATE utf8mb4_unicode_ci'
local STATEMENT_COLUMNS = ('id, citizenid %s AS citizenid, account_name %s AS account_name, amount, reason %s AS reason, statement_type %s AS statement_type, CAST(UNIX_TIMESTAMP(date) * 1000 AS UNSIGNED) AS date'):format(COLLATION, COLLATION, COLLATION, COLLATION)
local LEG_ID = ("CONCAT('operation:',id) %s"):format(COLLATION)

local function transactionRows(data, accountRowsList)
    local result = {}
    for _, account in ipairs(accountRowsList) do
        local rows
        if account.name == 'checking' then
            local sql = 'SELECT ' .. STATEMENT_COLUMNS .. ' FROM bank_statements WHERE citizenid = ? AND account_name = ?'
            local params = { data.citizenid, 'checking' }
            if durableHistory then
                sql = sql .. (' UNION ALL SELECT %s,citizenid %s,\'checking\' %s,amount,reason %s,direction %s,CAST(UNIX_TIMESTAMP(created_at) * 1000 AS UNSIGNED) FROM bank_operation_legs WHERE citizenid = ? ORDER BY date DESC,id DESC LIMIT 50')
                    :format(LEG_ID, COLLATION, COLLATION, COLLATION, COLLATION)
                params[3] = data.citizenid
            else sql = sql .. ' ORDER BY id DESC LIMIT 50' end
            rows = Kora.sql.query(sql, params) or {}
        else
            local sql = 'SELECT ' .. STATEMENT_COLUMNS .. ' FROM bank_statements WHERE account_name = ?'
            local params = { account.name }
            if durableHistory then
                sql = sql .. (' UNION ALL SELECT %s,citizenid %s,account_name %s,amount,reason %s,direction %s,CAST(UNIX_TIMESTAMP(created_at) * 1000 AS UNSIGNED) FROM bank_operation_legs WHERE account_name = ? ORDER BY date DESC,id DESC LIMIT 50')
                    :format(LEG_ID, COLLATION, COLLATION, COLLATION, COLLATION)
                params[2] = account.name
            else sql = sql .. ' ORDER BY id DESC LIMIT 50' end
            rows = Kora.sql.query(sql, params) or {}
        end
        -- Whatever the driver returns for the date column (number, string, table), the NUI gets Unix ms or nil.
        for _, row in ipairs(rows) do row.date = BankingDates.normalize(row.date) end
        result[account.name] = rows
    end
    return result
end

local cardRows
local dailyWithdrawalRemaining

local function snapshot(src, mode, unlocked, branch)
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
        branch = mode == 'bank' and branch and branch.enabled and branch.tier and {
            label = branch.label, tier = branch.tier, tierLabel = branch.tierLabel, gated = BankingTiers.gated(branch),
        } or nil,
        dates = { format = Config.dateFormat, showTime = Config.showTime, timeZone = BankingDates.timeZoneMode(Config.dateTimezone) },
        limits = { daily = Config.useDailyLimit and dailyWithdrawalRemaining(data) or nil, maxAccounts = Config.maxAccounts,
            min = { withdraw = minimumAmount('withdraw'), deposit = minimumAmount('deposit'), transfer = minimumAmount('transfer') },
            maxTransfer = BankingTiers.limit(branch, 'maxTransfer'),
            counterDaily = BankingTiers.limit(branch, 'dailyWithdraw') and dailyWithdrawalRemaining(data, BankingTiers.limit(branch, 'dailyWithdraw')) or nil },
    }
end

local BRANCH_RANGE = 3.0

-- The branch (with its tier) the player is physically standing at: the nearest configured location in range.
-- The client-sent index only has to name a real location; the tier never comes from the client.
local function branchAt(src, index)
    if not BankingTiers.entry(Config.locations[tonumber(index)]) then return nil end
    local ped = GetPlayerPed(src)
    if ped == 0 then return nil end
    return BankingTiers.resolve(GetEntityCoords(ped), BRANCH_RANGE)
end

-- Returns an error message when the branch's tier blocks the feature (always nil while tiers are disabled).
local function tierBlocks(branch, feature, what)
    if BankingTiers.can(branch, feature) then return nil end
    return ('%s is only available at %s.'):format(what, BankingTiers.availableAt(feature) or 'another branch')
end

local function nearAtm(src, location)
    if type(location) ~= 'table' then return false end
    local x, y, z = tonumber(location.x), tonumber(location.y), tonumber(location.z)
    if not x or not y or not z then return false end
    if x ~= x or y ~= y or z ~= z or math.abs(x) > 10000 or math.abs(y) > 10000 or math.abs(z) > 2000 then return false end
    local ped = GetPlayerPed(src)
    if ped == 0 then return false end
    return #(GetEntityCoords(ped) - vector3(x, y, z)) <= Config.atmDistance + (Config.atmTolerance or 1.0)
end

local function session(src, mode, unlocked, location)
    Sessions[src] = { mode = mode, unlocked = unlocked == true, location = location, attempts = 0, expires = os.time() + 300 }
end

local function activeSession(src)
    local current = Sessions[src]
    if not current or current.expires < os.time() then Sessions[src] = nil return nil end
    if current.mode == 'bank' then
        current.branch = branchAt(src, current.location)
        if not current.branch then Sessions[src] = nil return nil end
    end
    if current.mode == 'atm' and not nearAtm(src, current.location) then Sessions[src] = nil return nil end
    current.expires = os.time() + 300
    return current
end

local function hasBankCard(src)
    return exports.kora_core:getItemByName(src, 'bank_card') ~= nil
end

local function atmCardMissing(src)
    return Config.requireBankCard ~= false and not hasBankCard(src)
end

local function cardPins(src)
    local citizenid = exports.kora_core:getPlayerData(src, { 'citizenid' })
    if not citizenid then return {} end
    local items = exports.kora_core:getItemsByName(src, 'bank_card') or {}
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
    for _, item in pairs(exports.kora_core:getItemsByName(src, 'bank_card') or {}) do
        local info = item.info or {}
        local number = tostring(info.cardNumber or '')
        rows[#rows + 1] = { name = info.name or 'Bank card', number = #number >= 4 and ('**** %s'):format(number:sub(-4)) or 'Issued card' }
    end
    return rows
end

-- cap is a tier counter limit: those count the character's withdrawals from every account (shared ones too),
-- while the ATM allowance (no cap) only counts the personal account because ATMs only serve that account.
dailyWithdrawalRemaining = function(data, cap)
    local used = Kora.sql.scalar(
        "SELECT COALESCE(SUM(amount), 0) FROM bank_statements WHERE citizenid = ? AND (? = 1 OR account_name = 'checking') AND statement_type = 'withdraw' AND date >= CURRENT_DATE()",
        { data.citizenid, cap and 1 or 0 }
    ) or 0
    return math.max(0, (cap or Config.dailyLimit) - (tonumber(used) or 0))
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
        return exports.kora_core:removeMoney(src, 'bank', amount, reason, true) == true
    end
    return adjustAccount(account.account_name, -amount)
end

local function credit(src, account, amount, reason)
    if account.account_name == 'checking' then return exports.kora_core:addMoney(src, 'bank', amount, reason, true) == true end
    return adjustAccount(account.account_name, amount)
end

local function transactCash(src, data, current, payload)
    local amount = roundAmount(payload.amount)
    if not amount then return nil, 'Enter a valid amount.' end
    local account = sourceAccount(data, payload.account)
    if not account then return nil, 'You cannot use that account.' end
    if current.mode == 'atm' and account.account_name ~= 'checking' then return nil, 'ATMs only support your personal account.' end
    local reason = cleanText(payload.reason, payload.kind == 'deposit' and 'Cash deposit' or 'Cash withdrawal', 50)
    local tooSmall = belowMinimum(payload.kind == 'deposit' and 'deposit' or 'withdraw', amount)
    if tooSmall then return nil, tooSmall end
    local blocked = payload.kind == 'deposit' and tierBlocks(current.branch, 'deposit', 'Depositing cash')
        or payload.kind ~= 'deposit' and tierBlocks(current.branch, 'withdraw', 'Withdrawing cash') or nil
    if blocked then return nil, blocked end

    if payload.kind == 'deposit' then
        if (tonumber(data.money.cash) or 0) < amount then return nil, 'You do not have that much cash.' end
        if not exports.kora_core:removeMoney(src, 'cash', amount, reason, true) then return nil, 'The cash could not be deposited.' end
        if not credit(src, account, amount, reason) then
            exports.kora_core:addMoney(src, 'cash', amount, 'bank deposit rollback', true)
            return nil, 'The account could not be credited.'
        end
        statement(src, account.account_name, amount, reason, 'deposit')
        return ('Deposited $%s.'):format(amount)
    end

    if current.mode == 'atm' and Config.useDailyLimit and amount > dailyWithdrawalRemaining(data) then
        return nil, 'Above the limit of what you may withdraw at this ATM.'
    end
    local counterCap = current.mode == 'bank' and BankingTiers.limit(current.branch, 'dailyWithdraw') or nil
    if counterCap and amount > dailyWithdrawalRemaining(data, counterCap) then
        return nil, ('Above the daily withdrawal limit of $%d at %s.'):format(counterCap, current.branch.label or 'this bank')
    end
    if not debit(src, data, account, amount, reason) then return nil, 'That account does not have enough money.' end
    if not exports.kora_core:addMoney(src, 'cash', amount, reason, true) then
        credit(src, account, amount, 'bank withdrawal rollback')
        return nil, 'The cash could not be issued.'
    end
    statement(src, account.account_name, amount, reason, 'withdraw')
    return ('Withdrew $%s.'):format(amount)
end

local function transferSettings()
    local value = type(Config.Transfers) == 'table' and Config.Transfers or {}
    return { allowOffline = value.allowOffline ~= false, allowSharedAccounts = value.allowSharedAccounts ~= false, allowCardNumbers = value.allowCardNumbers ~= false }
end

-- Issued bank cards store their number in the item info (info.cardNumber, info.citizenid = issuing character).
local function findCardIssuer(node, number, depth)
    if type(node) ~= 'table' or depth > 6 then return nil end
    if tostring(node.cardNumber or '') == number and type(node.citizenid) == 'string' then return node.citizenid end
    for _, child in pairs(node) do
        local found = findCardIssuer(child, number, depth + 1)
        if found then return found end
    end
end

-- Resolves what the sender typed to a character (online or offline) or a shared / society / gang account:
-- citizen ID first, then account name, then bank card number.
local function resolveRecipient(ref, settings)
    local online = exports.kora_core:getPlayerByCitizenId(ref)
    if online and online.source then return { kind = 'player', citizenid = ref, source = online.source } end
    if settings.allowSharedAccounts then
        local account = Accounts[ref]
        if not account then
            local row = Kora.sql.single('SELECT account_name FROM bank_accounts WHERE account_name = ?', { ref })
            account = row and refreshAccount(row.account_name)
        end
        if account then return { kind = 'account', account = account } end
    end
    local function character(citizenid)
        local live = exports.kora_core:getPlayerByCitizenId(citizenid)
        if live and live.source then return { kind = 'player', citizenid = citizenid, source = live.source } end
        if Kora.sql.single('SELECT citizenid FROM players WHERE citizenid = ? AND deleted_at IS NULL', { citizenid }) then
            return { kind = 'player', citizenid = citizenid }
        end
    end
    local found = character(ref)
    if found then return found end
    if settings.allowCardNumbers and ref:match('^%d+$') and #ref >= 12 and #ref <= 19 then
        local rows = Kora.sql.query('SELECT citizenid, inventory FROM players WHERE deleted_at IS NULL AND inventory LIKE ?', { '%"cardNumber":"' .. ref .. '"%' }) or {}
        for _, row in ipairs(rows) do
            local inventory, decodeErr = Kora.util.decodeJson(row.inventory or '')
            local issuer = not decodeErr and findCardIssuer(inventory, ref, 0) or nil
            found = issuer and character(issuer) or nil
            if found then return found end
        end
    end
end

-- Offline recipients are credited in the database with the same guarded JSON update the durable ledger uses.
local function creditOffline(citizenid, amount)
    local changed = Kora.sql.update(
        [[UPDATE players SET money = JSON_SET(money, '$.bank', COALESCE(JSON_EXTRACT(money, '$.bank'), 0) + ?)
          WHERE citizenid = ? AND deleted_at IS NULL AND COALESCE(JSON_EXTRACT(money, '$.bank'), 0) + ? <= 9007199254740991]],
        { amount, citizenid, amount }
    )
    return applied(changed)
end

-- Debits `from`, then runs `creditDestination`; a failure at either step rolls the debit back.
-- Shared by every transfer() branch below -- only how the destination is credited differs.
local function moveFunds(src, data, from, amount, reason, creditDestination, creditFailureMessage)
    if not debit(src, data, from, amount, reason) then return nil, 'The source account does not have enough money.' end
    if not creditDestination() then
        credit(src, from, amount, 'transfer rollback')
        return nil, creditFailureMessage
    end
    return true
end

local function transfer(src, data, payload, branch)
    local amount = roundAmount(payload.amount)
    if not amount then return nil, 'Enter a valid amount.' end
    local from = sourceAccount(data, payload.from)
    if not from then return nil, 'You cannot use the source account.' end
    local reason = cleanText(payload.reason, 'Bank transfer', 50)
    local tooSmall = belowMinimum('transfer', amount)
    if tooSmall then return nil, tooSmall end
    local blocked = tierBlocks(branch, 'transfer', 'Transferring money')
    if blocked then return nil, blocked end
    local maxTransfer = BankingTiers.limit(branch, 'maxTransfer')
    if maxTransfer and amount > maxTransfer then
        local higher = BankingTiers.higherLimitAt('maxTransfer', maxTransfer)
        return nil, ('Transfers above $%d%s.'):format(maxTransfer, higher and (' are only available at ' .. higher) or ' are not allowed here')
    end

    if payload.to then
        local destination = sourceAccount(data, payload.to)
        if not destination then return nil, 'You cannot use the destination account.' end
        if destination.account_name == from.account_name then return nil, 'Choose two different accounts.' end
        local ok, err = moveFunds(src, data, from, amount, reason,
            function() return credit(src, destination, amount, reason) end,
            'The destination account could not be credited.')
        if not ok then return nil, err end
        statement(src, from.account_name, amount, reason, 'withdraw')
        statement(src, destination.account_name, amount, reason, 'deposit')
        return ('Transferred $%s.'):format(amount)
    end

    local ref = cleanText(payload.recipient, nil, 50)
    if not ref then return nil, 'Enter an account number.' end
    ref = ref:gsub('^%s+', ''):gsub('%s+$', ''):gsub('^(%d%d%d%d)[ %-](%d%d%d%d)[ %-](%d%d%d%d)[ %-](%d%d%d%d)$', '%1%2%3%4')
    local settings = transferSettings()
    local target = resolveRecipient(ref, settings)
    if not target then
        return nil, settings.allowOffline and 'No account was found with that number.' or 'That account holder must be online.'
    end

    if target.kind == 'account' then
        local name = target.account.account_name
        if name == from.account_name then return nil, 'Choose two different accounts.' end
        local ok, err = moveFunds(src, data, from, amount, reason,
            function() return credit(src, target.account, amount, reason) end,
            'The recipient could not be credited.')
        if not ok then return nil, err end
        statement(src, from.account_name, amount, reason, 'withdraw')
        statement(src, name, amount, reason, 'deposit')
        return ('Sent $%s.'):format(amount)
    end

    local citizenid = target.citizenid
    if citizenid == data.citizenid then return nil, 'Use an internal transfer for your own accounts.' end
    -- The holder may have logged in since the lookup; re-check so an online player is credited through their player object.
    local online = target.source and target or exports.kora_core:getPlayerByCitizenId(citizenid)
    local recipientSource = online and online.source or nil
    if not recipientSource and not settings.allowOffline then return nil, 'That account holder must be online.' end
    local ok, err = moveFunds(src, data, from, amount, reason,
        function()
            if recipientSource then return exports.kora_core:addMoney(recipientSource, 'bank', amount, reason, true) end
            return creditOffline(citizenid, amount)
        end,
        'The recipient could not be credited.')
    if not ok then return nil, err end
    statement(src, from.account_name, amount, reason, 'withdraw')
    statement(recipientSource, 'checking', amount, reason, 'deposit', citizenid)
    return ('Sent $%s.'):format(amount)
end

local MANAGE_FEATURES = {
    orderCard = { 'orderCard', 'Ordering a bank card' },
    create = { 'sharedAccounts', 'Opening a shared account' },
    rename = { 'sharedAccounts', 'Renaming a shared account' },
    delete = { 'sharedAccounts', 'Closing a shared account' },
    addMember = { 'manageMembers', 'Managing account members' },
    removeMember = { 'manageMembers', 'Managing account members' },
}

local function manage(src, data, payload, branch)
    local gate = MANAGE_FEATURES[payload.kind]
    local blocked = gate and tierBlocks(branch, gate[1], gate[2])
    if blocked then return nil, blocked end
    if payload.kind == 'orderCard' then
        local pin = tostring(payload.pin or '')
        if not pin:match('^%d%d%d%d$') then return nil, 'Choose a 4-digit PIN.' end
        local info = data.charinfo or {}
        local added = exports.kora_core:addItem(src, 'bank_card', 1, nil, {
            citizenid = data.citizenid,
            name = cleanText(('%s %s'):format(info.firstname or '', info.lastname or ''), data.citizenid, 80),
            cardNumber = tostring(math.random(10000000, 99999999)) .. tostring(math.random(10000000, 99999999)),
            cardPin = tonumber(pin),
        }, 'kora_banking:order-card')
        if not added then return nil, 'There is no room for a bank card.' end
        return 'Bank card issued.'
    end

    if payload.kind == 'create' then
        if tonumber(payload.amount) == 0 then return nil, 'You can not open a shared account with $0' end
        local amount = roundAmount(payload.amount)
        local name, nameErr = validAccountName(payload.name)
        if not name then return nil, nameErr end
        if not amount then return nil, 'Enter an opening balance.' end
        local count = 0
        for _, account in pairs(Accounts) do if account.citizenid == data.citizenid then count = count + 1 end end
        if count >= Config.maxAccounts then return nil, ('You can own up to %d shared accounts.'):format(Config.maxAccounts) end
        if Accounts[name] then return nil, 'That account name is already in use.' end
        if (tonumber(data.money.bank) or 0) < amount then return nil, 'Your personal account does not have enough money.' end
        if not exports.kora_core:removeMoney(src, 'bank', amount, 'Open shared account', true) then return nil, 'The opening balance could not be withdrawn.' end
        if not createAccount(name, amount, 'shared', data.citizenid, '[]') then
            exports.kora_core:addMoney(src, 'bank', amount, 'account creation rollback', true)
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
        local name = validAccountName(payload.name)
        if not name then return nil, 'Enter a valid account name.' end
        if Accounts[name] then return nil, 'That account name is already in use.' end
        local changed = Kora.sql.update('UPDATE bank_accounts SET account_name = ? WHERE account_name = ? AND citizenid = ?', { name, account.account_name, data.citizenid })
        if not applied(changed) then return nil, 'The account could not be renamed.' end
        Kora.sql.update('UPDATE bank_statements SET account_name = ? WHERE account_name = ?', { name, account.account_name })
        Accounts[account.account_name] = nil
        refreshAccount(name)
        return 'Shared account renamed.'
    elseif payload.kind == 'delete' then
        if tonumber(account.account_balance) ~= 0 then return nil, 'Move the remaining balance before closing this account.' end
        local changed = Kora.sql.update('DELETE FROM bank_accounts WHERE account_name = ? AND citizenid = ?', { account.account_name, data.citizenid })
        if not applied(changed) then return nil, 'The account could not be closed.' end
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
            if not Kora.sql.scalar('SELECT citizenid FROM players WHERE citizenid = ? LIMIT 1', { citizenid }) then
                return nil, 'No character has that citizen ID.'
            end
            list[#list + 1] = citizenid
        elseif not found then return nil, 'That person does not have access.' end
        local encoded = json.encode(list)
        if #encoded > Config.maxSharedMemberBytes then return nil, 'The account access list is too large.' end
        local changed = Kora.sql.update('UPDATE bank_accounts SET users = ? WHERE account_name = ? AND citizenid = ?', { encoded, account.account_name, data.citizenid })
        if not applied(changed) then return nil, 'Account access could not be updated.' end
        account.users = encoded
        return payload.kind == 'addMember' and 'Account access granted.' or 'Account access removed.'
    end
    return nil, 'Unknown account action.'
end

local function openBanking(src, mode, location)
    if not ready then return nil, 'Banking is still starting.' end
    mode = mode == 'atm' and 'atm' or 'bank'
    if mode == 'atm' then
        if atmCardMissing(src) then return nil, Config.atmNoCardMessage or 'You need a bank card to use an ATM.' end
        if not nearAtm(src, location) then return nil, 'Move closer to an ATM.' end
        local unlocked = Config.requireBankCard == false
        session(src, mode, unlocked, location)
        return snapshot(src, mode, unlocked)
    end
    if not branchAt(src, location) then return nil, 'Move closer to a bank counter.' end
    session(src, mode, true, location)
    return snapshot(src, mode, true, branchAt(src, location))
end

local function openCallback(src, mode, location)
    local ok, result, err = pcall(openBanking, src, mode, location)
    if ok then return result, err end
    print(('^1[kora_banking]^7 open failed for %s: %s'):format(src, tostring(result)))
    return nil, 'The bank encountered an internal error.'
end

-- Quick pre-check so the client can refuse before the animation and progress bar; openBanking stays the authority.
-- location is optional: the target visibility check asks for the card only, without a position.
local function atmCardCallback(src, location)
    if atmCardMissing(src) then return nil, Config.atmNoCardMessage or 'You need a bank card to use an ATM.' end
    if location ~= nil and not nearAtm(src, location) then return nil, 'Move closer to an ATM.' end
    return true
end

local function pinCallback(src, pin)
    local current = activeSession(src)
    if not current or current.mode ~= 'atm' then return nil, 'Open an ATM first.' end
    if current.lockedUntil and current.lockedUntil > os.time() then return nil, 'Too many attempts. Wait a moment and try again.' end
    if not hasBankCard(src) then return nil, Config.atmNoCardMessage or 'You need a bank card to use an ATM.' end
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

local function runAction(src, current, data, payload)
    local message, actionErr
    if payload.kind == 'deposit' or payload.kind == 'withdraw' then
        message, actionErr = transactCash(src, data, current, payload)
    elseif payload.kind == 'transfer' then
        if current.mode == 'atm' then return nil, 'Transfers are available inside a bank.' end
        message, actionErr = transfer(src, data, payload, current.branch)
    elseif current.mode == 'bank' then
        message, actionErr = manage(src, data, payload, current.branch)
    else
        return nil, 'That action is not available at an ATM.'
    end
    if not message then return nil, actionErr end
    return { message = message, snapshot = snapshot(src, current.mode, true, current.branch) }
end

local function actionCallback(src, payload)
    if type(payload) ~= 'table' then return nil, 'Invalid request.' end
    local current = activeSession(src)
    if not current or not current.unlocked then return nil, 'Your banking session expired.' end
    local data, err = player(src)
    if not data then return nil, err end
    -- Tier limit checks read the database before debiting; serialise a player's actions so two overlapping
    -- requests cannot both pass the same daily cap.
    if current.busy then return nil, 'Your previous banking request is still being processed.' end
    current.busy = true
    local ok, result, resultErr = pcall(runAction, src, current, data, payload)
    current.busy = nil
    if not ok then
        print(('^1[kora_banking]^7 action failed for %s: %s'):format(src, tostring(result)))
        return nil, 'The bank encountered an internal error.'
    end
    return result, resultErr
end

local function registerCallbacks()
    Kora.callback.register('kora_banking:open', openCallback)
    Kora.callback.register('kora_banking:pin', pinCallback)
    Kora.callback.register('kora_banking:action', actionCallback)
end

registerCallbacks()

-- Banking's own request channel is deliberately independent from kora_lib's
-- callback registry. A live kora_lib reload must not make open/PIN/action
-- requests disappear while kora_banking itself remains running.
RegisterNetEvent('kora_banking:server:request', function(requestId, operation, ...)
    local src = source
    if type(requestId) ~= 'number' or requestId % 1 ~= 0 or requestId < 1 then return end

    local handler = operation == 'open' and openCallback
        or operation == 'atmCard' and atmCardCallback
        or operation == 'pin' and pinCallback
        or operation == 'action' and actionCallback
    if not handler then
        return TriggerClientEvent('kora_banking:client:response', src, requestId, nil, 'Invalid banking request.')
    end

    local ok, result, err = pcall(handler, src, ...)
    if not ok then
        print(('^1[kora_banking]^7 %s request failed for %s: %s'):format(operation, src, tostring(result)))
        return TriggerClientEvent('kora_banking:client:response', src, requestId, nil, 'The bank encountered an internal error.')
    end
    TriggerClientEvent('kora_banking:client:response', src, requestId, result, err)
end)

-- kora_lib owns callback registrations. Reinstall ours after a live kora_lib
-- restart so bank and ATM requests never point at a cleared registry.
AddEventHandler('onResourceStart', function(resource)
    if resource ~= 'kora_lib' then return end
    SetTimeout(0, registerCallbacks)
end)

local function bankingExport(name, handler)
    exports(name, handler)
    Kora.compat.provideExport('qb-banking', name, handler)
end

local function createPlayerAccount(playerId, accountName, accountBalance, accountUsers)
    local data = exports.kora_core:getPlayerData(playerId)
    if not data then return false end
    return createAccount(accountName, math.max(0, math.floor(tonumber(accountBalance) or 0)), 'shared', data.citizenid, accountUsers)
end
bankingExport('CreatePlayerAccount', createPlayerAccount)

local function createJobAccount(name, balance) return createAccount(name, balance, 'job') end
local function createGangAccount(name, balance) return createAccount(name, balance, 'gang') end
bankingExport('CreateJobAccount', createJobAccount)
bankingExport('CreateGangAccount', createGangAccount)

local function createBankStatement(playerId, account, amount, reason, kind, accountType)
    if accountType == 'player' then account = 'checking' end
    return statement(playerId, account, math.floor(tonumber(amount) or 0), reason, kind)
end
bankingExport('CreateBankStatement', createBankStatement)

-- kora_sql logs history failures; a committed balance change must still report success.
local function addMoney(name, amount, reason)
    amount = roundAmount(amount)
    if not amount or not adjustAccount(name, amount) then return false end
    statement(0, name, amount, reason or 'External deposit', 'deposit')
    return true
end
local function removeMoney(name, amount, reason)
    amount = roundAmount(amount)
    if not amount or not adjustAccount(name, -amount) then return false end
    statement(0, name, amount, reason or 'External withdrawal', 'withdraw')
    return true
end
bankingExport('AddMoney', addMoney)
bankingExport('AddGangMoney', addMoney)
bankingExport('RemoveMoney', removeMoney)
bankingExport('RemoveGangMoney', removeMoney)
bankingExport('GetAccount', function(name) return Accounts[name] end)
bankingExport('GetGangAccount', function(name) return Accounts[name] end)
bankingExport('GetAccountBalance', function(name) return Accounts[name] and tonumber(Accounts[name].account_balance) or 0 end)

exports.kora_core:createUseable('bank_card', function(src)
    if hasBankCard(src) then TriggerClientEvent('kora_banking:client:useCard', src) end
end)

exports.kora_core:addCommand('givecash', 'Give nearby player cash', {
    { name = 'id', help = 'Player ID' }, { name = 'amount', help = 'Amount' },
}, true, function(src, args)
    local target, amount = tonumber(args[1]), roundAmount(args[2])
    if not target or not amount then return Kora.notify.send(src, { title = 'Banking', message = 'Enter a valid player and amount.', type = 'error' }) end
    local from, to = player(src), exports.kora_core:getPlayerData(target)
    if not from or not to then return Kora.notify.send(src, { title = 'Banking', message = 'Player not found.', type = 'error' }) end
    local a, b = GetEntityCoords(GetPlayerPed(src)), GetEntityCoords(GetPlayerPed(target))
    if #(a - b) > 5.0 then return Kora.notify.send(src, { title = 'Banking', message = 'That player is too far away.', type = 'error' }) end
    if not exports.kora_core:removeMoney(src, 'cash', amount, 'cash transfer', true) then return Kora.notify.send(src, { title = 'Banking', message = 'You do not have enough cash.', type = 'error' }) end
    if not exports.kora_core:addMoney(target, 'cash', amount, 'cash transfer', true) then
        exports.kora_core:addMoney(src, 'cash', amount, 'cash transfer rollback', true)
        return Kora.notify.send(src, { title = 'Banking', message = 'The transfer failed.', type = 'error' })
    end
    Kora.notify.send(src, { title = 'Banking', message = ('Gave $%d.'):format(amount), type = 'success' })
    Kora.notify.send(target, { title = 'Banking', message = ('Received $%d.'):format(amount), type = 'success' })
end)

RegisterNetEvent('kora_banking:close', function() Sessions[source] = nil end)
AddEventHandler('playerDropped', function()
    Sessions[source] = nil
end)

CreateThread(function()
    local available, readyErr = Kora.sql.ready(60000)
    if not available then
        print(('^1[kora_banking]^7 database unavailable: %s'):format(readyErr or 'unknown error'))
        return
    end
    -- Idempotent; guarantees bank_accounts/bank_statements exist before the first read (finance.lua ensures the same schema).
    local ensured, ensureErr = Kora.sql.ensureTables(KoraBankingSchema)
    if not ensured then
        print(('^1[kora_banking]^7 schema setup failed: %s'):format(ensureErr or 'unknown error'))
        return
    end
    local rows, loadErr = Kora.sql.query('SELECT * FROM bank_accounts')
    if not rows then
        print(('^1[kora_banking]^7 account load failed: %s'):format(loadErr or 'unknown error'))
        return
    end
    for _, account in ipairs(rows) do Accounts[account.account_name] = account end
    local deadline = GetGameTimer() + 5000
    while Kora.shared.epoch('jobs') == 0 and GetGameTimer() < deadline do Wait(25) end
    local jobs = Kora.shared.all('jobs')
    for _, definition in ipairs(jobs) do
        local name = definition.name
        if name ~= 'unemployed' and not Accounts[name] then
            if not createJobAccount(name, 0) then
                print(('^1[kora_banking]^7 job account creation failed for %s'):format(name))
                return
            end
        end
    end
    local gangs = Kora.shared.all('gangs')
    for _, definition in ipairs(gangs) do
        local name = definition.name
        if name ~= 'none' and not Accounts[name] then
            if not createGangAccount(name, 0) then
                print(('^1[kora_banking]^7 gang account creation failed for %s'):format(name))
                return
            end
        end
    end
    ready = true
end)
