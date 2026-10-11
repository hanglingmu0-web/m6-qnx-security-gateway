#!/bin/ksh
# Network startup never waits for HDMI/USB HID.
exec >>/dev/shmem/boot-progress.log 2>&1
echo 'M6-GW-v6 stage=kernel-shell'
uname -a
pidin info
slogger2 &
mqueue &
random &
export PCI_HW_MODULE=/lib/dll/pci/pci_hw-AMD_x86.so
export PCI_DEBUG_MODULE=/lib/dll/pci/pci_debug2.so
export PCI_SLOG_MODULE=/lib/dll/pci/pci_slog2.so
export PCI_BKWD_COMPAT_MODULE=/lib/dll/pci/pci_bkwd_compat.so
pci-server --aspace-enable --config=/etc/system/config/pci/pci_server.cfg &
waitfor /dev/pci 20 || exit 1
pci-tool -v >/dev/shmem/pci-snapshot.log 2>&1 &
ksh /proc/boot/ram-state.sh || exit 1
GW_DIR=/var/run/m6
umask 022
mkdir -p "$GW_DIR" /var/run/dhcpcd || exit 1
GATEWAY_MODE=$(cat /etc/gateway-mode)
PF_BOOTSTRAP=/etc/pf-bootstrap.conf
. /etc/m6-ports.conf
. /proc/boot/gateway-control.sh
echo 0 >"$GW_DIR/forwarding-on-requests"
echo 0 >"$GW_DIR/forwarding-on-successes"
gate_step STARTING
gate_event BOOT_START
dhcp_pid=
stop_gateway() {
    gate_failure
    echo 'M6-GW-v6 stopped; reboot required' >"$GW_DIR/fatal"
    close_gateway
    [ -z "$dhcp_pid" ] || kill "$dhcp_pid"
}
trap 'stop_gateway' EXIT
trap 'exit 1' HUP INT TERM
echo 'M6-GW-v6 io-sock=start-requested'
io-sock -m pci -m phy -d rt &
waitfor /dev/socket 20 || exit 1
# /dev/socket existence alone is not treated as interface readiness.
map_and_address_ports || exit 1
# Independent observer stays available after a gate failure, while io-sock works.
ksh /proc/boot/diagnostic-snapshot.sh >>/dev/shmem/diagnostic.log 2>&1 &
/usr/sbin/m6-diag >>/dev/shmem/diagnostic.log 2>&1 &
devinfo -v >"$GW_DIR/devinfo.txt" 2>&1
echo 'M6-GW-v6 io-sock=PASS MAC-map=PASS forwarding=0/0'
lock_gate || exit 1
if ! bootstrap_pf; then gate_failure; unlock_gate; exit 1; fi
unlock_gate
echo 'M6-GW-v6 stage=DHCP-ready PF=enabled forwarding=0/0'
# -B keeps a monitorable process; -4/-L prevent IPv6 and IPv4LL fallback.
# All lease/control files live in the RAM-backed /var.
gate_step WAITING_FOR_DHCP_HOOK
dhcpcd -4 -B -L -t 0 -f /etc/dhcpcd-gateway.conf -c /proc/boot/dhcp-gateway.sh "$A_IF" &
dhcp_pid=$!
sample=0
while :; do
    kill -0 "$dhcp_pid" 2>/dev/null || { gate_step DHCP_PROCESS_EXIT; gate_failure; echo 'M6-GW-v6 FAIL=dhcpcd-exit'; exit 1; }
    # DHCP callback and monitoring never alter/read a partially reloaded baseline.
    if mkdir "$GW_DIR/gate.lock" 2>/dev/null; then
        if ! check_running_gate; then
            gate_failure
            echo 'M6-GW-v6 FAIL=runtime-gate' >"$GW_DIR/fatal"
            close_gateway
            unlock_gate
            exit 1
        fi
        if [ "$sample" -eq 0 ]; then
            {
                echo "mode=$GATEWAY_MODE A=$A_IF B=$B_IF"
                ifconfig "$A_IF"
                ifconfig "$B_IF"
                sysctl net.inet.ip.forwarding net.inet6.ip6.forwarding
                route -n get default
                pfctl -si
            } >"$GW_DIR/latest-status.txt" 2>&1
        fi
        unlock_gate
    fi
    sample=$((sample + 1))
    [ "$sample" -lt 5 ] || sample=0
    sleep 2
done
