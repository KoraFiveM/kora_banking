-- The Config.minAmount descriptions must tell admins how to get a $5 minimum.
local handle = assert(io.open("config.lua", "r"))
local source = handle:read("*a")
handle:close()
local count = 0
for label in source:gmatch("label = (\x27Minimum %a+ %(%$%)\x27)") do
    count = count + 1
    local start = source:find(label, 1, true)
    local block = source:sub(start, start + 400)
    assert(block:find("set it to 5 for a $5 minimum", 1, true), label .. " description lacks the 5 hint")
end
assert(count == 3, "expected 3 minimum amount options, found " .. count)
print("minamount_docs ok")
