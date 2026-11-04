-- The FiveM client has no os library.
local realOs = os
os = nil
local root = debug.getinfo(1, 'S').source:sub(2):match('(.*/)') .. '../'
local netEvents, branchOptions, apps, atmOptions, createdBlips = {}, nil, {}, nil, {}
local atmZones = {}
local notifications = {}
local removedBlips, configHandlers = {}, {}
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
local stoppedAnims, targetExists = 0, true
_G.DoesEntityExist = function() return targetExists end
_G.StopAnimTask = function() stoppedAnims = stoppedAnims + 1 end
_G.RemoveAnimDict = function() end
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

noCard = false
local lastOpenLocation
_G.TriggerServerEvent = function(name, requestId, operation, mode, location)
    if name == 'qbbanking:close' then return end
    if operation == 'open' then lastOpenLocation = location end
    local result
    if operation == 'atmCard' then
        netEvents['qbbanking:client:response'](requestId, (not noCard) or nil, noCard and 'You need a bank card to use an ATM.' or nil)
        return
    end
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
        addSphereZone = function(_, options)
            if options.options[1].label == 'Use ATM' then atmZones[#atmZones + 1] = options; return 'atm-zone' end
            branchOptions = options.options
            return 'branch-target'
        end,
        removeZone = function() end,
        addModel = function(_, _, options) atmOptions = options; return 'atm-target' end,
        removeModel = function() end,
    },
}

_G.Kora = {
    util = {
        nearest = function(list, position, opts)
            local best, bestDistance
            for _, entry in pairs(list) do
                local coords = opts.coordsOf(entry)
                local dx, dy, dz = (position.x or 0) - (coords.x or 0), (position.y or 0) - (coords.y or 0), (position.z or 0) - (coords.z or 0)
                local distance = math.sqrt(dx * dx + dy * dy + dz * dz)
                if (opts.radius == nil or distance <= opts.radius) and (bestDistance == nil or distance < bestDistance) then
                    best, bestDistance = entry, distance
                end
            end
            return best, bestDistance
        end,
    },
    blips = {
        create = function(coords, options)
            createdBlips[#createdBlips + 1] = { coords = coords, options = options }
            return #createdBlips
        end,
        remove = function(blip) removedBlips[#removedBlips + 1] = blip return true end,
    },
    config = { onChange = function(path, handler) configHandlers[path] = handler end },
    cache = { onChange = function() end, vehicle = function() return false end, coords = function() return vector3(0.0, 0.0, 0.0) end },
    notify = { send = function(payload) notifications[#notifications + 1] = payload end },
    progressbar = { start = function() return true end },
    nui = {
        closeApp = function() return true end,
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
dofile(root .. 'tiers.lua')
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
for _, model in ipairs({ 'prop_atm_01', 'prop_atm_02', 'prop_atm_03', 'prop_fleeca_atm' }) do
    truthy(contains(Config.atmModels, model), model .. ' is a targetable ATM model')
end
truthy(contains(Config.atmModels, 'v_5_b_atm1') and contains(Config.atmModels, 'v_5_b_atm2'), 'bank lobby wall ATMs are targetable')
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
truthy(activity.rows[1].date.label:match('^%d%d/%d%d/%d%d%d%d'), 'activity dates render as formatted dates, not table addresses')
Config.dateFormat = 'YYYY-MM-DD'
Config.showTime = false
equal(BankingDates.format(1793326800000, { format = Config.dateFormat, showTime = Config.showTime, utc = true }), '2026-10-30', 'Config options drive the formatter')
equal(activity.rows[1].date.value, 1793326800000, 'activity date keeps the UTC epoch as the sortable value')
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
local unlockContent = locked.navigation[1].content
equal(locked.title, 'Kora ATM', 'the locked ATM header uses Kora branding')
equal(unlockContent.title, 'Enter your bank card PIN', 'the PIN heading has no hyphen')
equal(unlockContent.description, 'Repeated incorrect PIN entries will result in a temporary account lockout.', 'the lockout warning replaces the server note')
equal(#unlockContent.blocks, 1, 'the locked ATM has no Card required box')
equal(unlockContent.blocks[1].title, 'Secure Keypad', 'the keypad form is titled Secure Keypad')
local pin = unlockContent.blocks[1].fields[1]
equal(pin.label, 'PIN', 'the PIN field label is just PIN')
equal(pin.required, nil, 'the PIN field is not marked required (no asterisk or Required. text)')
equal(pin.description, 'Never share your PIN with anyone.', 'the PIN hint is the share warning')
truthy(pin.keypad and pin.numericOnly, 'the PIN field uses the compact numeric keypad')
equal(pin.labelAlign, 'center', 'the PIN label is centred above the keypad')
equal(pin.keypadActionVariant, 'outline', 'the keypad Clear and Backspace keys are outlined like the digits')
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

-- Tiers off (default): header and markers are unchanged. Tiers on: label in the header, gated actions disabled with a clear message.
equal(defaultBank.title, 'Kora Bank', 'the header is unchanged while tiers are disabled')
bankSnapshot.profile.cash = 700
bankSnapshot.branch = {
    label = 'Fleeca Bank - Test', tier = 'fleeca', tierLabel = 'Fleeca Bank',
    gated = { sharedAccounts = 'Pacific Standard', manageMembers = 'Pacific Standard' },
}
bankSnapshot.limits = { min = { withdraw = 1, deposit = 1, transfer = 1 }, maxTransfer = 10000, counterDaily = 5000 }
branchOptions[1].onSelect()
local tiered = apps[#apps]
equal(tiered.title, 'Fleeca Bank - Test', 'the header shows the branch label')
truthy(tiered.description:find('Fleeca Bank', 1, true), 'the header description shows the tier')
local tieredManage = view(tiered, 'manage')
local sharedTab = tab(tieredManage, 'shared').content
truthy(sharedTab.actions[1].disabled, 'creating a shared account is disabled at a Fleeca branch')
equal(sharedTab.blocks[1].text, 'Available at Pacific Standard.', 'the disabled action says where it is available')
truthy(not tab(tieredManage, 'card').content.actions[1].disabled, 'bank cards stay available at a Fleeca branch')
local accessBlock = tab(tieredManage, 'access').content.blocks
equal(accessBlock[1].text, 'Available at Pacific Standard.', 'member management shows the gate note')
for _, action in ipairs(accessBlock[2].actions) do truthy(action.disabled, action.id .. ' is disabled at a Fleeca branch') end
truthy(not tab(view(tiered, 'cash'), 'deposit').content.actions[1].disabled, 'deposits stay enabled at a Fleeca branch')
local tieredWithdraw = tab(view(tiered, 'cash'), 'withdraw').content.actions[1]
equal(tieredWithdraw.fields[2].max, 5000, 'the counter daily allowance caps the withdrawal input')
equal(tab(view(tiered, 'transfer'), 'player').content.actions[1].fields[3].max, 10000, 'the transfer input shows the tier maximum')
equal(view(tiered, 'accounts').tabs[1].content.blocks[1].items[3].value, 'Fleeca Bank', 'the summary shows the branch tier')
bankSnapshot.branch.gated = {}
branchOptions[1].onSelect()
local bigTier = apps[#apps]
truthy(not tab(view(bigTier, 'manage'), 'shared').content.actions[1].disabled, 'nothing is disabled when the tier gates nothing')
bankSnapshot.branch, bankSnapshot.limits = nil, nil

Config.tiers.enabled = true
for index = #createdBlips, 1, -1 do createdBlips[index] = nil end
dofile(root .. 'client.lua')
equal(createdBlips[1].options.sprite, Config.tiers.list.fleeca.blip.sprite, 'fleeca markers use the fleeca sprite')
equal(createdBlips[7].options.sprite, 106, 'Pacific Standard uses its own sprite')
equal(createdBlips[7].options.color, 5, 'Pacific Standard uses its own colour')
equal(createdBlips[7].options.name, 'Pacific Standard', 'the location label names the marker')
equal(createdBlips[7].options.category, 'Bank', 'tier markers stay in the Bank category')
equal(branchOptions[1].label, 'Open Blaine County Savings', 'targets use the location label (the mock keeps the last zone)')
Config.tiers.enabled = false

-- The server config arrives after this script has run: the change handlers rebuild markers and prompts.
truthy(configHandlers['tiers.enabled'] and configHandlers['tiers.default'], 'tier settings are watched for config updates')
for index = #createdBlips, 1, -1 do createdBlips[index] = nil end
removedBlips = {}
Config.tiers.enabled = true
configHandlers['tiers.enabled']()
equal(#removedBlips, #Config.locations, 'a config update removes the old markers')
equal(createdBlips[7].options.sprite, 106, 'a config update recreates markers with tier styling')
equal(branchOptions[1].label, 'Open Blaine County Savings', 'a config update re-registers the branch prompts with branch names')
Config.tiers.enabled = false

print(('qbbanking client: %d assertions passed'):format(passed))

-- The ATM animation is always stopped, and a failing progress bar notifies instead of leaving the player stuck.
local realStart = Kora.progressbar.start
local noticesBefore, stopsBefore = #notifications, stoppedAnims
Kora.progressbar.start = function(payload)
    equal(payload.anim.duration, Config.atmAccessTime, 'the ATM clip is bounded by the access time')
    equal(payload.disable.moveMode, 'controls', 'the ATM bar never freezes the ped in place by default')
    return false
end
atmOptions[1].onSelect(44)
Config.atmAccessMovement = 'freeze'
Kora.progressbar.start = function(payload)
    equal(payload.disable.moveMode, 'freeze', 'atmAccessMovement=freeze keeps the legacy freeze')
    return false
end
atmOptions[1].onSelect(44)
Config.atmAccessMovement = 'controls'
stopsBefore = stopsBefore + 1
equal(stoppedAnims, stopsBefore + 1, 'cancelling the ATM bar stops the animation')
Kora.progressbar.start = function() error('boom') end
atmOptions[1].onSelect(44)
equal(stoppedAnims, stopsBefore + 2, 'a crashing ATM bar still stops the animation')
equal(#notifications, noticesBefore + 1, 'a crashing ATM bar notifies the player')
Kora.progressbar.start = function() return false, 'A progress bar is already active.' end
atmOptions[1].onSelect(44)
equal(notifications[#notifications].message, 'A progress bar is already active.', 'a refused ATM bar explains why')
Kora.progressbar.start = realStart

-- No bank card: only the error notification, no progress bar and no animation.
noCard = true
local barCalls, noticesNoCard = 0, #notifications
Kora.progressbar.start = function() barCalls = barCalls + 1 return true end
atmOptions[1].onSelect(44)
equal(barCalls, 0, 'no bank card starts no progress bar or animation')
equal(notifications[#notifications].message, 'You need a bank card to use an ATM.', 'no bank card shows the error notification')
equal(#notifications, noticesNoCard + 1, 'no bank card shows exactly one notification')
Config.requireBankCard = false
atmOptions[1].onSelect(44)
equal(barCalls, 1, 'requireBankCard=false leaves the ATM flow unchanged')
Config.requireBankCard = true
noCard = false
Kora.progressbar.start = realStart
atmOptions[1].onSelect(44)

-- Map-baked ATMs: Config.atmCoords registers one Use ATM zone per coordinate and opens at that coordinate, not at a prop.
equal(atmZones[1].coords.x, 147.4, 'the default fallback zones cover the Legion Square Fleeca ATMs')
equal(atmZones[2].coords.x, 145.9, 'the default fallback zones cover both Legion Square Fleeca ATMs')
for index = #atmZones, 1, -1 do atmZones[index] = nil end
Config.atmCoords = { vector3(111.5, 222.5, 33.5), vector3(-44.0, 55.0, 6.0) }
dofile(root .. 'client.lua')
equal(#atmZones, 2, 'every Config.atmCoords entry registers an ATM zone')
equal(atmZones[1].coords.x, 111.5, 'the ATM zone sits on the configured coordinate')
equal(atmZones[1].radius, Config.atmZoneRadius, 'the ATM zone uses Config.atmZoneRadius')
atmZones[2].options[1].onSelect()
equal(lastOpenLocation.x, -44.0, 'a fallback zone opens the ATM at its own coordinate')
_G.GetClosestObjectOfType = function() return 0 end
targetExists = false
atmOptions[1].onSelect()
equal(notifications[#notifications].message, 'Move closer to an ATM.', 'away from every ATM the player is asked to move closer')
_G.GetEntityCoords = function() return vector3(111.0, 222.0, 33.0) end
atmOptions[1].onSelect()
equal(lastOpenLocation.x, 111.5, 'the event fallback finds a map-baked ATM from Config.atmCoords')

-- Zone dedupe: a fallback zone stays out of the way while the aimed prop is already an ATM model target.
_G.GetGameTimer = function() return 100000 end
_G.GetEntityModel = function(entity) return entity == 77 and 'prop_atm_01' or 'prop_bench_01' end
local zoneOption = atmZones[1].options[1]
equal(zoneOption.canInteract(77), false, 'the fallback zone hides when the aimed entity is an ATM model')
equal(zoneOption.canInteract(78), true, 'the fallback zone shows for other aimed entities')
equal(zoneOption.canInteract(nil), true, 'the fallback zone shows when the ray hits no entity')

-- Always-show target: with a missing card the option still shows and selecting it only notifies.
noCard = true
equal(atmOptions[1].canInteract(), true, 'the Use ATM target shows without a bank card by default')
local noticesAlways = #notifications
atmOptions[1].onSelect(44)
equal(notifications[#notifications].message, 'You need a bank card to use an ATM.', 'the server reply is shown when it gives one')
equal(#notifications, noticesAlways + 1, 'selecting the target without a card notifies once')

-- alwaysShowTarget off: the target follows the server card answer, refreshed on demand.
Config.atmAlwaysShowTarget = false
equal(atmOptions[1].canInteract(), false, 'without a card the target is hidden when alwaysShowTarget is off')
noCard = false
_G.GetGameTimer = function() return 200000 end
atmOptions[1].canInteract()
equal(atmOptions[1].canInteract(), true, 'the target shows once the server reports a card')
Config.requireBankCard = false
noCard = true
equal(atmOptions[1].canInteract(), true, 'the target always shows when cards are not required')
Config.requireBankCard = true
Config.atmAlwaysShowTarget = true
