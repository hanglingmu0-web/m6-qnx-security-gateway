# Threat model

## Objective and trust boundary

Restrict the network reach of a protected host using a separately managed QNX
gateway. The protected Windows/Linux PC may run untrusted automation, an AI agent,
or become compromised. Its local firewall is not the sole boundary protecting
the upstream LAN.

PF denies unsolicited upstream connections and restricts protected-host access
to the directly attached upstream LAN. Broad stateful Internet access remains
available, including ChatGPT, Codex, GitHub, and ordinary browsing. This policy
does not identify which process or actor generated a packet.

## Assumptions

- Protected traffic actually traverses M6; alternate Wi-Fi, VPN, or other routes
  must be considered separately.
- The gateway image, its administration, and the upstream router are trusted.
- A compromised protected PC cannot administer the gateway through TCP/18080.
- The measured topology has one upstream subnet and a distinct protected subnet.

## Addressed behavior

The controlled tests demonstrate rejection of a new upstream TCP connection and
protected-host traffic toward the upstream LAN, with PF counter evidence. This
can reduce lateral reach after external compromise or ransomware infection.
The forwarding-off control demonstrates that valid PF/NAT configuration alone
does not open the forwarding gate.

## Outside the measured boundary

Local file encryption, allowed Internet exfiltration, malicious HTTPS content,
credential theft, compromised gateway software/firmware, and physical attacks
are not prevented by these results. Same-L2 traffic between downstream devices
does not traverse the gateway; VLANs or client isolation would be separate work.

An OS different from the protected host provides implementation diversity, not
an inherent security guarantee. USB is writable and can be altered from Windows
or another machine. SHA-256 matching confirms equality to a chosen baseline,
not that the baseline is trustworthy or that secure boot is enforced.

Boot-time PF syntax-error fault injection remains unperformed. Runtime polling
does not provide instantaneous fail-closed behavior. Availability, throughput
under attack, long-duration stability, and USB endurance require further work.
