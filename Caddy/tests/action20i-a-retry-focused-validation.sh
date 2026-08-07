#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH
readonly PATH

readonly prefix=action_20i_a_retry_focused_validation
test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
readonly caddy_root=${test_directory%/tests}
readonly builder=$caddy_root/scripts/build-node-b-caddy-health-helper-postinstall-action20i-a-retry.sh
readonly outer=$caddy_root/scripts/run-node-b-caddy-health-helper-postinstall-action20i-a-retry-outer.sh

record_check() {
    local action20i_a_retry_focused_label=$1

    shift
    if "$@" >/dev/null; then
        printf '%s_check_%s=true\n' "$prefix" \
            "$action20i_a_retry_focused_label"
        return 0
    fi
    printf '%s_check_%s=false\n' "$prefix" \
        "$action20i_a_retry_focused_label" >&2
    return 1
}

record_check syntax /bin/bash -n "$builder" "$outer" "$0"
record_check shellcheck shellcheck "$builder" "$outer" "$0"
record_check canonical_format /bin/bash "$test_directory/shfmt-canonical.sh" --check \
    "$builder" "$outer" "$0"
record_check executable_policy /bin/bash \
    "$test_directory/executable-wrapper-policy-regression.sh"
record_check outer_label_policy /bin/bash \
    "$test_directory/outer-local-gate-label-policy-regression.sh" \
    --runner "$outer"
printf '%s_node_a_contacted=false\n' "$prefix"
printf '%s_node_b_contacted=false\n' "$prefix"
printf '%s_action_executed=false\n' "$prefix"
printf '%s_complete=true\n' "$prefix"
