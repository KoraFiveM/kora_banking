-- Banking presentation through kora_lib's shared AppShell. The server remains
-- the authority for every balance, card, proximity and account-access check.
-- kora_lib owns the browser frame and focus lifecycle.

local RESOURCE = GetCurrentResourceName()
local APP_ID = 'qbbanking:bank'
local REQUEST_TIMEOUT = 10000

local openingAtm = false
local ATM_ANIM = { dict = 'amb@prop_human_atm@male@enter', clip = 'enter' }
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
    local offset = BankingDates.timeZoneMode(Config.dateTimezone) == 'server' and 0 or BankingDates.localOffset()
    for _, transaction in ipairs(transactions) do
        local deposit = transaction.statement_type == 'deposit'
        rows[#rows + 1] = {
            id = transaction.id,
            type = { label = deposit and 'Deposit' or 'Withdrawal', badge = true, tone = deposit and 'success' or 'neutral' },
            amount = { label = (deposit and '+' or '-') .. money(transaction.amount), tone = deposit and 'success' or 'neutral' },
            reason = transaction.reason or (deposit and 'Deposit' or 'Withdrawal'),
            -- value is the UTC epoch (ms) so the column sorts chronologically; label is shown in the player's zone.
            date = {
                value = BankingDates.normalize(transaction.date),
                label = BankingDates.safeFormat(transaction.date, {
                    format = Config.dateFormat, showTime = Config.showTime, offset = offset,
                    locale = GetConvar and GetConvar('locale', 'en-US') or 'en-US',
                }),
            },
        }
    end
    return rows
end

local ACTION_FEATURES = {
    ['banking:withdraw'] = 'withdraw', ['banking:deposit'] = 'deposit',
    ['banking:transfer:internal'] = 'transfer', ['banking:transfer:player'] = 'transfer',
    ['banking:order-card'] = 'orderCard', ['banking:create-shared'] = 'sharedAccounts',
    ['banking:rename-shared'] = 'sharedAccounts', ['banking:delete-shared'] = 'sharedAccounts',
    ['banking:add-member'] = 'manageMembers', ['banking:remove-member'] = 'manageMembers',
}

local function appDefinition()
    local snapshot = currentSnapshot or { accounts = {}, profile = {} }
    local accounts = snapshot.accounts or {}
    local selected = accountByName(selectedAccount) or accounts[1]
    if selected then selectedAccount = selected.name end

    if snapshot.locked then
        return {
            id = APP_ID, title = 'Kora ATM', description = 'Secure cash access', icon = 'dollar-sign',
            accent = type(Config.ui.accent) == 'string' and Config.ui.accent or nil,
            layout = 'compact', width = 460, height = 660,
            navigation = {
                {
                    id = 'unlock', label = 'Verify card', icon = 'credit-card',
                    content = {
                        title = 'Enter your bank card PIN',
                        description = 'Repeated incorrect PIN entries will result in a temporary account lockout.',
                        blocks = {
                            { type = 'form', id = 'atm-pin', title = 'Secure Keypad', fields = {
                                -- labelAlign/keypadActionVariant need kora_lib with those field options;
                                -- older kora_lib bundles ignore them and keep the left label and plain keys.
                                { id = 'pin', label = 'PIN', type = 'password', labelAlign = 'center',
                                    minLength = 4, maxLength = 4, pattern = '^\\d{4}$', numericOnly = true, keypad = true,
                                    keypadActionVariant = 'outline',
                                    description = 'Never share your PIN with anyone.' },
                            }, action = { id = 'banking:unlock', label = 'Unlock ATM', icon = 'key', variant = 'primary' } },
                        },
                    },
                },
            },
            footer = 'ATM sessions are secured by the banking server.',
        }
    end

    local branch = snapshot.mode ~= 'atm' and snapshot.branch or nil
    local gated = branch and branch.gated or {}
    local accountSelect = accountOptions(accounts)
    local managedAccounts = managedAccountOptions(accounts)
    local managedItems = managedAccountItems(accounts)
    local minimums = snapshot.limits and snapshot.limits.min or {}
    local minWithdraw = math.max(1, tonumber(minimums.withdraw) or 1)
    local minDeposit = math.max(1, tonumber(minimums.deposit) or 1)
    local minTransfer = math.max(1, tonumber(minimums.transfer) or 1)
    local maxTransfer = snapshot.limits and tonumber(snapshot.limits.maxTransfer) or nil
    local transferNote = maxTransfer and (' Maximum transfer at this bank: ' .. money(maxTransfer) .. '.') or ''
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

    local counterDaily = snapshot.mode ~= 'atm' and snapshot.limits and tonumber(snapshot.limits.counterDaily) or nil
    if counterDaily then
        local field = cashActions[1].fields[2]
        field.max = counterDaily >= minWithdraw and counterDaily or nil
        field.description = (field.description or '') .. (' Daily withdrawal allowance left at this bank: %s.'):format(money(counterDaily))
        if counterDaily < minWithdraw then cashActions[1].disabled = true end
    end

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
                                branch and { label = 'Branch', value = branch.tierLabel or branch.label, icon = 'landmark' } or nil,
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
                            { id = 'amount', label = 'Amount', type = 'number', min = minTransfer, max = maxTransfer, required = true,
                                placeholder = '0', presets = amountPresets(), description = 'Each source account option shows its current available balance.' .. (minTransfer > 1 and (' Minimum transfer: ' .. money(minTransfer) .. '.') or '') .. transferNote },
                            { id = 'reason', label = 'Reference', type = 'text', placeholder = 'Optional', maxLength = 50 },
                        },
                    },
                        },
                    },
                },
                {
                    id = 'player', label = 'Another player',
                    content = {
                        title = 'Send to another player', description = (Config.Transfers and Config.Transfers.allowOffline == false) and 'The recipient must be online for a player transfer to complete.' or 'Send money to a personal account number, a shared or business account name, or a bank card number. The recipient can be offline.',
                        actions = {
                    {
                        id = 'banking:transfer:player', label = 'To another player', icon = 'arrow-right', variant = 'secondary',
                        fields = {
                            { id = 'from', label = 'From', type = 'select', options = accountSelect, default = selected and selected.name or 'checking', required = true },
                            { id = 'recipient', label = (Config.Transfers and Config.Transfers.allowCardNumbers == false) and 'Recipient account number' or 'Recipient account or card number', type = 'text', required = true, minLength = 1 },
                            { id = 'amount', label = 'Amount', type = 'number', min = minTransfer, max = maxTransfer, required = true,
                                placeholder = '0', presets = amountPresets(), description = 'Each source account option shows its current available balance.' .. (minTransfer > 1 and (' Minimum transfer: ' .. money(minTransfer) .. '.') or '') .. transferNote },
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
                            minLength = 4, maxLength = 4, pattern = '^\\d{4}$', numericOnly = true, keypad = true,
                            keypadActionVariant = 'outline' } },
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

    -- Tier gating is enforced by the server; this only disables the controls and says where they are available.
    local notes = {}
    for _, view in ipairs(navigation) do
        for _, tab in ipairs(view.tabs or {}) do
            local content = tab.content or {}
            local locked = {}
            local lists = { content.actions or {} }
            for _, block in ipairs(content.blocks or {}) do
                if block.type == 'actions' then lists[#lists + 1] = block.actions or {} end
            end
            for _, list in ipairs(lists) do
                for _, action in ipairs(list) do
                    local where = gated[ACTION_FEATURES[action.id]]
                    if where then action.disabled = true locked[where] = true end
                end
            end
            for where in pairs(locked) do
                content.blocks = content.blocks or {}
                table.insert(content.blocks, 1, { type = 'text', title = 'Not available at this branch', text = ('Available at %s.'):format(where) })
                tab.content = content
            end
        end
    end

    local branchTitle = branch and (branch.label or branch.tierLabel) or nil
    local branchDescription = 'Secure account services'
    if branch and branch.tierLabel and branch.tierLabel ~= branchTitle then branchDescription = branch.tierLabel .. ' · ' .. branchDescription end
    return {
        id = APP_ID, title = branchTitle or (snapshot.mode == 'atm' and 'Kora ATM' or 'Kora Bank'),
        description = snapshot.mode == 'atm' and 'Personal banking' or branchDescription, icon = 'dollar-sign',
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
                notify(message)
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

-- ATM sessions end when the player drives off or walks away from the machine (Config.atmCloseDistance, 0 disables the distance check).
local atmSession

local function closeAtmSession()
    if not atmSession then return end
    atmSession = nil
    Kora.nui.closeApp(APP_ID)
end

local function watchAtmSession(position)
    local session = { position = position }
    atmSession = session
    local maxDistance = tonumber(Config.atmCloseDistance) or 0
    if maxDistance <= 0 then return end
    CreateThread(function()
        while atmSession == session do
            local coords = Kora.cache.coords()
            local dx, dy, dz = coords.x - position.x, coords.y - position.y, coords.z - position.z
            if dx * dx + dy * dy + dz * dz > maxDistance * maxDistance then
                closeAtmSession()
                break
            end
            Wait(500)
        end
    end)
end

Kora.cache.onChange('vehicle', function(vehicle)
    if vehicle and Config.atmCloseInVehicle ~= false then closeAtmSession() end
end)

local function open(mode, location)
    if appOpen then return end
    CreateThread(function()
        local snapshot, err = request('open', mode, location)
        if not snapshot then return notify(err or 'You cannot access banking here.') end
        currentSnapshot = snapshot
        selectedAccount = 'checking'
        appOpen = true
        if mode == 'atm' and type(location) == 'table' then
            if Kora.cache.vehicle() and Config.atmCloseInVehicle ~= false then
                appOpen = false
                currentSnapshot = nil
                TriggerServerEvent('qbbanking:close')
                return notify(Config.atmVehicleMessage or 'You cannot use an ATM from a vehicle.')
            end
            watchAtmSession(location)
        end
        refreshApp()
        local result = Kora.nui.openApp(APP_ID, { viewId = snapshot.locked and 'unlock' or 'accounts' })
        atmSession = nil
        closeSession()
        if result == nil then notify('The banking interface could not be opened.') end
    end)
end

local function nearAtm()
    local coords = GetEntityCoords(PlayerPedId())
    local radius = Config.atmDistance + (Config.atmTolerance or 1.0)
    for _, modelName in ipairs(Config.atmModels) do
        local entity = GetClosestObjectOfType(coords.x, coords.y, coords.z, radius, joaat(modelName), false, false, false)
        if entity ~= 0 then return entity end
    end
end

-- Map-baked ATMs are not entities, so Config.atmCoords is the fallback for the closest listed machine within reach.
local function nearAtmCoords()
    local coords = GetEntityCoords(PlayerPedId())
    local radius = Config.atmDistance + (Config.atmTolerance or 1.0)
    local best, bestDistance
    for _, atm in ipairs(Config.atmCoords or {}) do
        local dx, dy, dz = coords.x - atm.x, coords.y - atm.y, coords.z - atm.z
        local distance = math.sqrt(dx * dx + dy * dy + dz * dz)
        if distance <= radius and (not bestDistance or distance < bestDistance) then best, bestDistance = atm, distance end
    end
    return best
end

-- Where the ATM is: the fixed zone coordinates, the aimed/nearest ATM entity, or the nearest fallback coordinates.
local function atmPosition(target, fixed)
    if fixed then return fixed end
    local entity = type(target) == 'number' and target ~= 0 and DoesEntityExist(target) and target or nearAtm()
    if entity then
        local coords = GetEntityCoords(entity)
        return { x = coords.x, y = coords.y, z = coords.z }
    end
    local atm = nearAtmCoords()
    return atm and { x = atm.x, y = atm.y, z = atm.z } or nil
end

-- The access animation must never outlive the attempt, whatever way it ends.
local function stopAtmAnimation()
    local ped = PlayerPedId()
    pcall(function() StopAnimTask(ped, ATM_ANIM.dict, ATM_ANIM.clip, 8.0) end)
    pcall(function() RemoveAnimDict(ATM_ANIM.dict) end)
end

-- target = the entity the player aimed at (kora_target passes it to onSelect); events pass nothing.
-- fixed = the coordinates of a Config.atmCoords fallback zone.
local function accessAtm(target, fixed)
    if openingAtm or appOpen then return end
    if Config.atmCloseInVehicle ~= false and Kora.cache.vehicle() then
        return notify(Config.atmVehicleMessage or 'You cannot use an ATM from a vehicle.')
    end
    if not atmPosition(target, fixed) then return notify('Move closer to an ATM.') end

    openingAtm = true
    CreateThread(function()
        -- Refuse before any animation or progress bar when the player has no bank card (the server stays the authority).
        if Config.requireBankCard ~= false then
            local hasCard, cardErr = request('atmCard')
            if not hasCard then
                openingAtm = false
                return notify(cardErr or Config.atmNoCardMessage or 'You need a bank card to use an ATM.')
            end
        end
        local ok, completed, err = pcall(Kora.progressbar.start, {
            label = 'Accessing ATM...', duration = Config.atmAccessTime, canCancel = true,
            disable = { move = true, combat = true, car = true },
            -- The clip is bounded by the access time so it can not loop if the bar is never cleaned up.
            anim = { dict = ATM_ANIM.dict, clip = ATM_ANIM.clip, duration = Config.atmAccessTime > 0 and Config.atmAccessTime or nil },
            props = { { model = 'prop_cs_credit_card', bone = 28422, offset = vector3(0.1, 0.03, -0.05), rotation = vector3(0.0, 0.0, 180.0) } },
        })
        openingAtm = false
        stopAtmAnimation()
        if not ok then
            print(('[kora_banking] ATM progress bar failed: %s'):format(tostring(completed)))
            return notify('The ATM could not be started. Try again.')
        end
        if not completed then
            if err then notify(err) end
            return
        end
        local position = atmPosition(target, fixed)
        if not position then return notify('Move closer to an ATM.') end
        open('atm', position)
    end)
end

local function registerBranchTargets()
    for _, targetId in pairs(branchTargetIds) do
        pcall(function() exports.kora_target:removeZone(targetId) end)
    end
    branchTargetIds = {}

    for index in ipairs(Config.locations) do
        local info = BankingTiers.info(index)
        branchTargetIds[index] = exports.kora_target:addSphereZone({
            coords = info.coords,
            radius = 1.2,
            options = {
                { icon = 'building-columns', label = info.enabled and info.label and ('Open %s'):format(info.label) or 'Open bank',
                    distance = 1.8, onSelect = function() open('bank', index) end },
            },
        })
    end
end

-- ATM props stream in and out with the map, so this must remain a model target.
-- Config.atmCoords adds sphere zones for ATMs that are baked into the map and never hit as an entity.
local atmTargetId
local atmZoneIds = {}
local atmHashes = {}
local CARD_CHECK_MS = 5000
local cardKnown, cardCheckedAt, cardChecking = false, -CARD_CHECK_MS, false

local function isAtmEntity(entity)
    if type(entity) ~= 'number' or entity == 0 then return false end
    local ok, model = pcall(GetEntityModel, entity)
    return ok and atmHashes[model] == true
end

-- Only used when Config.atmAlwaysShowTarget is off: shows the target from the server's last card answer (refreshed on demand
-- while the player aims, never in a loop). Selecting the option still asks the server, which stays the authority.
local function cardAllowsTarget()
    if Config.requireBankCard == false then return true end
    if not cardChecking and GetGameTimer() - cardCheckedAt >= CARD_CHECK_MS then
        cardChecking = true
        CreateThread(function()
            local hasCard = request('atmCard')
            cardKnown, cardCheckedAt, cardChecking = hasCard == true, GetGameTimer(), false
        end)
    end
    return cardKnown
end

local function showAtmOption()
    return Config.atmAlwaysShowTarget ~= false or cardAllowsTarget()
end

local function registerAtmZones()
    for _, zoneId in pairs(atmZoneIds) do pcall(function() exports.kora_target:removeZone(zoneId) end) end
    atmZoneIds = {}
    for index, atm in ipairs(Config.atmCoords or {}) do
        local fixed = { x = atm.x, y = atm.y, z = atm.z }
        local ok, result = pcall(function()
            return exports.kora_target:addSphereZone({
                coords = vector3(atm.x, atm.y, atm.z),
                radius = Config.atmZoneRadius or 1.2,
                options = {
                    { icon = 'credit-card', label = 'Use ATM', distance = Config.atmDistance, onSelect = function() accessAtm(nil, fixed) end,
                        -- The model target covers any ATM prop the ray resolves, so the zone only stands in where it does not.
                        canInteract = function(entity) return not isAtmEntity(entity) and showAtmOption() end },
                },
            })
        end)
        if ok then atmZoneIds[index] = result else print(('[kora_banking] ATM zone %d registration failed: %s'):format(index, tostring(result))) end
    end
end

local function registerAtmTargets()
    if atmTargetId then pcall(function() exports.kora_target:removeModel(Config.atmModels, atmTargetId) end) end
    atmTargetId = nil
    atmHashes = {}
    for _, modelName in ipairs(Config.atmModels) do atmHashes[joaat(modelName)] = true end
    registerAtmZones()
    local ok, result = pcall(function()
        return exports.kora_target:addModel(Config.atmModels, {
            { icon = 'credit-card', label = 'Use ATM', onSelect = accessAtm, canInteract = showAtmOption },
        }, Config.atmDistance)
    end)
    if ok then atmTargetId = result else print(('[kora_banking] ATM target registration failed: %s'):format(tostring(result))) end
end

-- ATMs register first and each registration is isolated: a failing bank-branch zone must never stop ATMs from registering.
-- targetsRegistered stays true only while the registrations live in the running kora_target, so a start event that arrives
-- after our own startup registration (client start order is not guaranteed) can not register every option a second time.
local targetsRegistered = false
local function registerTargets()
    registerAtmTargets()
    local ok, err = pcall(registerBranchTargets)
    if not ok then print(('[kora_banking] bank branch target registration failed: %s'):format(tostring(err))) end
    targetsRegistered = ok and atmTargetId ~= nil
end

registerTargets()
AddEventHandler('onClientResourceStop', function(resource)
    if resource ~= 'kora_target' then return end
    -- kora_target stopped: its registry is gone and its ids restart, so stale ids must not be removed (they could hit another resource's targets).
    targetsRegistered = false
    atmTargetId = nil
    atmZoneIds = {}
    branchTargetIds = {}
end)
AddEventHandler('onClientResourceStart', function(resource)
    if resource ~= 'kora_target' or targetsRegistered then return end
    registerTargets()
end)

-- With tiers enabled each marker takes its tier's sprite/colour/scale and the location label as its name.
local function blipOptions(info)
    if not (info.enabled and info.tier) then return Config.blipInfo end
    local options = {}
    for key, value in pairs(Config.blipInfo) do options[key] = value end
    for _, key in ipairs({ 'sprite', 'color', 'scale' }) do
        if info.blip and info.blip[key] ~= nil then options[key] = info.blip[key] end
    end
    options.name = info.label
    return options
end

local branchBlips = {}
local function createBranchBlips()
    for _, blip in pairs(branchBlips) do pcall(function() Kora.blips.remove(blip) end) end
    branchBlips = {}
    for index in ipairs(Config.locations) do
        local info = BankingTiers.info(index)
        branchBlips[index] = Kora.blips.create(info.coords, blipOptions(info))
    end
end
createBranchBlips()

-- This script runs before kora_lib delivers the server config snapshot, so a tier setting enabled in the
-- server config (config.local.lua or the config editor) only arrives afterwards: rebuild markers and prompts then.
if Kora.config and Kora.config.onChange then
    local function refreshBranches()
        createBranchBlips()
        registerBranchTargets()
    end
    Kora.config.onChange('tiers.enabled', refreshBranches)
    Kora.config.onChange('tiers.default', refreshBranches)
end

RegisterNetEvent('qbbanking:client:useCard', accessAtm)
RegisterNetEvent('qb-banking:client:useCard', accessAtm)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= RESOURCE then return end
    closeSession()
    for _, targetId in pairs(branchTargetIds) do pcall(function() exports.kora_target:removeZone(targetId) end) end
    if atmTargetId then pcall(function() exports.kora_target:removeModel(Config.atmModels, atmTargetId) end) end
end)
