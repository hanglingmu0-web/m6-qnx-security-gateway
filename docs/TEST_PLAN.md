# Test plan

Completed hardware results are in [TEST_RESULTS.md](TEST_RESULTS.md). These
procedures support reproduction; do not infer success from a configured rule.
Use the documented lab topology and disable alternative host routes during the
test. No live `pfctl -d` fault test is part of Phase 1.

## Normal baseline

On the protected PC (192.168.77.2/24, gateway/DNS 192.168.77.1):

```powershell
& .\scripts\read-gateway-status.ps1
ping 192.168.77.1
nslookup github.com 192.168.77.1
Test-NetConnection 1.1.1.1 -Port 443 -InformationLevel Detailed
```

Require a fresh normal snapshot, PF checks and NAT `OK`, `READY=YES`, forwarding
1, IPv6 forwarding 0, successful DNS, and TCP/443 from 192.168.77.2.
For upstream-LAN isolation, compare `M6_UPSTREAM_DENY_PACKETS` before/after a
controlled non-DNS connection attempt to the upstream subnet. Connection failure
without a corresponding PF drop counter is not sufficient attribution.

## Upstream to protected new TCP

Read the current `A_IP`; the following 192.168.0.136 is the measured example.
Run these helpers in elevated PowerShell **on the two test PCs, not on M6**.
They retain Windows Firewall, create only scoped temporary test rules/routes,
and clean up in `finally`.

Protected PC, terminal 1:

```powershell
& .\tests\Start-DownstreamListener.ps1 -DurationSeconds 600
```

Confirm its printed `LISTEN` state. Protected PC, terminal 2:

```powershell
& .\scripts\read-gateway-status.ps1
```

Upstream PC 192.168.0.186:

```powershell
& .\tests\Invoke-UpstreamDenyTest.ps1 -Gateway 192.168.0.136
```

The helper creates `192.168.77.0/24` via the actual A address in `ActiveStore`,
runs `Test-NetConnection 192.168.77.2 -Port 18082`, and removes the route. Expect
TCP failure plus an increase in `M6_WAN_TO_LAN_DENY_PACKETS`, with gateway READY
and forwarding 1. Repeat the normal DNS/Internet check afterward.

If a PowerShell process is forcibly terminated, inspect and remove only its
named test objects. On the upstream PC, using its measured interface index:

```powershell
Get-NetRoute -PolicyStore ActiveStore -DestinationPrefix 192.168.77.0/24
# Substitute the actual test interface index and current A address:
Remove-NetRoute -PolicyStore ActiveStore -DestinationPrefix 192.168.77.0/24 `
  -InterfaceIndex <test-interface-index> -NextHop 192.168.0.136
```

On the protected PC:

```powershell
Get-NetFirewallRule -PolicyStore ActiveStore -Name M6-GW-v6-Test-18082
Remove-NetFirewallRule -PolicyStore ActiveStore -Name M6-GW-v6-Test-18082
```

Do not replace existing unrelated routes or firewall rules.

## Forwarding-off control

Boot the separately built `forwarding-off` variant. Require normal PF syntax,
load, enabled/readback and NAT checks, but `CURRENT_STATE=TEST_MODE`, `READY=NO`,
`FAIL_REASON=NONE`, both forwarding values 0, and forwarding-on requests and
successes 0. The sampled ever-1 indicator should be 0 as supplementary evidence.

Run local ping, Internet TCP/443, DNS through B, and upstream TCP/80 as in the
results table. Expect local ping success and external failures. Re-read counters
afterward; Internet failure alone is not the acceptance criterion.

## Normal restoration

Restore the saved validated normal IFS, not a fresh fault-test build. Match its
recorded SHA-256 to the USB file, boot manually, and repeat normal diagnostics,
DNS, and TCP/443. This final restoration passed in Phase 1.

## Phase 2 and future

Deliberate syntax-error boot testing must use a separate image and preserve the
normal baseline. Expected future observation: PF syntax failure, load skipped,
READY no, both forwarding values 0, and zero forwarding-on requests/successes.
This hardware test is deferred. Host mock coverage is not a substitute.

Runtime instantaneous fail-closed requires separate design and testing. Begin
traffic-rate work with `scripts/sample-gateway-baseline.ps1` in monitoring-only
mode; do not invent restrictive connection thresholds from a short run.
