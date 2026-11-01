-- Config.tiers must ship off by default, tag the default locations, and be documented.
local function read(path)
    local handle = assert(io.open(path, "r"))
    local text = handle:read("*a")
    handle:close()
    return text
end
function vector3(x, y, z) return { x = x, y = y, z = z } end
dofile("config.lua")
dofile("tiers.lua")
assert(Config.tiers.enabled == false, "tiers must be opt-in")
assert(Config.tiers.default == "fleeca" and Config.tiers.list.fleeca and Config.tiers.list.bigbank, "default presets")
local bigbank, fleeca = 0, 0
for index, location in ipairs(Config.locations) do
    local info = BankingTiers.entry(location)
    assert(info.coords and info.tier and info.label, "every shipped location is tagged and labelled: " .. index)
    if info.tier == "bigbank" then bigbank = bigbank + 1 else fleeca = fleeca + 1 end
end
assert(bigbank == 1 and fleeca == 7, "Pacific Standard is the only bigbank location")
local bigFeatures, fleecaFeatures = Config.tiers.list.bigbank.features, Config.tiers.list.fleeca.features
assert(bigFeatures.sharedAccounts and bigFeatures.manageMembers, "Pacific Standard opens shared accounts and manages members")
assert(not fleecaFeatures.sharedAccounts and not fleecaFeatures.manageMembers, "Fleeca does not")
assert(Config.tiers.list.bigbank.limits.dailyWithdraw > Config.tiers.list.fleeca.limits.dailyWithdraw, "higher daily limit at Pacific Standard")
local readme = read("README.md")
for _, term in ipairs({ "Config.tiers", "Config.locations", "Pacific Standard", "maxTransfer", "dailyWithdraw", "sharedAccounts", "manageMembers" }) do
    assert(readme:find(term, 1, true), "README must document " .. term)
end
print("tiers_docs ok")
