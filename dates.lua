-- Date helpers shared by the banking server (normalise) and client (format).
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

-- options: { format = Config.dateFormat, showTime = Config.showTime, locale = 'en-US', fallback = 'Recently' }
function BankingDates.format(value, options)
    options = options or {}
    local ms = BankingDates.normalize(value)
    if not ms then return options.fallback or 'Recently' end
    local pattern = BankingDates.resolvePattern(options.format, options.locale)
    local t = os.date(options.utc and '!*t' or '*t', ms // 1000)
    local text = pattern:gsub('YYYY', ('%04d'):format(t.year)):gsub('MM', ('%02d'):format(t.month)):gsub('DD', ('%02d'):format(t.day))
    if options.showTime == false then return text end
    local twelve = options.hour12
    if twelve == nil then twelve = (options.format == nil or options.format == 'locale') and pattern == 'MM/DD/YYYY' end
    if twelve then
        return ('%s %d:%02d %s'):format(text, (t.hour + 11) % 12 + 1, t.min, t.hour < 12 and 'AM' or 'PM')
    end
    return ('%s %02d:%02d'):format(text, t.hour, t.min)
end
