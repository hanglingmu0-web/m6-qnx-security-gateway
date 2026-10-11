# Troubleshooting

These issues occurred during the project. They describe observed causes and
fixes, not changes that every reproducer must apply.

## Japanese Windows user profile path

Japanese characters and spaces in a Windows user profile path caused QNX
Software Center workspace/license-directory issues. Separating work and
configuration into ASCII paths such as `C:\QNXWS`, `C:\QNXCONFIG`, and `C:\QNX\`
resolved the problem. QSC supports its `-data` workspace option; configure the
QNX license/configuration location using the installed QNX tools. Do not publish
license files or copy them into this repository.

Keep the BSP build, temporary directories, and tool inputs in ASCII paths without
spaces. Use the official `qnxsdp-env.bat` for the installed SDK, with process-local
environment settings where possible.

## Missing IPv4 default route

A previous fixed IPv4 configuration used for RPC left Windows without an IPv4
default route. IPv6 Internet access worked, while an IPv4-only QNX site could
not be reached. Returning that interface to DHCP resolved the problem. A working
browser over IPv6 alone did not establish IPv4 reachability. Inspect the actual
route before changing networking; no automatic host network reset is supplied.

## HDMI appearance

After USB boot, the display remained near the GMKtec logo. QNX had actually
booted and both RTL8125 ports worked. Isolated network ping first established
kernel/driver progress; later RAM snapshots and TCP/18080 supplied diagnostics.
Do not equate an unchanged HDMI image with a failed QNX boot.

## NIC mapping

The two ports were verified independently on isolated subnets, then identified
by MAC for upstream/protected roles. Observed names were rt1/rt0; startup does
not assume those names. Configure your own MACs in an ignored local ports file.

## Gateway readiness versus past events

An earlier diagnostic mixed a historical forwarding-mismatch event with current
READY state. v6 separates current state from event history. Use a fresh snapshot,
current state, forwarding values, and PF checks together; a historical event
alone is not a current fault.

DNS is PF redirection, not a DNS-forwarder daemon. A DNS timeout can reflect a
closed forwarding gate even when B-local ping/diagnostics still work. Check the
PF phase, default route, NAT/readback, and gate reason before repeating NIC bring-up.
