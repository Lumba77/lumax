# push_script.ps1
# Surgical push tool for Lumax Project to Meta Quest

param (
    [string]$SourcePath = ".",
    [string]$QuestDestination = "/sdcard/Projects/Lumax-Vulkan"
)

$ErrorActionPreference = "Stop"

# Resolve absolute path
$FullSourcePath = Resolve-Path $SourcePath
$RelativePath = $FullSourcePath.Path.Replace("C:\Users\lumba\Program\Lumax\", "").Replace("C:\Users\lumba\Program\Lumax", "")

# Determine final destination on Quest
if ($RelativePath -ne "") {
    $FinalDest = "$QuestDestination/$RelativePath".Replace("\", "/").Replace("//", "/")
} else {
    $FinalDest = $QuestDestination
}

Write-Host "--- 🚀 Lumax Surgical Push ---" -ForegroundColor Cyan
Write-Host "Source: $FullSourcePath" -ForegroundColor White
Write-Host "Target: $FinalDest" -ForegroundColor White

# 1. Check ADB Connection
$devices = adb devices | Select-String -Pattern "\tdevice$"
if ($null -eq $devices) {
    Write-Error "No ADB devices found. Connect your Quest via USB or WiFi."
    exit 1
}

# 2. Push Logic
try {
    if (Test-Path -Path $FullSourcePath -PathType Container) {
        # It's a directory
        Write-Host "Pushing directory contents..." -ForegroundColor Yellow
        $items = Get-ChildItem -Path $FullSourcePath -Exclude ".godot", ".import", ".git", "models", "node_modules"
        foreach ($item in $items) {
            adb push $item.FullName "$FinalDest"
        }
    } else {
        # It's a file
        Write-Host "Pushing file..." -ForegroundColor Yellow
        adb push $FullSourcePath $FinalDest
    }
    Write-Host "`n✅ Push Successful!" -ForegroundColor Green
} catch {
    Write-Error "Failed to push! Error: $_"
}
