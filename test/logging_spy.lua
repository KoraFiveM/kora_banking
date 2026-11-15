-- Test helper: a Kora.logging stub that records every call.
-- Usage: local spy = dofile('test/logging_spy.lua'); Kora.logging = spy.logging; spy.calls[i] = { level, event, message, fields }
local spy = { calls = {} }
spy.logging = { isEnabled = function() return true end }
for _, level in ipairs({ 'trace', 'debug', 'info', 'warn', 'error', 'fatal' }) do
    spy.logging[level] = function(event, message, fields)
        spy.calls[#spy.calls + 1] = { level = level, event = event, message = message, fields = fields }
        return true
    end
end
function spy.find(event)
    for _, call in ipairs(spy.calls) do if call.event == event then return call end end
end
return spy
