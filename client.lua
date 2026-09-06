local RESOURCE = GetCurrentResourceName()
local ready = false
local pending = {}
local focused = false
local openingAtm = false
local nextRequestId = 0
local pendingRequests = {}

local REQUEST_TIMEOUT = 10000

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

local function pushTheme()
    QBTheme.apply(Config.ui and Config.ui.accent or nil)
end

local function open(mode, location)
    CreateThread(function()
        local snapshot, err = request('open', mode, location)
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

-- Register the four stock GTA ATM props from Config.atmModels as one model
-- target, so every streamed ATM variant shares the same option.
local atmTargetId

local function registerAtmTargets()
    if atmTargetId then pcall(function() QB.interact.removeModel(Config.atmModels, atmTargetId) end) end
    atmTargetId = QB.interact.addModel(Config.atmModels, {
        {
            icon = 'credit-card',
            label = 'Use ATM',
            action = accessAtm,
        },
    }, Config.atmDistance)
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
    local snapshot, err = request('pin', data and data.pin)
    cb(snapshot and { ok = true, snapshot = snapshot } or { ok = false, error = err or 'Incorrect PIN.' })
end)

RegisterNUICallback('qbbanking:action', function(data, cb)
    local result, err = request('action', data)
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
    if atmTargetId then pcall(function() QB.interact.removeModel(Config.atmModels, atmTargetId) end) end
end)
