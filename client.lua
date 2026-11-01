-- Banking presentation through kora_lib's shared AppShell. The server remains
-- the authority for every balance, card, proximity and account-access check.
-- kora_lib owns the browser frame and focus lifecycle.

local RESOURCE = GetCurrentResourceName()
local APP_ID = 'qbbanking:bank'
local REQUEST_TIMEOUT = 10000

local openingAtm = false
local nextRequestId = 0
local pendingRequests = {}
local currentSnapshot
local selectedAccount = 'checking'
local appOpen = false
local branchTargetIds = {}

local function notify(message, kind)
    Kora.notify.send({ title = 'Banking', message = message, type = kind or 'error' })
end

-- Keep banking's request transport independent from kora_lib's callback
-- registry, so a live kora_lib restart cannot strand a banking session.
local function request(operation, ...)
    nextRequestId = nextRequestId + 1
    if nextRequestId > 2147483647 then nextRequestId = 1 end

    local requestId = nextRequestId
    local response = promise.new()
    pendingRequests[requestId] = response
    TriggerServerEvent('qbbanking:server:request', requestId, operation, ...)

    SetTimeout(REQUEST_TIMEOUT, function()
        if pendingRequests[requestId] ~= response then return end
        pendingRequests[requestId] = nil
        response:resolve({ error = 'The bank did not answer. Try again.' })
    end)

    local reply = Citizen.Await(response)
    if type(reply) ~= 'table' then return nil, 'The bank did not answer. Try again.' end
    return reply.result, reply.error
end

RegisterNetEvent('qbbanking:client:response', function(requestId, result, err)
    local response = pendingRequests[requestId]
    if not response then return end
    pendingRequests[requestId] = nil
    response:resolve({ result = result, error = err })
end)

local function money(value)
    return ('$%s'):format(math.floor(tonumber(value) or 0))
end

local function accountByName(name)
    for _, account in ipairs((currentSnapshot and currentSnapshot.accounts) or {}) do
        if account.name == name then return account end
    end
end

local function accountOptions(accounts)
    local options = {}
    for _, account in ipairs(accounts or {}) do
        options[#options + 1] = {
            value = account.name,
            label = ('%s — %s'):format(account.owner or account.label or account.name, money(account.balance)),
        }
    end
    return options
end

local function managedAccountOptions(accounts)
    local options = {}
    for _, account in ipairs(accounts or {}) do
        if account.type == 'shared' and account.canManage then
            options[#options + 1] = { value = account.name, label = account.owner or account.name }
        end
    end
    return options
end

local function managedAccountItems(accounts)
    local items = {}
    for _, account in ipairs(accounts or {}) do
        if account.type == 'shared' and account.canManage then
            items[#items + 1] = {
                id = account.name, label = account.owner or account.name, description = account.name,
                badge = money(account.balance), icon = 'users',
                metadata = { { label = 'Available', value = money(account.balance) } },
            }
        end
    end
    return items
end

local function amountPresets()
    return {
        { label = '$50', value = 50 }, { label = '$100', value = 100 },
        { label = '$250', value = 250 }, { label = '$500', value = 500 },
    }
end

local function activityRows()
    local transactions = currentSnapshot and currentSnapshot.transactions and currentSnapshot.transactions[selectedAccount] or {}
    local rows = {}
    for _, transaction in ipairs(transactions) do
        local deposit = transaction.statement_type == 'deposit'
        rows[#rows + 1] = {
            id = transaction.id,
            type = { label = deposit and 'Deposit' or 'Withdrawal', badge = true, tone = deposit and 'success' or 'neutral' },
            amount = { label = (deposit and '+' or '-') .. money(transaction.amount), tone = deposit and 'success' or 'neutral' },
            dateMs = BankingDates.normalize(transaction.date),
            reason = transaction.reason or (deposit and 'Deposit' or 'Withdrawal'),
            date = BankingDates.safeFormat(transaction.date, {
                format = Config.dateFormat, showTime = Config.showTime,
                offset = BankingDates.timeZoneMode(Config.dateTimezone) == 'server' and 0 or BankingDates.localOffset(),
                locale = GetConvar and GetConvar('locale', 'en-US') or 'en-US',
            }),
        }
    end
    return rows
end

local function appDefinition()
    local snapshot = currentSnapshot or { accounts = {}, profile = {} }
    local accounts = snapshot.accounts or {}
    local selected = accountByName(selectedAccount) or accounts[1]
    if selected then selectedAccount = selected.name end

    if snapshot.locked then
        return {
            id = APP_ID, title = 'QBCore ATM', description = 'Secure cash access', icon = 'dollar-sign',
            accent = type(Config.ui.accent) == 'string' and Config.ui.accent or nil,
            layout = 'compact', width = 460, height = 700,
            navigation = {
                {
                    id = 'unlock', label = 'Verify card', icon = 'credit-card',
                    content = {
                        title = 'Enter your bank-card PIN',
                        description = 'Your PIN is checked only by the banking server.',
                        blocks = {
                            { type = 'text', title = 'Card required', text = 'Use a bank card issued to this character. Repeated incorrect PINs are temporarily locked.' },
                            { type = 'form', id = 'atm-pin', title = 'Secure keypad', fields = {
                                { id = 'pin', label = '4-digit PIN', type = 'password', required = true,
                                    minLength = 4, maxLength = 4, pattern = '^\\d{4}$', numericOnly = true, keypad = true,
                                    description = 'Four digits; never shared with the client resource after verification.' },
                            }, action = { id = 'banking:unlock', label = 'Unlock ATM', icon = 'key', variant = 'primary' } },
                        },
                    },
                },
            },
            footer = 'ATM sessions are secured by the banking server.',
        }
    end

    local accountSelect = accountOptions(accounts)
    local managedAccounts = managedAccountOptions(accounts)
    local managedItems = managedAccountItems(accounts)
    local minimums = snapshot.limits and snapshot.limits.min or {}
    local minWithdraw = math.max(1, tonumber(minimums.withdraw) or 1)
    local minDeposit = math.max(1, tonumber(minimums.deposit) or 1)
    local minTransfer = math.max(1, tonumber(minimums.transfer) or 1)
    local atmDailyRemaining = snapshot.mode == 'atm' and snapshot.limits and tonumber(snapshot.limits.daily) or nil
    local cardItems = {}
    for _, card in ipairs(snapshot.profile.cards or {}) do
        cardItems[#cardItems + 1] = {
            id = card.number, label = card.name or 'Bank card', description = card.number,
            icon = 'credit-card', badge = 'Issued', tone = 'success',
        }
    end
    local accountItems = {}
    for _, account in ipairs(accounts) do
        accountItems[#accountItems + 1] = {
            id = account.name, label = account.owner or account.label or account.name,
            description = ('%s · %s'):format(account.label or 'Bank account', account.name), badge = money(account.balance),
            icon = account.type == 'checking' and 'wallet' or account.type == 'job' and 'briefcase' or account.type == 'gang' and 'shield' or 'users',
            tone = account.name == selectedAccount and 'primary' or 'neutral', action = 'banking:select-account',
            metadata = {
                { label = 'Type', value = account.type or 'account' },
                { label = 'Available', value = money(account.balance) },
            },
        }
    end

    local cashActions = {
        {
            id = 'banking:withdraw', label = 'Withdraw cash', icon = 'dollar-sign', variant = 'primary',
            disabled = snapshot.mode == 'atm' and (not selected or (tonumber(selected.balance) or 0) < minWithdraw
                or (atmDailyRemaining ~= nil and atmDailyRemaining < minWithdraw)),
            fields = {
                { id = 'account', label = 'From account', type = 'select', options = accountSelect, default = selected and selected.name or 'checking', required = true },
                { id = 'amount', label = 'Amount', type = 'number', min = minWithdraw,
                    max = snapshot.mode == 'atm' and selected and (tonumber(selected.balance) or 0) >= minWithdraw
                        and (atmDailyRemaining == nil and selected.balance or math.min(tonumber(selected.balance), atmDailyRemaining)) or nil,
                    required = true, placeholder = '0', presets = amountPresets(),
                    description = snapshot.mode == 'atm' and selected and (money(selected.balance) .. ' available in this account')
                        or 'Each account option shows its current available balance.' .. (minWithdraw > 1 and (' Minimum withdrawal: ' .. money(minWithdraw) .. '.') or '') },
                { id = 'reason', label = 'Reference', type = 'text', placeholder = 'Optional', maxLength = 50 },
            },
        },
        {
            id = 'banking:deposit', label = 'Deposit cash', icon = 'dollar-sign', variant = 'secondary',
            disabled = (tonumber(snapshot.profile.cash) or 0) < minDeposit,
            fields = {
                { id = 'account', label = 'To account', type = 'select', options = accountSelect, default = selected and selected.name or 'checking', required = true },
                { id = 'amount', label = 'Amount', type = 'number', min = minDeposit,
                    max = (tonumber(snapshot.profile.cash) or 0) >= minDeposit and tonumber(snapshot.profile.cash) or nil,
                    required = true, placeholder = '0', presets = amountPresets(),
                    description = money(snapshot.profile.cash) .. ' cash available' .. (minDeposit > 1 and (' Minimum deposit: ' .. money(minDeposit) .. '.') or '') },
                { id = 'reason', label = 'Reference', type = 'text', placeholder = 'Optional', maxLength = 50 },
            },
        },
    }

    local navigation = {
        {
            id = 'accounts', label = 'Accounts', icon = 'wallet', badge = #accounts,
            defaultTab = 'summary',
            tabs = {
                {
                    id = 'summary', label = 'Summary',
                    content = {
                        title = 'Accessible accounts', description = 'Choose an account to view its current balance and activity.',
                        blocks = {
                            { type = 'stats', items = {
                                { label = 'Cash on hand', value = money(snapshot.profile.cash), icon = 'dollar-sign' },
                                { label = 'Selected balance', value = selected and money(selected.balance) or '—', icon = 'dollar-sign', tone = 'primary' },
                            } },
                            { type = 'list', id = 'bank-accounts', title = 'Accounts', layout = 'cards', searchable = true,
                                pageSize = 6, items = accountItems, empty = 'No accounts are available.' },
                        },
                    },
                },
                {
                    id = 'activity', label = 'Activity',
                    content = {
                        title = selected and (selected.owner or selected.name) or 'Account activity',
                        description = selected and ('Recent transactions for %s.'):format(selected.label or selected.name) or 'Choose an account first.',
                        blocks = {
                            {
                                type = 'table', id = 'bank-activity', title = 'Recent transactions', searchable = true, pageSize = 10,
                                columns = {
                                    { key = 'type', label = 'Type', sortable = true }, { key = 'amount', label = 'Amount', align = 'right', sortable = true },
                                    { key = 'reason', label = 'Reference' }, { key = 'date', label = 'Date', sortable = true },
                                },
                                rows = activityRows(), empty = 'No transactions yet.',
                            },
                        },
                    },
                },
            },
        },
        {
            id = 'cash', label = 'Cash', icon = 'dollar-sign',
            defaultTab = 'withdraw',
            tabs = {
                {
                    id = 'withdraw', label = 'Withdraw',
                    content = {
                        title = snapshot.mode == 'atm' and 'ATM withdrawal' or 'Withdraw cash',
                        description = snapshot.mode == 'atm' and (Config.useDailyLimit and ('Remaining daily withdrawal limit: %s.'):format(money(snapshot.limits.daily or 0)) or 'Withdraw cash using your personal account.')
                            or 'Withdraw cash from an account you can use.',
                        actions = { cashActions[1] }, blocks = { { type = 'text', text = ('Cash on hand: %s'):format(money(snapshot.profile.cash)) } },
                    },
                },
                {
                    id = 'deposit', label = 'Deposit',
                    content = {
                        title = 'Deposit cash', description = 'Deposit cash into an account you can use.',
                        actions = { cashActions[2] }, blocks = { { type = 'text', text = ('Cash on hand: %s'):format(money(snapshot.profile.cash)) } },
                    },
                },
            },
        },
    }

    if snapshot.mode ~= 'atm' then
        navigation[#navigation + 1] = {
            id = 'transfer', label = 'Transfer', icon = 'arrow-right',
            defaultTab = 'accounts',
            tabs = {
                {
                    id = 'accounts', label = 'My accounts',
                    content = {
                        title = 'Move money between accounts', description = 'Transfers are checked by the banking server before any funds move.',
                        actions = {
                    {
                        id = 'banking:transfer:internal', label = 'Between my accounts', icon = 'arrow-right', variant = 'primary',
                        fields = {
                            { id = 'from', label = 'From', type = 'select', options = accountSelect, default = selected and selected.name or 'checking', required = true },
                            { id = 'to', label = 'To', type = 'select', options = accountSelect, required = true },
                            { id = 'amount', label = 'Amount', type = 'number', min = minTransfer, required = true,
                                placeholder = '0', presets = amountPresets(), description = 'Each source account option shows its current available balance.' .. (minTransfer > 1 and (' Minimum transfer: ' .. money(minTransfer) .. '.') or '') },
                            { id = 'reason', label = 'Reference', type = 'text', placeholder = 'Optional', maxLength = 50 },
                        },
                    },
                        },
                    },
                },
                {
                    id = 'player', label = 'Another player',
                    content = {
                        title = 'Send to another player', description = 'The recipient must be online for a player transfer to complete.',
                        actions = {
                    {
                        id = 'banking:transfer:player', label = 'To another player', icon = 'arrow-right', variant = 'secondary',
                        fields = {
                            { id = 'from', label = 'From', type = 'select', options = accountSelect, default = selected and selected.name or 'checking', required = true },
                            { id = 'recipient', label = 'Recipient account number', type = 'text', required = true, minLength = 1 },
                            { id = 'amount', label = 'Amount', type = 'number', min = minTransfer, required = true,
                                placeholder = '0', presets = amountPresets(), description = 'Each source account option shows its current available balance.' .. (minTransfer > 1 and (' Minimum transfer: ' .. money(minTransfer) .. '.') or '') },
                            { id = 'reason', label = 'Reference', type = 'text', placeholder = 'Optional', maxLength = 50 },
                        },
                    },
                        },
                    },
                },
            },
        }

        navigation[#navigation + 1] = {
            id = 'manage', label = 'Manage', icon = 'settings',
            defaultTab = 'shared',
            tabs = {
                {
                    id = 'shared', label = 'Shared accounts',
                    content = {
                        title = 'Create a shared account', description = 'Shared accounts are funded from your personal bank balance.',
                        blocks = {
                            { type = 'list', id = 'managed-shared-accounts', title = 'Your shared accounts', layout = 'cards',
                                items = managedItems, empty = 'No shared accounts owned by you.' },
                        },
                        actions = {
                    {
                        id = 'banking:create-shared', label = 'Create shared account', icon = 'plus', variant = 'primary',
                        fields = {
                            { id = 'name', label = 'Account name', type = 'text', required = true },
                            { id = 'amount', label = 'Opening balance', type = 'number', min = 0, required = true, default = 0 },
                        },
                    },
                        },
                    },
                },
                {
                    id = 'card', label = 'Bank card',
                    content = {
                        title = 'Issue a bank card', description = 'A personal bank card is required for secure ATM access.',
                        blocks = {
                            { type = 'list', id = 'issued-bank-cards', title = 'Issued cards', layout = 'cards',
                                items = cardItems, empty = 'No bank cards have been issued.' },
                        },
                        actions = {
                    {
                        id = 'banking:order-card', label = 'Issue bank card', icon = 'credit-card', variant = 'secondary',
                        fields = { { id = 'pin', label = 'Choose a 4-digit PIN', type = 'password', required = true,
                            minLength = 4, maxLength = 4, pattern = '^\\d{4}$', numericOnly = true, keypad = true } },
                    },
                        },
                    },
                },
                {
                    id = 'access', label = 'Account access',
                    content = {
                        title = 'Manage account access', description = 'Only shared-account owners can make these changes.',
                        blocks = {
                    {
                        type = 'actions', title = 'Account access', actions = {
                            {
                                id = 'banking:rename-shared', label = 'Rename shared account', icon = 'pencil', variant = 'outline', disabled = #managedAccounts == 0,
                                fields = {
                                    { id = 'account', label = 'Account', type = 'select', options = managedAccounts, required = true },
                                    { id = 'name', label = 'New name', type = 'text', required = true },
                                },
                            },
                            {
                                id = 'banking:add-member', label = 'Grant access', icon = 'user', variant = 'outline', disabled = #managedAccounts == 0,
                                fields = {
                                    { id = 'account', label = 'Account', type = 'select', options = managedAccounts, required = true },
                                    { id = 'citizenid', label = 'Citizen ID', type = 'text', required = true },
                                },
                            },
                            {
                                id = 'banking:remove-member', label = 'Revoke access', icon = 'user', variant = 'destructive', disabled = #managedAccounts == 0,
                                confirm = 'Remove this person from the selected shared account?',
                                fields = {
                                    { id = 'account', label = 'Account', type = 'select', options = managedAccounts, required = true },
                                    { id = 'citizenid', label = 'Citizen ID', type = 'text', required = true },
                                },
                            },
                            {
                                id = 'banking:delete-shared', label = 'Close shared account', icon = 'trash-2', variant = 'destructive', disabled = #managedAccounts == 0,
                                confirm = 'Close this shared account? It must have a zero balance.',
                                fields = { { id = 'account', label = 'Account', type = 'select', options = managedAccounts, required = true } },
                            },
                        },
                    },
                        },
                    },
                },
            },
        }
    end

    return {
        id = APP_ID, title = snapshot.mode == 'atm' and 'QBCore ATM' or 'QBCore Bank',
        description = snapshot.mode == 'atm' and 'Personal banking' or 'Secure account services', icon = 'dollar-sign',
        accent = type(Config.ui.accent) == 'string' and Config.ui.accent or nil,
        layout = snapshot.mode == 'atm' and 'compact' or 'standard',
        width = snapshot.mode == 'atm' and 540 or 1180, height = snapshot.mode == 'atm' and 720 or 760,
        defaultView = snapshot.mode == 'atm' and 'cash' or 'accounts', navigation = navigation,
        footer = 'Every transaction is verified by the banking server.',
    }
end

local function appUpdate()
    local definition = appDefinition()
    return {
        title = definition.title, description = definition.description, accent = definition.accent,
        layout = definition.layout, width = definition.width, height = definition.height, defaultView = definition.defaultView,
        navigation = definition.navigation, footer = definition.footer,
    }
end

local function refreshApp()
    local definition = appDefinition()
    definition.onAction = function(actionId, context)
        local values = type(context and context.value) == 'table' and context.value or {}

        if actionId == 'banking:unlock' then
            local snapshot, err = request('pin', values.pin)
            if not snapshot then
                local message = err or 'Invalid PIN.'
                if Kora.notify and Kora.notify.send then notify(message) end
                return { notice = { tone = 'destructive', message = message } }
            end
            currentSnapshot = snapshot
            selectedAccount = 'checking'
            return { update = appUpdate() }
        end

        if actionId == 'banking:select-account' then
            local account = accountByName(context and context.itemId)
            if not account then error('That account is no longer available.') end
            selectedAccount = account.name
            return { update = appUpdate() }
        end

        local payload
        if actionId == 'banking:withdraw' or actionId == 'banking:deposit' then
            payload = { kind = actionId:match('banking:(.+)'), account = values.account, amount = values.amount, reason = values.reason }
        elseif actionId == 'banking:transfer:internal' then
            payload = { kind = 'transfer', from = values.from, to = values.to, amount = values.amount, reason = values.reason }
        elseif actionId == 'banking:transfer:player' then
            payload = { kind = 'transfer', from = values.from, recipient = values.recipient, amount = values.amount, reason = values.reason }
        elseif actionId == 'banking:order-card' then
            payload = { kind = 'orderCard', pin = values.pin }
        elseif actionId == 'banking:create-shared' then
            payload = { kind = 'create', name = values.name, amount = values.amount }
        elseif actionId == 'banking:rename-shared' then
            payload = { kind = 'rename', account = values.account, name = values.name }
        elseif actionId == 'banking:delete-shared' then
            payload = { kind = 'delete', account = values.account }
        elseif actionId == 'banking:add-member' then
            payload = { kind = 'addMember', account = values.account, citizenid = values.citizenid }
        elseif actionId == 'banking:remove-member' then
            payload = { kind = 'removeMember', account = values.account, citizenid = values.citizenid }
        else
            error('That banking action is no longer available.')
        end

        local result, err = request('action', payload)
        if not result then
            notify(err or 'The transaction was declined.')
            return {}
        end
        currentSnapshot = result.snapshot
        if not accountByName(selectedAccount) then selectedAccount = 'checking' end
        return { update = appUpdate(), notice = result.message and { tone = 'success', message = result.message } or nil }
    end
    Kora.nui.registerApp(definition)
end

local function closeSession()
    if not appOpen then return end
    appOpen = false
    currentSnapshot = nil
    TriggerServerEvent('qbbanking:close')
end

local function open(mode, location)
    if appOpen then return end
    CreateThread(function()
        local snapshot, err = request('open', mode, location)
        if not snapshot then return notify(err or 'You cannot access banking here.') end
        currentSnapshot = snapshot
        selectedAccount = 'checking'
        appOpen = true
        refreshApp()
        local result = Kora.nui.openApp(APP_ID, { viewId = snapshot.locked and 'unlock' or 'accounts' })
        closeSession()
        if result == nil then notify('The banking interface could not be opened.') end
    end)
end

local function nearAtm()
    local coords = GetEntityCoords(PlayerPedId())
    for _, modelName in ipairs(Config.atmModels) do
        local entity = GetClosestObjectOfType(coords.x, coords.y, coords.z, Config.atmDistance, joaat(modelName), false, false, false)
        if entity ~= 0 then return entity end
    end
end

local function accessAtm()
    if openingAtm or appOpen then return end
    local entity = nearAtm()
    if not entity then return notify('Move closer to an ATM.') end

    openingAtm = true
    CreateThread(function()
        local completed = Kora.progressbar.start({
            label = 'Accessing ATM...', duration = Config.atmAccessTime, canCancel = true,
            disable = { move = true, combat = true, car = true },
            anim = { dict = 'amb@prop_human_atm@male@enter', clip = 'enter' },
            props = { { model = 'prop_cs_credit_card', bone = 28422, offset = vector3(0.1, 0.03, -0.05), rotation = vector3(0.0, 0.0, 180.0) } },
        })
        openingAtm = false
        if not completed then return end
        entity = nearAtm()
        if not entity then return notify('Move closer to an ATM.') end
        local coords = GetEntityCoords(entity)
        open('atm', { x = coords.x, y = coords.y, z = coords.z })
    end)
end

local function registerBranchTargets()
    for _, targetId in pairs(branchTargetIds) do
        pcall(function() exports.kora_target:removeZone(targetId) end)
    end
    branchTargetIds = {}

    for index, coords in ipairs(Config.locations) do
        local branchIndex = index
        branchTargetIds[index] = exports.kora_target:addSphereZone({
            coords = coords,
            radius = 1.2,
            options = {
                { icon = 'building-columns', label = 'Open bank', distance = 1.8, onSelect = function() open('bank', branchIndex) end },
            },
        })
    end
end

-- ATM props stream in and out with the map, so this must remain a model target.
local atmTargetId
local function registerAtmTargets()
    if atmTargetId then pcall(function() exports.kora_target:removeModel(Config.atmModels, atmTargetId) end) end
    atmTargetId = exports.kora_target:addModel(Config.atmModels, {
        { icon = 'credit-card', label = 'Use ATM', onSelect = accessAtm },
    }, Config.atmDistance)
end

registerBranchTargets()
registerAtmTargets()
AddEventHandler('onClientResourceStart', function(resource)
    if resource ~= 'kora_target' then return end
    registerBranchTargets()
    registerAtmTargets()
end)

for _, coords in ipairs(Config.locations) do
    Kora.blips.create(coords, Config.blipInfo)
end

RegisterNetEvent('qbbanking:client:useCard', accessAtm)
RegisterNetEvent('qb-banking:client:useCard', accessAtm)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= RESOURCE then return end
    closeSession()
    for _, targetId in pairs(branchTargetIds) do pcall(function() exports.kora_target:removeZone(targetId) end) end
    if atmTargetId then pcall(function() exports.kora_target:removeModel(Config.atmModels, atmTargetId) end) end
end)
