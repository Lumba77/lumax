# connect_quest.ps1 - ADB WiFi Connection Helper for Lumax
# Usage: .\connect_quest.ps1 [IP_ADDRESS]

param (
    [string]$IP = ""
)

$ErrorActionPreference = "Stop"

Write-Host "--- 📶 Lumax Quest WiFi Connector ---" -ForegroundColor Cyan

# 1. Try to find a device
$devices = adb devices | Select-String -Pattern "\tdevice$"
if ($null -eq $devices) {
    Write-Host "No devices found. Ensure your Quest is connected via USB or already on WiFi." -ForegroundColor Red
    exit 1
}

# 2. Identify the device IP or Serial
$targetDevice = ""
if ($IP -ne "") {
    $targetDevice = "$IP:5555"
} else {
    # Match an existing WiFi device (e.g., 192.168.8.201:5555)
    if ($devices -match "(\d+\.\d+\.\d+\.\d+:5555)") {
        $targetDevice = $matches[1]
        Write-Host "Found existing WiFi connection: $targetDevice" -ForegroundColor Green
    } else {
        # Check for USB device
        Write-Host "No WiFi connection found. Scanning for Quest on USB..." -ForegroundColor Yellow
        # Enable TCP/IP on port 5555
        adb tcpip 5555
        Start-Sleep -Seconds 2
        
        # Try to find the IP address
        Write-Host "Attempting to find Quest IP via Shell..."
        $ip_info = adb shell "ip addr show wlan0"
        if ($ip_info -match "inet (\d+\.\d+\.\d+\.\d+)") {
            $IP = $matches[1]
            $targetDevice = "$IP:5555"
            Write-Host "Detected Quest IP: $IP" -ForegroundColor Green
            Write-Host "Connecting to detected IP..."
            adb connect $targetDevice
        } else {
            Write-Host "Could not detect IP automatically. Please provide it as an argument." -ForegroundColor Red
            exit 1
        }
    }
}

Write-Host "`nEnsuring connection to $targetDevice..." -ForegroundColor Yellow
$connResult = adb connect $targetDevice
adb devices

# 3. SETUP PORT REVERSALS (User Preferred Localhost Pattern)
Write-Host "`n🔄 Setting up Port Reverse Forwarding (Quest -> PC)..." -ForegroundColor Yellow
adb -s $targetDevice reverse tcp:8000 tcp:8000 # Soul
adb -s $targetDevice reverse tcp:8001 tcp:8001 # Ears
adb -s $targetDevice reverse tcp:8002 tcp:8002 # Mouth
adb -s $targetDevice reverse tcp:8004 tcp:8004 # Creativity
adb -s $targetDevice reverse tcp:8020 tcp:8020 # Chatterbox
adb -s $targetDevice reverse tcp:8005 tcp:8005 # Turbo TTS

Write-Host "`n✅ Connected and Ports Reversed!" -ForegroundColor Green
Write-Host "You can now use 127.0.0.1 in Godot to reach the backend." -ForegroundColor Gray
