fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'midnight_firearms'
author 'MidnightMTB'
description 'Ottawa Region Scripts | Multi-framework firearms access gate (Discord role + DB overrides) with admin panel'
version '1.2.0'

ui_page 'web/index.html'

files {
  'web/index.html',
  'web/style.css',
  'web/app.js'
}

shared_scripts {
  '@ox_lib/init.lua',
  'config.lua'
}

client_scripts {
  'client.lua'
}

server_scripts {
  'server.lua'
}

dependencies {
  'ox_lib',
  'oxmysql'
}