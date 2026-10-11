#!/bin/ksh
# Observes only: never loads PF, changes routes, or writes forwarding sysctls.
GW_DIR=/var/run/m6
umask 022
. "$GW_DIR/interfaces"
mode=$(cat /etc/gateway-mode)
observed_on=0
sample_number=0
value() { if [ -s "$GW_DIR/$1" ]; then cat "$GW_DIR/$1"; else echo "${2:-NOT_RUN}"; fi; }
section() {
    [ -f "$GW_DIR/$1" ] || return 0
    echo "--- $1 (last 24 lines) ---"
    tail -n 24 "$GW_DIR/$1"
}
while :; do
    sample_number=$((sample_number + 1))
    # Separate filenames avoid interfering with the gate's checks.
    ifconfig "$A_IF" >"$GW_DIR/diag-ifconfig" 2>&1
    route -n get default >"$GW_DIR/diag-route" 2>&1
    pfctl -si >"$GW_DIR/diag-pf-status" 2>&1
    pfctl -sr >"$GW_DIR/diag-filter" 2>&1
    pfctl -sn >"$GW_DIR/diag-nat" 2>&1
    # Bounded tails, not packet payloads; helps distinguish READY from data flow.
    pfctl -ss 2>&1 | tail -n 24 >"$GW_DIR/diag-states"
    pfctl -s labels >"$GW_DIR/diag-counters" 2>&1
    v4=$(sysctl -n net.inet.ip.forwarding 2>/dev/null) || v4=UNKNOWN
    v6=$(sysctl -n net.inet6.ip6.forwarding 2>/dev/null) || v6=UNKNOWN
    [ "$v4" != 1 ] || observed_on=1
    ip=$(sed -n 's/^[[:space:]]*inet[[:space:]][[:space:]]*\([^[:space:]]*\).*$/\1/p' "$GW_DIR/diag-ifconfig")
    gateway=$(sed -n 's/^[[:space:]]*gateway:[[:space:]]*//p' "$GW_DIR/diag-route")
    route_if=$(sed -n 's/^[[:space:]]*interface:[[:space:]]*//p' "$GW_DIR/diag-route")
    link=UNKNOWN
    grep -q 'status: active' "$GW_DIR/diag-ifconfig" && link=UP
    grep -q 'status: no carrier' "$GW_DIR/diag-ifconfig" && link=DOWN
    pf=FAIL
    grep -q '^Status: Enabled' "$GW_DIR/diag-pf-status" && pf=OK
    route=FAIL
    [ -n "$gateway" ] && [ "$route_if" = "$A_IF" ] && route=OK
    nat=FAIL
    dns=FAIL
    # OK requires a gateway baseline that passed full load/readback verification.
    if [ "$(value pf-phase)" = GATEWAY ] && [ "$(value pf-verify)" = OK ] &&
        [ "$pf" = OK ] && [ -f "$GW_DIR/loaded.nat" ] && [ -f "$GW_DIR/loaded.rules" ] &&
        [ "$(cat "$GW_DIR/loaded.rules")" = "$(cat "$GW_DIR/diag-filter")" ] &&
        [ "$(cat "$GW_DIR/loaded.nat")" = "$(cat "$GW_DIR/diag-nat")" ]; then
        [ "$(grep -c '^nat ' "$GW_DIR/diag-nat")" = 1 ] && nat=OK
        [ "$(grep -c '^rdr ' "$GW_DIR/diag-nat")" = 2 ] && dns=OK
    fi
    ready=NO
    busy=NO
    [ ! -d "$GW_DIR/gate.lock" ] || busy=YES
    [ -f "$GW_DIR/ready" ] && [ "$v4:$v6:$pf:$nat:$dns:$route:$busy" = 1:0:OK:OK:OK:OK:NO ] && ready=YES
    failure=$(value fail-reason NONE)
    step=$(value gate-step STARTING)
    current=NOT_READY
    if [ "$busy" = YES ]; then
        current=CHECKING
    elif [ "$ready" = YES ] && [ "$mode" = normal ]; then
        current=READY; step=READY; failure=NONE
    elif [ "$mode" = forwarding-off ] && [ -f "$GW_DIR/ready" ] &&
        [ "$v4:$v6:$pf:$nat:$dns:$route" = 0:0:OK:OK:OK:OK ]; then
        current=TEST_MODE; step=TEST_MODE; failure=NONE
    elif [ "$failure" != NONE ] || [ -f "$GW_DIR/fatal" ]; then
        current=BLOCKED
    elif [ ! -f "$GW_DIR/ready" ]; then
        current=WAITING_FOR_DHCP
    fi
    [ "$current" = READY ] || ready=NO
    # pfctl -s labels: label/evaluations/packets/bytes/in-packets/in-bytes/
    # out-packets/out-bytes/state-creations. Measure B only to avoid A+B doubles.
    lan_packets=0; lan_bytes=0; lan_creations=0; lan_labels=0
    wan_deny=NOT_PRESENT; upstream_deny=NOT_PRESENT
    while read label evaluations packets bytes pin bin pout bout creations; do
        case "$packets:$bytes:$creations" in *[!0-9:]*|:*|*:|*::*) continue ;; esac
        case "$label" in
            M6_LAN_OUT|M6_DNS_UDP|M6_DNS_TCP)
                lan_packets=$((lan_packets + packets)); lan_bytes=$((lan_bytes + bytes))
                lan_creations=$((lan_creations + creations)); lan_labels=$((lan_labels + 1)) ;;
            M6_WAN_TO_LAN_DENY) wan_deny=$packets ;;
            M6_UPSTREAM_DENY) upstream_deny=$packets ;;
        esac
    done <"$GW_DIR/diag-counters"
    if [ "$lan_labels" != 3 ]; then lan_packets=UNKNOWN; lan_bytes=UNKNOWN; lan_creations=UNKNOWN; fi
    entries=$(sed -n 's/^[[:space:]]*current entries[[:space:]][[:space:]]*\([0-9][0-9]*\).*$/\1/p' "$GW_DIR/diag-pf-status")
    inserts=$(sed -n 's/^[[:space:]]*inserts[[:space:]][[:space:]]*\([0-9][0-9]*\).*$/\1/p' "$GW_DIR/diag-pf-status")
    {
        echo "IMAGE=M6-GW-v6-$mode"
        echo "TEST_MODE=$mode"
        echo "SAMPLE_NUMBER=$sample_number"
        echo "A_LINK=$link"
        echo "A_INTERFACE=$A_IF"
        echo "A_IP=${ip:-UNKNOWN}"
        echo "A_GATEWAY=${gateway:-UNKNOWN}"
        echo "DEFAULT_ROUTE=$route"
        echo "DEFAULT_ROUTE_INTERFACE=${route_if:-UNKNOWN}"
        echo "B_INTERFACE=$B_IF"
        echo 'B_IP=192.168.77.1'
        echo "DHCP_EVENT=$(value dhcp-event WAITING)"
        echo "LEASE_VALIDATION=$(value lease-validation)"
        echo "PF_PHASE=$(value pf-phase)"
        echo "PF_SYNTAX=$(value pf-syntax)"
        echo "PF_LOAD=$(value pf-load)"
        echo "PF_ENABLED=$pf"
        echo "PF_READBACK=$(value pf-verify)"
        echo "NAT=$nat"
        echo "FORWARDING=$v4"
        echo "IPV6_FORWARDING=$v6"
        echo 'DNS_MODE=PF_RDR'
        echo 'DNS_DAEMON=NOT_USED'
        echo "DNS_FORWARDER=$dns"
        echo 'DNS_FORWARDER_MEANING=rule-readback-only; external-query-not-tested'
        echo "CURRENT_STATE=$current"
        echo "GATE_STEP=$step"
        echo "GATE_BUSY=$busy"
        echo "READY=$ready"
        echo "FAIL_REASON=$failure"
        if [ -f "$GW_DIR/last-event" ]; then cat "$GW_DIR/last-event"; else echo 'LAST_EVENT=NONE'; echo 'LAST_EVENT_TIME=UNKNOWN'; fi
        if [ -f "$GW_DIR/last-failure" ]; then cat "$GW_DIR/last-failure"; else echo 'LAST_FAILURE=NONE'; echo 'LAST_FAILURE_TIME=UNKNOWN'; fi
        echo 'EVENT_TIME_SOURCE=QNX_CLOCK_NOT_NTP_SYNCED'
        echo "FORWARDING_ON_REQUESTS=$(value forwarding-on-requests UNKNOWN)"
        echo "FORWARDING_ON_SUCCESSES=$(value forwarding-on-successes UNKNOWN)"
        echo "FORWARDING_OBSERVED_EVER_1=$observed_on"
        echo "PF_STATE_ENTRIES=${entries:-UNKNOWN}"
        echo "PF_STATE_INSERTS_TOTAL=${inserts:-UNKNOWN}"
        echo "LAN_PASSED_PACKETS_TOTAL=$lan_packets"
        echo "LAN_PASSED_BYTES_TOTAL=$lan_bytes"
        echo "LAN_STATE_CREATIONS_TOTAL=$lan_creations"
        echo "M6_UPSTREAM_DENY_PACKETS=$upstream_deny"
        echo "M6_WAN_TO_LAN_DENY_PACKETS=$wan_deny"
        echo "FATAL=$(value fatal NONE)"
        for file in lease-inputs diag-route diag-ifconfig pf-syntax.err pf-load.txt \
            pf-enable.txt pf-read.err pf-nat.err pf-readback.err expected.rules \
            loaded.rules readback.rules expected.nat loaded.nat readback.nat diag-nat \
            diag-pf-status diag-states diag-counters; do section "$file"; done
        echo '--- boot-progress.log (last 40 lines) ---'
        tail -n 40 /dev/shmem/boot-progress.log
    } >"$GW_DIR/diagnostic.tmp" 2>&1
    # Atomic publication; the TCP process has UID/GID 65534 and read-only access.
    chmod 644 "$GW_DIR/diagnostic.tmp"
    mv -f "$GW_DIR/diagnostic.tmp" "$GW_DIR/diagnostic.txt"
    sleep 2
done
