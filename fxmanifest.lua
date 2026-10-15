fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'qbbanking'
author 'qbcore2'
version '3.0.0'
description 'Personal, shared, society and gang banking for qbcore'

provide 'qb-banking'

-- Banking renders through qblib's headless AppShell, whose frame consumes the
-- shared palette. Keep the provider ordered before this resource even though
-- banking no longer owns a private NUI page or imports the bridge itself.
dependency 'qbtheme'
dependency 'qblib'
dependency 'qbsql'
dependency 'qbcore'
dependency 'qbtarget'
dependency 'qbinventory'

shared_scripts {
    '@qblib/init.lua',
    '@qbsql/init.lua',
    '@qbcore/init.lua',
    'config.lua',
}

client_scripts {
    'client.lua',
}

server_scripts { 'server.lua', 'server/finance.lua' }

files {
    'banking.sql',
    'sql/*.sql',
}
