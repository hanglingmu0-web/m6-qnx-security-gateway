#!/bin/ksh
# Official dhcpcd -c hook API; address/routes are installed by dhcpcd itself.
exec >>/dev/shmem/boot-progress.log 2>&1
GW_DIR=/var/run/m6
. /etc/m6-ports.conf
. "$GW_DIR/interfaces"
. /proc/boot/gateway-control.sh
PF_GATEWAY=/etc/pf-gateway.conf
GATEWAY_MODE=$(cat /etc/gateway-mode)
printf '%s\n' "$reason" >"$GW_DIR/dhcp-event"
# Only routing inputs, never the full environment or lease credentials.
printf 'IP=%s\nMASK=%s\nCIDR=%s\nROUTERS=%s\nDNS=%s\n' \
    "${new_ip_address:-}" "${new_subnet_mask:-}" "${new_subnet_cidr:-}" \
    "${new_routers:-}" "${new_domain_name_servers:-}" >"$GW_DIR/lease-inputs"
gate_step DHCP_HOOK_INTERFACE
[ "$interface" = "$A_IF" ] || { gate_failure; exit 1; }
if ! lock_gate; then
    gate_step DHCP_LOCK_TIMEOUT
    gate_failure
    echo 'M6-GW-v6 FAIL=DHCP-lock-timeout' >"$GW_DIR/fatal"
    close_gateway
    exit 1
fi
hook_ok=no
hook_exit() {
    if [ "$hook_ok" != yes ]; then gate_failure; close_gateway; fi
    unlock_gate
}
trap 'hook_exit' EXIT
trap 'close_gateway; exit 1' HUP INT TERM
echo "M6-GW-v6 DHCP-event=$reason interface=$interface"
case "$reason" in
    BOUND|RENEW|REBIND|REBOOT)
        if ! activate_lease; then
            gate_failure
            close_gateway
            echo 'M6-GW-v6 DHCP/PF-gate=FAIL forwarding=OFF'
            exit 1
        fi ;;
    PREINIT|EXPIRE|NAK|NOCARRIER|NOCARRIER_ROAMING|STOP|STOPPED|DEPARTED|FAIL|TIMEOUT)
        gate_step "DHCP_$reason"
        close_gateway || exit 1 ;;
    CARRIER) : ;;
    *) echo "M6-GW-v6 DHCP-event=$reason ignored" ;;
esac
hook_ok=yes
