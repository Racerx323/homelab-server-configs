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
readonly inspector="$caddy_root/scripts/inspect-node-b-unbound-post-activation-action17g-a.sh"
readonly runner="$caddy_root/scripts/run-node-b-unbound-post-activation-action17g-a.sh"
readonly collision_checker="$script_dir/check-shell-readonly-local-collisions.sh"

run_regression() {
    bash -n "$inspector" "$runner"
    "$inspector" --self-test >/dev/null
    "$runner" --self-test >/dev/null
    "$runner" --contract-test >/dev/null
    "$collision_checker" "$inspector" "$runner" >/dev/null

    grep -Fq 'expected_assertion_count=72' "$runner"
    grep -Fq 'action_17g_a_first_failure=' "$inspector"
    grep -Fq 'action_17g_a_before_state_sha256=' "$inspector"
    grep -Fq 'action_17g_a_after_state_sha256=' "$inspector"
    grep -Fq 'dns_queries_performed=true' "$inspector"
    grep -Fq 'service_mutations=false' "$inspector"
    grep -Fq 'persistent_mutations=false' "$inspector"
    grep -Fq 'cd / && exec /bin/bash -s --' "$runner"

    if grep -Eq \
        '^[[:space:]]*(chmod|chown|cp|install|ln|mkdir|mktemp|mv|rm|rmdir|touch|truncate)([[:space:]]|$)' \
        "$inspector"; then
        printf 'Action 17g-a inspector contains a filesystem mutation.\n' >&2
        exit 1
    fi
    if grep -Eq \
        'systemctl[[:space:]]+(start|stop|restart|reload|enable|disable|mask|unmask|daemon-reload|reset-failed)|unbound-control' \
        "$inspector"; then
        printf 'Action 17g-a inspector contains a service mutation.\n' >&2
        exit 1
    fi
    if grep -Eq '^[[:space:]]*(ssh|rsync|scp|sftp)([[:space:]]|$)' \
        "$inspector"; then
        printf 'Action 17g-a inspector contains a peer connection.\n' >&2
        exit 1
    fi

    printf 'action_17g_a_post_activation_regression_complete=true\n'
}

case "${1:-}" in
    --self-test | --production-test)
        [[ $# -eq 1 ]]
        run_regression
        ;;
    *)
        printf 'Usage: %s --self-test|--production-test\n' "${0##*/}" >&2
        exit 2
        ;;
esac
