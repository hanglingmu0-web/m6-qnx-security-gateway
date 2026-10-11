#Requires -RunAsAdministrator
# Run on the downstream PC only. No persistent firewall policy or route changes.
param([ValidateRange(60,3600)][int]$DurationSeconds = 600)
$ErrorActionPreference = 'Stop'
$address = '192.168.77.2'
$ruleName = 'M6-GW-v6-Test-18082'
if (@(Get-NetIPAddress -AddressFamily IPv4 -IPAddress $address -ErrorAction SilentlyContinue).Count -ne 1) {
    throw 'Run this on the downstream PC with 192.168.77.2, not on M6.'
}
if (Get-NetFirewallRule -PolicyStore ActiveStore -Name $ruleName -ErrorAction SilentlyContinue) {
    throw 'The named test rule already exists. Inspect/remove that test rule before retrying.'
}
$listener = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Parse($address),18082)
$created = $false
try {
    $listener.Start()
    New-NetFirewallRule -PolicyStore ActiveStore -Name $ruleName -DisplayName $ruleName `
        -Direction Inbound -Action Allow -Enabled True -Profile Any -Protocol TCP `
        -LocalAddress $address -LocalPort 18082 -RemoteAddress 192.168.0.186 `
        -Program (Get-Process -Id $PID).Path | Out-Null
    $created = $true
    Write-Host "LISTENING $address`:18082; remote allow=192.168.0.186; temporary $DurationSeconds seconds"
    Get-NetTCPConnection -LocalAddress $address -LocalPort 18082 -State Listen | Format-Table
    $timer = [Diagnostics.Stopwatch]::StartNew()
    while ($timer.Elapsed.TotalSeconds -lt $DurationSeconds) {
        if ($listener.Pending()) {
            $client = $listener.AcceptTcpClient()
            try { Write-Host "ACCEPTED $($client.Client.RemoteEndPoint)" } finally { $client.Dispose() }
        }
        Start-Sleep -Milliseconds 100
    }
} finally {
    $listener.Stop()
    if ($created) { Remove-NetFirewallRule -PolicyStore ActiveStore -Name $ruleName }
    Write-Host 'Listener stopped; test firewall rule removed.'
}
