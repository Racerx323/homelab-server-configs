#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_20o_retry2_focused_validation
readonly transaction_sha256=3cd507078e91156122f2d0212686c66a99ca213f15061c3050f6930aa558342b
readonly outer_sha256=a118feb9b39a7ed3a5b1edb3a6c56bdd7cbba15bb096e58f40ba2639ca82ef2b
readonly regression_sha256=2af3eb9ffc4b3055b157e49fcaf44dda54d7d872307db3ead0215ac636b128b8

test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
readonly caddy_root=${test_directory%/tests}
readonly transaction=$caddy_root/scripts/activate-node-b-keepalived-dbus-action20o-retry2.sh
readonly outer=$caddy_root/scripts/run-node-b-keepalived-dbus-action20o-retry2-outer.sh
readonly regression=$test_directory/action20o-retry2-node-b-keepalived-dbus-regression.sh

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }
record_check() {
    local action20o_retry2_focused_label=$1

    shift
    if "$@" >/dev/null; then
        printf '%s_check_%s=true\n' "$prefix" "$action20o_retry2_focused_label"
        return 0
    fi
    printf '%s_check_%s=false\n' "$prefix" "$action20o_retry2_focused_label" >&2
    return 1
}

record_check transaction_hash test "$(file_hash "$transaction")" = "$transaction_sha256"
record_check outer_hash test "$(file_hash "$outer")" = "$outer_sha256"
record_check regression_hash test "$(file_hash "$regression")" = "$regression_sha256"
record_check syntax /bin/bash -n "$transaction" "$outer" "$regression" "$0"
record_check shellcheck shellcheck "$transaction" "$outer" "$regression" "$0"
record_check canonical_format /bin/bash "$test_directory/shfmt-canonical.sh" --check \
    "$transaction" "$outer" "$regression" "$0"
record_check collision_policy /bin/bash "$test_directory/check-shell-readonly-local-collisions-v2.sh" \
    "$transaction" "$outer" "$regression" "$0"
record_check conditional_policy /bin/bash "$test_directory/conditional-validator-errexit-policy-regression.sh"
record_check output_evidence_policy /bin/bash "$test_directory/transaction-output-evidence-policy-regression.sh"
record_check multifile_grep_policy /bin/bash "$test_directory/multifile-grep-count-policy.sh" --check \
    "$transaction" "$outer" "$regression" "$0"
record_check portable_awk_policy /bin/bash "$test_directory/portable-awk-policy.sh" --check \
    "$transaction" "$outer" "$regression" "$0"
record_check accepted_live_hash_policy /bin/bash "$test_directory/accepted-live-hash-policy.sh" --check
record_check root_cwd_policy /bin/bash "$test_directory/remote-streamed-bash-cwd-policy.sh" --check "$outer"
record_check outer_label_policy /bin/bash "$test_directory/outer-local-gate-label-policy-regression.sh" --runner "$outer"
record_check executable_policy /bin/bash "$test_directory/executable-wrapper-policy-regression.sh"
record_check transaction_self_test /bin/bash "$transaction" --self-test
record_check regression /bin/bash "$regression"
record_check outer_self_test /bin/bash "$outer" --self-test

printf '%s_node_a_contacted=false\n' "$prefix"
printf '%s_node_b_contacted=false\n' "$prefix"
printf '%s_keepalived_reload=false\n' "$prefix"
printf '%s_keepalived_restart=false\n' "$prefix"
printf '%s_dbus_runtime_activation=false\n' "$prefix"
printf '%s_service_mutation=false\n' "$prefix"
printf '%s_filesystem_mutation=false\n' "$prefix"
printf '%s_vrrp_transition=false\n' "$prefix"
printf '%s_vip_mutation=false\n' "$prefix"
printf '%s_action_executed=false\n' "$prefix"
printf '%s_complete_suite_bypassed=true\n' "$prefix"
printf '%s_complete=true\n' "$prefix"
