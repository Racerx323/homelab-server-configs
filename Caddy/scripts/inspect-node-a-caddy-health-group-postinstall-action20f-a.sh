#!/usr/bin/env bash
# shellcheck disable=SC2317

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH
readonly PATH

readonly prefix=action_20f_a
readonly fragment=/etc/keepalived/conf.d/caddy-ha.conf
readonly main_configuration=/etc/keepalived/keepalived.conf
readonly environment_file=/etc/default/caddy-ha
readonly rollback_root=/var/backups/caddy-ha
readonly expected_backup_path=/var/backups/caddy-ha/action19e-node-a-keepalived-fragment.JgYBbS
readonly expected_action19e_fragment_sha256=3a6f4c038d646bf12484d1a521a8f7fc01d05c56919ac8e6217ca50c2ab84bc5
readonly expected_fragment_sha256=6f5a58ca8fd39a1218de6fc964f54aef69f374351c0727bbb0fabf899a80ef39
readonly expected_main_sha256=cf4858888ae80772f1a50dda7c0ea120ff083eafae33a0ad4ca291d44755c1e2
readonly expected_environment_sha256=2e439dd4c868736fd7a9dceff7ba3627a1d9fe8780ba7dcef2ce5d0e5e62a2b8
readonly expected_health_sha256=9bf531ab7cbb047f8f09ce5956b597d5c8b6ede397c166f0b040e2e92fe8bbab
readonly expected_old_health_sha256=c3bc1c080cd148efc0a64440a2a411ec115d0ca83f8e6a66220d7bd201971414
readonly expected_notification_sha256=5862b494301f972d039477d4ed93a7d56156b141cba31c41ccd61d7f843321d8
readonly expected_active_release=/etc/caddy/releases/action16ar-retry-node-a-default-deny
readonly expected_health_backup_path=/var/backups/caddy-ha/action20c-node-a-health-context.DzQFvI
readonly expected_group_backup_path=/var/backups/caddy-ha/action20f-node-a-health-group.AuUZOk
readonly health_script=/usr/local/libexec/check-caddy.sh
readonly notification_script=/usr/local/libexec/lsyncd-ha-failover-notify.sh
readonly vip_ipv4_cidr=10.1.0.56/22
readonly vip_ipv6_cidr=fd36:5aa8:6971:1::56/128
readonly maximum_stream_bytes=1048576
readonly maximum_stream_lines=4096

readonly -a continuity_units=(
    keepalived.service
    caddy.service
    lighttpd.service
    lsyncd.service
    caddy-lsyncd.service
    caddy-sync-reconcile.path
    caddy-sync-reconcile.service
)
readonly -a common_properties=(ActiveState SubState UnitFileState)
readonly -a common_property_labels=(active_state sub_state unit_file_state)
readonly -a service_properties=(MainPID NRestarts)
readonly -a service_property_labels=(main_pid n_restarts)

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }
tree_hash() {
    local tree_root=$1

    (
        cd "$tree_root"
        find . -type f -print0 | LC_ALL=C sort -z | xargs -0 -r sha256sum
    ) | sha256sum | awk '{ print $1 }'
}
address_count() {
    local address_family=$1
    local expected_cidr=$2

    ip -o "-$address_family" address show dev eth0 2>/dev/null |
        awk -v expected="$expected_cidr" '$4 == expected { count++ }
            END { print count + 0 }'
}
unit_property() {
    local property_name=$1
    local unit_name=$2

    if [[ "$property_name" == UnitFileState ]]; then
        systemctl is-enabled "$unit_name" 2>/dev/null || true
        return 0
    fi
    systemctl show "$unit_name" --no-pager --property "$property_name" --value
}

expected_assertions() {
    printf '%s\n' \
        identity_root working_directory_root hostname_node_a architecture_arm64 \
        physical_ipv4_exact physical_ipv6_exact \
        fragment_regular fragment_not_symlink fragment_metadata_exact \
        fragment_hash_exact fragment_dualstack_group fragment_ipv4_instance \
        fragment_ipv6_instance fragment_ipv4_vrid fragment_ipv6_vrid \
        fragment_priority fragment_ipv4_source fragment_ipv4_peer \
        fragment_ipv6_source fragment_ipv6_peer fragment_ipv4_vip \
        fragment_ipv6_vip fragment_preempt_delay_count \
        fragment_initial_backup_count fragment_health_user_group_exact \
        fragment_old_health_user_absent fragment_health_command fragment_notify_command \
        main_configuration_regular main_configuration_not_symlink \
        main_configuration_excludes_fragment main_hash_exact \
        health_script_regular health_script_not_symlink \
        health_script_metadata_exact health_script_hash_exact \
        health_environment_file_regular health_environment_file_not_symlink \
        health_environment_file_metadata_exact health_environment_file_hash_exact \
        keepalived_script_identity_exact keepalived_script_uid_exact \
        caddy_tls_identity_exact caddy_tls_gid_exact \
        keepalived_caddy_tls_membership_exact exact_context_runtime_metadata \
        exact_context_environment_access exact_context_fullchain_access \
        exact_context_private_key_access exact_context_caddy_validate \
        exact_context_curl exact_context_full_helper exact_context_runtime_cleanup \
        health_helper_transient_residue_absent \
        notification_script_regular notification_script_not_symlink \
        notification_script_metadata_exact notification_script_hash_exact \
        backup_count_one backup_directory_regular backup_directory_not_symlink \
        backup_directory_metadata_exact backup_manifest_regular \
        backup_manifest_not_symlink backup_manifest_metadata_exact \
        backup_manifest_line_count_exact backup_manifest_action_exact \
        backup_manifest_node_exact backup_manifest_fragment_pre_state_exact \
        backup_manifest_directory_pre_state_supported \
        backup_manifest_main_hash_exact backup_manifest_candidate_hash_exact \
        action20c_backup_count_one action20c_backup_directory_regular \
        action20c_backup_directory_not_symlink \
        action20c_backup_directory_metadata_exact \
        action20c_backup_helper_regular action20c_backup_helper_not_symlink \
        action20c_backup_helper_metadata_exact action20c_backup_helper_hash_exact \
        action20c_backup_manifest_regular action20c_backup_manifest_not_symlink \
        action20c_backup_manifest_metadata_exact \
        action20c_backup_manifest_line_count_exact \
        action20c_backup_manifest_action_exact action20c_backup_manifest_node_exact \
        action20c_backup_manifest_old_hash_exact \
        action20c_backup_manifest_candidate_hash_exact \
        action20c_run_stage_count_zero action20c_tmp_stage_count_zero \
        action20c_install_stage_absent \
        action20f_backup_count_one action20f_backup_directory_regular \
        action20f_backup_directory_not_symlink action20f_backup_directory_metadata_exact \
        action20f_backup_fragment_regular action20f_backup_fragment_not_symlink \
        action20f_backup_fragment_metadata_exact action20f_backup_fragment_hash_exact \
        action20f_backup_manifest_regular action20f_backup_manifest_not_symlink \
        action20f_backup_manifest_metadata_exact action20f_backup_manifest_line_count_exact \
        action20f_backup_manifest_action_exact action20f_backup_manifest_node_exact \
        action20f_backup_manifest_old_hash_exact action20f_backup_manifest_candidate_hash_exact \
        action20f_backup_manifest_main_hash_exact action20f_run_stage_count_zero \
        action20f_tmp_stage_count_zero action20f_install_stage_absent \
        action19e_run_stage_count_zero action19e_tmp_stage_count_zero \
        action19e_install_stage_absent keepalived_active keepalived_enabled \
        caddy_active lighttpd_active lsyncd_inactive lsyncd_masked \
        caddy_lsyncd_inactive caddy_lsyncd_disabled reconcile_path_inactive \
        reconcile_service_inactive current_link_exact current_target_exact \
        caddy_ipv4_vip_absent caddy_ipv6_vip_absent \
        dns_ipv4_vip_count_supported dns_ipv6_vip_count_supported \
        dns_vip_dualstack_coherent before_state_status_zero \
        before_state_stderr_empty before_state_hash_format \
        after_state_status_zero after_state_stderr_empty after_state_hash_format \
        state_unchanged

    local property_index
    local unit_label
    local unit_name
    for unit_name in "${continuity_units[@]}"; do
        unit_label=${unit_name//[-.]/_}
        for property_index in "${!common_properties[@]}"; do
            printf 'service_%s_%s_observed\n' "$unit_label" \
                "${common_property_labels[$property_index]}"
        done
        if [[ "$unit_name" == *.service ]]; then
            for property_index in "${!service_properties[@]}"; do
                printf 'service_%s_%s_observed\n' "$unit_label" \
                    "${service_property_labels[$property_index]}"
            done
        fi
    done
}

record_command() {
    local assertion_label=$1

    shift
    if "$@"; then
        printf '%s_assertion_%s=true\n' "$prefix" "$assertion_label"
        return 0
    fi
    printf '%s_assertion_%s=false\n' "$prefix" "$assertion_label"
    return 1
}

snapshot_state() {
    local property_name
    local unit_name

    printf 'keepalived_tree_sha256=%s\n' "$(tree_hash /etc/keepalived)"
    printf 'main_sha256=%s\n' "$(file_hash "$main_configuration")"
    printf 'fragment_sha256=%s\n' "$(file_hash "$fragment" 2>/dev/null || true)"
    printf 'backup_tree_sha256=%s\n' \
        "$(tree_hash "$expected_backup_path" 2>/dev/null || true)"
    printf 'health_backup_tree_sha256=%s\n' \
        "$(tree_hash "$expected_health_backup_path" 2>/dev/null || true)"
    printf 'group_backup_tree_sha256=%s\n' \
        "$(tree_hash "$expected_group_backup_path" 2>/dev/null || true)"
    printf 'ipv4_vip_count=%s\n' "$(address_count 4 "$vip_ipv4_cidr")"
    printf 'ipv6_vip_count=%s\n' "$(address_count 6 "$vip_ipv6_cidr")"
    for unit_name in "${continuity_units[@]}"; do
        for property_name in "${common_properties[@]}"; do
            printf 'unit=%s property=%s value=%s\n' "$unit_name" "$property_name" \
                "$(unit_property "$property_name" "$unit_name")"
        done
        if [[ "$unit_name" == *.service ]]; then
            for property_name in "${service_properties[@]}"; do
                printf 'unit=%s property=%s value=%s\n' "$unit_name" \
                    "$property_name" "$(unit_property "$property_name" "$unit_name")"
            done
        fi
    done
}

line_count() { awk 'END { print NR }' "$1"; }
safe_stream() {
    local action20fa_stream_path=$1

    [[ "$(wc -c <"$action20fa_stream_path")" -le "$maximum_stream_bytes" ]] || return 1
    [[ "$(line_count "$action20fa_stream_path")" -le "$maximum_stream_lines" ]] || return 1
    ! LC_ALL=C grep -n '[^[:print:][:space:]]' "$action20fa_stream_path" >/dev/null || return 1
    ! grep -Eqi \
        'BEGIN [A-Z ]*PRIVATE KEY|CADDY_TLS_PRIVATE_KEY_PEM|PRIVATE_KEY=|DOPPLER_TOKEN|Authorization:[[:space:]]*Bearer' \
        "$action20fa_stream_path" || return 1
}
emit_stream() {
    local action20fa_stream_label=$1
    local action20fa_stream_path=$2

    printf '%s_capture_%s_bytes=%s\n' "$prefix" "$action20fa_stream_label" \
        "$(wc -c <"$action20fa_stream_path")"
    printf '%s_capture_%s_lines=%s\n' "$prefix" "$action20fa_stream_label" \
        "$(line_count "$action20fa_stream_path")"
    printf '%s_capture_%s_sha256=%s\n' "$prefix" "$action20fa_stream_label" \
        "$(file_hash "$action20fa_stream_path")"
    printf '%s_capture_%s_classification=bounded_safe\n' "$prefix" "$action20fa_stream_label"
    if [[ ! -s "$action20fa_stream_path" ]]; then
        printf '%s_capture_%s_content_secured=empty\n' "$prefix" "$action20fa_stream_label"
        return 0
    fi
    printf '%s_capture_%s_begin\n' "$prefix" "$action20fa_stream_label"
    sed "s/^/${prefix}_capture_${action20fa_stream_label}_content=/" "$action20fa_stream_path"
    printf '%s_capture_%s_end\n' "$prefix" "$action20fa_stream_label"
}
run_probe() {
    local action20fa_probe_label=$1
    local action20fa_probe_root=$2
    local action20fa_probe_stdout=$action20fa_probe_root/$action20fa_probe_label.stdout
    local action20fa_probe_stderr=$action20fa_probe_root/$action20fa_probe_label.stderr
    local action20fa_probe_status=0

    shift 2
    : >"$action20fa_probe_stdout"
    : >"$action20fa_probe_stderr"
    chmod 0600 "$action20fa_probe_stdout" "$action20fa_probe_stderr"
    "$@" >"$action20fa_probe_stdout" 2>"$action20fa_probe_stderr" || action20fa_probe_status=$?
    safe_stream "$action20fa_probe_stdout" && safe_stream "$action20fa_probe_stderr" || return 97
    emit_stream "${action20fa_probe_label}_stdout" "$action20fa_probe_stdout"
    emit_stream "${action20fa_probe_label}_stderr" "$action20fa_probe_stderr"
    printf '%s_value_%s_status=%s\n' "$prefix" "$action20fa_probe_label" "$action20fa_probe_status"
    [[ "$action20fa_probe_status" -eq 0 ]]
}

case "${1:-}" in
    --expected-assertions)
        [[ $# -eq 1 ]]
        expected_assertions
        exit 0
        ;;
    --self-test)
        [[ $# -eq 1 ]]
        expected_root=$(mktemp -d /tmp/caddy-action20f-a-expected.XXXXXX)
        trap 'rm -rf -- "$expected_root"' EXIT
        expected_assertions >"$expected_root/labels"
        [[ -s "$expected_root/labels" ]]
        [[ "$(wc -l <"$expected_root/labels")" -eq "$(LC_ALL=C sort -u "$expected_root/labels" | wc -l)" ]]
        ! grep -Ev '^[a-z0-9_]+$' "$expected_root/labels" | grep -q .
        printf '%s_inspector_self_test_complete=true\n' "$prefix"
        exit 0
        ;;
    "")
        [[ $# -eq 0 ]]
        ;;
    *)
        printf 'Usage: %s [--self-test|--expected-assertions]\n' "${0##*/}" >&2
        exit 64
        ;;
esac

work_directory=$(mktemp -d /tmp/caddy-action20f-a-inspector.XXXXXX)
readonly work_directory
# shellcheck disable=SC2317
cleanup() { rm -rf -- "$work_directory"; }
trap cleanup EXIT
readonly before_stdout=$work_directory/before.out
readonly before_stderr=$work_directory/before.err
readonly after_stdout=$work_directory/after.out
readonly after_stderr=$work_directory/after.err
readonly probe_root=$work_directory/probes
: >"$before_stdout"
: >"$before_stderr"
: >"$after_stdout"
: >"$after_stderr"
chmod 0600 "$before_stdout" "$before_stderr" "$after_stdout" "$after_stderr"
mkdir -m 0700 "$probe_root"

before_status=0
snapshot_state >"$before_stdout" 2>"$before_stderr" || before_status=$?
readonly before_status
before_state_sha256=$(file_hash "$before_stdout")
readonly before_state_sha256

failed_count=0
first_failure=none
run_assertion() {
    local assertion_label=$1

    shift
    if ! record_command "$assertion_label" "$@"; then
        failed_count=$((failed_count + 1))
        if [[ "$first_failure" == none ]]; then first_failure=$assertion_label; fi
    fi
}

run_assertion identity_root test "$(id -u)" -eq 0
run_assertion working_directory_root test "$(pwd -P)" = /
run_assertion hostname_node_a test "$(hostname)" = j1-svpihole0
run_assertion architecture_arm64 test "$(dpkg --print-architecture)" = arm64
run_assertion physical_ipv4_exact test "$(address_count 4 10.1.0.53/22)" -eq 1
run_assertion physical_ipv6_exact test \
    "$(address_count 6 fd36:5aa8:6971:1::53/64)" -eq 1
run_assertion fragment_regular test -f "$fragment"
run_assertion fragment_not_symlink test ! -L "$fragment"
run_assertion fragment_metadata_exact test \
    "$(stat -c '%U:%G:%a' "$fragment" 2>/dev/null || true)" = root:root:644
run_assertion fragment_hash_exact test \
    "$(file_hash "$fragment" 2>/dev/null || true)" = "$expected_fragment_sha256"
run_assertion fragment_dualstack_group grep -Fq 'vrrp_sync_group CADDY_DUALSTACK {' "$fragment"
run_assertion fragment_ipv4_instance grep -Fq 'vrrp_instance CADDY_IPV4 {' "$fragment"
run_assertion fragment_ipv6_instance grep -Fq 'vrrp_instance CADDY_IPV6 {' "$fragment"
run_assertion fragment_ipv4_vrid grep -Fq 'virtual_router_id 110' "$fragment"
run_assertion fragment_ipv6_vrid grep -Fq 'virtual_router_id 111' "$fragment"
run_assertion fragment_priority grep -Fq 'priority 140' "$fragment"
run_assertion fragment_ipv4_source grep -Fq 'unicast_src_ip 10.1.0.53' "$fragment"
run_assertion fragment_ipv4_peer grep -Fq '10.1.0.54 min_ttl 255 max_ttl 255' "$fragment"
run_assertion fragment_ipv6_source grep -Fq \
    'unicast_src_ip fd36:5aa8:6971:1::53' "$fragment"
run_assertion fragment_ipv6_peer grep -Fq \
    'fd36:5aa8:6971:1::54 min_ttl 255 max_ttl 255' "$fragment"
run_assertion fragment_ipv4_vip grep -Fq '10.1.0.56/22 dev eth0' "$fragment"
run_assertion fragment_ipv6_vip grep -Fq \
    'fd36:5aa8:6971:1::56/128 dev eth0 preferred_lft forever' "$fragment"
run_assertion fragment_preempt_delay_count test \
    "$(grep -Fxc '    preempt_delay 30' "$fragment")" -eq 2
run_assertion fragment_initial_backup_count test \
    "$(grep -Fxc '    state BACKUP' "$fragment")" -eq 2
run_assertion fragment_health_user_group_exact test \
    "$(grep -Fxc '    user keepalived_script caddy-tls' "$fragment")" -eq 1
run_assertion fragment_old_health_user_absent test \
    "$(grep -Fxc '    user keepalived_script' "$fragment" || true)" -eq 0
run_assertion fragment_health_command grep -Fq \
    'script "/usr/local/libexec/check-caddy.sh"' "$fragment"
run_assertion fragment_notify_command grep -Fq \
    'notify "/usr/local/libexec/lsyncd-ha-failover-notify.sh"' "$fragment"
run_assertion main_configuration_regular test -f "$main_configuration"
run_assertion main_configuration_not_symlink test ! -L "$main_configuration"
# The child Bash expands its positional parameter.
# shellcheck disable=SC2016
run_assertion main_configuration_excludes_fragment bash -c \
    '! grep -Eq "^[[:space:]]*(include|include_dir).*conf\\.d|caddy-ha\\.conf" "$1"' \
    _ "$main_configuration"
# The child Bash expands its positional parameter.
# shellcheck disable=SC2016
main_sha256=$(file_hash "$main_configuration")
readonly main_sha256
run_assertion main_hash_exact test "$main_sha256" = "$expected_main_sha256"
run_assertion health_script_regular test -f "$health_script"
run_assertion health_script_not_symlink test ! -L "$health_script"
run_assertion health_script_metadata_exact test \
    "$(stat -c '%U:%G:%a' "$health_script" 2>/dev/null || true)" = root:root:755
run_assertion health_script_hash_exact test \
    "$(file_hash "$health_script" 2>/dev/null || true)" = "$expected_health_sha256"
run_assertion health_environment_file_regular test -f "$environment_file"
run_assertion health_environment_file_not_symlink test ! -L "$environment_file"
run_assertion health_environment_file_metadata_exact test \
    "$(stat -c '%U:%G:%a' "$environment_file" 2>/dev/null || true)" = root:caddy-tls:640
run_assertion health_environment_file_hash_exact test \
    "$(file_hash "$environment_file" 2>/dev/null || true)" = "$expected_environment_sha256"
run_assertion keepalived_script_identity_exact test \
    "$(getent passwd keepalived_script)" = \
    'keepalived_script:x:993:989::/home/keepalived_script:/usr/sbin/nologin'
run_assertion keepalived_script_uid_exact test "$(id -u keepalived_script)" -eq 993
run_assertion caddy_tls_identity_exact test \
    "$(getent group caddy-tls)" = 'caddy-tls:x:991:caddy,caddy-sync,keepalived_script'
run_assertion caddy_tls_gid_exact test "$(getent group caddy-tls | cut -d: -f3)" -eq 991
run_assertion keepalived_caddy_tls_membership_exact test \
    "$(id -Gn keepalived_script | tr ' ' '\n' | grep -Fxc caddy-tls)" -eq 1

context_runtime_root=$(mktemp -d /tmp/caddy-action20f-a-context.XXXXXX)
readonly context_runtime_root
chown 993:991 "$context_runtime_root"
chmod 0700 "$context_runtime_root"
mkdir -m 0700 "$context_runtime_root/home" "$context_runtime_root/config" \
    "$context_runtime_root/data"
chown 993:991 "$context_runtime_root/home" "$context_runtime_root/config" \
    "$context_runtime_root/data"
run_assertion exact_context_runtime_metadata test \
    "$(stat -c '%u:%g:%a' "$context_runtime_root")" = 993:991:700
readonly -a exact_context=(setpriv --reuid 993 --regid 991 --clear-groups --)
run_assertion exact_context_environment_access \
    "${exact_context[@]}" test -r "$environment_file"
run_assertion exact_context_fullchain_access \
    "${exact_context[@]}" test -r "$expected_active_release/tls/fullchain.pem"
run_assertion exact_context_private_key_access \
    "${exact_context[@]}" test -r "$expected_active_release/tls/privkey.pem"
run_assertion exact_context_caddy_validate run_probe exact_context_caddy_validate \
    "$probe_root" "${exact_context[@]}" /usr/bin/env \
    HOME="$context_runtime_root/home" XDG_CONFIG_HOME="$context_runtime_root/config" \
    XDG_DATA_HOME="$context_runtime_root/data" /bin/bash -c \
    'set -a; source /etc/default/caddy-ha; set +a; exec /usr/bin/caddy validate --config /etc/caddy/current/Caddyfile --adapter caddyfile'
run_assertion exact_context_curl run_probe exact_context_curl "$probe_root" \
    "${exact_context[@]}" /usr/bin/curl --insecure --head --fail --silent \
    --show-error --max-time 3 https://localhost
run_assertion exact_context_full_helper run_probe exact_context_full_helper "$probe_root" \
    "${exact_context[@]}" /bin/bash "$health_script"
rm -rf -- "$context_runtime_root"
run_assertion exact_context_runtime_cleanup test ! -e "$context_runtime_root"
run_assertion health_helper_transient_residue_absent test -z \
    "$(find /tmp -mindepth 1 -maxdepth 1 -name 'caddy-health.*' -print -quit 2>/dev/null)"
run_assertion notification_script_regular test -f "$notification_script"
run_assertion notification_script_not_symlink test ! -L "$notification_script"
run_assertion notification_script_metadata_exact test \
    "$(stat -c '%U:%G:%a' "$notification_script" 2>/dev/null || true)" = root:root:755
run_assertion notification_script_hash_exact test \
    "$(file_hash "$notification_script" 2>/dev/null || true)" = \
    "$expected_notification_sha256"

backup_count=$(find "$rollback_root" -mindepth 1 -maxdepth 1 -type d \
    -name 'action19e-node-a-keepalived-fragment.*' -printf '.' 2>/dev/null | wc -c)
readonly backup_count
readonly backup_manifest=$expected_backup_path/manifest
run_assertion backup_count_one test "$backup_count" -eq 1
run_assertion backup_directory_regular test -d "$expected_backup_path"
run_assertion backup_directory_not_symlink test ! -L "$expected_backup_path"
run_assertion backup_directory_metadata_exact test \
    "$(stat -c '%U:%G:%a' "$expected_backup_path" 2>/dev/null || true)" = root:root:700
run_assertion backup_manifest_regular test -f "$backup_manifest"
run_assertion backup_manifest_not_symlink test ! -L "$backup_manifest"
run_assertion backup_manifest_metadata_exact test \
    "$(stat -c '%U:%G:%a' "$backup_manifest" 2>/dev/null || true)" = root:root:600
run_assertion backup_manifest_line_count_exact test \
    "$(awk 'END { print NR }' "$backup_manifest" 2>/dev/null || true)" -eq 6
run_assertion backup_manifest_action_exact test \
    "$(grep -Fxc 'action=action19e' "$backup_manifest" 2>/dev/null || true)" -eq 1
run_assertion backup_manifest_node_exact test \
    "$(grep -Fxc 'node=node-a' "$backup_manifest" 2>/dev/null || true)" -eq 1
run_assertion backup_manifest_fragment_pre_state_exact test \
    "$(grep -Fxc 'fragment_pre_state=absent' "$backup_manifest" 2>/dev/null || true)" -eq 1
run_assertion backup_manifest_directory_pre_state_supported test \
    "$(grep -Ec '^fragment_directory_preexisting=(true|false)$' "$backup_manifest" 2>/dev/null || true)" -eq 1
run_assertion backup_manifest_main_hash_exact test \
    "$(grep -Fxc "main_configuration_sha256=$main_sha256" "$backup_manifest" 2>/dev/null || true)" -eq 1
run_assertion backup_manifest_candidate_hash_exact test \
    "$(grep -Fxc "fragment_candidate_sha256=$expected_action19e_fragment_sha256" "$backup_manifest" 2>/dev/null || true)" -eq 1

action20c_backup_count=$(find "$rollback_root" -mindepth 1 -maxdepth 1 -type d \
    -name 'action20c-node-a-health-context.*' -printf '.' 2>/dev/null | wc -c)
readonly action20c_backup_count
readonly action20c_backup_manifest=$expected_health_backup_path/manifest
readonly action20c_backup_helper=$expected_health_backup_path/check-caddy.sh
run_assertion action20c_backup_count_one test "$action20c_backup_count" -eq 1
run_assertion action20c_backup_directory_regular test -d "$expected_health_backup_path"
run_assertion action20c_backup_directory_not_symlink test ! -L "$expected_health_backup_path"
run_assertion action20c_backup_directory_metadata_exact test \
    "$(stat -c '%U:%G:%a' "$expected_health_backup_path" 2>/dev/null || true)" = root:root:700
run_assertion action20c_backup_helper_regular test -f "$action20c_backup_helper"
run_assertion action20c_backup_helper_not_symlink test ! -L "$action20c_backup_helper"
run_assertion action20c_backup_helper_metadata_exact test \
    "$(stat -c '%U:%G:%a' "$action20c_backup_helper" 2>/dev/null || true)" = root:root:600
run_assertion action20c_backup_helper_hash_exact test \
    "$(file_hash "$action20c_backup_helper" 2>/dev/null || true)" = \
    "$expected_old_health_sha256"
run_assertion action20c_backup_manifest_regular test -f "$action20c_backup_manifest"
run_assertion action20c_backup_manifest_not_symlink test ! -L "$action20c_backup_manifest"
run_assertion action20c_backup_manifest_metadata_exact test \
    "$(stat -c '%U:%G:%a' "$action20c_backup_manifest" 2>/dev/null || true)" = root:root:600
run_assertion action20c_backup_manifest_line_count_exact test \
    "$(awk 'END { print NR }' "$action20c_backup_manifest" 2>/dev/null || true)" -eq 4
run_assertion action20c_backup_manifest_action_exact test \
    "$(grep -Fxc 'action=action20c' "$action20c_backup_manifest" 2>/dev/null || true)" -eq 1
run_assertion action20c_backup_manifest_node_exact test \
    "$(grep -Fxc 'node=node-a' "$action20c_backup_manifest" 2>/dev/null || true)" -eq 1
run_assertion action20c_backup_manifest_old_hash_exact test \
    "$(grep -Fxc "old_health_sha256=$expected_old_health_sha256" "$action20c_backup_manifest" 2>/dev/null || true)" -eq 1
run_assertion action20c_backup_manifest_candidate_hash_exact test \
    "$(grep -Fxc "candidate_sha256=$expected_health_sha256" "$action20c_backup_manifest" 2>/dev/null || true)" -eq 1

action20c_run_stage_count=$(find /run -mindepth 1 -maxdepth 1 -type d \
    -name 'caddy-action20c-*' -printf '.' 2>/dev/null | wc -c)
readonly action20c_run_stage_count
action20c_tmp_stage_count=$(find /tmp -mindepth 1 -maxdepth 1 -type d \
    -name 'caddy-action20c-*' ! -path "$work_directory" -printf '.' 2>/dev/null | wc -c)
readonly action20c_tmp_stage_count
run_assertion action20c_run_stage_count_zero test "$action20c_run_stage_count" -eq 0
run_assertion action20c_tmp_stage_count_zero test "$action20c_tmp_stage_count" -eq 0
run_assertion action20c_install_stage_absent test -z \
    "$(find /usr/local/libexec -mindepth 1 -maxdepth 1 \
        -name '.check-caddy.action20c.*' -print -quit 2>/dev/null)"

action20f_backup_count=$(find "$rollback_root" -mindepth 1 -maxdepth 1 -type d \
    -name 'action20f-node-a-health-group.*' -printf '.' 2>/dev/null | wc -c)
readonly action20f_backup_count
readonly action20f_backup_manifest=$expected_group_backup_path/manifest
readonly action20f_backup_fragment=$expected_group_backup_path/caddy-ha.conf
run_assertion action20f_backup_count_one test "$action20f_backup_count" -eq 1
run_assertion action20f_backup_directory_regular test -d "$expected_group_backup_path"
run_assertion action20f_backup_directory_not_symlink test ! -L "$expected_group_backup_path"
run_assertion action20f_backup_directory_metadata_exact test \
    "$(stat -c '%U:%G:%a' "$expected_group_backup_path" 2>/dev/null || true)" = root:root:700
run_assertion action20f_backup_fragment_regular test -f "$action20f_backup_fragment"
run_assertion action20f_backup_fragment_not_symlink test ! -L "$action20f_backup_fragment"
run_assertion action20f_backup_fragment_metadata_exact test \
    "$(stat -c '%U:%G:%a' "$action20f_backup_fragment" 2>/dev/null || true)" = root:root:600
run_assertion action20f_backup_fragment_hash_exact test \
    "$(file_hash "$action20f_backup_fragment" 2>/dev/null || true)" = \
    "$expected_action19e_fragment_sha256"
run_assertion action20f_backup_manifest_regular test -f "$action20f_backup_manifest"
run_assertion action20f_backup_manifest_not_symlink test ! -L "$action20f_backup_manifest"
run_assertion action20f_backup_manifest_metadata_exact test \
    "$(stat -c '%U:%G:%a' "$action20f_backup_manifest" 2>/dev/null || true)" = root:root:600
run_assertion action20f_backup_manifest_line_count_exact test \
    "$(awk 'END { print NR }' "$action20f_backup_manifest" 2>/dev/null || true)" -eq 5
run_assertion action20f_backup_manifest_action_exact test \
    "$(grep -Fxc 'action=action20f' "$action20f_backup_manifest" 2>/dev/null || true)" -eq 1
run_assertion action20f_backup_manifest_node_exact test \
    "$(grep -Fxc 'node=node-a' "$action20f_backup_manifest" 2>/dev/null || true)" -eq 1
run_assertion action20f_backup_manifest_old_hash_exact test \
    "$(grep -Fxc "old_fragment_sha256=$expected_action19e_fragment_sha256" "$action20f_backup_manifest" 2>/dev/null || true)" -eq 1
run_assertion action20f_backup_manifest_candidate_hash_exact test \
    "$(grep -Fxc "candidate_fragment_sha256=$expected_fragment_sha256" "$action20f_backup_manifest" 2>/dev/null || true)" -eq 1
run_assertion action20f_backup_manifest_main_hash_exact test \
    "$(grep -Fxc "main_sha256=$expected_main_sha256" "$action20f_backup_manifest" 2>/dev/null || true)" -eq 1
action20f_run_stage_count=$(find /run -mindepth 1 -maxdepth 1 -type d \
    -name 'caddy-action20f-stage.*' -printf '.' 2>/dev/null | wc -c)
readonly action20f_run_stage_count
action20f_tmp_stage_count=$(find /tmp -mindepth 1 -maxdepth 1 -type d \
    -name 'caddy-action20f-*' ! -path "$work_directory" -printf '.' 2>/dev/null | wc -c)
readonly action20f_tmp_stage_count
run_assertion action20f_run_stage_count_zero test "$action20f_run_stage_count" -eq 0
run_assertion action20f_tmp_stage_count_zero test "$action20f_tmp_stage_count" -eq 0
run_assertion action20f_install_stage_absent test -z \
    "$(find /etc/keepalived/conf.d -mindepth 1 -maxdepth 1 \
        -name '.caddy-ha.action20f.*' -print -quit 2>/dev/null)"

action19e_run_stage_count=$(find /run -mindepth 1 -maxdepth 1 -type d \
    -name 'caddy-action19e-stage.*' -printf '.' 2>/dev/null | wc -c)
readonly action19e_run_stage_count
action19e_tmp_stage_count=$(find /tmp -mindepth 1 -maxdepth 1 -type d \
    -name 'caddy-action19e-*' ! -path "$work_directory" -printf '.' 2>/dev/null | wc -c)
readonly action19e_tmp_stage_count
run_assertion action19e_run_stage_count_zero test "$action19e_run_stage_count" -eq 0
run_assertion action19e_tmp_stage_count_zero test "$action19e_tmp_stage_count" -eq 0
run_assertion action19e_install_stage_absent test -z \
    "$(find /etc/keepalived/conf.d -mindepth 1 -maxdepth 1 \
        -name '.caddy-ha.conf.action19e.*' -print -quit 2>/dev/null)"
run_assertion keepalived_active test "$(systemctl is-active keepalived.service)" = active
run_assertion keepalived_enabled test "$(systemctl is-enabled keepalived.service)" = enabled
run_assertion caddy_active test "$(systemctl is-active caddy.service)" = active
run_assertion lighttpd_active test "$(systemctl is-active lighttpd.service)" = active
run_assertion lsyncd_inactive test "$(systemctl is-active lsyncd.service || true)" = inactive
run_assertion lsyncd_masked test "$(systemctl is-enabled lsyncd.service || true)" = masked
run_assertion caddy_lsyncd_inactive test \
    "$(systemctl is-active caddy-lsyncd.service || true)" = inactive
run_assertion caddy_lsyncd_disabled test \
    "$(systemctl is-enabled caddy-lsyncd.service || true)" = disabled
run_assertion reconcile_path_inactive test \
    "$(systemctl is-active caddy-sync-reconcile.path || true)" = inactive
run_assertion reconcile_service_inactive test \
    "$(systemctl is-active caddy-sync-reconcile.service || true)" = inactive
run_assertion current_link_exact test "$(readlink /etc/caddy/current)" = "$expected_active_release"
run_assertion current_target_exact test "$(readlink -f /etc/caddy/current)" = "$expected_active_release"
caddy_ipv4_vip_count=$(address_count 4 "$vip_ipv4_cidr")
readonly caddy_ipv4_vip_count
caddy_ipv6_vip_count=$(address_count 6 "$vip_ipv6_cidr")
readonly caddy_ipv6_vip_count
dns_ipv4_vip_count=$(address_count 4 10.1.0.55/22)
readonly dns_ipv4_vip_count
dns_ipv6_vip_count=$(address_count 6 fd36:5aa8:6971:1::55/128)
readonly dns_ipv6_vip_count
run_assertion caddy_ipv4_vip_absent test "$caddy_ipv4_vip_count" -eq 0
run_assertion caddy_ipv6_vip_absent test "$caddy_ipv6_vip_count" -eq 0
run_assertion dns_ipv4_vip_count_supported test "$dns_ipv4_vip_count" -ge 0
run_assertion dns_ipv6_vip_count_supported test "$dns_ipv6_vip_count" -ge 0
run_assertion dns_vip_dualstack_coherent test "$dns_ipv4_vip_count" -eq "$dns_ipv6_vip_count"

run_assertion before_state_status_zero test "$before_status" -eq 0
run_assertion before_state_stderr_empty test ! -s "$before_stderr"
# The child Bash expands its positional parameter.
# shellcheck disable=SC2016
run_assertion before_state_hash_format bash -c '[[ "$1" =~ ^[0-9a-f]{64}$ ]]' \
    _ "$before_state_sha256"

property_index=0
for unit_name in "${continuity_units[@]}"; do
    unit_label=${unit_name//[-.]/_}
    for property_index in "${!common_properties[@]}"; do
        property_value=$(unit_property "${common_properties[$property_index]}" "$unit_name")
        run_assertion "service_${unit_label}_${common_property_labels[$property_index]}_observed" \
            test -n "$property_value"
    done
    if [[ "$unit_name" == *.service ]]; then
        for property_index in "${!service_properties[@]}"; do
            property_value=$(unit_property "${service_properties[$property_index]}" "$unit_name")
            run_assertion "service_${unit_label}_${service_property_labels[$property_index]}_observed" \
                test -n "$property_value"
        done
    fi
done

after_status=0
snapshot_state >"$after_stdout" 2>"$after_stderr" || after_status=$?
readonly after_status
after_state_sha256=$(file_hash "$after_stdout")
readonly after_state_sha256
run_assertion after_state_status_zero test "$after_status" -eq 0
run_assertion after_state_stderr_empty test ! -s "$after_stderr"
# The child Bash expands its positional parameter.
# shellcheck disable=SC2016
run_assertion after_state_hash_format bash -c '[[ "$1" =~ ^[0-9a-f]{64}$ ]]' \
    _ "$after_state_sha256"
run_assertion state_unchanged test "$before_state_sha256" = "$after_state_sha256"

expected_assertion_count=$(expected_assertions | wc -l)
readonly expected_assertion_count
# The runner independently reconciles the emitted transcript against the exact
# exported producer inventory. This inspector reports its own derived totals.
printf '%s_value_expected_assertion_count=%s\n' "$prefix" "$expected_assertion_count"
printf '%s_value_backup_path=%s\n' "$prefix" "$expected_backup_path"
printf '%s_value_backup_count=%s\n' "$prefix" "$backup_count"
printf '%s_value_health_backup_path=%s\n' "$prefix" "$expected_health_backup_path"
printf '%s_value_health_backup_count=%s\n' "$prefix" "$action20c_backup_count"
printf '%s_value_group_backup_path=%s\n' "$prefix" "$expected_group_backup_path"
printf '%s_value_group_backup_count=%s\n' "$prefix" "$action20f_backup_count"
printf '%s_value_health_sha256=%s\n' "$prefix" \
    "$(file_hash "$health_script" 2>/dev/null || true)"
printf '%s_value_main_sha256=%s\n' "$prefix" "$main_sha256"
printf '%s_value_fragment_sha256=%s\n' "$prefix" \
    "$(file_hash "$fragment" 2>/dev/null || true)"
printf '%s_value_before_state_sha256=%s\n' "$prefix" "$before_state_sha256"
printf '%s_value_after_state_sha256=%s\n' "$prefix" "$after_state_sha256"
printf '%s_assertion_count=%s\n' "$prefix" "$expected_assertion_count"
printf '%s_failed_assertion_count=%s\n' "$prefix" "$failed_count"
printf '%s_first_failure=%s\n' "$prefix" "$first_failure"
printf '%s_helper_execution=true\n' "$prefix"
printf '%s_exact_context_uid=993\n' "$prefix"
printf '%s_exact_context_gid=991\n' "$prefix"
printf '%s_exact_context_supplementary_groups=cleared\n' "$prefix"
printf '%s_exact_context_validation=true\n' "$prefix"
printf '%s_filesystem_mutations=false\n' "$prefix"
printf '%s_service_mutations=false\n' "$prefix"
printf '%s_vrrp_mutations=false\n' "$prefix"
printf '%s_vip_mutations=false\n' "$prefix"
printf '%s_persistent_mutations=false\n' "$prefix"
printf '%s_remote_complete=true\n' "$prefix"

if [[ "$failed_count" -eq 0 ]]; then exit 0; fi
exit 1
