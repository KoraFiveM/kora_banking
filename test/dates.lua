-- The FiveM client has no os library; every assertion below must pass without it.
local realOs = os
os = nil
local root = debug.getinfo(1, 'S').source:sub(2):match('(.*/)') .. '../'
dofile(root .. 'dates.lua')
local D = BankingDates
local function equal(a, b, m) if a ~= b then error(('%s: expected %s, got %s'):format(m, tostring(b), tostring(a)), 2) end end

-- normalize: 2026-10-30 02:20:00 UTC
local ms = 1793326800000
equal(D.normalize(ms), ms, 'ms number')
equal(D.normalize(ms // 1000), ms, 'seconds number')
equal(D.normalize(tostring(ms)), ms, 'numeric string')
equal(D.normalize('2026-10-30 02:20:00'), ms, 'datetime string')
equal(D.normalize('2026-10-30T02:20:00Z'), ms, 'ISO string')
equal(D.normalize({ year = 2026, month = 10, day = 30, hour = 2, min = 20, sec = 0 }), ms, 'os.date table')
equal(D.normalize({ timestamp = ms }), ms, 'table with timestamp')
equal(D.normalize({}), nil, 'empty table')
equal(D.normalize('garbage'), nil, 'garbage string')
equal(D.normalize(nil), nil, 'nil')
equal(D.normalize(0), nil, 'zero')
equal(D.normalize(0 / 0), nil, 'nan')

-- format (utc keeps the test timezone independent)
local function fmt(o) return D.format(ms, o) end
equal(fmt({ format = 'DD/MM/YYYY' }), '30/10/2026 02:20', 'DD/MM/YYYY')
equal(fmt({ format = 'MM/DD/YYYY' }), '10/30/2026 02:20', 'MM/DD/YYYY')
equal(fmt({ format = 'YYYY-MM-DD' }), '2026-10-30 02:20', 'YYYY-MM-DD')
equal(fmt({ format = 'YYYY-MM-DD', showTime = false }), '2026-10-30', 'no time')
equal(fmt({ format = 'locale', locale = 'en-US' }), '10/30/2026 2:20 AM', 'locale en-US')
equal(fmt({ locale = 'en-US' }), '10/30/2026 2:20 AM', 'default format follows locale')
equal(fmt({ format = 'locale', locale = 'en-GB' }), '30/10/2026 02:20', 'locale en-GB')
equal(fmt({ format = 'locale', locale = 'de-DE' }), '30/10/2026 02:20', 'locale de-DE')
equal(fmt({ format = 'locale', locale = 'ja-JP' }), '2026-10-30 02:20', 'locale ja-JP')
equal(fmt({ format = 'locale', locale = 'en-US', showTime = false }), '10/30/2026', 'locale date only')
equal(D.format({}, {}), 'Recently', 'invalid falls back')
equal(D.format('x', { fallback = '-' }), '-', 'custom fallback')
equal(fmt({ format = 'YYYY-MM-DD', offset = -5 * 3600 }), '2026-10-29 21:20', 'negative offset crosses day')
equal(fmt({ format = 'YYYY-MM-DD', offset = 5.5 * 3600 }), '2026-10-30 07:50', 'half-hour offset')
equal(D.format(951782400000, { format = 'YYYY-MM-DD' }), '2000-02-29 00:00', 'leap day')
equal(D.format(100000000000, { format = "YYYY-MM-DD" }), "1973-03-03 09:46", "1973")
equal(D.safeFormat(ms, { format = 'YYYY-MM-DD', showTime = false }), '2026-10-30', 'safeFormat passes through')
equal(D.safeFormat('x'), 'Recently', 'safeFormat fallback')
local original = D.format
D.format = function() error('boom') end
equal(D.safeFormat(ms), '2026-10-30T02:20:00Z', 'safeFormat falls back to ISO when format throws')
D.format = original
equal(D.localOffset(), 0, 'localOffset is 0 without natives')
_G.GetLocalTime = function() return 2026, 10, 29, 21, 20, 0 end
_G.GetCloudTimeAsInt = function() return ms // 1000 end
equal(D.localOffset(), -5 * 3600, 'localOffset from natives')
_G.GetLocalTime, _G.GetCloudTimeAsInt = nil, nil
os = realOs
-- Both UNION halves must project the date as Unix milliseconds, whatever the table column type.
local source = assert(io.open(root .. 'server.lua')):read('a')
local _, halves = source:gsub('CAST%(UNIX_TIMESTAMP%(', '')
equal(halves, 3, 'statement and both operation-leg queries normalise the date in SQL')
print('dates ok')
