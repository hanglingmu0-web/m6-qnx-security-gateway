# Architecture

The gateway is a separate machine from the protected PC. The M6 itself alternates
between Windows compute mode and QNX gateway mode; both do not run concurrently.
QNX boots from removable USB without changing Windows Boot Manager, BCD, the
Windows ESP, or the internal SSD partition layout. QNX does not mount that SSD.

| Role | Measured interface | IPv4 configuration |
|---|---|---|
| A, upstream toward Archer C6 | rt1 | DHCP; 192.168.0.136/24 during the test |
| B, protected LAN | rt0 | 192.168.77.1/24 |
| Protected PC | Ethernet | 192.168.77.2/24; gateway and DNS 192.168.77.1 |

MAC addresses bind physical roles at startup. Public configuration uses example
MACs; replace them with local measurements. Interface enumeration order alone
does not select a role. The upstream gateway/DNS observed in this lab was
192.168.0.1; the DHCP lease, not that example, configures the gateway.

## Startup and packet handling

1. Start AMD PCI support, RAM state storage, `io-sock`, and the RTL8125 driver.
2. Match both MACs and set the B address; keep IPv4 and IPv6 forwarding off.
3. Load a bootstrap PF policy allowing DHCP and B-local development access.
4. Obtain an upstream IPv4 lease; validate its subnet, DNS, and default route.
5. Render the gateway PF template. Check syntax, load, enable, and read back
   filtering and translation rules.
6. In normal mode, call the single forwarding-on function. In forwarding-off
   mode, leave the gate closed and report `TEST_MODE`, not a failure.

PF uses interface-bound states. B ingress admits traffic and tags it; A egress
permits the tagged traffic after NAT. DNS addressed to B port 53 is redirected
to the configured upstream DNS with TCP and UDP `rdr` rules. No DNS daemon is used.

The policy denies new upstream TCP toward the protected subnet with the label
`M6_WAN_TO_LAN_DENY`; default deny covers other unsolicited traffic. The
`M6_UPSTREAM_DENY` label rejects protected-host access to the directly attached
upstream subnet, except the explicit DNS path. This is not an all-private-address
or application-level policy. NAT is not the security boundary by itself.

## State and diagnostics

Runtime state, DHCP files, and logs are in RAM. The validated image uses a small
RAM-backed `/var`; ongoing USB logging is avoided. The original BSP and its RAM
storage integration must be obtained/configured locally.

The development service binds 192.168.77.1:18080, accepts only the protected /24,
and returns a fixed status snapshot. It is plaintext, read-only, and has no
command, arbitrary file retrieval, or configuration endpoint. It runs without
root privileges, dropping them before creating the listening socket. Remove it
from a future production image.

`CURRENT_STATE` describes the current gate state. `LAST_EVENT` and associated
fields preserve past events without presenting them as a current failure.
Forwarding request/success counters describe the controlled software path;
sampled observations cannot prove absence of every transient state.

Runtime checking polls approximately every two seconds. It is not an atomic
interlock between PF and forwarding, and does not guarantee zero packet leakage
after a runtime fault.

## Mode separation

While Windows runs on M6, this QNX gateway is absent. Restore a suitable network
path and disconnect the M6 upstream connection before returning it to compute
mode. Use the firmware's one-time USB boot menu; no permanent dual-boot entry is
part of this project. The USB can be modified by a host that can write it.
