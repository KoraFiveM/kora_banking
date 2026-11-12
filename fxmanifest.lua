fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'kora_banking'
author 'qbcore2'
version '0.2.1'
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
    '@kora_core/init.lua',
    'config.lua',
    'dates.lua',
    'tiers.lua',
}

client_scripts {
    'client.lua',
}

server_scripts { '@kora_sql/init.lua', 'server/schema.lua', 'server.lua', 'server/finance.lua' }

-- kora_qa: Gherkin test scenarios (converted legacy tests), see [kora]/kora_qa/README.md
qa_feature 'tests/*.feature'
