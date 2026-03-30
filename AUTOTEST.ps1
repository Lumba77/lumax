# 🤖 JEN SENTINEL LOOP (v1.9 - SPEED OPTIMIZED)
# Log-Watching Vision Capture

Write-Host "🤖 Initiating Optimized Sentinel Loop..." -ForegroundColor Cyan

$env:XR_RUNTIME_JSON = "C:\Program Files\MetaXRSimulator\v85.0\meta_openxr_simulator.json"
# Define Paths
$GodotExe = "C:\Users\lumba\Program\Lumax\Godot_v4.2.2-stable_win64_console.exe"
$GodotProject = "C:\Users\lumba\Program\Lumax\Godot"
$DEBUG_LOG = "C:\Users\lumba\Program\Lumax\godot_debug_output.txt"
$ERROR_LOG = "C:\Users\lumba\Program\Lumax\godot_error_output.txt"

# 1. Faster Editor Sync
Write-Host "🧠 Syncing Cells..." -ForegroundColor Yellow
$syncProc = Start-Process $GodotExe -ArgumentList "--path `"$GodotProject`" --editor --quit --headless" -PassThru -Wait

# 2. Launch Manifest
if (Test-Path $DEBUG_LOG) { Remove-Item $DEBUG_LOG }
if (Test-Path $ERROR_LOG) { Remove-Item $ERROR_LOG }
Write-Host "🚀 Waking her up with Meta Simulator SDK..." -ForegroundColor Green
$proc = Start-Process $GodotExe -ArgumentList "--path `"$GodotProject`" --xr-mode on" -PassThru -NoNewWindow -RedirectStandardOutput $DEBUG_LOG -RedirectStandardError $ERROR_LOG

# 3. Dynamic Vision Capture (Watch for "XR started")
Write-Host "⏳ Watching for manifestation trigger..." -ForegroundColor Gray
$manifested = $false
for ($i=0; $i -lt 30; $i++) {
    if (Test-Path $DEBUG_LOG) {
        $content = Get-Content $DEBUG_LOG
        if ($content -match "XR started") {
            Start-Sleep -Seconds 2 # Short buffer for rendering
            $manifested = $true
            break
        }
    }
    Start-Sleep -Seconds 1
}

if ($manifested) {
    Write-Host "📸 Trigger Received. Waiting 15s for filming..." -ForegroundColor Cyan
    Start-Sleep -Seconds 15
    Write-Host "📸 Capturing Vision..." -ForegroundColor Green
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    $Screen = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
    $Bitmap = New-Object System.Drawing.Bitmap $Screen.Width, $Screen.Height
    $Graphics = [System.Drawing.Graphics]::FromImage($Bitmap)
    $Graphics.CopyFromScreen($Screen.X, $Screen.Y, 0, 0, $Bitmap.Size)
    $Bitmap.Save("c:\Users\lumba\Program\Lumax\div\image\auto_test_vision.png", [System.Drawing.Imaging.ImageFormat]::Png)
} else {
    Write-Host "⚠️ Manifestation timed out." -ForegroundColor Red
}

# 4. Purge
Write-Host "🛑 Purging manifestation..." -ForegroundColor Red
Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
Get-Process -Name "Godot*" -ErrorAction SilentlyContinue | Stop-Process -Force

Write-Host "📜 Final Mind Pass (DEBUG):" -ForegroundColor Yellow
if (Test-Path $DEBUG_LOG) { Get-Content $DEBUG_LOG -Tail 30 }
Write-Host "📜 Final Mind Pass (ERROR):" -ForegroundColor Red
if (Test-Path $ERROR_LOG) { Get-Content $ERROR_LOG -Tail 30 }
