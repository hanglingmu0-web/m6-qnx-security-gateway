# Limitations

- Experimental, real-hardware-validated PoC; not a commercial firewall.
- QNX is not treated as an inherent security guarantee.
- No IDS/IPS, TLS inspection, or process-level attribution of human/AI traffic.
- Internet egress remains broad; allowed connections can carry harmful content.
- PF syntax-error boot fault injection has not been performed on hardware.
- Runtime instantaneous fail-closed is not demonstrated or guaranteed.
- Long-duration stability and USB flash endurance are not validated.
- Development plaintext TCP/18080 diagnostics remain present, restricted to B.
- No high availability; one gateway outage interrupts its network path.
- IPv6 forwarding is intentionally disabled in the current PoC.
- Same-L2 communication and alternate host routes may bypass the gateway.
- The public source requires integration with a separately licensed QNX BSP;
  it is not a downloadable boot image or a turnkey BSP distribution.

Normal and forwarding-off behavior were measured on the documented M6. Host-side
mock tests exercise control logic but do not establish QNX kernel/PF behavior.
