#!/bin/ksh
# Single PF writer: DHCP hook under gate.lock; monitor never enables forwarding.
gate_step() { printf '%s\n' "$1" >"$GW_DIR/gate-step"; }
gate_event() {
    event_time=$(date -u '+%Y-%m-%dT%H:%M:%SZ') || event_time=UNKNOWN
    printf 'LAST_EVENT=%s\nLAST_EVENT_TIME=%s\n' "$1" "$event_time" >"$GW_DIR/last-event.tmp"
    mv -f "$GW_DIR/last-event.tmp" "$GW_DIR/last-event"
}
gate_failure() {
    if [ ! -s "$GW_DIR/fail-reason" ]; then
        if [ -s "$GW_DIR/gate-step" ]; then
            cat "$GW_DIR/gate-step" >"$GW_DIR/fail-reason"
        else
            echo EARLY_STARTUP >"$GW_DIR/fail-reason"
        fi
        gate_event "$(cat "$GW_DIR/fail-reason")"
        sed 's/^LAST_EVENT/LAST_FAILURE/' "$GW_DIR/last-event" >"$GW_DIR/last-failure"
    fi
    gate_step BLOCKED
}
forwarding_on() {
    # Audit this controller's sole ON write path; these counters never reset on renew.
    on_requests=$(cat "$GW_DIR/forwarding-on-requests" 2>/dev/null) || on_requests=0
    printf '%s\n' "$((on_requests + 1))" >"$GW_DIR/forwarding-on-requests"
    sysctl -w net.inet.ip.forwarding=1 || return 1
    on_successes=$(cat "$GW_DIR/forwarding-on-successes" 2>/dev/null) || on_successes=0
    printf '%s\n' "$((on_successes + 1))" >"$GW_DIR/forwarding-on-successes"
}
forwarding_off() {
    sysctl -w net.inet.ip.forwarding=0 || return 1
    sysctl -w net.inet6.ip6.forwarding=0 || return 1
    v4=$(sysctl -n net.inet.ip.forwarding) || return 1
    v6=$(sysctl -n net.inet6.ip6.forwarding) || return 1
    [ "$v4" = 0 ] && [ "$v6" = 0 ]
}
close_gateway() {
    echo 'M6-GW-v6 action=forwarding-off'
    rm -f "$GW_DIR/ready"
    if ! forwarding_off; then
        echo 'M6-GW-v6 FAIL=cannot-confirm-forwarding-off stopping-io-sock'
        slay -f io-sock
        return 1
    fi
}
lock_gate() {
    lock_attempt=0
    while ! mkdir "$GW_DIR/gate.lock" 2>/dev/null; do
        lock_attempt=$((lock_attempt + 1))
        [ "$lock_attempt" -lt 15 ] || return 1
        sleep 1
    done
}
unlock_gate() { rmdir "$GW_DIR/gate.lock"; }
map_and_address_ports() {
    forwarding_off || return 1
    A_IF=
    B_IF=
    attempt=0
    while [ "$attempt" -lt 30 ]; do
        rt_ports=
        ifaces=$(ifconfig -l) || return 1
        for iface in $ifaces; do
            if echo "$iface" | grep -Eq '^rt[0-9]+$'; then rt_ports="$rt_ports $iface"; fi
        done
        set -- $rt_ports
        [ "$#" -ge 2 ] && break
        attempt=$((attempt + 1))
        sleep 1
    done
    set -- $rt_ports
    [ "$#" = 2 ] || { echo 'M6-GW-v6 FAIL=rtl-count'; return 1; }
    for iface in $rt_ports; do
        ifconfig "$iface" >"$GW_DIR/$iface.ifconfig" || return 1
        mac=$(sed -n 's/^[[:space:]]*ether[[:space:]][[:space:]]*\([^[:space:]]*\).*$/\1/p' "$GW_DIR/$iface.ifconfig" | tr 'A-F' 'a-f')
        case "$mac" in
            "$A_MAC") [ -z "$A_IF" ] || return 1; A_IF=$iface ;;
            "$B_MAC") [ -z "$B_IF" ] || return 1; B_IF=$iface ;;
            *) echo "M6-GW-v6 FAIL=unexpected-mac interface=$iface mac=$mac"; return 1 ;;
        esac
    done
    [ -n "$A_IF" ] && [ -n "$B_IF" ] && [ "$A_IF" != "$B_IF" ] || return 1
    ifconfig "$B_IF" inet "$B_IP" netmask 255.255.255.0 up || return 1
    ifconfig "$A_IF" up || return 1
    forwarding_off || return 1
    # Only validated interface names enter this local, RAM-only shell file.
    printf 'A_IF=%s\nB_IF=%s\n' "$A_IF" "$B_IF" >"$GW_DIR/interfaces"
    echo "A upstream interface=$A_IF mac=$A_MAC address=DHCP"
    echo "B downstream interface=$B_IF mac=$B_MAC ip=$B_IP/24"
    ifconfig "$A_IF"
    ifconfig "$B_IF"
}
same_rule_text() {
    [ -f "$1" ] && [ -f "$2" ] || return 1
    rule_text_expected=$(cat "$1") || return 1
    rule_text_actual=$(cat "$2") || return 1
    [ "$rule_text_expected" = "$rule_text_actual" ]
}
canonical_rules() {
    [ -f "$1" ] || return 1
    sed 's/^@[0-9][0-9]*[[:space:]][[:space:]]*//' "$1" >"$GW_DIR/canonical.tmp" || return 1
    grep -E "$3" "$GW_DIR/canonical.tmp" >"$2"
    canonical_result=$?
    [ "$canonical_result" -le 1 ]
}
pf_enabled() {
    pfctl -si >"$GW_DIR/pf-status.txt" 2>&1 || return 1
    grep -q '^Status: Enabled' "$GW_DIR/pf-status.txt"
}
render_pf() {
    sed -e "s/@A_IF@/$A_IF/g" -e "s/@B_IF@/$B_IF/g" \
        -e "s/@WAN_DNS@/${WAN_DNS:-0.0.0.0}/g" "$1" >"$GW_DIR/pf.conf"
}
verify_pf_readback() {
    gate_step PF_READ_FILTERS
    pfctl -sr >"$GW_DIR/loaded.rules" 2>"$GW_DIR/pf-read.err" || return 1
    gate_step PF_READ_TRANSLATIONS
    pfctl -sn >"$GW_DIR/loaded.nat" 2>"$GW_DIR/pf-nat.err" || return 1
    # Reparse translations before filters with the same pfctl formatter.
    cat "$GW_DIR/loaded.nat" "$GW_DIR/loaded.rules" >"$GW_DIR/readback.conf" || return 1
    gate_step PF_REPARSE_READBACK
    pfctl -n -v -o none -f "$GW_DIR/readback.conf" >"$GW_DIR/readback.parsed" 2>"$GW_DIR/pf-readback.err" || return 1
    canonical_rules "$GW_DIR/readback.parsed" "$GW_DIR/readback.rules" '^(block|pass) ' || return 1
    canonical_rules "$GW_DIR/readback.parsed" "$GW_DIR/readback.nat" '^(nat|rdr|binat|no nat|no rdr) ' || return 1
    gate_step PF_FILTER_READBACK_MISMATCH
    same_rule_text "$GW_DIR/expected.rules" "$GW_DIR/readback.rules" || return 1
    gate_step PF_NAT_READBACK_MISMATCH
    same_rule_text "$GW_DIR/expected.nat" "$GW_DIR/readback.nat" || return 1
    gate_step PF_LOADED_RULE_COUNTS
    [ "$(grep -c '^' "$GW_DIR/loaded.rules")" = "$PF_RULE_COUNT" ] || return 1
    [ "$(grep -c '^' "$GW_DIR/loaded.nat")" = "$PF_NAT_COUNT" ] || return 1
}
apply_pf() {
    # Caller holds gate.lock. Always OFF while changing rules/state.
    gate_step PF_FORWARDING_OFF
    forwarding_off || return 1
    echo SKIPPED >"$GW_DIR/pf-load"
    echo NOT_RUN >"$GW_DIR/pf-verify"
    echo FAIL >"$GW_DIR/pf-syntax"
    gate_step PF_SYNTAX
    pfctl -n -v -o none -f "$GW_DIR/pf.conf" >"$GW_DIR/pf-syntax.txt" 2>"$GW_DIR/pf-syntax.err" || {
        echo 'M6-GW-v6 PF-syntax=FAIL PF-load=SKIPPED'; return 1;
    }
    echo 'M6-GW-v6 PF-syntax=PASS'
    echo OK >"$GW_DIR/pf-syntax"
    gate_step PF_EXPECTED_RULE_COUNTS
    canonical_rules "$GW_DIR/pf-syntax.txt" "$GW_DIR/expected.rules" '^(block|pass) ' || return 1
    canonical_rules "$GW_DIR/pf-syntax.txt" "$GW_DIR/expected.nat" '^(nat|rdr|binat|no nat|no rdr) ' || return 1
    [ "$(grep -c '^' "$GW_DIR/expected.rules")" = "$PF_RULE_COUNT" ] || return 1
    [ "$(grep -c '^' "$GW_DIR/expected.nat")" = "$PF_NAT_COUNT" ] || return 1
    gate_step PF_DEFAULT_DENY_MISSING
    grep -Eq '^block .*all label "M6_DEFAULT_DENY"$' "$GW_DIR/expected.rules" || return 1
    for label in $PF_LABELS; do
        gate_step "PF_REQUIRED_LABEL_$label"
        grep -q "label \"$label\"" "$GW_DIR/expected.rules" || return 1
    done
    gate_step PF_LOAD
    echo FAIL >"$GW_DIR/pf-load"
    pfctl -o none -f "$GW_DIR/pf.conf" >"$GW_DIR/pf-load.txt" 2>&1 || { echo 'M6-GW-v6 PF-load=FAIL'; return 1; }
    echo OK >"$GW_DIR/pf-load"
    gate_step PF_CLEAR_STATES
    pfctl -F states >"$GW_DIR/pf-states-clear.txt" 2>&1 || return 1
    # A renewal must not fail just because PF is already enabled.
    if ! pf_enabled; then
        gate_step PF_ENABLE
        pfctl -e >"$GW_DIR/pf-enable.txt" 2>&1 || return 1
    fi
    gate_step PF_ENABLED_READBACK
    pf_enabled || return 1
    echo FAIL >"$GW_DIR/pf-verify"
    verify_pf_readback || { echo 'M6-GW-v6 PF-readback=FAIL'; return 1; }
    echo OK >"$GW_DIR/pf-verify"
    echo "M6-GW-v6 PF-load=PASS PF-enabled=PASS PF-readback=PASS rules=$PF_RULE_COUNT translations=$PF_NAT_COUNT"
}
bootstrap_pf() {
    echo BOOTSTRAP >"$GW_DIR/pf-phase"
    gate_step PF_BOOTSTRAP_RENDER
    PF_RULE_COUNT=6
    PF_NAT_COUNT=0
    PF_LABELS='M6_DHCP_OUT M6_DHCP_IN M6_DHCP_BCAST M6_LAN_PING M6_DIAGNOSTIC'
    render_pf "$PF_BOOTSTRAP" && apply_pf && forwarding_off
}
ipv4_number() {
    # No eval; reject shell syntax, short forms, octal notation and invalid octets.
    ip_tail=$1
    ip_number=0
    ip_index=0
    while [ "$ip_index" -lt 4 ]; do
        ip_octet=${ip_tail%%.*}
        case "$ip_octet" in 0|[1-9]|[1-9][0-9]|[1-9][0-9][0-9]) ;; *) return 1 ;; esac
        [ "$ip_octet" -le 255 ] || return 1
        ip_number=$((ip_number * 256 + ip_octet))
        ip_index=$((ip_index + 1))
        if [ "$ip_index" -lt 4 ]; then
            [ "$ip_tail" != "${ip_tail#*.}" ] || return 1
            ip_tail=${ip_tail#*.}
        else
            [ "$ip_tail" = "$ip_octet" ] || return 1
        fi
    done
    echo "$ip_number"
}
unicast_number() {
    unicast=$(ipv4_number "$1") || return 1
    # Exclude unspecified, loopback, link-local, multicast and reserved addresses.
    [ "$unicast" -ge 16777216 ] && [ "$unicast" -lt 3758096384 ] || return 1
    [ $((unicast >> 24)) -ne 127 ] || return 1
    [ $((unicast >> 16)) -ne 43518 ] || return 1
    echo "$unicast"
}
read_default_route() {
    gate_step DEFAULT_ROUTE_QUERY
    route -n get default >"$GW_DIR/default-route.txt" 2>&1 || return 1
    ROUTE_GW=$(sed -n 's/^[[:space:]]*gateway:[[:space:]]*//p' "$GW_DIR/default-route.txt")
    ROUTE_IF=$(sed -n 's/^[[:space:]]*interface:[[:space:]]*//p' "$GW_DIR/default-route.txt")
    gate_step DEFAULT_ROUTE_INTERFACE_MISMATCH
    [ "$ROUTE_IF" = "$A_IF" ]
}
validate_lease() {
    WAN_IP=${new_ip_address:-}
    WAN_MASK=${new_subnet_mask:-}
    WAN_CIDR=${new_subnet_cidr:-}
    gate_step DHCP_IP_INVALID
    wan_number=$(unicast_number "$WAN_IP") || return 1
    gate_step DHCP_MASK_INVALID
    mask_number=$(ipv4_number "$WAN_MASK") || return 1
    gate_step DHCP_PREFIX_INVALID
    case "$WAN_CIDR" in [1-9]|[12][0-9]|30) ;; *) return 1 ;; esac
    mask_expected=$(( (4294967295 << (32 - WAN_CIDR)) & 4294967295 ))
    gate_step DHCP_MASK_PREFIX_MISMATCH
    [ "$mask_number" = "$mask_expected" ] || return 1
    wan_first=$((wan_number & mask_number))
    wan_last=$((wan_first | (4294967295 ^ mask_number)))
    gate_step DHCP_IP_NETWORK_OR_BROADCAST
    [ "$wan_number" -gt "$wan_first" ] && [ "$wan_number" -lt "$wan_last" ] || return 1
    lan_first=$(ipv4_number 192.168.77.0) || return 1
    lan_last=$((lan_first + 255))
    gate_step DHCP_SUBNET_OVERLAP
    if [ "$wan_first" -le "$lan_last" ] && [ "$wan_last" -ge "$lan_first" ]; then
        echo 'M6-GW-v6 FAIL=upstream-overlaps-LAN'; return 1
    fi
    read_default_route || return 1
    WAN_GW=$ROUTE_GW
    gate_step DHCP_GATEWAY_INVALID_OR_OFF_SUBNET
    gw_number=$(unicast_number "$WAN_GW") || return 1
    [ "$gw_number" -gt "$wan_first" ] && [ "$gw_number" -lt "$wan_last" ] && [ "$WAN_GW" != "$WAN_IP" ] || return 1
    router_found=no
    gate_step DHCP_DEFAULT_ROUTE_NOT_IN_ROUTERS
    for router in ${new_routers:-}; do
        unicast_number "$router" >/dev/null || return 1
        [ "$router" != "$WAN_GW" ] || router_found=yes
    done
    [ "$router_found" = yes ] || return 1
    WAN_DNS=
    gate_step DHCP_DNS_INVALID_OR_MISSING
    for dns in ${new_domain_name_servers:-}; do
        dns_number=$(unicast_number "$dns") || return 1
        [ "$dns" != "$WAN_IP" ] || return 1
        if [ "$dns_number" -ge "$lan_first" ] && [ "$dns_number" -le "$lan_last" ]; then return 1; fi
        [ -n "$WAN_DNS" ] || WAN_DNS=$dns
    done
    [ -n "$WAN_DNS" ] || return 1
    check_live_uplink || return 1
    printf '%s\n' "$WAN_IP/$WAN_CIDR $WAN_MASK $WAN_GW $WAN_DNS" >"$GW_DIR/candidate.lease"
}
check_live_uplink() {
    gate_step LIVE_ADDRESS_QUERY
    ifconfig "$A_IF" >"$GW_DIR/wan-current.txt" || return 1
    live_ip=$(sed -n 's/^[[:space:]]*inet[[:space:]][[:space:]]*\([^[:space:]]*\).*$/\1/p' "$GW_DIR/wan-current.txt")
    live_mask=$(sed -n 's/.*netmask[[:space:]][[:space:]]*\([^[:space:]]*\).*$/\1/p' "$GW_DIR/wan-current.txt")
    expected_mask_hex=$(printf '0x%x' "$mask_number")
    gate_step LIVE_IP_MISMATCH
    [ "$live_ip" = "$WAN_IP" ] || return 1
    gate_step LIVE_MASK_MISMATCH
    [ "$live_mask" = "$WAN_MASK" ] || [ "$live_mask" = "$expected_mask_hex" ] || return 1
    read_default_route || return 1
    gate_step LIVE_DEFAULT_GATEWAY_MISMATCH
    [ "$ROUTE_GW" = "$WAN_GW" ]
}
check_pf_current() {
    gate_step RUNTIME_PF_DISABLED
    pf_enabled || return 1
    gate_step RUNTIME_PF_READBACK
    pfctl -sr >"$GW_DIR/current.rules" 2>"$GW_DIR/pf-current.err" || return 1
    pfctl -sn >"$GW_DIR/current.nat" 2>"$GW_DIR/pf-current-nat.err" || return 1
    gate_step RUNTIME_FILTER_CHANGED
    same_rule_text "$GW_DIR/loaded.rules" "$GW_DIR/current.rules" || return 1
    gate_step RUNTIME_NAT_CHANGED
    same_rule_text "$GW_DIR/loaded.nat" "$GW_DIR/current.nat"
}
activate_lease() {
    # The hook holds the same lock as the monitor; no concurrent enable writes.
    rm -f "$GW_DIR/fail-reason"
    gate_step DHCP_FORWARDING_OFF
    close_gateway || return 1
    gate_step FATAL_LATCHED
    [ ! -e "$GW_DIR/fatal" ] || return 1
    echo FAIL >"$GW_DIR/lease-validation"
    validate_lease || { echo 'M6-GW-v6 DHCP-validation=FAIL forwarding=0/0'; return 1; }
    echo OK >"$GW_DIR/lease-validation"
    echo "M6-GW-v6 DHCP=PASS A=$WAN_IP/$WAN_CIDR mask=$WAN_MASK gateway=$WAN_GW DNS=$WAN_DNS"
    PF_RULE_COUNT=13
    PF_NAT_COUNT=3
    PF_LABELS='M6_DHCP_OUT M6_DHCP_IN M6_DHCP_BCAST M6_LAN_PING M6_DIAGNOSTIC M6_DNS_UDP M6_DNS_TCP M6_SELF_DENY M6_UPSTREAM_DENY M6_LAN_OUT M6_WAN_OUT M6_WAN_TO_LAN_DENY'
    # Identical renewals retain existing states, after verifying live PF.
    if [ "$GATEWAY_MODE" = normal ] && same_rule_text "$GW_DIR/active.lease" "$GW_DIR/candidate.lease" && check_pf_current; then
        echo 'M6-GW-v6 DHCP-renew=unchanged PF-reload=SKIPPED'
    else
        echo GATEWAY >"$GW_DIR/pf-phase"
        gate_step PF_GATEWAY_RENDER
        render_pf "$PF_GATEWAY" || return 1
        if [ "$GATEWAY_MODE" = syntax-error ]; then
            echo 'THIS_IS_AN_INTENTIONAL_PF_SYNTAX_ERROR {' >>"$GW_DIR/pf.conf"
        fi
        apply_pf || return 1
    fi
    check_live_uplink || return 1
    gate_step PF_FINAL_ENABLED_CHECK
    pf_enabled || return 1
    gate_step FINAL_FORWARDING_OFF
    forwarding_off || return 1
    gate_step FATAL_LATCHED
    [ ! -e "$GW_DIR/fatal" ] || return 1
    case "$GATEWAY_MODE" in
        normal) gate_step FORWARDING_ENABLE; forwarding_on || return 1; expected_forward=1 ;;
        forwarding-off) expected_forward=0 ;;
        *) return 1 ;;
    esac
    gate_step FORWARDING_FINAL_READBACK
    v4=$(sysctl -n net.inet.ip.forwarding) || return 1
    v6=$(sysctl -n net.inet6.ip6.forwarding) || return 1
    [ "$v4" = "$expected_forward" ] && [ "$v6" = 0 ] || return 1
    gate_step READY_PUBLISH
    cat "$GW_DIR/candidate.lease" >"$GW_DIR/active.lease" || return 1
    # Strictly validated values, never sourced from raw DHCP text.
    printf 'WAN_IP=%s\nWAN_MASK=%s\nWAN_GW=%s\nmask_number=%s\n' \
        "$WAN_IP" "$WAN_MASK" "$WAN_GW" "$mask_number" >"$GW_DIR/active-uplink" || return 1
    printf 'M6-GW-v6 mode=%s forwarding=%s/0 DNS=192.168.77.1->%s\n' \
        "$GATEWAY_MODE" "$expected_forward" "$WAN_DNS" >"$GW_DIR/ready" || return 1
    cat "$GW_DIR/ready"
    if [ "$GATEWAY_MODE" = forwarding-off ]; then gate_step TEST_MODE; else gate_step READY; fi
    gate_event "$(cat "$GW_DIR/gate-step")"
}
check_running_gate() {
    check_pf_current || return 1
    expected_forward=0
    if [ -f "$GW_DIR/ready" ]; then
        . "$GW_DIR/active-uplink"
        check_live_uplink || return 1
        [ "$GATEWAY_MODE" != normal ] || expected_forward=1
    fi
    gate_step RUNTIME_FORWARDING_MISMATCH
    v4=$(sysctl -n net.inet.ip.forwarding) || return 1
    v6=$(sysctl -n net.inet6.ip6.forwarding) || return 1
    [ "$v4" = "$expected_forward" ] && [ "$v6" = 0 ] || return 1
    # The pre-check name is not an event. Publish the successful current state.
    if [ -f "$GW_DIR/ready" ]; then
        if [ "$GATEWAY_MODE" = forwarding-off ]; then gate_step TEST_MODE; else gate_step READY; fi
    elif [ -s "$GW_DIR/fail-reason" ]; then
        gate_step BLOCKED
    else
        gate_step WAITING_FOR_DHCP
    fi
}
