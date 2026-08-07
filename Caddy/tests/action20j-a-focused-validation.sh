#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH
readonly PATH

readonly prefix=action_20j_a_focused_validation
readonly builder_sha256=1b488289ee70698b20d05e2eec177b0c2af50b1d1e02e40c9f832d7f3c76a4e0
readonly regression_sha256=5992607f5416988ec4bd9309e6753ffd2c11e760943a2a44a932e45d72fae9a1
readonly outer_sha256=5854bac1b0930ab3887e34b72aba7296065c4dc451123fa5b63ad8fb3ab8c87b

test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
readonly caddy_root=${test_directory%/tests}
readonly builder=$caddy_root/scripts/build-dual-node-caddy-postactivation-action20j-a.sh
readonly regression=$test_directory/action20j-a-postactivation-regression.sh
readonly outer=$caddy_root/scripts/run-dual-node-caddy-postactivation-action20j-a-outer.sh

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }
record_check() {
    local action20j_a_focused_label=$1

    shift
    if "$@" >/dev/null; then
        printf '%s_check_%s=true\n' "$prefix" "$action20j_a_focused_label"
        return 0
    fi
    printf '%s_check_%s=false\n' "$prefix" "$action20j_a_focused_label" >&2
    return 1
}

record_check builder_hash test "$(file_hash "$builder")" = "$builder_sha256"
record_check regression_hash test "$(file_hash "$regression")" = "$regression_sha256"
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
record_check outer_label_policy /bin/bash \
    "$test_directory/outer-local-gate-label-policy-regression.sh" \
    --runner "$outer"
record_check conditional_policy /bin/bash \
    "$test_directory/conditional-validator-errexit-policy-regression.sh"
record_check output_evidence_policy /bin/bash \
    "$test_directory/transaction-output-evidence-policy-regression.sh"
record_check multifile_grep_policy /bin/bash \
    "$test_directory/multifile-grep-count-policy.sh" --check \
    "$builder" "$regression" "$outer" "$0"
record_check portable_awk_policy /bin/bash \
    "$test_directory/portable-awk-policy.sh" --check \
    "$builder" "$regression" "$outer" "$0"
record_check accepted_live_hash_policy /bin/bash \
    "$test_directory/accepted-live-hash-policy.sh" --check
record_check builder_self_test /bin/bash "$builder" --self-test
record_check builder_contract_test /bin/bash "$builder" --contract-test
record_check production_regression /bin/bash "$regression"
record_check outer_self_test /bin/bash "$outer" --self-test
printf '%s_node_a_contacted=false\n' "$prefix"
printf '%s_node_b_contacted=false\n' "$prefix"
printf '%s_health_helpers_invoked=false\n' "$prefix"
printf '%s_keepalived_reload=false\n' "$prefix"
printf '%s_vrrp_transition=false\n' "$prefix"
printf '%s_vip_assignment=false\n' "$prefix"
printf '%s_action_executed=false\n' "$prefix"
printf '%s_persistent_mutations=false\n' "$prefix"
printf '%s_complete_suite_bypassed=true\n' "$prefix"
printf '%s_complete=true\n' "$prefix"
