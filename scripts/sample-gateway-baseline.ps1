# Read-only sampling from the downstream PC. No traffic limits or PF changes.
param(
    [ValidateSet('Mixed','Windows','GitHub','ChatGPT','Codex')][string]$Activity = 'Mixed',
    [ValidateRange(2,3600)][int]$Samples = 91,
    [ValidateRange(5,300)][int]$IntervalSeconds = 10,
    [string]$OutputPath = (Join-Path (Get-Location) ('m6-baseline-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.csv'))
)
$ErrorActionPreference = 'Stop'
if (Test-Path -LiteralPath $OutputPath) { throw 'Choose a new CSV path; existing measurements will not be overwritten.' }
$watch = [Diagnostics.Stopwatch]::StartNew()
$previous = $null
for ($i=0; $i -lt $Samples; $i++) {
    $fields = @{}
    $status = 'OK'
    try {
        $text = & (Join-Path $PSScriptRoot 'read-gateway-status.ps1')
        foreach($line in ($text -split '\r?\n')) {
            if($line -match '^([A-Z0-9_]+)=(.*)$') { $fields[$Matches[1]]=$Matches[2] }
        }
    } catch { $status='READ_FAILED' }
    $elapsed = $watch.Elapsed.TotalSeconds
    $numbers = @{}
    foreach($key in @('SAMPLE_NUMBER','PF_STATE_ENTRIES','PF_STATE_INSERTS_TOTAL','LAN_PASSED_PACKETS_TOTAL','LAN_PASSED_BYTES_TOTAL','LAN_STATE_CREATIONS_TOTAL')) {
        if ($fields[$key] -match '^\d+$') { $numbers[$key] = [decimal]$fields[$key] } elseif ($status -eq 'OK') { $status='METRICS_UNAVAILABLE' }
    }
    if ($status -eq 'OK' -and ($fields['SNAPSHOT_FRESH'] -ne 'YES' -or $fields['CURRENT_STATE'] -ne 'READY')) {
        $status='NOT_FRESH_READY'
    }
    $rates = @{}
    if ($status -eq 'OK' -and $null -ne $previous) {
        if ($fields['IMAGE'] -ne $previous.Image -or $numbers.SAMPLE_NUMBER -le $previous.Numbers.SAMPLE_NUMBER) {
            $status='RESET_OR_REPEATED_SAMPLE'
        } else {
            foreach($key in @('PF_STATE_INSERTS_TOTAL','LAN_PASSED_PACKETS_TOTAL','LAN_PASSED_BYTES_TOTAL','LAN_STATE_CREATIONS_TOTAL')) {
                $delta=$numbers[$key]-$previous.Numbers[$key]
                if ($delta -lt 0) { $status='COUNTER_RESET'; break }
                $rates[$key]=[Math]::Round([double]$delta/($elapsed-$previous.Elapsed),3)
            }
        }
    }
    if ($status -ne 'OK') { $rates=@{} }
    [pscustomobject][ordered]@{
        TimeUtc=[DateTime]::UtcNow.ToString('o'); Activity=$Activity; SampleStatus=$status
        Image=$fields['IMAGE']; CurrentState=$fields['CURRENT_STATE']; SampleNumber=$numbers.SAMPLE_NUMBER
        PFStateEntries=$numbers.PF_STATE_ENTRIES; PFStateInsertsTotal=$numbers.PF_STATE_INSERTS_TOTAL
        LanPacketsTotal=$numbers.LAN_PASSED_PACKETS_TOTAL; LanBytesTotal=$numbers.LAN_PASSED_BYTES_TOTAL
        LanStateCreationsTotal=$numbers.LAN_STATE_CREATIONS_TOTAL
        ApproxPFInsertsPerSecond=$rates.PF_STATE_INSERTS_TOTAL
        ApproxLanPacketsPerSecond=$rates.LAN_PASSED_PACKETS_TOTAL
        ApproxLanBytesPerSecond=$rates.LAN_PASSED_BYTES_TOTAL
        ApproxLanStateCreationsPerSecond=$rates.LAN_STATE_CREATIONS_TOTAL
    } | Export-Csv -LiteralPath $OutputPath -NoTypeInformation -Append -Encoding UTF8
    # Reset the measurement baseline after resets; never convert a reset to a rate.
    if ($status -eq 'OK' -or $status -eq 'COUNTER_RESET' -or $status -eq 'RESET_OR_REPEATED_SAMPLE') {
        $previous=@{Numbers=$numbers; Elapsed=$elapsed; Image=$fields['IMAGE']}
    } else { $previous=$null }
    if ($i+1 -lt $Samples) { Start-Sleep -Seconds $IntervalSeconds }
}
Write-Output "Saved monitoring-only baseline: $OutputPath"
