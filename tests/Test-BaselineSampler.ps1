# Mock snapshots only; does not connect to QNX or alter host networking.
$ErrorActionPreference='Stop'
$repo=Split-Path $PSScriptRoot -Parent
$dir=Join-Path $repo ('output\sampler-test-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $dir | Out-Null
Copy-Item -LiteralPath (Join-Path $repo 'scripts\sample-gateway-baseline.ps1') -Destination $dir
$mock=@'
$n=0
$counterPath=Join-Path $PSScriptRoot 'sample-number.txt'
if(Test-Path -LiteralPath $counterPath){$n=[int](Get-Content -LiteralPath $counterPath)}
$n++
[IO.File]::WriteAllText($counterPath,[string]$n)
if($n -eq 5){throw 'simulated timeout'}
$counter=if($n -le 2){$n*100}else{($n-2)*10}
@"
IMAGE=M6-GW-v6-normal
SNAPSHOT_FRESH=YES
CURRENT_STATE=READY
SAMPLE_NUMBER=$n
PF_STATE_ENTRIES=42
PF_STATE_INSERTS_TOTAL=$counter
LAN_PASSED_PACKETS_TOTAL=$counter
LAN_PASSED_BYTES_TOTAL=$($counter*100)
LAN_STATE_CREATIONS_TOTAL=$counter
"@
'@
[IO.File]::WriteAllText((Join-Path $dir 'read-gateway-status.ps1'),$mock,[Text.UTF8Encoding]::new($false))
function Start-Sleep { param($Seconds) } # No long wait during host unit test.
$csv=Join-Path $dir 'result.csv'
& (Join-Path $dir 'sample-gateway-baseline.ps1') -Samples 5 -IntervalSeconds 5 -OutputPath $csv
$rows=@(Import-Csv -LiteralPath $csv)
if($rows.Count -ne 5){throw 'Wrong row count'}
if($rows[0].ApproxLanBytesPerSecond -ne ''){throw 'First sample must not invent a rate'}
if([double]$rows[1].ApproxLanBytesPerSecond -le 0){throw 'Positive delta rate missing'}
if($rows[2].SampleStatus -ne 'COUNTER_RESET' -or $rows[2].ApproxLanBytesPerSecond -ne ''){throw 'Reset became a false rate'}
if([double]$rows[3].ApproxLanBytesPerSecond -le 0){throw 'Did not recover after reset'}
if($rows[4].SampleStatus -ne 'READ_FAILED' -or $rows[4].PFStateEntries -ne ''){throw 'Read failure must not become zero measurement'}
'PASS sampler-first-delta-reset-recovery-read-failure'
