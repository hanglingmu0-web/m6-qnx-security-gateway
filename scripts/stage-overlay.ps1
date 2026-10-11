# Stage original project files only. Does not edit a BSP, build an IFS, or write USB.
param(
    [ValidateSet('normal','forwarding-off','syntax-error')][string]$Mode = 'normal',
    [string]$PortsFile
)
$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent
if (-not $PortsFile) { $PortsFile = Join-Path $repo 'config\ports.conf' }
$ports = [IO.File]::ReadAllText((Resolve-Path -LiteralPath $PortsFile).Path)
$macs = @{}
foreach ($role in @('A','B')) {
    $match = [regex]::Match($ports, "(?m)^${role}_MAC=([0-9A-Fa-f]{2}(?::[0-9A-Fa-f]{2}){5})\r?$")
    if (-not $match.Success) { throw "Missing or invalid ${role}_MAC" }
    $macs[$role] = $match.Groups[1].Value.ToLowerInvariant()
}
if ($macs.A -eq $macs.B) { throw 'A and B must use different measured MAC addresses.' }
if ($macs.A -eq '02:00:00:00:78:01' -or $macs.B -eq '02:00:00:00:77:01') {
    throw 'Replace the example MAC addresses with your measured port MACs before staging.'
}
if ($ports -notmatch '(?m)^B_IP=192\.168\.77\.1\r?$' -or $ports -notmatch '(?m)^B_NET=192\.168\.77\.0/24\r?$') {
    throw 'The current policy expects the documented protected subnet.'
}
$stage = Join-Path $repo "build\overlay-$Mode"
New-Item -ItemType Directory -Path $stage -Force | Out-Null
$encoding = [Text.UTF8Encoding]::new($false)
$manifest = [Collections.Generic.List[string]]::new()
foreach ($name in @('network-bringup.sh','gateway-control.sh','dhcp-gateway.sh','diagnostic-snapshot.sh')) {
    $text = [IO.File]::ReadAllText((Join-Path $repo "src\boot\$name"))
    [IO.File]::WriteAllText((Join-Path $stage $name),$text.Replace("`r`n","`n"),$encoding)
    $manifest.Add("$name -> /proc/boot/$name")
}
foreach ($name in @('pf-bootstrap.conf','pf-gateway.conf','dhcpcd-gateway.conf')) {
    $text = [IO.File]::ReadAllText((Join-Path $repo "config\$name"))
    [IO.File]::WriteAllText((Join-Path $stage $name),$text.Replace("`r`n","`n"),$encoding)
    $manifest.Add("$name -> /etc/$name")
}
[IO.File]::WriteAllText((Join-Path $stage 'm6-ports.conf'),$ports.Replace("`r`n","`n"),$encoding)
[IO.File]::WriteAllText((Join-Path $stage 'gateway-mode'),"$Mode`n",$encoding)
$manifest.Add('m6-ports.conf -> /etc/m6-ports.conf')
$manifest.Add('gateway-mode -> /etc/gateway-mode')
$manifest.Add('Compiled output/m6-diag -> /usr/sbin/m6-diag (add separately)')
[IO.File]::WriteAllLines((Join-Path $stage 'MANIFEST.txt'),$manifest,$encoding)
Write-Output "Staged original source/config in $stage. Complete licensed BSP integration per docs/REPRODUCTION.md."
