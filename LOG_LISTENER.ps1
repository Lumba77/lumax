$Listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 6007)
$Listener.Start()
Write-Host "📡 Ready: Awaiting Godot Debug Packet on Port 6007..."
$TotalLogs = ""

while ($true) {
    if ($Listener.Pending()) {
        $Client = $Listener.AcceptTcpClient()
        $Stream = $Client.GetStream()
        $Reader = New-Object System.IO.StreamReader($Stream)
        
        while ($Client.Connected) {
            if ($Stream.DataAvailable) {
                $Log = $Reader.ReadLine()
                if ($Log) {
                    Write-Host ">>> $Log"
                    $TotalLogs += "$Log`n"
                    $TotalLogs | Out-File -FilePath "C:\Users\lumba\Program\Lumax\REMOTE_GODOT.log" -Encoding utf8
                }
            }
            Start-Sleep -Milliseconds 50
        }
        $Client.Close()
    }
    Start-Sleep -Seconds 1
}
