fx_version 'cerulean'
game 'gta5'

author 'County RP'
description 'Motel room rental: NPC desk, timed rentals, door lock, per-room stash + wardrobe'
version '1.0.0'

shared_scripts {
    '@ox_lib/init.lua',
    'shared/config.lua',
}

client_scripts {
    'client/main.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/main.lua',
}

dependencies {
    'qb-core',
    'ox_lib',
    'tgiann-target',
    'codem-inventory',
    'illenium-appearance',
}

lua54 'yes'
