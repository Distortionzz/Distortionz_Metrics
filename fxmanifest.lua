fx_version 'cerulean'
game 'gta5'
lua54 'yes'

author 'Distortionz'
description 'Distortionz Metrics — premium developer dashboard. Live resource browser, server health, opt-in per-script tick samples. Tier-gated via distortionz_perms.'
version '1.0.1'
repository 'https://github.com/Distortionzz/Distortionz_Metrics'

ui_page 'html/index.html'

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua',
}

client_scripts {
    'client.lua',
}

server_scripts {
    'server.lua',
    'version_check.lua',
}

files {
    'html/index.html',
    'html/style.css',
    'html/app.js',
}

dependencies {
    'ox_lib',
    'qbx_core',
    'distortionz_perms',
}
