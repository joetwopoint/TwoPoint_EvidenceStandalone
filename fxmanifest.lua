fx_version 'cerulean'
game 'gta5'
lua54 'yes'

author 'TwoPoint Development'
description 'Standalone evidence + forensic system (SQL only, pe-core compatible)'
version '1.1.0'

dependencies {
  '/onesync',
  'oxmysql'
}

shared_scripts {
  'config.lua'
}

server_scripts {
  '@oxmysql/lib/MySQL.lua',
  'server/main.lua'
}

client_scripts {
  'client/main.lua'
}

ui_page 'html/index.html'

files {
  'html/index.html',
  'html/style.css',
  'html/app.js'
}
