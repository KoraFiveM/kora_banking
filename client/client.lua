-- Banking presentation through kora_lib's shared AppShell. The server remains
-- the authority for every balance, card, proximity and account-access check.
-- kora_lib owns the browser frame and focus lifecycle.

local RESOURCE = GetCurrentResourceName()
local APP_ID = 'kora_banking:bank'
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
    Kora.notify.send({ title = Kora.lang('title'), message = message, type = kind or 'error' })
end

-- Keep banking's request transport independent from kora_lib's callback
-- registry, so a live kora_lib restart cannot strand a banking session.
local function request(operation, ...)
    nextRequestId = nextRequestId + 1
    if nextRequestId > 2147483647 then nextRequestId = 1 end

    local requestId = nextRequestId
    local response = promise.new()
    pendingRequests[requestId] = response
    TriggerServerEvent('kora_banking:server:request', requestId, operation, ...)

    SetTimeout(REQUEST_TIMEOUT, function()
        if pendingRequests[requestId] ~= response then return end
        pendingRequests[requestId] = nil
        response:resolve({ error = Kora.lang('error.bank_no_answer') })
    end)

    local reply = Citizen.Await(response)
    if type(reply) ~= 'table' then return nil, Kora.lang('error.bank_no_answer') end
    return reply.result, reply.error
end

RegisterNetEvent('kora_banking:client:response', function(requestId, result, err)
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
                metadata = { { label = Kora.lang('ui.available'), value = money(account.balance) } },
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
            type = { label = deposit and Kora.lang('ui.deposit') or Kora.lang('ui.withdrawal'), badge = true, tone = deposit and 'success' or 'neutral' },
            amount = { label = (deposit and '+' or '-') .. money(transaction.amount), tone = deposit and 'success' or 'neutral' },
            reason = transaction.reason or (deposit and Kora.lang('ui.deposit') or Kora.lang('ui.withdrawal')),
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
            id = APP_ID, title = Kora.lang('atm'), description = Kora.lang('ui.secure_cash'), icon = 'dollar-sign',
            accent = type(Config.ui.accent) == 'string' and Config.ui.accent or nil,
            layout = 'compact', width = 460, height = 660,
            navigation = {
                {
                    id = 'unlock', label = Kora.lang('ui.verify_card'), icon = 'credit-card',
                    content = {
                        title = Kora.lang('ui.enter_pin'),
                        description = Kora.lang('ui.pin_lockout'),
                        blocks = {
                            { type = 'form', id = 'atm-pin', title = Kora.lang('ui.keypad'), fields = {
                                -- labelAlign/keypadActionVariant need kora_lib with those field options;
                                -- older kora_lib bundles ignore them and keep the left label and plain keys.
                                { id = 'pin', label = Kora.lang('ui.pin'), type = 'password', labelAlign = 'center',
                                    minLength = 4, maxLength = 4, pattern = '^\\d{4}$', numericOnly = true, keypad = true,
                                    keypadActionVariant = 'outline',
                                    description = Kora.lang('ui.pin_safety') },
                            }, action = { id = 'banking:unlock', label = Kora.lang('ui.unlock_atm'), icon = 'key', variant = 'primary' } },
                        },
                    },
                },
            },
            footer = Kora.lang('ui.atm_footer'),
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
    local atmDailyRemaining = snapshot.mode == 'atm' and snapshot.limits and tonumber(snapshot.limits.daily) or nil
    local cardItems = {}
    for _, card in ipairs(snapshot.profile.cards or {}) do
        cardItems[#cardItems + 1] = {
            id = card.number, label = card.name or Kora.lang('ui.bank_card'), description = card.number,
            icon = 'credit-card', badge = Kora.lang('ui.issued'), tone = 'success',
        }
    end
    local accountItems = {}
    for _, account in ipairs(accounts) do
        accountItems[#accountItems + 1] = {
            id = account.name, label = account.owner or account.label or account.name,
            description = Kora.lang('ui.account_description', account.label or Kora.lang('ui.account_fallback'), account.name), badge = money(account.balance),
            icon = account.type == 'checking' and 'wallet' or account.type == 'job' and 'briefcase' or account.type == 'gang' and 'shield' or 'users',
            tone = account.name == selectedAccount and 'primary' or 'neutral', action = 'banking:select-account',
            metadata = {
                { label = Kora.lang('ui.account_type'), value = account.type or Kora.lang('ui.account_fallback') },
                { label = Kora.lang('ui.available'), value = money(account.balance) },
            },
        }
    end

    -- A max below the min (e.g. the daily limit is used up) makes kora_lib reject the whole app update.
    local atmWithdrawMax
    if snapshot.mode == 'atm' and selected then
        local available = tonumber(selected.balance) or 0
        if atmDailyRemaining ~= nil then available = math.min(available, atmDailyRemaining) end
        if available >= minWithdraw then atmWithdrawMax = available end
    end

    local cashActions = {
        {
            id = 'banking:withdraw', label = Kora.lang('ui.withdraw_cash'), icon = 'dollar-sign', variant = 'primary',
            disabled = snapshot.mode == 'atm' and (not selected or (tonumber(selected.balance) or 0) < minWithdraw
                or (atmDailyRemaining ~= nil and atmDailyRemaining < minWithdraw)),
            fields = {
                { id = 'account', label = Kora.lang('ui.from_account'), type = 'select', options = accountSelect, default = selected and selected.name or 'checking', required = true },
                { id = 'amount', label = Kora.lang('ui.amount'), type = 'number', min = minWithdraw,
                    max = atmWithdrawMax,
                    required = true, placeholder = '0', presets = amountPresets(),
                    description = snapshot.mode == 'atm' and selected and Kora.lang('ui.available_account', money(selected.balance))
                        or Kora.lang('ui.account_balance_hint') .. (minWithdraw > 1 and Kora.lang('ui.minimum_withdrawal', money(minWithdraw)) or '') },
                { id = 'reason', label = Kora.lang('ui.reference'), type = 'text', placeholder = Kora.lang('ui.optional'), maxLength = 50 },
            },
        },
        {
            id = 'banking:deposit', label = Kora.lang('ui.deposit_cash'), icon = 'dollar-sign', variant = 'secondary',
            disabled = (tonumber(snapshot.profile.cash) or 0) < minDeposit,
            fields = {
                { id = 'account', label = Kora.lang('ui.to_account'), type = 'select', options = accountSelect, default = selected and selected.name or 'checking', required = true },
                { id = 'amount', label = Kora.lang('ui.amount'), type = 'number', min = minDeposit,
                    max = (tonumber(snapshot.profile.cash) or 0) >= minDeposit and tonumber(snapshot.profile.cash) or nil,
                    required = true, placeholder = '0', presets = amountPresets(),
                    description = Kora.lang('ui.cash_available', money(snapshot.profile.cash)) .. (minDeposit > 1 and Kora.lang('ui.minimum_deposit', money(minDeposit)) or '') },
                { id = 'reason', label = Kora.lang('ui.reference'), type = 'text', placeholder = Kora.lang('ui.optional'), maxLength = 50 },
            },
        },
    }

    local counterDaily = snapshot.mode ~= 'atm' and snapshot.limits and tonumber(snapshot.limits.counterDaily) or nil
    if counterDaily then
        local field = cashActions[1].fields[2]
        field.max = counterDaily >= minWithdraw and counterDaily or nil
        field.description = (field.description or '') .. Kora.lang('ui.daily_allowance', money(counterDaily))
        if counterDaily < minWithdraw then cashActions[1].disabled = true end
    end

    local navigation = {
        {
            id = 'accounts', label = Kora.lang('ui.accounts'), icon = 'wallet', badge = #accounts,
            defaultTab = 'summary',
            tabs = {
                {
                    id = 'summary', label = Kora.lang('ui.summary'),
                    content = {
                        title = Kora.lang('ui.accessible_accounts'), description = Kora.lang('ui.choose_account'),
                        blocks = {
                            { type = 'stats', items = {
                                { label = Kora.lang('ui.cash_on_hand'), value = money(snapshot.profile.cash), icon = 'dollar-sign' },
                                { label = Kora.lang('ui.selected_balance'), value = selected and money(selected.balance) or '—', icon = 'dollar-sign', tone = 'primary' },
                                branch and { label = Kora.lang('ui.branch'), value = branch.tierLabel or branch.label, icon = 'landmark' } or nil,
                            } },
                            { type = 'list', id = 'bank-accounts', title = Kora.lang('ui.accounts'), layout = 'cards', searchable = true,
                                pageSize = 6, items = accountItems, empty = Kora.lang('ui.no_accounts') },
                        },
                    },
                },
                {
                    id = 'activity', label = Kora.lang('ui.activity'),
                    content = {
                        title = selected and (selected.owner or selected.name) or Kora.lang('ui.account_activity'),
                        description = selected and Kora.lang('ui.recent_for', selected.label or selected.name) or Kora.lang('ui.choose_first'),
                        blocks = {
                            {
                                type = 'table', id = 'bank-activity', title = Kora.lang('ui.recent_transactions'), searchable = true, pageSize = 10,
                                columns = {
                                    { key = 'type', label = Kora.lang('ui.type'), sortable = true }, { key = 'amount', label = Kora.lang('ui.amount'), align = 'right', sortable = true },
                                    { key = 'reason', label = Kora.lang('ui.reference') }, { key = 'date', label = Kora.lang('ui.date'), sortable = true },
                                },
                                rows = activityRows(), empty = Kora.lang('ui.no_transactions'),
                            },
                        },
                    },
                },
            },
        },
        {
            id = 'cash', label = Kora.lang('ui.cash'), icon = 'dollar-sign',
            defaultTab = 'withdraw',
            tabs = {
                {
                    id = 'withdraw', label = Kora.lang('ui.withdraw'),
                    content = {
                        title = snapshot.mode == 'atm' and Kora.lang('ui.atm_withdraw') or Kora.lang('ui.withdraw_cash'),
                        description = snapshot.mode == 'atm' and (Config.useDailyLimit and Kora.lang('ui.remaining_daily_limit', money(snapshot.limits.daily or 0)) or Kora.lang('ui.personal_withdraw')) or Kora.lang('ui.account_balance_hint'),
                        actions = { cashActions[1] }, blocks = { { type = 'text', text = Kora.lang('ui.cash_on_hand_format', money(snapshot.profile.cash)) } },
                    },
                },
                {
                    id = 'deposit', label = Kora.lang('ui.deposit'),
                    content = {
                        title = Kora.lang('ui.deposit_cash'), description = Kora.lang('ui.deposit_description'),
                        actions = { cashActions[2] }, blocks = { { type = 'text', text = Kora.lang('ui.cash_on_hand_format', money(snapshot.profile.cash)) } },
                    },
                },
            },
        },
    }

    if snapshot.mode ~= 'atm' then
        navigation[#navigation + 1] = {
            id = 'transfer', label = Kora.lang('ui.transfer'), icon = 'arrow-right',
            defaultTab = 'accounts',
            tabs = {
                {
                    id = 'accounts', label = Kora.lang('ui.my_accounts'),
                    content = {
                        title = Kora.lang('ui.move_money'), description = Kora.lang('ui.transfer_security'),
                        actions = {
                    {
                        id = 'banking:transfer:internal', label = Kora.lang('ui.between_accounts'), icon = 'arrow-right', variant = 'primary',
                        fields = {
                            { id = 'from', label = Kora.lang('ui.from'), type = 'select', options = accountSelect, default = selected and selected.name or 'checking', required = true },
                            { id = 'to', label = Kora.lang('ui.to'), type = 'select', options = accountSelect, required = true },
                            { id = 'amount', label = Kora.lang('ui.amount'), type = 'number', min = minTransfer, max = maxTransfer, required = true,
                                placeholder = '0', presets = amountPresets(), description = Kora.lang('ui.source_balance_hint') .. (minTransfer > 1 and Kora.lang('ui.minimum_transfer', money(minTransfer)) or '') .. (maxTransfer and Kora.lang('ui.max_transfer_note', money(maxTransfer)) or '') },
                            { id = 'reason', label = Kora.lang('ui.reference'), type = 'text', placeholder = Kora.lang('ui.optional'), maxLength = 50 },
                        },
                    },
                        },
                    },
                },
                {
                    id = 'player', label = Kora.lang('ui.another_player'),
                    content = {
                        title = Kora.lang('ui.send_player'), description = (Config.Transfers and Config.Transfers.allowOffline == false) and Kora.lang('ui.recipient_online') or Kora.lang('ui.send_offline'),
                        actions = {
                    {
                        id = 'banking:transfer:player', label = Kora.lang('ui.to_player'), icon = 'arrow-right', variant = 'secondary',
                        fields = {
                            { id = 'from', label = Kora.lang('ui.from'), type = 'select', options = accountSelect, default = selected and selected.name or 'checking', required = true },
                            { id = 'recipient', label = (Config.Transfers and Config.Transfers.allowCardNumbers == false) and Kora.lang('ui.recipient_account') or Kora.lang('ui.recipient_card'), type = 'text', required = true, minLength = 1 },
                            { id = 'amount', label = Kora.lang('ui.amount'), type = 'number', min = minTransfer, max = maxTransfer, required = true,
                                placeholder = '0', presets = amountPresets(), description = Kora.lang('ui.source_balance_hint') .. (minTransfer > 1 and Kora.lang('ui.minimum_transfer', money(minTransfer)) or '') .. (maxTransfer and Kora.lang('ui.max_transfer_note', money(maxTransfer)) or '') },
                            { id = 'reason', label = Kora.lang('ui.reference'), type = 'text', placeholder = Kora.lang('ui.optional'), maxLength = 50 },
                        },
                    },
                        },
                    },
                },
            },
        }

        navigation[#navigation + 1] = {
            id = 'manage', label = Kora.lang('ui.manage'), icon = 'settings',
            defaultTab = 'shared',
            tabs = {
                {
                    id = 'shared', label = Kora.lang('ui.shared_accounts'),
                    content = {
                        title = Kora.lang('ui.create_shared'), description = Kora.lang('ui.shared_funding'),
                        blocks = {
                            { type = 'list', id = 'managed-shared-accounts', title = Kora.lang('ui.your_shared_accounts'), layout = 'cards',
                                items = managedItems, empty = Kora.lang('ui.no_shared_accounts') },
                        },
                        actions = {
                    {
                        id = 'banking:create-shared', label = Kora.lang('ui.create_shared_action'), icon = 'plus', variant = 'primary',
                        fields = {
                            { id = 'name', label = Kora.lang('ui.account_name'), type = 'text', required = true },
                            { id = 'amount', label = Kora.lang('ui.opening_balance'), type = 'number', min = 0, required = true, default = 0 },
                        },
                    },
                        },
                    },
                },
                {
                    id = 'card', label = Kora.lang('ui.card'),
                    content = {
                        title = Kora.lang('ui.issue_card'), description = Kora.lang('ui.card_required'),
                        blocks = {
                            { type = 'list', id = 'issued-bank-cards', title = Kora.lang('ui.issued_cards'), layout = 'cards',
                                items = cardItems, empty = Kora.lang('ui.no_cards') },
                        },
                        actions = {
                    {
                        id = 'banking:order-card', label = Kora.lang('ui.issue_card_action'), icon = 'credit-card', variant = 'secondary',
                        fields = { { id = 'pin', label = Kora.lang('ui.choose_pin'), type = 'password', required = true,
                            minLength = 4, maxLength = 4, pattern = '^\\d{4}$', numericOnly = true, keypad = true,
                            keypadActionVariant = 'outline' } },
                    },
                        },
                    },
                },
                {
                    id = 'access', label = Kora.lang('ui.account_access'),
                    content = {
                        title = Kora.lang('ui.manage_access'), description = Kora.lang('ui.owner_access'),
                        blocks = {
                    {
                        type = 'actions', title = Kora.lang('ui.account_access'), actions = {
                            {
                                id = 'banking:rename-shared', label = Kora.lang('ui.rename_shared'), icon = 'pencil', variant = 'outline', disabled = #managedAccounts == 0,
                                fields = {
                                    { id = 'account', label = Kora.lang('ui.account'), type = 'select', options = managedAccounts, required = true },
                                    { id = 'name', label = Kora.lang('ui.new_name'), type = 'text', required = true },
                                },
                            },
                            {
                                id = 'banking:add-member', label = Kora.lang('ui.grant_access'), icon = 'user', variant = 'outline', disabled = #managedAccounts == 0,
                                fields = {
                                    { id = 'account', label = Kora.lang('ui.account'), type = 'select', options = managedAccounts, required = true },
                                    { id = 'citizenid', label = Kora.lang('ui.citizen_id'), type = 'text', required = true },
                                },
                            },
                            {
                                id = 'banking:remove-member', label = Kora.lang('ui.revoke_access'), icon = 'user', variant = 'destructive', disabled = #managedAccounts == 0,
                                confirm = Kora.lang('ui.remove_member_confirm'),
                                fields = {
                                    { id = 'account', label = Kora.lang('ui.account'), type = 'select', options = managedAccounts, required = true },
                                    { id = 'citizenid', label = Kora.lang('ui.citizen_id'), type = 'text', required = true },
                                },
                            },
                            {
                                id = 'banking:delete-shared', label = Kora.lang('ui.close_shared'), icon = 'trash-2', variant = 'destructive', disabled = #managedAccounts == 0,
                                confirm = Kora.lang('ui.close_confirm'),
                                fields = { { id = 'account', label = Kora.lang('ui.account'), type = 'select', options = managedAccounts, required = true } },
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
                table.insert(content.blocks, 1, { type = 'text', title = Kora.lang('ui.branch_unavailable'), text = Kora.lang('ui.available_at', where) })
                tab.content = content
            end
        end
    end

    local branchTitle = branch and (branch.label or branch.tierLabel) or nil
    local branchDescription = Kora.lang('secure_services')
    if branch and branch.tierLabel and branch.tierLabel ~= branchTitle then branchDescription = branch.tierLabel .. ' · ' .. branchDescription end
    return {
        id = APP_ID, title = branchTitle or (snapshot.mode == 'atm' and Kora.lang('atm') or Kora.lang('bank')),
        description = snapshot.mode == 'atm' and Kora.lang('ui.personal_banking') or branchDescription, icon = 'dollar-sign',
        accent = type(Config.ui.accent) == 'string' and Config.ui.accent or nil,
        layout = snapshot.mode == 'atm' and 'compact' or 'standard',
        width = snapshot.mode == 'atm' and 540 or 1180, height = snapshot.mode == 'atm' and 720 or 760,
        defaultView = snapshot.mode == 'atm' and 'cash' or 'accounts', navigation = navigation,
        footer = Kora.lang('ui.transaction_footer'),
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
                local message = err or Kora.lang('error.pin')
                notify(message)
                return { notice = { tone = 'destructive', message = message } }
            end
            currentSnapshot = snapshot
            selectedAccount = 'checking'
            return { update = appUpdate() }
        end

        if actionId == 'banking:select-account' then
            local account = accountByName(context and context.itemId)
            if not account then error(Kora.lang('error.account')) end
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
            error(Kora.lang('error.unknown_action'))
        end

        local result, err = request('action', payload)
        if not result then
            notify(err or Kora.lang('error.transaction_declined'))
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
    TriggerServerEvent('kora_banking:close')
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
        if not snapshot then return notify(err or Kora.lang('error.cannot_access')) end
        currentSnapshot = snapshot
        selectedAccount = 'checking'
        appOpen = true
        if mode == 'atm' and type(location) == 'table' then
            if Kora.cache.vehicle() and Config.atmCloseInVehicle ~= false then
                appOpen = false
                currentSnapshot = nil
                TriggerServerEvent('kora_banking:close')
                return notify(Config.atmVehicleMessage or Kora.lang('error.atm_vehicle'))
            end
            watchAtmSession(location)
        end
        refreshApp()
        local result = Kora.nui.openApp(APP_ID, { viewId = snapshot.locked and 'unlock' or 'accounts' })
        atmSession = nil
        closeSession()
        if result == nil then notify(Kora.lang('error.interface_failed')) end
    end)
end

-- Same reach as the server's nearAtm: centre-to-ped distance within atmDistance + atmTolerance.
local function distanceSquared(point)
    local ped = GetEntityCoords(PlayerPedId())
    local dx, dy, dz = ped.x - point.x, ped.y - point.y, ped.z - point.z
    return dx * dx + dy * dy + dz * dz
end

local function inAtmReach(point)
    local limit = Config.atmDistance + (Config.atmTolerance or 1.0)
    return distanceSquared(point) <= limit * limit
end

local function nearAtm()
    local coords = GetEntityCoords(PlayerPedId())
    local radius = Config.atmDistance + (Config.atmTolerance or 1.0)
    local best, bestDistance
    for _, modelName in ipairs(Config.atmModels) do
        local entity = GetClosestObjectOfType(coords.x, coords.y, coords.z, radius, joaat(modelName), false, false, false)
        if entity ~= 0 then
            -- Wide props can be returned although their origin is out of reach, so only the nearest in-reach one counts.
            local point = GetEntityCoords(entity)
            local d = distanceSquared(point)
            if inAtmReach(point) and (not bestDistance or d < bestDistance) then best, bestDistance = entity, d end
        end
    end
    return best
end

-- Map-baked ATMs are not entities, so Config.atmCoords is the fallback for the closest listed machine within reach.
local function nearAtmCoords()
    local coords = GetEntityCoords(PlayerPedId())
    local radius = Config.atmDistance + (Config.atmTolerance or 1.0)
    return Kora.util.nearest(Config.atmCoords or {}, coords, {
        radius = radius,
        coordsOf = function(atm) return atm end,
    })
end

-- Where the ATM is: the fixed zone coordinates, the aimed/nearest ATM entity, or the nearest fallback coordinates.
local function atmPosition(target, fixed)
    if fixed then return inAtmReach(fixed) and fixed or nil end
    local entity = type(target) == 'number' and target ~= 0 and DoesEntityExist(target) and target or nearAtm()
    if entity then
        local coords = GetEntityCoords(entity)
        if inAtmReach(coords) then return { x = coords.x, y = coords.y, z = coords.z } end
    end
    local atm = nearAtmCoords()
    if atm and inAtmReach(atm) then return { x = atm.x, y = atm.y, z = atm.z } end
    return nil
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
        return notify(Config.atmVehicleMessage or Kora.lang('error.atm_vehicle'))
    end
    local position = atmPosition(target, fixed)
    if not position then return notify(Kora.lang('error.near_atm')) end

    openingAtm = true
    CreateThread(function()
        -- Refuse before any animation or progress bar when the card is missing or the server says we are too far (the server stays the authority).
        local hasCard, cardErr = request('atmCard', position)
        if not hasCard then
            openingAtm = false
            return notify(cardErr or Config.atmNoCardMessage or Kora.lang('error.need_card'))
        end
        local ok, completed, err = pcall(Kora.progressbar.start, {
            label = Kora.lang('progress.atm'), duration = Config.atmAccessTime, canCancel = true,
            -- Config.atmAccessMovement: 'controls' ignores the movement keys, only 'freeze' freezes the ped in place.
            disable = { move = true, moveMode = Config.atmAccessMovement == 'freeze' and 'freeze' or 'controls', combat = true, car = true },
            -- The clip is bounded by the access time so it can not loop if the bar is never cleaned up.
            anim = { dict = ATM_ANIM.dict, clip = ATM_ANIM.clip, duration = Config.atmAccessTime > 0 and Config.atmAccessTime or nil },
            props = { { model = 'prop_cs_credit_card', bone = 28422, offset = vector3(0.1, 0.03, -0.05), rotation = vector3(0.0, 0.0, 180.0) } },
        })
        openingAtm = false
        stopAtmAnimation()
        if not ok then
            print(('[kora_banking] ATM progress bar failed: %s'):format(tostring(completed)))
            return notify(Kora.lang('error.atm_start_failed'))
        end
        if not completed then
            if err then notify(err) end
            return
        end
        local current = atmPosition(target, fixed)
        if not current then return notify(Kora.lang('error.near_atm')) end
        open('atm', current)
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
                { icon = 'building-columns', label = info.enabled and info.label and Kora.lang('ui.open_branch', info.label) or Kora.lang('ui.open_bank'),
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
                    { icon = 'credit-card', label = Kora.lang('ui.use_atm'), distance = Config.atmDistance, onSelect = function() accessAtm(nil, fixed) end,
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
            { icon = 'credit-card', label = Kora.lang('ui.use_atm'), onSelect = accessAtm, canInteract = showAtmOption },
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

RegisterNetEvent('kora_banking:client:useCard', accessAtm)
RegisterNetEvent('qb-banking:client:useCard', accessAtm)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= RESOURCE then return end
    closeSession()
    for _, targetId in pairs(branchTargetIds) do pcall(function() exports.kora_target:removeZone(targetId) end) end
    if atmTargetId then pcall(function() exports.kora_target:removeModel(Config.atmModels, atmTargetId) end) end
end)
