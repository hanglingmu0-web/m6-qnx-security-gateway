#!/bin/sh
# Run from the repository root using a POSIX shell and standard text utilities.
# Network commands are mocks; these tests do not change host networking.
set -eu
work="output/host-tests-$$"
mkdir -p "$work"
sh tests/test-gateway-control.sh src/boot/gateway-control.sh \
    config/pf-bootstrap.conf config/pf-gateway.conf config/ports.conf.example "$work/gate"
sh tests/test-diagnostic-snapshot.sh src/boot/diagnostic-snapshot.sh \
    "$work/gate" "$work/observer"
echo "Host test artifacts: $work"
