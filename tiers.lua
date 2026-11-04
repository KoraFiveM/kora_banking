-- Bank tier helpers shared by the banking server (enforcement) and client (blips, targets).
-- Config.locations entries are either plain coords (legacy) or { coords = vector3/4, tier = 'fleeca', label = '...' }.
-- Tiers only apply when Config.tiers.enabled is true; otherwise every helper reports "no restriction".
-- Everything is read from Config at call time so live config changes apply immediately.
BankingTiers = {}

BankingTiers.FEATURES = { 'deposit', 'withdraw', 'transfer', 'sharedAccounts', 'manageMembers', 'orderCard' }

local function settings()
    return type(Config) == 'table' and type(Config.tiers) == 'table' and Config.tiers or {}
end

local function tierList()
    local list = settings().list
    return type(list) == 'table' and list or {}
end

-- Tier names sorted alphabetically, so "the first tier that qualifies" is deterministic.
local function sortedTierNames()
    local names = {}
    for name in pairs(tierList()) do names[#names + 1] = tostring(name) end
    table.sort(names)
    return names
end

function BankingTiers.enabled()
    return settings().enabled == true
end

-- Name of the tier used for plain-coordinate locations and unknown tier names.
function BankingTiers.defaultName()
    local name = settings().default
    local list = tierList()
    if type(name) == 'string' and type(list[name]) == 'table' then return name end
    if type(list.fleeca) == 'table' then return 'fleeca' end
    return nil
end

-- Returns { name, label, features, limits, blip } for a configured tier, or nil.
function BankingTiers.get(name)
    local tier = type(name) == 'string' and tierList()[name] or nil
    if type(tier) ~= 'table' then return nil end
    return {
        name = name,
        label = type(tier.label) == 'string' and tier.label ~= '' and tier.label or name,
        features = type(tier.features) == 'table' and tier.features or {},
        limits = type(tier.limits) == 'table' and tier.limits or {},
        blip = type(tier.blip) == 'table' and tier.blip or {},
    }
end

-- Accepts a legacy plain coordinate or a { coords, tier, label } table. Returns { coords, tier, label } or nil.
function BankingTiers.entry(raw)
    if raw == nil then return nil end
    if type(raw) == 'table' and raw.coords ~= nil then
        return {
            coords = raw.coords,
            tier = type(raw.tier) == 'string' and raw.tier or nil,
            label = type(raw.label) == 'string' and raw.label ~= '' and raw.label or nil,
        }
    end
    return { coords = raw }
end

-- Full description of Config.locations[index]. tier is the effective tier (unknown/missing names use the default).
function BankingTiers.info(index)
    local locations = type(Config) == 'table' and Config.locations or nil
    local entry = type(locations) == 'table' and BankingTiers.entry(locations[tonumber(index)]) or nil
    if not entry then return nil end
    local info = { index = tonumber(index), coords = entry.coords, label = entry.label, enabled = BankingTiers.enabled() }
    if not info.enabled then return info end
    local tier = BankingTiers.get(entry.tier) or BankingTiers.get(BankingTiers.defaultName())
    if tier then
        info.tier, info.tierLabel, info.features, info.limits, info.blip = tier.name, tier.label, tier.features, tier.limits, tier.blip
    end
    info.label = info.label or info.tierLabel
    return info
end

-- Nearest configured location within range of position ({x,y,z}); never trusts a client-sent index or tier.
function BankingTiers.resolve(position, range)
    if type(position) ~= 'table' and type(position) ~= 'vector3' and type(position) ~= 'vector4' then return nil end
    local px, py, pz = tonumber(position.x), tonumber(position.y), tonumber(position.z)
    if not px or not py or not pz then return nil end
    local candidates = {}
    for index, raw in ipairs(type(Config) == 'table' and Config.locations or {}) do
        local entry = BankingTiers.entry(raw)
        local c = entry and entry.coords
        local cx, cy, cz = c and tonumber(c.x), c and tonumber(c.y), c and tonumber(c.z)
        if cx and cy and cz then
            candidates[#candidates + 1] = { index = index, coords = { x = cx, y = cy, z = cz } }
        end
    end

    local nearest = Kora.util.nearest(candidates, { x = px, y = py, z = pz }, {
        radius = range,
        coordsOf = function(candidate) return candidate.coords end,
    })
    return nearest and BankingTiers.info(nearest.index) or nil
end

-- A feature is allowed unless tiers are enabled and the location's tier explicitly sets it to false.
function BankingTiers.can(info, feature)
    if not info or not info.enabled or not info.features then return true end
    return info.features[feature] ~= false
end

-- Positive numeric limit for the location's tier, or nil for "no limit" (tiers disabled, unset or <= 0).
function BankingTiers.limit(info, key)
    if not info or not info.enabled or not info.limits then return nil end
    local value = tonumber(info.limits[key])
    if value and value == value and value > 0 and value < math.huge then return math.floor(value) end
    return nil
end

-- Label of the first tier (sorted by name) that allows the feature, for "Available at ..." messages.
function BankingTiers.availableAt(feature)
    for _, name in ipairs(sortedTierNames()) do
        local tier = BankingTiers.get(name)
        if tier and tier.features[feature] ~= false then return tier.label end
    end
end

-- { feature = "Pacific Standard", ... } for features the location blocks; empty when nothing is gated.
function BankingTiers.gated(info)
    local result = {}
    if not info or not info.enabled then return result end
    for _, feature in ipairs(BankingTiers.FEATURES) do
        if not BankingTiers.can(info, feature) then result[feature] = BankingTiers.availableAt(feature) or 'another branch' end
    end
    return result
end

-- Label of the first tier (sorted by name) whose limit for key is higher than `current` (or unlimited).
function BankingTiers.higherLimitAt(key, current)
    for _, name in ipairs(sortedTierNames()) do
        local tier = BankingTiers.get(name)
        local value = tier and tonumber(tier.limits[key])
        if tier and (not value or value <= 0 or value > current) then return tier.label end
    end
end
