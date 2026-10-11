#!/bin/sh
# Real gate functions; QNX network commands mocked. No host network changes.
set -eu
control=$1
PF_BOOTSTRAP=$2
PF_GATEWAY=$3
ports=$4
test_root=$5
mkdir -p "$test_root"
. "$control"
. "$ports"
sysctl() {
    echo "sysctl $*" >>"$GW_DIR/events"
    case "$*" in
        '-w net.inet.ip.forwarding=0') [ "$scenario" != v4-off-fail ] || return 1; v4state=0 ;;
        '-w net.inet6.ip6.forwarding=0') [ "$scenario" != v6-off-fail ] || return 1; v6state=0 ;;
        '-w net.inet.ip.forwarding=1') [ "$scenario" != enable-write-fail ] || return 1; v4state=1 ;;
        '-n net.inet.ip.forwarding') [ "$scenario" != read-fail ] || return 1; echo "$v4state" ;;
        '-n net.inet6.ip6.forwarding')
            if [ "$scenario" = bad-v6-readback ]; then echo 1; else echo "$v6state"; fi ;;
        *) return 1 ;;
    esac
}
ifconfig() {
    echo "ifconfig $*" >>"$GW_DIR/events"
    if [ "$1" = -l ]; then
        case "$scenario" in missing-nic) echo rt7 ;; reversed) echo 'rt2 rt7' ;; *) echo 'rt7 rt2' ;; esac
    elif [ "$#" = 1 ]; then
        case "$1" in rt7) mac=$B_MAC ;; rt2) mac=$A_MAC ;; *) return 1 ;; esac
        [ "$scenario:$1" != wrong-mac:rt2 ] || mac=00:11:22:33:44:55
        [ "$scenario:$1" != duplicate-mac:rt2 ] || mac=$B_MAC
        printf '%s: flags=UP\n    ether %s\n    status: active\n' "$1" "$mac"
        if [ "$1" = rt2 ] && [ "$pf_stage" = gateway ]; then
            printf '    inet %s netmask 0xffffff00 broadcast 192.168.0.255\n' "$live_address"
        fi
    fi
}
route() {
    [ "$scenario" != no-route ] || return 1
    echo "gateway: $test_router"
    if [ "$scenario" = wrong-route-interface ]; then echo 'interface: rt7'; else echo 'interface: rt2'; fi
}
sleep() { :; }
slay() { echo "slay $*" >>"$GW_DIR/events"; }
pfctl() {
    echo "pfctl $*" >>"$GW_DIR/events"
    case "$1" in
        -n)
            while [ "$1" != -f ]; do shift; done
            file=$2
            [ "$pf_stage:$scenario" != gateway:syntax-fail ] || return 1
            if grep -q THIS_IS_AN_INTENTIONAL "$file"; then return 1; fi
            grep -E '^(block|pass|nat|rdr) ' "$file" | sed -e 's/^block all/block drop all/' -e 's/^/@0 /'
            ;;
        -o)
            [ "$pf_stage:$scenario" != gateway:load-fail ] || return 1
            grep -E '^(block|pass) ' "$GW_DIR/pf.conf" | sed 's/^block all/block drop all/' >"$GW_DIR/mock-filter"
            grep -E '^(nat|rdr) ' "$GW_DIR/pf.conf" >"$GW_DIR/mock-nat" || :
            ;;
        -F) [ "$pf_stage:$scenario" != gateway:states-fail ] || return 1 ;;
        -e) [ "$scenario" != pf-enable-fail ] || return 1; pf_on=1 ;;
        -si) if [ "$pf_on" = 1 ]; then echo 'Status: Enabled for 0 days'; else echo 'Status: Disabled'; fi ;;
        -sr)
            case "$pf_stage:$scenario" in
                gateway:missing-rule) sed '/M6_UPSTREAM_DENY/d' "$GW_DIR/mock-filter" ;;
                gateway:missing-egress) sed '/M6_WAN_OUT/d' "$GW_DIR/mock-filter" ;;
                gateway:missing-diagnostic) sed '/M6_DIAGNOSTIC/d' "$GW_DIR/mock-filter" ;;
                gateway:missing-wan-deny) sed '/M6_WAN_TO_LAN_DENY/d' "$GW_DIR/mock-filter" ;;
                gateway:tampered-rule) sed 's/block in quick/pass in quick/g' "$GW_DIR/mock-filter" ;;
                gateway:extra-rule) cat "$GW_DIR/mock-filter"; echo 'pass all' ;;
                *) cat "$GW_DIR/mock-filter" ;;
            esac ;;
        -sn)
            case "$pf_stage:$scenario" in
                gateway:missing-nat) sed '/^nat /d' "$GW_DIR/mock-nat" ;;
                gateway:tampered-nat) sed 's/192.168.77.0\/24/192.168.0.0\/24/g' "$GW_DIR/mock-nat" ;;
                gateway:missing-dns-rdr) sed '/^rdr .*proto tcp /d' "$GW_DIR/mock-nat" ;;
                *) cat "$GW_DIR/mock-nat" ;;
            esac ;;
        *) return 1 ;;
    esac
}
run_case() {
    scenario=$1
    expected=$2
    GW_DIR="$test_root/$scenario"
    mkdir -p "$GW_DIR"
    rm -f "$GW_DIR/ready" "$GW_DIR/active.lease" "$GW_DIR/fatal" "$GW_DIR/fail-reason"
    echo 0 >"$GW_DIR/forwarding-on-requests"
    echo 0 >"$GW_DIR/forwarding-on-successes"
    : >"$GW_DIR/events"
    v4state=0
    v6state=0
    pf_on=0
    pf_stage=bootstrap
    GATEWAY_MODE=normal
    new_ip_address=192.168.0.100
    new_subnet_mask=255.255.255.0
    new_subnet_cidr=24
    new_routers=192.168.0.1
    new_domain_name_servers='192.168.0.1 1.1.1.1'
    test_router=192.168.0.1
    case "$scenario" in
        alternate-subnet) new_ip_address=10.22.5.100; test_router=10.22.5.1; new_routers=$test_router; new_domain_name_servers=$test_router ;;
        external-dns) new_domain_name_servers='1.1.1.1 9.9.9.9' ;;
        off-control) GATEWAY_MODE=forwarding-off ;;
        corrupt-control) GATEWAY_MODE=syntax-error ;;
        no-dns) new_domain_name_servers= ;;
        invalid-dns) new_domain_name_servers='192.168.0.1;touch /tmp/pwned' ;;
        loopback-dns) new_domain_name_servers=127.0.0.1 ;;
        multicast-dns) new_domain_name_servers=224.0.0.1 ;;
        lan-dns) new_domain_name_servers=192.168.77.2 ;;
        self-dns) new_domain_name_servers=$new_ip_address ;;
        invalid-ip) new_ip_address=192.168.0.999 ;;
        overlap) new_ip_address=192.168.77.100 ;;
        broad-overlap) new_subnet_mask=255.255.0.0; new_subnet_cidr=16 ;;
        bad-mask) new_subnet_mask=255.0.255.0 ;;
        bad-prefix) new_subnet_cidr='24+1' ;;
        no-router) new_routers= ;;
        wrong-router) test_router=192.168.0.254 ;;
    esac
    live_address=$new_ip_address
    printf '%s\n' "$GATEWAY_MODE" >"$GW_DIR/test-mode"
    [ "$scenario" != live-ip-mismatch ] || live_address=192.168.0.101
    result=1
    if map_and_address_ports && bootstrap_pf; then
        [ "$v4state:$v6state" = 0:0 ] || exit 1
        if grep -q 'sysctl -w net.inet.ip.forwarding=1' "$GW_DIR/events"; then echo 'FAIL bootstrap enables'; exit 1; fi
        pf_stage=gateway
        if activate_lease; then result=0; fi
    fi
    if [ "$result" != 0 ]; then gate_failure; close_gateway || :; fi
    [ "$result" = "$expected" ] || { echo "FAIL $scenario result=$result"; exit 1; }
    if [ "$expected" = 1 ] || [ "$scenario" = off-control ]; then
        [ "$v4state:$v6state" = 0:0 ] || { echo "FAIL $scenario forwarded"; exit 1; }
        if [ "$scenario" != enable-write-fail ] && grep -q 'sysctl -w net.inet.ip.forwarding=1' "$GW_DIR/events"; then
            echo "FAIL premature enable in $scenario"; exit 1
        fi
    else
        [ "$A_IF:$B_IF:$v4state:$v6state" = rt2:rt7:1:0 ] || exit 1
        check_running_gate || { echo 'FAIL running gate'; exit 1; }
        [ "$(cat "$GW_DIR/gate-step")" = READY ] || { echo 'FAIL stale runtime check displayed as fault'; exit 1; }
        grep -q -- "-> $WAN_DNS port 53" "$GW_DIR/mock-nat" || exit 1
    fi
    case "$scenario" in v4-off-fail|v6-off-fail|read-fail|bad-v6-readback) grep -q 'slay -f io-sock' "$GW_DIR/events" || exit 1 ;; esac
    # Post-DHCP failures must identify the failed check, not just a generic gate.
    case "$scenario" in
        no-route) cause=DEFAULT_ROUTE_QUERY ;;
        wrong-route-interface) cause=DEFAULT_ROUTE_INTERFACE_MISMATCH ;;
        syntax-fail|corrupt-control) cause=PF_SYNTAX ;;
        load-fail) cause=PF_LOAD ;;
        missing-nat|tampered-nat|missing-dns-rdr) cause=PF_NAT_READBACK_MISMATCH ;;
        missing-egress|missing-diagnostic|missing-wan-deny) cause=PF_FILTER_READBACK_MISMATCH ;;
        enable-write-fail) cause=FORWARDING_ENABLE ;;
        *) cause= ;;
    esac
    if [ -n "$cause" ]; then
        [ "$(cat "$GW_DIR/fail-reason")" = "$cause" ] || { echo "FAIL $scenario reason"; exit 1; }
        grep -q "^LAST_FAILURE=$cause$" "$GW_DIR/last-failure" || exit 1
    fi
    case "$scenario" in
        syntax-fail|corrupt-control|off-control)
            [ "$(cat "$GW_DIR/forwarding-on-requests")" = 0 ] || exit 1
            [ "$(cat "$GW_DIR/forwarding-on-successes")" = 0 ] || exit 1 ;;
    esac
    if [ "$scenario" = off-control ]; then
        check_running_gate || exit 1
        [ "$(cat "$GW_DIR/gate-step")" = TEST_MODE ] || exit 1
    fi
    echo "PASS $scenario"
}
for case_name in normal reversed alternate-subnet external-dns off-control; do run_case "$case_name" 0; done
for case_name in missing-nic wrong-mac duplicate-mac v4-off-fail v6-off-fail read-fail bad-v6-readback \
    no-dns invalid-dns loopback-dns multicast-dns lan-dns self-dns invalid-ip overlap broad-overlap bad-mask bad-prefix \
    no-router wrong-router no-route wrong-route-interface live-ip-mismatch syntax-fail corrupt-control \
    load-fail states-fail pf-enable-fail missing-rule missing-egress missing-diagnostic missing-wan-deny tampered-rule extra-rule missing-nat tampered-nat missing-dns-rdr enable-write-fail; do
    run_case "$case_name" 1
done
run_case normal 0
load_before=$(grep -c 'pfctl -o' "$GW_DIR/events")
activate_lease || exit 1
[ "$(grep -c 'pfctl -o' "$GW_DIR/events")" = "$load_before" ] || { echo 'FAIL renew destroyed states'; exit 1; }
echo 'PASS unchanged-renewal-keeps-state'
new_domain_name_servers=9.9.9.9
activate_lease || exit 1
[ "$(grep -c 'pfctl -o' "$GW_DIR/events")" = "$((load_before + 1))" ] || exit 1
grep -q -- '-> 9.9.9.9 port 53' "$GW_DIR/loaded.nat" || exit 1
echo 'PASS changed-DNS-reloads-under-forwarding-off'
close_gateway || exit 1
[ "$v4state:$v6state" = 0:0 ] && [ ! -f "$GW_DIR/ready" ] || exit 1
echo 'PASS lease-loss-closes-forwarding'
activate_lease || exit 1
pf_on=0
if check_running_gate; then echo 'FAIL disabled PF accepted'; exit 1; fi
close_gateway || exit 1
[ "$v4state:$v6state" = 0:0 ] || exit 1
echo 'PASS runtime-PF-disable-detected'
echo fatal >"$GW_DIR/fatal"
if activate_lease; then echo 'FAIL fatal revived'; exit 1; fi
[ "$v4state" = 0 ] || exit 1
echo 'PASS fatal-does-not-reenable'
