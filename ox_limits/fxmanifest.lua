
fx_version 'cerulean'
game 'gta5'

lua54 'yes'
use_experimental_fxv2_oal 'yes'

name 'ox_limits'
version '1.2.0'

shared_scripts {
    '@es_extended/imports.lua',
    '@ox_lib/init.lua',
    'config.lua',
}

client_scripts {
    'client/rob.lua'
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/utils.lua',
    'server/limits.lua',
    'server/looting.lua',
    'server/robbery.lua',
    'server/init.lua'
}

dependencies {
    'ox_inventory',
    'ox_lib'
}
