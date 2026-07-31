#!/usr/bin/env bash

set -euo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_dir
caddy_root=$(cd -- "$script_dir/.." && pwd)
readonly caddy_root
readonly inspector="$caddy_root/scripts/inspect-node-b-unbound-local-zone-stage-action17f-c.sh"
readonly runner="$caddy_root/scripts/run-node-b-unbound-local-zone-stage-verification-action17f-c.sh"

run_static_test() {
    bash -n "$inspector" "$runner"
    "$inspector" --self-test >/dev/null
    "$runner" --self-test >/dev/null
    "$runner" --contract-test >/dev/null

    grep -Fq 'cd / && exec /bin/bash -s --' "$runner"
    grep -Fq 'action_17f_c_first_failure=' "$inspector"
    grep -Fq 'combined_checkconf_status=' "$inspector"
    grep -Fq 'local_zone_stage=/var/tmp/caddy-unbound-node-b-action17f-local-zone' \
        "$inspector"
    grep -Fq 'accepted_live_state_sha256=3a05c0487101f3b44f8e5ba41a4a74713d07cddc369542f04d4a8b1f417cb824' \
        "$inspector"

    if grep -Eq \
        '^[[:space:]]*(chmod|chown|cp|install|ln|mkdir|mktemp|mv|rm|rmdir|touch|truncate)([[:space:]]|$)' \
        "$inspector"; then
        printf 'Action 17f-c inspector contains a filesystem mutation.\n' >&2
        exit 1
    fi
    if grep -Eq \
        'systemctl[[:space:]]+(start|stop|restart|reload|enable|disable|mask|unmask|daemon-reload|reset-failed)|unbound-control|(^|[[:space:]])dig([[:space:]]|$)' \
        "$inspector"; then
        printf 'Action 17f-c inspector contains a query or service mutation.\n' \
            >&2
        exit 1
    fi

    printf 'action_17f_c_static_regression_complete=true\n'
}

case "${1:-}" in
    --self-test | --production-test)
        [[ $# -eq 1 ]]
        run_static_test
        ;;
    *)
        printf 'Usage: %s --self-test|--production-test\n' "${0##*/}" >&2
        exit 2
        ;;
esac
