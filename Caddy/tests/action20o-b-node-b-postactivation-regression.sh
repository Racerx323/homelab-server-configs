#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
readonly caddy_root=${test_directory%/tests}
readonly inspector=$caddy_root/scripts/inspect-node-b-keepalived-dbus-postactivation-action20o-b.sh
readonly outer=$caddy_root/scripts/run-node-b-keepalived-dbus-postactivation-action20o-b-outer.sh
readonly collision_checker=$test_directory/check-shell-readonly-local-collisions-v2.sh
readonly state_hash=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa

record_check() {
    local action20ob_regression_check_label=$1

    shift
    if "$@"; then
        printf 'action_20o_b_regression_check_%s=true\n' "$action20ob_regression_check_label"
        return 0
    fi
    printf 'action_20o_b_regression_check_%s=false\n' "$action20ob_regression_check_label" >&2
    return 1
}

fixture() {
    local action20ob_regression_mode=${1:-success}
    local action20ob_regression_label
    local action20ob_regression_first=true
    local action20ob_regression_check_count

    action20ob_regression_check_count=$("$inspector" --expected-checks | wc -l) || return 1
    while IFS= read -r action20ob_regression_label; do
        if [[ "$action20ob_regression_mode" = missing && "$action20ob_regression_label" = identity_root ]]; then
            continue
        fi
        if [[ "$action20ob_regression_mode" = reordered && "$action20ob_regression_first" = true ]]; then
            action20ob_regression_first=false
            continue
        fi
        if [[ "$action20ob_regression_mode" = false_label &&
            "$action20ob_regression_label" = dbus_ipv4_state_backup_before ]]; then
            printf 'action_20o_b_check_%s=false\n' "$action20ob_regression_label"
        else
            printf 'action_20o_b_check_%s=true\n' "$action20ob_regression_label"
        fi
    done < <("$inspector" --expected-checks)
    if [[ "$action20ob_regression_mode" = reordered ]]; then
        printf 'action_20o_b_check_identity_root=true\n'
    fi
    if [[ "$action20ob_regression_mode" = duplicate ]]; then
        printf 'action_20o_b_check_identity_root=true\n'
    fi
    for action20ob_regression_observation in \
        ip4_before ip6_before dbus_list_before dbus_tree_before \
        dbus_ipv4_state_before dbus_ipv6_state_before ip4_after ip6_after \
        dbus_list_after dbus_tree_after dbus_ipv4_state_after dbus_ipv6_state_after; do
        action20ob_regression_status=0
        if [[ "$action20ob_regression_mode" = query_failure &&
            "$action20ob_regression_observation" = dbus_tree_before ]]; then
            action20ob_regression_status=1
        fi
        printf 'action_20o_b_observation_%s_status=%s\n' \
            "$action20ob_regression_observation" "$action20ob_regression_status"
        printf 'action_20o_b_observation_%s_classification=bounded_safe\n' \
            "$action20ob_regression_observation"
    done
    printf '%s\n' \
        "action_20o_b_value_expected_check_count=$action20ob_regression_check_count" \
        'action_20o_b_value_main_sha256=5480e6994994b65b0a498f42cb7943b5de86958416732a44983e341a93db1393' \
        'action_20o_b_value_fragment_sha256=0dd8ec0a5410bcd3c41db0d3fed74cf8bd75978f09b01a797468dd6266b4b518' \
        'action_20o_b_value_health_sha256=5cb42ba05b36fecd0c0cf5bc649741661b847e8f8dce94a19288d21874d87fb3' \
        'action_20o_b_value_dbus_service=org.keepalived.Vrrp1'
    if [[ "$action20ob_regression_mode" = altered_object ]]; then
        printf '%s\n' \
            'action_20o_b_value_dbus_ipv4_object=/org/keepalived/Vrrp1/Instance/eth0/999/IPv4'
    else
        printf '%s\n' \
            'action_20o_b_value_dbus_ipv4_object=/org/keepalived/Vrrp1/Instance/eth0/110/IPv4'
    fi
    printf '%s\n' \
        'action_20o_b_value_dbus_ipv6_object=/org/keepalived/Vrrp1/Instance/eth0/111/IPv6' \
        'action_20o_b_value_dbus_state=Backup' \
        'action_20o_b_value_dbus_snapshot_normalization=process_column_busctl_only' \
        "action_20o_b_value_before_state_sha256=$state_hash"
    if [[ "$action20ob_regression_mode" = changed_state ]]; then
        printf 'action_20o_b_value_after_state_sha256=%064d\n' 0
    else
        printf 'action_20o_b_value_after_state_sha256=%s\n' "$state_hash"
    fi
    printf '%s\n' "action_20o_b_check_count=$action20ob_regression_check_count"
    if [[ "$action20ob_regression_mode" = false_label ]]; then
        printf '%s\n' 'action_20o_b_failed_check_count=1' \
            'action_20o_b_first_failure=dbus_ipv4_state_backup_before'
    else
        printf '%s\n' 'action_20o_b_failed_check_count=0' 'action_20o_b_first_failure=none'
    fi
    printf '%s\n' \
        'action_20o_b_read_only=true' \
        'action_20o_b_health_helpers_invoked=false' \
        'action_20o_b_keepalived_reload=false' \
        'action_20o_b_keepalived_restart=false' \
        'action_20o_b_filesystem_mutations=false' \
        'action_20o_b_service_mutations=false' \
        'action_20o_b_vrrp_mutations=false' \
        'action_20o_b_vip_mutations=false' \
        'action_20o_b_remote_complete=true'
}
expect_rejected() {
    local action20ob_regression_mode=$1
    local action20ob_regression_fixture=$2

    fixture "$action20ob_regression_mode" >"$action20ob_regression_fixture"
    if /bin/bash "$outer" --validate-transcript "$action20ob_regression_fixture"; then
        printf 'action_20o_b_regression_unexpected_acceptance=%s\n' "$action20ob_regression_mode" >&2
        return 1
    fi
}
production_path_test() {
    local action20ob_regression_root=$1
    local action20ob_regression_fixture=$action20ob_regression_root/fixture
    local action20ob_regression_status=0

    fixture success >"$action20ob_regression_fixture"
    cat >"$action20ob_regression_root/ssh" <<'MOCK'
#!/usr/bin/env bash
set -Eeuo pipefail
[[ "$#" -eq 7 ]] || exit 91
[[ "$1" = -T && "$2" = -o && "$3" = BatchMode=yes ]] || exit 92
[[ "$4" = -o && "$5" = ConnectTimeout=10 ]] || exit 93
[[ "$6" = pi@10.1.0.54 ]] || exit 94
[[ "$7" = 'cd / && sudo -n /bin/bash -s --' ]] || exit 95
payload_hash=$(sha256sum | awk '{ print $1 }')
[[ "$payload_hash" = "$ACTION20OB_EXPECTED_INSPECTOR_SHA256" ]] || exit 96
if [[ "${ACTION20OB_SSH_MODE:-success}" = nonzero ]]; then
    printf 'bounded remote failure\n' >&2
    exit 23
fi
cat "$ACTION20OB_FIXTURE"
if [[ "${ACTION20OB_SSH_MODE:-success}" = stderr ]]; then
    printf 'unexpected bounded stderr\n' >&2
fi
MOCK
    chmod 0755 "$action20ob_regression_root/ssh"
    CADDY_ACTION20OB_SSH_BIN=$action20ob_regression_root/ssh \
        ACTION20OB_FIXTURE=$action20ob_regression_fixture \
        ACTION20OB_EXPECTED_INSPECTOR_SHA256=$(sha256sum "$inspector" | awk '{ print $1 }') \
        /bin/bash "$outer" --transport-test >"$action20ob_regression_root/stdout" \
        2>"$action20ob_regression_root/stderr" || action20ob_regression_status=$?
    [[ "$action20ob_regression_status" -eq 0 ]] || return 1
    [[ ! -s "$action20ob_regression_root/stderr" ]] || return 1
    grep -Fqx 'action_20o_b_outer_complete=true' "$action20ob_regression_root/stdout" || return 1
    grep -Fqx 'action_20o_b_outer_node_b_contacted=true' "$action20ob_regression_root/stdout" || return 1
    grep -Fqx 'action_20o_b_outer_node_a_ssh_contacted=false' "$action20ob_regression_root/stdout" || return 1
    if CADDY_ACTION20OB_SSH_BIN=$action20ob_regression_root/ssh \
        ACTION20OB_FIXTURE=$action20ob_regression_fixture \
        ACTION20OB_EXPECTED_INSPECTOR_SHA256=$(sha256sum "$inspector" | awk '{ print $1 }') \
        ACTION20OB_SSH_MODE=nonzero /bin/bash "$outer" --transport-test \
        >"$action20ob_regression_root/nonzero.stdout" 2>"$action20ob_regression_root/nonzero.stderr"; then
        return 1
    fi
    if CADDY_ACTION20OB_SSH_BIN=$action20ob_regression_root/ssh \
        ACTION20OB_FIXTURE=$action20ob_regression_fixture \
        ACTION20OB_EXPECTED_INSPECTOR_SHA256=$(sha256sum "$inspector" | awk '{ print $1 }') \
        ACTION20OB_SSH_MODE=stderr /bin/bash "$outer" --transport-test \
        >"$action20ob_regression_root/stderr.stdout" 2>"$action20ob_regression_root/stderr.stderr"; then
        return 1
    fi
}
collision_negative_test() {
    local action20ob_regression_root=$1

    # The dollar-prefixed name is literal fixture source.
    # shellcheck disable=SC2016
    printf '%s\n' \
        '#!/usr/bin/env bash' \
        'readonly action20ob_collision=value' \
        'collision_function() {' \
        '    local action20ob_collision=other' \
        '    printf '\''%s\n'\'' "$action20ob_collision"' \
        '}' >"$action20ob_regression_root/collision.sh"
    if /bin/bash "$collision_checker" "$action20ob_regression_root/collision.sh" >/dev/null 2>&1; then
        return 1
    fi
}

regression_root=$(mktemp -d /tmp/caddy-action20o-b-regression.XXXXXX)
readonly regression_root
trap 'rm -rf -- "$regression_root"' EXIT INT TERM

record_check production_path production_path_test "$regression_root" || exit 1
for regression_mode in false_label missing duplicate reordered query_failure altered_object changed_state; do
    record_check "${regression_mode}_rejected" expect_rejected \
        "$regression_mode" "$regression_root/$regression_mode.fixture" || exit 1
done
record_check collision_negative collision_negative_test "$regression_root" || exit 1

printf '%s\n' \
    action_20o_b_regression_positive_production_path=true \
    action_20o_b_regression_false_label_rejected=true \
    action_20o_b_regression_missing_label_rejected=true \
    action_20o_b_regression_duplicate_label_rejected=true \
    action_20o_b_regression_reordered_label_rejected=true \
    action_20o_b_regression_query_failure_rejected=true \
    action_20o_b_regression_altered_object_rejected=true \
    action_20o_b_regression_changed_state_rejected=true \
    action_20o_b_regression_nonzero_status_rejected=true \
    action_20o_b_regression_stderr_rejected=true \
    action_20o_b_regression_dynamic_scope_collision_rejected=true \
    action_20o_b_regression_complete=true
