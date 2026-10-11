#!/bin/sh
# Exercise the actual observer with saved gate-test fixtures and read-only mocks.
set -eu
observer=$1
fixtures=$2
work=$3
mkdir -p "$work"
ifconfig() { printf 'rt2: flags=UP\n    inet 192.168.0.136 netmask 0xffffff00\n    status: active\n'; }
route() {
    [ "$scenario" != no-route ] || return 1
    printf 'gateway: 192.168.0.1\ninterface: rt2\n'
}
pfctl() {
    case "$1" in
        -si) printf 'Status: Enabled for 0 days\nState Table\n  current entries 42\n  inserts 1000 2.1/s\n' ;;
        -sr) cat "$GW_DIR/loaded.rules" ;;
        -sn) cat "$GW_DIR/loaded.nat" ;;
        -ss) : ;;
        -s)
            printf 'M6_LAN_OUT 10 100 10000 60 6000 40 4000 5\nM6_DNS_UDP 10 20 2000 10 1000 10 1000 2\nM6_DNS_TCP 1 4 400 2 200 2 200 1\nM6_UPSTREAM_DENY 71 71 4000 71 4000 0 0 0\nM6_WAN_TO_LAN_DENY 3 3 120 3 120 0 0 0\n' ;;
        *) echo 'FAIL observer attempted a PF mutation' >&2; exit 30 ;;
    esac
}
sysctl() {
    case "$*" in
        '-n net.inet.ip.forwarding') echo "$expected_v4" ;;
        '-n net.inet6.ip6.forwarding') echo 0 ;;
        *) echo 'FAIL observer attempted a sysctl mutation' >&2; exit 31 ;;
    esac
}
sleep() { exit 0; } # Stop the observer subprocess after one published snapshot.
check() { grep -q "^$1$" "$fixtures/$scenario/diagnostic.txt" || { echo "FAIL $scenario $1"; exit 1; }; }
for scenario in reversed off-control corrupt-control syntax-fail load-fail missing-nat no-route; do
    expected_v4=0
    [ "$scenario" != reversed ] || expected_v4=1
    # The target's fixed RAM paths are replaced only in this host test copy.
    sed -e "s|^GW_DIR=/var/run/m6$|GW_DIR=$fixtures/$scenario|" \
        -e "s|/etc/gateway-mode|$fixtures/$scenario/test-mode|" \
        -e "s|/dev/shmem/boot-progress.log|$fixtures/$scenario/events|" \
        "$observer" >"$work/observer.sh"
    (set +e; . "$work/observer.sh")
    check A_IP=192.168.0.136
    check IPV6_FORWARDING=0
    check DNS_DAEMON=NOT_USED
    check PF_STATE_ENTRIES=42
    check PF_STATE_INSERTS_TOTAL=1000
    check LAN_PASSED_PACKETS_TOTAL=124
    check LAN_PASSED_BYTES_TOTAL=12400
    check LAN_STATE_CREATIONS_TOTAL=8
    check M6_WAN_TO_LAN_DENY_PACKETS=3
    if [ "$scenario" = reversed ]; then
        check READY=YES; check NAT=OK; check DNS_FORWARDER=OK; check FORWARDING=1
        check CURRENT_STATE=READY; check GATE_STEP=READY; check FAIL_REASON=NONE
    elif [ "$scenario" = off-control ]; then
        check READY=NO; check CURRENT_STATE=TEST_MODE; check GATE_STEP=TEST_MODE
        check NAT=OK; check PF_LOAD=OK; check FORWARDING=0; check FAIL_REASON=NONE
        check FORWARDING_ON_REQUESTS=0; check FORWARDING_ON_SUCCESSES=0
    else
        check READY=NO; check NAT=FAIL; check DNS_FORWARDER=FAIL; check FORWARDING=0
        case "$scenario" in
            syntax-fail|corrupt-control) check PF_SYNTAX=FAIL; check PF_LOAD=SKIPPED; check FAIL_REASON=PF_SYNTAX; check FORWARDING_ON_REQUESTS=0 ;;
            load-fail) check PF_SYNTAX=OK; check PF_LOAD=FAIL; check FAIL_REASON=PF_LOAD ;;
            missing-nat) check PF_LOAD=OK; check PF_READBACK=FAIL; check FAIL_REASON=PF_NAT_READBACK_MISMATCH ;;
            no-route) check DEFAULT_ROUTE=FAIL; check FAIL_REASON=DEFAULT_ROUTE_QUERY ;;
        esac
        check CURRENT_STATE=BLOCKED
    fi
    echo "PASS diagnostic-$scenario"
done
# Historical failure must remain visible without turning a healthy state into FAIL.
scenario=reversed
expected_v4=1
printf 'LAST_FAILURE=RUNTIME_FORWARDING_MISMATCH\nLAST_FAILURE_TIME=2026-10-11T00:00:00Z\n' >"$fixtures/$scenario/last-failure"
sed -e "s|^GW_DIR=/var/run/m6$|GW_DIR=$fixtures/$scenario|" \
    -e "s|/etc/gateway-mode|$fixtures/$scenario/test-mode|" \
    -e "s|/dev/shmem/boot-progress.log|$fixtures/$scenario/events|" "$observer" >"$work/observer.sh"
(set +e; . "$work/observer.sh")
check CURRENT_STATE=READY; check GATE_STEP=READY; check FAIL_REASON=NONE
check LAST_FAILURE=RUNTIME_FORWARDING_MISMATCH
echo 'PASS diagnostic-history-separate-from-current-state'
