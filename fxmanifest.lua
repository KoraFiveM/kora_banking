fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'qbbanking'
author 'qbcore2'
version '3.0.0'
description 'Personal, shared, society and gang banking for qbcore'

provide 'qb-banking'

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
    '@qbtheme/client/bridge.lua',
    'client.lua',
}

server_script 'server.lua'

ui_page 'web/build/index.html'

files {
    'banking.sql',
    'web/build/index.html',
    'web/build/assets/**/*',
}
