#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_20m_focused_validation
readonly installer_sha256=603b36c877831ba6cbef09c239e72ddf121e55cb2e5bd985ceaf6da477d78d13
readonly regression_sha256=9611ebe5ff2142eb91f9ce7b1930b5552a20602ccfbbc7cf15cb826bd58a9eeb
readonly outer_sha256=e5888f78ed8195e9a368df002c71a99a4f602de9de780c9dc7578b3803eaeeb2
readonly source_sha256=9aa36b630f304bab674e31af96d96a1dbafb330728b01e2d8216c8dbab2df148
readonly candidate_sha256=5480e6994994b65b0a498f42cb7943b5de86958416732a44983e341a93db1393

test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
readonly caddy_root=${test_directory%/tests}
readonly server_root=${caddy_root%/Caddy}
readonly workspace_root=${server_root%/homelab-server-configs}
readonly installer=$caddy_root/scripts/install-node-b-keepalived-dbus-main-action20m.sh
readonly regression=$test_directory/action20m-node-b-keepalived-dbus-main-regression.sh
readonly outer=$caddy_root/scripts/run-node-b-keepalived-dbus-main-action20m-outer.sh
readonly source_configuration=$workspace_root/homelab-dns/Keepalived/configs/keepalived-pihole00.conf

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }
record_check() {
    local action20m_focused_label=$1

    shift
    if "$@" >/dev/null; then
        printf '%s_check_%s=true\n' "$prefix" "$action20m_focused_label"
        return 0
    fi
    printf '%s_check_%s=false\n' "$prefix" "$action20m_focused_label" >&2
    return 1
}
candidate_hash_contract() {
    {
        cat "$source_configuration"
        printf '\ninclude /etc/keepalived/conf.d/caddy-ha.conf\n'
    } | sha256sum | awk -v expected="$candidate_sha256" '$1 == expected { valid=1 }
        END { exit(valid == 1 ? 0 : 1) }'
}
no_runtime_mutation_commands() {
    local action20m_focused_path=$1

    [[ "$(grep -Ec '(^|[[:space:]])systemctl[[:space:]]+(reload|restart|start|stop|enable|disable)[[:space:]]+keepalived' "$action20m_focused_path" || true)" -eq 0 ]] || return 1
    [[ "$(grep -Ec '(^|[[:space:]])(keepalived|service)[[:space:]]' "$action20m_focused_path" || true)" -eq 0 ]] || return 1
}

record_check installer_hash test "$(file_hash "$installer")" = "$installer_sha256"
record_check regression_hash test "$(file_hash "$regression")" = "$regression_sha256"
record_check outer_hash test "$(file_hash "$outer")" = "$outer_sha256"
record_check source_hash test "$(file_hash "$source_configuration")" = "$source_sha256"
record_check candidate_hash_contract candidate_hash_contract
record_check syntax /bin/bash -n "$installer" "$regression" "$outer" "$0"
record_check shellcheck shellcheck "$installer" "$regression" "$outer" "$0"
record_check canonical_format /bin/bash "$test_directory/shfmt-canonical.sh" \
    --check "$installer" "$regression" "$outer" "$0"
record_check collision_policy /bin/bash \
    "$test_directory/check-shell-readonly-local-collisions-v2.sh" \
    "$installer" "$regression" "$outer" "$0"
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
    "$installer" "$regression" "$outer" "$0"
record_check portable_awk_policy /bin/bash \
    "$test_directory/portable-awk-policy.sh" --check \
    "$installer" "$regression" "$outer" "$0"
record_check accepted_live_hash_policy /bin/bash \
    "$test_directory/accepted-live-hash-policy.sh" --check
record_check installer_self_test /bin/bash "$installer" --self-test
record_check production_regression /bin/bash "$regression"
record_check outer_self_test /bin/bash "$outer" --self-test
record_check installer_no_runtime_mutation no_runtime_mutation_commands "$installer"
record_check outer_no_runtime_mutation no_runtime_mutation_commands "$outer"
printf '%s_node_a_contacted=false\n' "$prefix"
printf '%s_node_b_contacted=false\n' "$prefix"
printf '%s_keepalived_reload=false\n' "$prefix"
printf '%s_keepalived_restart=false\n' "$prefix"
printf '%s_service_mutation=false\n' "$prefix"
printf '%s_vrrp_transition=false\n' "$prefix"
printf '%s_vip_mutation=false\n' "$prefix"
printf '%s_action_executed=false\n' "$prefix"
printf '%s_persistent_live_mutations=false\n' "$prefix"
printf '%s_complete_suite_bypassed=true\n' "$prefix"
printf '%s_complete=true\n' "$prefix"
