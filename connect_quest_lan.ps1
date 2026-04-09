# Deprecated: renamed to connect_quest.ps1 (LAN is the default). This wrapper forwards all arguments.
Write-Host "connect_quest_lan.ps1 -> connect_quest.ps1" -ForegroundColor DarkGray
& "$PSScriptRoot\connect_quest.ps1" @args
