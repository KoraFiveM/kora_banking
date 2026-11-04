fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'kora_banking'
-- Keep the legacy resource name resolvable for exports['qbbanking'] callers.
provide 'qbbanking'
author 'qbcore2'
version '3.1.2'
description 'Personal, shared, society and gang banking for Kora'

provide 'qb-banking'

-- Banking renders through kora_lib's headless AppShell, whose frame consumes the
-- shared palette. Keep the provider ordered before this resource even though
-- banking no longer owns a private NUI page or imports the bridge itself.
dependency 'kora_theme'
dependency 'kora_lib'
dependency 'kora_sql'
dependency 'kora_core'
dependency 'kora_target'
dependency 'kora_inventory'

shared_scripts {
    '@kora_lib/init.lua',
    '@kora_sql/init.lua',
    '@kora_core/init.lua',
    'config.lua',
    'dates.lua',
    'tiers.lua',
}

client_scripts {
    'client.lua',
}

server_scripts { 'server/schema.lua', 'server.lua', 'server/finance.lua' }
