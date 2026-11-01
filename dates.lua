-- Date helpers shared by the banking server (normalise) and client (format).
-- The FiveM client Lua runtime has no `os` library, so nothing in this file may touch `os`.
-- Transaction dates travel as Unix milliseconds so every source table and driver return type renders the same.
BankingDates = {}

local function utcMillis(y, mo, d, h, mi, s)
    y, mo, d = tonumber(y), tonumber(mo), tonumber(d)
    if not (y and mo and d) then return nil end
    -- days-from-civil (proleptic Gregorian), avoids os.time's local-timezone dependence
    y = mo <= 2 and y - 1 or y
    local era = (y >= 0 and y or y - 399) // 400
    local yoe = y - era * 400
    local doy = (153 * (mo + (mo > 2 and -3 or 9)) + 2) // 5 + d - 1
    local doe = yoe * 365 + yoe // 4 - yoe // 100 + doy
    local days = era * 146097 + doe - 719468
    return ((days * 86400) + (tonumber(h) or 0) * 3600 + (tonumber(mi) or 0) * 60 + (tonumber(s) or 0)) * 1000
end

-- Accepts a number (seconds or milliseconds), numeric string, 'YYYY-MM-DD[ T]HH:MM:SS' string, or a table
-- ({year,month,day,hour,min,sec} os.date-style, or {time|timestamp|ms|unix = number}). Returns integer ms or nil.
function BankingDates.normalize(value)
    local kind = type(value)
    if kind == 'number' then
        if value ~= value or value <= 0 or value == math.huge then return nil end
        return math.floor(value < 100000000000 and value * 1000 or value)
    elseif kind == 'string' then
        local number = tonumber(value)
        if number then return BankingDates.normalize(number) end
        local y, mo, d, h, mi, s = value:match('^(%d%d%d%d)-(%d%d)-(%d%d)[ T]?(%d*):?(%d*):?(%d*)')
        if y then return utcMillis(y, mo, d, h ~= '' and h or 0, mi ~= '' and mi or 0, s ~= '' and s or 0) end
    elseif kind == 'table' then
        for _, key in ipairs({ 'ms', 'timestamp', 'time', 'unix', 'epoch' }) do
            if value[key] ~= nil and type(value[key]) ~= 'table' then
                local result = BankingDates.normalize(value[key])
                if result then return result end
            end
        end
        return utcMillis(value.year, value.month or value.mon, value.day, value.hour, value.min or value.minute, value.sec or value.second)
    end
    return nil
end

-- Inverse of days-from-civil: days since 1970-01-01 -> year, month, day.
local function civilFromDays(days)
    days = days + 719468
    local era = (days >= 0 and days or days - 146096) // 146097
    local doe = days - era * 146097
    local yoe = (doe - doe // 1460 + doe // 36524 - doe // 146096) // 365
    local doy = doe - (365 * yoe + yoe // 4 - yoe // 100)
    local mp = (5 * doy + 2) // 153
    local d = doy - (153 * mp + 2) // 5 + 1
    local m = mp < 10 and mp + 3 or mp - 9
    return yoe + era * 400 + (m <= 2 and 1 or 0), m, d
end

-- Breaks Unix milliseconds (plus a timezone offset in seconds) into calendar fields without `os`.
function BankingDates.fields(ms, offsetSeconds)
    local seconds = ms // 1000 + (tonumber(offsetSeconds) or 0)
    local days, rest = seconds // 86400, seconds % 86400
    local year, month, day = civilFromDays(days)
    return { year = year, month = month, day = day, hour = rest // 3600, min = rest % 3600 // 60, sec = rest % 60 }
end

-- FiveM resolves natives lazily through the _G metatable, so rawget(_G, name) misses them and made every
-- player look like UTC. Plain indexing honours the metatable and still works for ordinary globals.
local function native(name)
    local fn = _G[name]
    return type(fn) == 'function' and fn or nil
end

-- Client only: the UTC offset in seconds of the player machine (0 when natives are missing or unsynced).
-- GetLocalTime is the player machine clock; GetUtcTime is the same instant in UTC, so their difference is the zone offset.
-- GetCloudTimeAsInt is only a fallback because it is 0 until the cloud time has synced.
function BankingDates.localOffset()
    local ok, offset = pcall(function()
        local localTime = native('GetLocalTime')
        if not localTime then return 0 end
        local y, mo, d, h, mi, s = localTime()
        local asLocal = utcMillis(y, mo, d, h, mi, s)
        if not asLocal then return 0 end
        local utcSeconds
        local utcTime = native('GetUtcTime')
        if utcTime then
            local uy, umo, ud, uh, umi, us = utcTime()
            local asUtc = utcMillis(uy, umo, ud, uh, umi, us)
            utcSeconds = asUtc and asUtc // 1000
        end
        if not utcSeconds then
            local cloudTime = native('GetCloudTimeAsInt')
            utcSeconds = cloudTime and tonumber(cloudTime()) or nil
        end
        if not utcSeconds or utcSeconds <= 0 then return 0 end
        local diff = math.floor((asLocal // 1000 - utcSeconds) / 900 + 0.5) * 900
        return math.abs(diff) <= 14 * 3600 and diff or 0
    end)
    return ok and tonumber(offset) or 0
end

-- Config.dateTimezone -> 'player' or 'server'. The older values 'local' and 'utc' keep working.
function BankingDates.timeZoneMode(value)
    if value == 'server' or value == 'utc' then return 'server' end
    return 'player'
end

local LOCALE_LAYOUT = { us = 'MM/DD/YYYY', ca = 'MM/DD/YYYY', ph = 'MM/DD/YYYY' }
local ISO_LANGUAGES = { ja = true, zh = true, ko = true, hu = true, sv = true, lt = true }

-- Resolves Config.dateFormat to a concrete pattern; 'locale' follows the player's locale (e.g. en-US).
function BankingDates.resolvePattern(format, locale)
    if format == 'DD/MM/YYYY' or format == 'MM/DD/YYYY' or format == 'YYYY-MM-DD' then return format end
    local language, region = tostring(locale or 'en-US'):lower():match('^(%a+)[-_]?(%a*)')
    if language == 'en' and region == '' then region = 'us' end
    if LOCALE_LAYOUT[region] and language == 'en' then return LOCALE_LAYOUT[region] end
    if ISO_LANGUAGES[language] then return 'YYYY-MM-DD' end
    return 'DD/MM/YYYY'
end

-- options: { offset = seconds east of UTC (default 0), format = Config.dateFormat, showTime = Config.showTime, locale = 'en-US', fallback = 'Recently' }
function BankingDates.format(value, options)
    options = options or {}
    local ms = BankingDates.normalize(value)
    if not ms then return options.fallback or 'Recently' end
    local pattern = BankingDates.resolvePattern(options.format, options.locale)
    local t = BankingDates.fields(ms, options.offset)
    local text = pattern:gsub('YYYY', ('%04d'):format(t.year)):gsub('MM', ('%02d'):format(t.month)):gsub('DD', ('%02d'):format(t.day))
    if options.showTime == false then return text end
    local twelve = options.hour12
    if twelve == nil then twelve = (options.format == nil or options.format == 'locale') and pattern == 'MM/DD/YYYY' end
    if twelve then
        return ('%s %d:%02d %s'):format(text, (t.hour + 11) % 12 + 1, t.min, t.hour < 12 and 'AM' or 'PM')
    end
    return ('%s %02d:%02d'):format(text, t.hour, t.min)
end

-- Never throws: a formatting problem must not stop the bank from opening.
function BankingDates.safeFormat(value, options)
    local ok, text = pcall(BankingDates.format, value, options)
    if ok and type(text) == 'string' then return text end
    local fallback = type(options) == 'table' and options.fallback or 'Recently'
    local isoOk, iso = pcall(function()
        local ms = BankingDates.normalize(value)
        if not ms then return nil end
        local t = BankingDates.fields(ms, 0)
        return ('%04d-%02d-%02dT%02d:%02d:%02dZ'):format(t.year, t.month, t.day, t.hour, t.min, t.sec)
    end)
    return isoOk and iso or fallback
end
