#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH
readonly PATH

readonly prefix=action_20i_focused_validation
test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
readonly caddy_root=${test_directory%/tests}
readonly builder=$caddy_root/scripts/build-node-b-caddy-health-helper-action20i.sh
readonly regression=$test_directory/action20i-node-b-health-helper-regression.sh
readonly outer=$caddy_root/scripts/run-node-b-caddy-health-helper-action20i-outer.sh
readonly outer_regression=$test_directory/action20i-outer-production-path-regression.sh

record_check() {
    local action20i_focused_label=$1

    shift
    if "$@" >/dev/null; then
        printf '%s_check_%s=true\n' "$prefix" "$action20i_focused_label"
        return 0
    fi
    printf '%s_check_%s=false\n' "$prefix" "$action20i_focused_label" >&2
    return 1
}

record_check syntax /bin/bash -n "$builder" "$regression" "$outer" \
    "$outer_regression" "$0"
record_check shellcheck shellcheck "$builder" "$regression" "$outer" \
    "$outer_regression" "$0"
record_check canonical_format /bin/bash "$test_directory/shfmt-canonical.sh" --check \
    "$builder" "$regression" "$outer" "$outer_regression" "$0"
record_check collision_policy /bin/bash \
    "$test_directory/check-shell-readonly-local-collisions-v2.sh" \
    "$builder" "$regression" "$outer" "$outer_regression" "$0"
record_check conditional_policy /bin/bash \
    "$test_directory/conditional-validator-errexit-policy-regression.sh"
record_check multifile_grep_policy /bin/bash \
    "$test_directory/multifile-grep-count-policy.sh" --check \
    "$builder" "$regression" "$outer" "$outer_regression" "$0"
record_check portable_awk_policy /bin/bash \
    "$test_directory/portable-awk-policy-regression.sh"
record_check builder_self_test /bin/bash "$builder" --self-test
record_check production_regression /bin/bash "$regression"
record_check outer_label_policy /bin/bash \
    "$test_directory/outer-local-gate-label-policy-regression.sh" --runner "$outer"
record_check outer_production_regression /bin/bash "$outer_regression"
printf '%s_node_contact=false\n' "$prefix"
printf '%s_action_executed=false\n' "$prefix"
printf '%s_complete=true\n' "$prefix"
