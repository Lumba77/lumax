$ErrorActionPreference = "Continue"
Write-Host "📡 Connecting to CUSTOM Debug Protocol on 127.0.0.1:6002..."
try {
    $client = [System.Net.Sockets.TcpClient]::new("127.0.0.1", 6002)
    $stream = $client.GetStream()
    $reader = New-Object System.IO.StreamReader($stream)
    
    Write-Host "✅ Connected! Listening for heartbeat logs..." -ForegroundColor Green
    
    while ($client.Connected) {
        if ($stream.DataAvailable) {
            $log = $reader.ReadLine()
            if ($log) {
                Write-Output "LOG >>> $log"
                $log | Out-File -FilePath "C:\Users\lumba\Program\Lumax\REMOTE_6002.log" -Append -Encoding utf8
            }
        }
        Start-Sleep -Milliseconds 100
    }
} catch {
    Write-Error $_.Exception.Message
} finally {
    if ($client) { $client.Close() }
}
