# Real-hardware test results

**Phase 1: Basic Gateway and Network-Boundary PoC — COMPLETE.**
These are operator-reported measurements on the physical M6, including the final
normal-baseline restoration. They are distinct from host-side mocked tests.

## Completed

| Test | Result |
|---|---|
| USB UEFI boot / QNX OS 8 on GMKtec M6 Ultra | PASS |
| AMD Ryzen 5 7640HS / RTL8125 x2 | PASS |
| Upstream DHCP / protected fixed LAN | PASS |
| PF syntax, load, enabled state, rule readback | PASS |
| NAT / DNS redirect | PASS |
| Protected host to Internet TCP/443 | PASS |
| Protected host to upstream LAN block | PASS; PF counter evidence |
| Upstream to protected host new TCP block | PASS; dedicated PF counter evidence |
| IPv6 forwarding disabled | PASS |
| Forwarding gate / forwarding-off control | PASS |
| Validated normal baseline restored to USB | PASS; SHA-256 match |
| Normal operation after restoration | PASS |

## Normal gateway and boundary tests

The upstream DHCP lease was 192.168.0.136/24 on A/rt1, with gateway and DNS
192.168.0.1. B/rt0 was 192.168.77.1/24. The protected PC was 192.168.77.2/24
with gateway/DNS 192.168.77.1. These upstream values describe this test run.

Protected-to-upstream LAN attempts increased `M6_UPSTREAM_DENY` (an earlier run
observed 0 to 71). Required DNS was an explicit exception. This is measured PF
dropping, not a claim that every upstream service was individually tested.

For the reverse direction:

- Upstream test PC: 192.168.0.186.
- Protected PC: an actual TCP listener on 192.168.77.2:18082, confirmed `LISTEN`.
- Windows Firewall stayed enabled, with a temporary allowance limited to the
  upstream test PC and that listener.
- An ActiveStore-only route on the upstream PC sent 192.168.77.0/24 via
  192.168.0.136. Absence of a route was therefore not the explanation for failure.
- `Test-NetConnection 192.168.77.2 -Port 18082` failed.
- `M6_WAN_TO_LAN_DENY_PACKETS` increased **0 -> 5** while `CURRENT_STATE=READY`,
  `READY=YES`, and `FORWARDING=1` were maintained.
- DNS resolution and Internet TCP/443 still succeeded after the test.

This confirms QNX/PF dropped the tested new upstream TCP connection. Five packets
is a measured count, not a fixed expected value; SYN retries can change it.
Normal mode also reported `FORWARDING_ON_REQUESTS=1` and
`FORWARDING_ON_SUCCESSES=1`.

## Forwarding-off control

```ini
IMAGE=M6-GW-v6-forwarding-off
TEST_MODE=forwarding-off
PF_PHASE=GATEWAY
PF_SYNTAX=OK
PF_LOAD=OK
PF_ENABLED=OK
PF_READBACK=OK
NAT=OK
CURRENT_STATE=TEST_MODE
GATE_STEP=TEST_MODE
READY=NO
FAIL_REASON=NONE
FORWARDING=0
IPV6_FORWARDING=0
FORWARDING_ON_REQUESTS=0
FORWARDING_ON_SUCCESSES=0
FORWARDING_OBSERVED_EVER_1=0
```

| Protected-PC command | Observed result |
|---|---|
| `ping 192.168.77.1` | Success |
| `Test-NetConnection 1.1.1.1 -Port 443` | False |
| `nslookup github.com 192.168.77.1` | Timeout |
| `Test-NetConnection 192.168.0.1 -Port 80` | False |

After these attempts, forwarding stayed 0 and both forwarding-on counters stayed
0. PF and NAT can be fully configured while packet forwarding remains disabled.
The control experiment confirmed that forwarding does not begin until the gate
is explicitly opened.

The result combines valid PF/NAT, gate counters, forwarding readback, and traffic
outcomes. Failure of 192.168.0.1:80 alone is not sufficient evidence. A sampled
`FORWARDING_OBSERVED_EVER_1=0` is not continuous proof against transient changes.
This control is not a complete boot-time PF-fault fail-closed validation.

## Final normal restoration

The previously saved, validated `M6-GW-v6-normal` IFS was restored to
`EFI/BOOT/BOOTX64.EFI`; it was not rebuilt from fault-test sources.

Baseline and USB SHA-256 both matched:

```text
51E34462BB572C45CEB39BB5644989517476AC191D95A1E975D6C36BF2B2A85B
```

After a subsequent real USB boot:

```ini
IMAGE=M6-GW-v6-normal
TEST_MODE=normal
SNAPSHOT_FRESH=YES
PF_PHASE=GATEWAY
PF_SYNTAX=OK
PF_LOAD=OK
PF_ENABLED=OK
PF_READBACK=OK
NAT=OK
FORWARDING=1
IPV6_FORWARDING=0
CURRENT_STATE=READY
GATE_STEP=READY
READY=YES
FAIL_REASON=NONE
```

`nslookup github.com 192.168.77.1` succeeded (20.27.177.113 in this run).
`Test-NetConnection 1.1.1.1 -Port 443` reported `TcpTestSucceeded=True` and
`SourceAddress=192.168.77.2`. The DNS answer is a measurement, not a pinned target.
The IFS, EFI file, and private baseline archives are not published here.

## Deferred

- Deliberate PF syntax-error boot fault injection: **not tested on hardware**;
  the syntax-error variant has not been installed on the USB.
- Runtime instantaneous fail-closed: **not implemented as an instantaneous
  guarantee / not verified**. Current monitoring is polling.
- Long-duration operation, USB endurance, production removal of TCP/18080,
  AI/automation-specific traffic baselines, anomaly detection, and rate controls.

## Public-source checks

The published control/diagnostic sources and PF templates match the selected
original local sources (apart from line endings). Port MACs are replaced by a
configuration example. Gate and diagnostic mock tests and the PowerShell sampler
test passed. The diagnostic C service compiled with the recorded QNX toolchain;
the public staging helper was checked with synthetic MACs. These publication
checks did not rebuild or replace the validated USB image.
