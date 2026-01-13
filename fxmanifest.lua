fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'TwoPoint_EvidenceStandalone'
author 'TwoPoint Development'
description 'Standalone forensics/evidence system (SQL-only) with labs, blips, BigDaddy Chat name sync, and LB-Phone wiretap.'
version '1.0.0'

shared_scripts {
  'config.lua'
}

server_scripts {
  '@oxmysql/lib/MySQL.lua',
  'server/main.lua',
  'server/wiretap.lua'
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
