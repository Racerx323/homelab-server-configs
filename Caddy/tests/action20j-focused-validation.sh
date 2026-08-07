#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH
readonly PATH

readonly prefix=action_20j_focused_validation
readonly builder_sha256=79ec3c5318f378dae1438a005e6ac1da32cf4cbe0b12c113ebbd50b1566861b6
readonly regression_sha256=2957a5660d100564abe068feabf1ef93bc596feab784e99856d353a36bc350ca
readonly outer_sha256=50d302239c5675784e100bff358355651d30bdd96f8d02094c565f6403186ae7

test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
readonly caddy_root=${test_directory%/tests}
readonly builder=$caddy_root/scripts/build-node-b-caddy-vrrp-activation-action20j.sh
readonly regression=$test_directory/action20j-node-b-vrrp-activation-regression.sh
readonly outer=$caddy_root/scripts/run-node-b-caddy-vrrp-activation-action20j-outer.sh

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }
record_check() {
    local action20j_focused_label=$1

    shift
    if "$@" >/dev/null; then
        printf '%s_check_%s=true\n' "$prefix" "$action20j_focused_label"
        return 0
    fi
    printf '%s_check_%s=false\n' "$prefix" "$action20j_focused_label" >&2
    return 1
}

record_check builder_hash test "$(file_hash "$builder")" = "$builder_sha256"
record_check regression_hash test "$(file_hash "$regression")" = \
    "$regression_sha256"
record_check outer_hash test "$(file_hash "$outer")" = "$outer_sha256"
record_check syntax /bin/bash -n "$builder" "$regression" "$outer" "$0"
record_check shellcheck shellcheck "$builder" "$regression" "$outer" "$0"
record_check canonical_format /bin/bash "$test_directory/shfmt-canonical.sh" \
    --check "$builder" "$regression" "$outer" "$0"
record_check collision_policy /bin/bash \
    "$test_directory/check-shell-readonly-local-collisions-v2.sh" \
    "$builder" "$regression" "$outer" "$0"
record_check executable_policy /bin/bash \
    "$test_directory/executable-wrapper-policy-regression.sh"
record_check builder_self_test /bin/bash "$builder" --self-test
record_check production_regression /bin/bash "$regression"
record_check outer_self_test /bin/bash "$outer" --self-test
printf '%s_node_a_contacted=false\n' "$prefix"
printf '%s_node_b_contacted=false\n' "$prefix"
printf '%s_keepalived_reload=false\n' "$prefix"
printf '%s_vrrp_transition=false\n' "$prefix"
printf '%s_vip_assignment=false\n' "$prefix"
printf '%s_action_executed=false\n' "$prefix"
printf '%s_persistent_mutations=false\n' "$prefix"
printf '%s_complete=true\n' "$prefix"
