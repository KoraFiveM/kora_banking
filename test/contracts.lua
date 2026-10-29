local root = debug.getinfo(1, 'S').source:sub(2):match('(.*/)') .. '../'
local server = assert(io.open(root .. 'server.lua')):read('*a')

assert(server:find('local function ensureOrganizationAccounts%(data%)'), 'missing live organization account discovery')
assert(server:find("createAccount%(job%.name, 0, 'job'%)"), 'job bosses must create missing job accounts')
assert(server:find("createAccount%(gang%.name, 0, 'gang'%)"), 'gang bosses must create missing gang accounts')
assert(server:find("if mode == 'bank' then ensureOrganizationAccounts%(data%) end"), 'bank snapshots must discover current organizations')

-- Both statement UNIONs must pin the legs side to bank_statements' collation (tester report: 'Illegal mix of collations').
local _, collated = server:gsub("CONCAT%('operation:',id%) COLLATE utf8mb4_unicode_ci", '')
assert(collated == 2, 'both durable-history UNION queries must collate the bank_operation_legs columns')

print('qbbanking contracts: 5 assertions passed')
