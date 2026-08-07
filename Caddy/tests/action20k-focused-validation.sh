#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH
readonly PATH

readonly prefix=action_20k_focused_validation
readonly installer_sha256=abe962654982e9ab7cbcf6eabc4875a54eec2c81bf41868b3b5b6c393553a76e
readonly regression_sha256=4718b3169c31317451a4657bc6770f09b2021d0e0c2e99a96c77db8b99719e65
readonly outer_sha256=0ad806d5fc08b8a05b55d4ee756f43379846d58db16e2da094c6167732e3422d
readonly template_sha256=fd5ca8528468c97be6792e2184a71d6c06dc2c2a16abd44183bbfc170ff1f036
readonly node_a_main_source_sha256=6162cfb9d83f7e524db1df6a3b041ced90a7639fceaf28eacf713270c2a66a65
readonly node_b_main_source_sha256=9aa36b630f304bab674e31af96d96a1dbafb330728b01e2d8216c8dbab2df148

test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
readonly caddy_root=${test_directory%/tests}
readonly server_root=${caddy_root%/Caddy}
readonly code_root=${server_root%/homelab-server-configs}
readonly installer=$caddy_root/scripts/install-caddy-unicast-ttl-action20k.sh
readonly regression=$test_directory/action20k-unicast-ttl-regression.sh
readonly outer=$caddy_root/scripts/run-caddy-unicast-ttl-action20k-outer.sh
readonly template=$caddy_root/templates/keepalived-caddy-ha.conf.in
readonly node_a_main_source=$code_root/homelab-dns/Keepalived/configs/keepalived-pihole0.conf
readonly node_b_main_source=$code_root/homelab-dns/Keepalived/configs/keepalived-pihole00.conf

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }
record_check() {
    local action20k_focused_label=$1

    shift
    if "$@" >/dev/null; then
        printf '%s_check_%s=true\n' "$prefix" "$action20k_focused_label"
        return 0
    fi
    printf '%s_check_%s=false\n' "$prefix" "$action20k_focused_label" >&2
    return 1
}
dbus_global_exact() {
    local action20k_focused_main=$1

    [[ "$(grep -Fxc '    enable_dbus' "$action20k_focused_main")" -eq 1 ]] || return 1
    awk '
        /^global_defs[[:space:]]*\{/ { in_global=1; next }
        in_global && /^}/ { in_global=0 }
        in_global && $1 == "enable_dbus" { found++ }
        END { exit(found == 1 ? 0 : 1) }
    ' "$action20k_focused_main"
}

record_check installer_hash test "$(file_hash "$installer")" = "$installer_sha256"
record_check regression_hash test "$(file_hash "$regression")" = "$regression_sha256"
record_check outer_hash test "$(file_hash "$outer")" = "$outer_sha256"
record_check template_hash test "$(file_hash "$template")" = "$template_sha256"
record_check node_a_main_source_hash test \
    "$(file_hash "$node_a_main_source")" = "$node_a_main_source_sha256"
record_check node_b_main_source_hash test \
    "$(file_hash "$node_b_main_source")" = "$node_b_main_source_sha256"
record_check node_a_enable_dbus_global dbus_global_exact "$node_a_main_source"
record_check node_b_enable_dbus_global dbus_global_exact "$node_b_main_source"
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
record_check installer_self_test /bin/bash "$installer" --self-test
record_check production_regression /bin/bash "$regression"
record_check outer_self_test /bin/bash "$outer" --self-test
printf '%s_node_a_contacted=false\n' "$prefix"
printf '%s_node_b_contacted=false\n' "$prefix"
printf '%s_keepalived_reload=false\n' "$prefix"
printf '%s_keepalived_restart=false\n' "$prefix"
printf '%s_vrrp_transition=false\n' "$prefix"
printf '%s_vip_assignment=false\n' "$prefix"
printf '%s_action_executed=false\n' "$prefix"
printf '%s_persistent_live_mutations=false\n' "$prefix"
printf '%s_complete_suite_bypassed=true\n' "$prefix"
printf '%s_complete=true\n' "$prefix"
