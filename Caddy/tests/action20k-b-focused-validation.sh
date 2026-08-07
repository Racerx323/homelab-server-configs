#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_20k_b_focused_validation
readonly inspector_sha256=414f6ada4119863c9575dbec017af9d640434bd2ee4ba11a5875ce5945f61a0d
readonly outer_sha256=dbaa0d330d10868eab157f7528b0e23bee1449adc983a44f1785b3102f10aaa6
readonly regression_sha256=5d05dcb675a970f033c9be97129443f12ca071b1b870a2e87bd25e9c46a395a8

test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
readonly caddy_root=${test_directory%/tests}
readonly inspector=$caddy_root/scripts/inspect-node-b-unicast-ttl-postinstall-action20k-b.sh
readonly outer=$caddy_root/scripts/run-node-b-unicast-ttl-postinstall-action20k-b-outer.sh
readonly regression=$test_directory/action20k-b-node-b-unicast-ttl-postinstall-regression.sh

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }
record_check() {
    local action20kb_focused_label=$1

    shift
    if "$@" >/dev/null; then
        printf '%s_check_%s=true\n' "$prefix" "$action20kb_focused_label"
        return 0
    fi
    printf '%s_check_%s=false\n' "$prefix" "$action20kb_focused_label" >&2
    return 1
}

record_check inspector_hash test "$(file_hash "$inspector")" = "$inspector_sha256"
record_check outer_hash test "$(file_hash "$outer")" = "$outer_sha256"
record_check regression_hash test "$(file_hash "$regression")" = "$regression_sha256"
record_check syntax /bin/bash -n "$inspector" "$outer" "$regression" "$0"
record_check shellcheck shellcheck "$inspector" "$outer" "$regression" "$0"
record_check canonical_format /bin/bash "$test_directory/shfmt-canonical.sh" \
    --check "$inspector" "$outer" "$regression" "$0"
record_check collision_policy /bin/bash \
    "$test_directory/check-shell-readonly-local-collisions-v2.sh" \
    "$inspector" "$outer" "$regression" "$0"
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
    "$inspector" "$outer" "$regression" "$0"
record_check portable_awk_policy /bin/bash \
    "$test_directory/portable-awk-policy.sh" --check \
    "$inspector" "$outer" "$regression" "$0"
record_check inspector_self_test /bin/bash "$inspector" --self-test
record_check production_regression /bin/bash "$regression"
record_check outer_self_test /bin/bash "$outer" --self-test
printf '%s_node_a_contacted=false\n' "$prefix"
printf '%s_node_b_contacted=false\n' "$prefix"
printf '%s_helper_execution=false\n' "$prefix"
printf '%s_keepalived_reload=false\n' "$prefix"
printf '%s_keepalived_restart=false\n' "$prefix"
printf '%s_service_mutation=false\n' "$prefix"
printf '%s_vrrp_mutation=false\n' "$prefix"
printf '%s_vip_mutation=false\n' "$prefix"
printf '%s_action_executed=false\n' "$prefix"
printf '%s_persistent_live_mutations=false\n' "$prefix"
printf '%s_complete_suite_bypassed=true\n' "$prefix"
printf '%s_complete=true\n' "$prefix"
