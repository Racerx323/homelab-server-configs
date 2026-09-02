#!/bin/bash

set -Eeuo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly script_dir
readonly service_template="$script_dir/../templates/reconya.service"

fail() {
    printf 'FAIL: %s\n' "$1" >&2
    exit 1
}

require_line() {
    local expected="$1"

    grep -Fxq -- "$expected" "$service_template" ||
        fail "service template missing: $expected"
}

[[ -f $service_template ]] || fail "service template not found: $service_template"

require_line 'KillSignal=SIGINT'
require_line 'TimeoutStopSec=15s'
require_line 'FinalKillSignal=SIGKILL'
require_line 'Restart=on-failure'
require_line 'After=network-online.target'

if grep -Eq '^TimeoutStopSec=(0|infinity)$' "$service_template"; then
    fail 'service template permits an unbounded stop'
fi
if grep -Fxq 'KillSignal=SIGTERM' "$service_template"; then
    fail 'service template bypasses the v0.26.0 graceful SIGINT handler'
fi

printf 'PASS: ReconYa SIGINT workaround and shutdown bound\n'
