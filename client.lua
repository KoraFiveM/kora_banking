local RESOURCE = GetCurrentResourceName()
local ready = false
local pending = {}
local focused = false
local openingAtm = false

local function send(action, data)
    if not ready then
        pending[#pending + 1] = { action = action, data = data }
        return
    end
    SendNUIMessage({ action = action, data = data })
end

local function setFocus(value)
    if focused == value then return end
    focused = value
    SetNuiFocus(value, value)
end

local function notify(message, kind)
    QB.notify.send({ title = 'Banking', message = message, type = kind or 'error' })
end

local function request(name, ...)
    local result, err = QB.callback.trigger(name, ...)
    if result == nil and err == nil then return nil, 'The bank did not answer. Try again.' end
    return result, err
end

local function pushTheme()
    local ok, tokens = pcall(function() return QB.theme.tokens(Config.ui and Config.ui.accent or nil) end)
    if ok and type(tokens) == 'table' then send('qbbanking:theme', tokens) end
end

local function open(mode, location)
    CreateThread(function()
        local snapshot, err = request('qbbanking:open', mode, location)
        if not snapshot then return notify(err or 'You cannot access banking here.') end
        setFocus(true)
        pushTheme()
        send('qbbanking:open', snapshot)
    end)
end

local function close()
    setFocus(false)
    send('qbbanking:close', {})
    TriggerServerEvent('qbbanking:close')
end

local function nearAtm()
    local coords = GetEntityCoords(PlayerPedId())
    for _, modelName in ipairs(Config.atmModels) do
        local entity = GetClosestObjectOfType(coords.x, coords.y, coords.z, Config.atmDistance, joaat(modelName), false, false, false)
        if entity ~= 0 then return entity end
    end
end

local function accessAtm()
    if openingAtm or focused then return end
    local entity = nearAtm()
    if not entity then return notify('Move closer to an ATM.') end

    openingAtm = true
    CreateThread(function()
        local completed = QB.progressbar.start({
            label = 'Accessing ATM...',
            duration = Config.atmAccessTime,
            canCancel = true,
            disable = { move = true, combat = true, car = true },
            anim = { dict = 'amb@prop_human_atm@male@enter', clip = 'enter' },
            props = {
                {
                    model = 'prop_cs_credit_card',
                    bone = 28422,
                    offset = vector3(0.1, 0.03, -0.05),
                    rotation = vector3(0.0, 0.0, 180.0),
                },
            },
        })
        openingAtm = false
        if not completed then return end

        entity = nearAtm()
        if not entity then return notify('Move closer to an ATM.') end
        local coords = GetEntityCoords(entity)
        open('atm', { x = coords.x, y = coords.y, z = coords.z })
    end)
end

for index, coords in ipairs(Config.locations) do
    local branchIndex = index
    QB.interact.addCircleZone(('qbbanking:branch:%d'):format(index), coords, 1.2, {
        {
            icon = 'building-columns',
            label = 'Open bank',
            distance = 1.8,
            action = function() open('bank', branchIndex) end,
        },
    }, false)
end

local atmTargets = {}

local function registerAtmTargets()
    for model, id in pairs(atmTargets) do pcall(function() QB.interact.removeModel(model, id) end) end
    atmTargets = {}
    for _, model in ipairs(Config.atmModels) do
        atmTargets[model] = QB.interact.addModel(model, {
            {
                icon = 'credit-card',
                label = 'Use ATM',
                item = 'bank_card',
                action = accessAtm,
            },
        }, Config.atmDistance)
    end
end

registerAtmTargets()

AddEventHandler('onClientResourceStart', function(resource)
    if resource ~= 'qbtarget' then return end
    registerAtmTargets()
end)

for _, coords in ipairs(Config.locations) do
    local blip = AddBlipForCoord(coords.x, coords.y, coords.z)
    SetBlipSprite(blip, Config.blipInfo.sprite)
    SetBlipDisplay(blip, 4)
    SetBlipScale(blip, Config.blipInfo.scale)
    SetBlipColour(blip, Config.blipInfo.color)
    SetBlipAsShortRange(blip, true)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName(Config.blipInfo.name)
    EndTextCommandSetBlipName(blip)
end

local function useCard()
    accessAtm()
end

RegisterNetEvent('qbbanking:client:useCard', useCard)
RegisterNetEvent('qb-banking:client:useCard', useCard)

RegisterNUICallback('qbbanking:ready', function(_, cb)
    cb({})
    ready = true
    for _, message in ipairs(pending) do SendNUIMessage(message) end
    pending = {}
    pushTheme()
end)

RegisterNUICallback('qbbanking:close', function(_, cb)
    cb({})
    close()
end)

RegisterNUICallback('qbbanking:pin', function(data, cb)
    local snapshot, err = request('qbbanking:pin', data and data.pin)
    cb(snapshot and { ok = true, snapshot = snapshot } or { ok = false, error = err or 'Incorrect PIN.' })
end)

RegisterNUICallback('qbbanking:action', function(data, cb)
    local result, err = request('qbbanking:action', data)
    cb(result and { ok = true, result = result } or { ok = false, error = err or 'The transaction was declined.' })
    if result and result.message then
        notify(result.message, 'success')
    elseif err then
        notify(err, 'error')
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= RESOURCE then return end
    setFocus(false)
    for index in ipairs(Config.locations) do pcall(function() QB.interact.removeZone(('qbbanking:branch:%d'):format(index)) end) end
    for model, id in pairs(atmTargets) do pcall(function() QB.interact.removeModel(model, id) end) end
end)
