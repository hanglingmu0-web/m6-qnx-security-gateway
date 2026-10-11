#Requires -RunAsAdministrator
# Run on 192.168.0.186 only. The route is ActiveStore, never persistent.
param([string]$Gateway = '192.168.0.136')
$ErrorActionPreference = 'Stop'
$source = @(Get-NetIPAddress -AddressFamily IPv4 -IPAddress 192.168.0.186 -ErrorAction SilentlyContinue)
if ($source.Count -ne 1) { throw 'Run this on the upstream PC with 192.168.0.186, not on M6.' }
$index = $source[0].InterfaceIndex
$parsed = $null
if (-not [Net.IPAddress]::TryParse($Gateway,[ref]$parsed) -or $parsed.AddressFamily -ne 'InterNetwork') {
    throw 'Gateway must be the actual IPv4 A_IP from the QNX diagnostic.'
}
$prefix = '192.168.77.0/24'
$existing = @(Get-NetRoute -PolicyStore ActiveStore -AddressFamily IPv4 -DestinationPrefix $prefix -ErrorAction SilentlyContinue)
if ($existing.Count -gt 0) { throw 'A route to the test subnet already exists; inspect it before this isolated test.' }
$created = $false
try {
    New-NetRoute -PolicyStore ActiveStore -DestinationPrefix $prefix -InterfaceIndex $index `
        -NextHop $Gateway -RouteMetric 5 | Format-Table
    $created = $true
    Get-NetRoute -PolicyStore ActiveStore -DestinationPrefix $prefix | Format-Table
    Test-NetConnection -ComputerName 192.168.77.2 -Port 18082 -InformationLevel Detailed
} finally {
    if ($created) {
        Remove-NetRoute -PolicyStore ActiveStore -DestinationPrefix $prefix -InterfaceIndex $index `
            -NextHop $Gateway -Confirm:$false
        Write-Host 'Temporary route removed.'
    }
}
