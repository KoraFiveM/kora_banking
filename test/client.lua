-- The FiveM client has no os library.
local realOs = os
os = nil
local root = debug.getinfo(1, 'S').source:sub(2):match('(.*/)') .. '../'
local netEvents, branchOptions, apps, atmOptions, createdBlips = {}, nil, {}, nil, {}
local notifications = {}
local actionError
local pinError
local unlockResult

_G.vector3 = function(x, y, z) return { x = x, y = y, z = z } end
_G.GetCurrentResourceName = function() return 'kora_banking' end
_G.RegisterNetEvent = function(name, handler) netEvents[name] = handler end
_G.AddEventHandler = function() end
_G.CreateThread = function(handler) handler() end
_G.SetTimeout = function() end
_G.RegisterCommand = function() end
_G.PlayerPedId = function() return 1 end
_G.GetEntityCoords = function(entity)
    if entity == 44 then return vector3(10, 20, 30) end
    return vector3(0, 0, 0)
end
_G.GetClosestObjectOfType = function() return 44 end
_G.joaat = function(value) return value end
_G.promise = { new = function()
    local value = {}
    function value:resolve(result) self.value = result end
    return value
end }
_G.Citizen = { Await = function(value) return value.value end }

local bankSnapshot = {
    mode = 'bank', locked = false, profile = { cash = 700, cards = { { name = 'Bank card', number = '**** 1234' } } },
    accounts = {
        { name = 'checking', owner = 'Jamie', label = 'Personal', balance = 2400, type = 'checking' },
        { name = 'club', owner = 'Club Account', label = 'Shared', balance = 900, type = 'shared', canManage = true },
    },
    transactions = { checking = { { id = 1, statement_type = 'deposit', amount = 125, reason = 'Pay', date = 1793326800000 } } },
}
local lockedAtm = { mode = 'atm', locked = true, profile = { cash = 700 }, accounts = {}, limits = { daily = 5000, maxAccounts = 2 } }
local unlockedAtm = {
    mode = 'atm', locked = false, profile = { cash = 700 },
    accounts = { { name = 'checking', owner = 'Jamie', label = 'Personal', balance = 2400, type = 'checking' } },
    transactions = { checking = {} },
    limits = { daily = 5000, maxAccounts = 2 },
}

_G.TriggerServerEvent = function(name, requestId, operation, mode)
    if name == 'qbbanking:close' then return end
    local result
    if operation == 'open' then result = mode == 'atm' and lockedAtm or bankSnapshot
    elseif operation == 'pin' then
        result = pinError and nil or unlockedAtm
        if pinError then result = false end
    end
    netEvents['qbbanking:client:response'](requestId, result,
        operation == 'action' and actionError or operation == 'pin' and pinError or nil)
end

_G.exports = {
    kora_target = {
        addSphereZone = function(_, options) branchOptions = options.options; return 'branch-target' end,
        removeZone = function() end,
        addModel = function(_, _, options) atmOptions = options; return 'atm-target' end,
        removeModel = function() end,
    },
}

_G.Kora = {
    blips = {
        create = function(coords, options)
            createdBlips[#createdBlips + 1] = { coords = coords, options = options }
            return #createdBlips
        end,
    },
    notify = { send = function(payload) notifications[#notifications + 1] = payload end },
    progressbar = { start = function() return true end },
    nui = {
        registerApp = function(definition) apps[#apps + 1] = definition end,
        openApp = function()
            local definition = apps[#apps]
            if definition.navigation[1].id == 'unlock' then
                unlockResult = definition.onAction('banking:unlock', { value = { pin = '1234' } })
            end
            return { closed = true }
        end,
    },
}

dofile(root .. 'config.lua')
dofile(root .. 'dates.lua')
dofile(root .. 'client.lua')

local passed = 0
local function equal(actual, expected, message)
    if actual ~= expected then error(('%s: expected %s, got %s'):format(message, tostring(expected), tostring(actual)), 2) end
    passed = passed + 1
end
local function truthy(value, message)
    if not value then error(message, 2) end
    passed = passed + 1
end
local function contains(values, expected)
    for _, value in ipairs(values) do
        if value == expected then return true end
    end
    return false
end
local function view(definition, id)
    for _, candidate in ipairs(definition.navigation) do if candidate.id == id then return candidate end end
end
local function tab(candidate, id)
    for _, value in ipairs(candidate.tabs or {}) do if value.id == id then return value end end
end

truthy(contains(Config.atmModels, 'gabz_sm_pb_atmframe'), 'the Gabz Fleeca ATM frame is targetable')
equal(#createdBlips, #Config.locations, 'every configured branch creates one kora_lib-owned marker')
equal(createdBlips[1].options.category, 'Bank', 'branch markers share the canonical Bank category')
equal(createdBlips[1].options.name, nil, 'generic bank markers do not repeat the category as a name')
equal(createdBlips[1].options.label, nil, 'kora_lib composes the map label')

branchOptions[1].onSelect()
local bank = apps[#apps]
equal(bank.id, 'qbbanking:bank', 'banking registers the shared AppShell')
equal(bank.layout, 'standard', 'a branch uses the standard workspace')
local accounts = view(bank, 'accounts').tabs[1].content.blocks[2]
equal(accounts.layout, 'cards', 'accounts use cards')
truthy(accounts.searchable, 'accounts are searchable')
local deposit = tab(view(bank, 'cash'), 'deposit').content.actions[1]
equal(deposit.fields[2].max, 700, 'deposit validation reflects cash on hand')
equal(#deposit.fields[2].presets, 4, 'amount presets are available')
local branchWithdraw = tab(view(bank, 'cash'), 'withdraw').content.actions[1]
equal(branchWithdraw.fields[2].description, 'Each account option shows its current available balance.',
    'branch withdrawal feedback remains accurate when the form account changes')
local activity = tab(view(bank, 'accounts'), 'activity').content.blocks[1]
truthy(activity.searchable and activity.pageSize == 10, 'activity is searchable and paged')
truthy(activity.rows[1].date:match('^%d%d/%d%d/%d%d%d%d'), 'activity dates render as formatted dates, not table addresses')
Config.dateFormat = 'YYYY-MM-DD'
Config.showTime = false
equal(BankingDates.format(1793326800000, { format = Config.dateFormat, showTime = Config.showTime, utc = true }), '2026-10-30', 'Config options drive the formatter')
truthy(activity.rows[1].type.badge, 'transaction status uses a rich badge cell')
local manageView = view(bank, 'manage')
local sharedBlocks = tab(manageView, 'shared').content.blocks
local cardBlocks = tab(manageView, 'card').content.blocks
equal(sharedBlocks[1].items[1].label, 'Club Account', 'owned shared accounts are shown in Manage')
equal(cardBlocks[1].items[1].description, '**** 1234', 'issued bank cards are shown in Manage')

atmOptions[1].onSelect()
local locked = apps[#apps]
equal(locked.layout, 'compact', 'a locked ATM uses compact layout')
equal(locked.width, 460, 'the secure keypad permits a narrow ATM frame')
local pin = locked.navigation[1].content.blocks[2].fields[1]
truthy(pin.keypad and pin.numericOnly, 'the PIN field uses the compact numeric keypad')
equal(pin.minLength, 4, 'the PIN field requires four digits')
equal(pin.maxLength, 4, 'the PIN field rejects extra digits')

pinError = 'Incorrect PIN.'
local rejectedPin = locked.onAction('banking:unlock', { value = { pin = '0000' } })
equal(rejectedPin.notice.message, 'Incorrect PIN.', 'an invalid ATM PIN returns the server error message')
equal(rejectedPin.notice.tone, 'destructive', 'an invalid ATM PIN returns a destructive notice')
equal(notifications[#notifications].message, 'Incorrect PIN.', 'an invalid ATM PIN is shown in the banking toast')
pinError = nil

equal(unlockResult.update.layout, 'compact', 'unlock remains in the compact ATM shell')
local withdrawTab = tab(view({ navigation = unlockResult.update.navigation }, 'cash'), 'withdraw')
local withdraw = withdrawTab.content.actions[1]
equal(withdraw.fields[2].max, 2400, 'ATM withdrawals expose the selected available balance')
equal(#withdraw.fields[2].presets, 4, 'ATM withdrawals retain compact amount presets')
equal(withdrawTab.content.description, 'Remaining daily withdrawal limit: $5000.', 'ATM withdrawal copy shows the remaining limit')

unlockedAtm.limits.daily = 3000
local refreshedAtm = locked.onAction('banking:unlock', { value = { pin = '1234' } })
local refreshedWithdraw = tab(view({ navigation = refreshedAtm.update.navigation }, 'cash'), 'withdraw').content.actions[1]
equal(refreshedWithdraw.fields[2].max, 2400, 'ATM withdrawal maximum uses the smaller account balance')
unlockedAtm.accounts[1].balance = 5000
local refreshedAtmWithLimit = locked.onAction('banking:unlock', { value = { pin = '1234' } })
local limitedWithdraw = tab(view({ navigation = refreshedAtmWithLimit.update.navigation }, 'cash'), 'withdraw').content.actions[1]
equal(limitedWithdraw.fields[2].max, 3000, 'ATM withdrawal maximum uses the remaining global limit')
unlockedAtm.accounts[1].balance = 2400
unlockedAtm.limits.daily = 5000

actionError = 'Above the limit of what you may withdraw at this ATM.'
local rejectedWithdrawal = locked.onAction('banking:withdraw', { value = { account = 'checking', amount = 6000 } })
truthy(rejectedWithdrawal and next(rejectedWithdrawal) == nil, 'a rejected ATM withdrawal returns a valid empty action result')
equal(notifications[#notifications].message, actionError, 'an ATM limit rejection is shown in the banking toast')
actionError = nil

-- Configured minimums reach the form inputs and helper text; defaults keep min = 1.
bankSnapshot.profile.cash = 700
bankSnapshot.limits = { min = { withdraw = 5, deposit = 6, transfer = 7 } }
branchOptions[1].onSelect()
local minBank = apps[#apps]
local minWithdraw = tab(view(minBank, 'cash'), 'withdraw').content.actions[1]
equal(minWithdraw.fields[2].min, 5, 'withdraw input shows the configured minimum')
truthy(minWithdraw.fields[2].description:find('Minimum withdrawal: $5', 1, true), 'withdraw helper text states the minimum')
equal(tab(view(minBank, 'cash'), 'deposit').content.actions[1].fields[2].min, 6, 'deposit input shows the configured minimum')
local minTransfers = view(minBank, 'transfer').tabs
equal(minTransfers[1].content.actions[1].fields[3].min, 7, 'internal transfer input shows the configured minimum')
equal(minTransfers[2].content.actions[1].fields[3].min, 7, 'player transfer input shows the configured minimum')
bankSnapshot.limits = nil
branchOptions[1].onSelect()
local defaultBank = apps[#apps]
equal(tab(view(defaultBank, 'cash'), 'withdraw').content.actions[1].fields[2].min, 1, 'default withdraw minimum stays 1')
equal(tab(view(defaultBank, 'cash'), 'deposit').content.actions[1].fields[2].min, 1, 'default deposit minimum stays 1')

bankSnapshot.profile.cash = 0
branchOptions[1].onSelect()
local emptyDeposit = tab(view(apps[#apps], 'cash'), 'deposit').content.actions[1]
truthy(emptyDeposit.disabled, 'deposit is disabled when the player has no cash')
equal(emptyDeposit.fields[2].max, nil, 'zero cash never produces invalid min/max bounds')

unlockedAtm.accounts[1].balance = 0
atmOptions[1].onSelect()
local emptyWithdraw = tab(view({ navigation = unlockResult.update.navigation }, 'cash'), 'withdraw').content.actions[1]
truthy(emptyWithdraw.disabled, 'ATM withdrawal is disabled at a zero balance')
equal(emptyWithdraw.fields[2].max, nil, 'zero balance never produces invalid min/max bounds')

print(('qbbanking client: %d assertions passed'):format(passed))
