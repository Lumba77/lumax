# push_all.ps1 - Ultimate Sync for Lumax (v2.6)
# Fixes: Forces Animations inclusion, Corrects project.godot logic

param (
    [string]$Target = "godot",
    [string]$QuestRoot = "/sdcard/Projects/Lumax-Vulkan"
)

$ErrorActionPreference = "Stop"

# Auto-detect the Quest ID
Write-Host "🔍 Searching for Quest..." -ForegroundColor Gray
$adbDevices = adb devices | Select-String -Pattern "\tdevice$"
if ($adbDevices.Count -eq 0) {
    Write-Host "❌ Error: Quest not found! Reconnect USB or WiFi." -ForegroundColor Red
    exit 1
}
$DEVICE_ID = $adbDevices[0].ToString().Split("`t")[0].Trim()
Write-Host "🎯 Target Device: $DEVICE_ID" -ForegroundColor Cyan

# Define local paths
$SourceGodot = "C:\Users\lumba\Program\Lumax\Godot"

# 1. RESET THE AI BRIDGE (Quest -> PC)
Write-Host "🔄 Resetting AI Communication Ports (STT/TTS)..." -ForegroundColor Yellow
adb -s $DEVICE_ID reverse --remove-all
adb -s $DEVICE_ID reverse tcp:8000 tcp:8000 # Soul
adb -s $DEVICE_ID reverse tcp:8001 tcp:8001 # Ears
adb -s $DEVICE_ID reverse tcp:8002 tcp:8002 # Mouth
adb -s $DEVICE_ID reverse tcp:6006 tcp:6006 # Console
adb -s $DEVICE_ID reverse tcp:6007 tcp:6007 # Logs

# 2. PERFORM SYNC
function Push-Safe {
    param($src, $dest)
    Write-Host "📂 Scanning: $src" -ForegroundColor Cyan
    
    $items = Get-ChildItem -Path $src
    foreach ($item in $items) {
        # SKIP THE MASSIVE CACHE FOLDERS
        if ($item.PSIsContainer -and ($item.Name -eq ".godot" -or $item.Name -eq ".import")) { continue }
        
        Write-Host "📤 Syncing: $($item.Name)" -ForegroundColor Gray
        adb -s $DEVICE_ID push $item.FullName $dest
    }
}

# The Target "godot" now performs a CLEAN, FAST overwrite of the code + root project.
if ($Target -eq "godot") {
    Write-Host "🚀 Running Core Logic Sync..." -ForegroundColor Green
    Push-Safe $SourceGodot $QuestRoot
}

Write-Host "`n✅ Full Ready! Target: $Target" -ForegroundColor Green
Write-Host "Project is located at: $QuestRoot" -ForegroundColor Gray
