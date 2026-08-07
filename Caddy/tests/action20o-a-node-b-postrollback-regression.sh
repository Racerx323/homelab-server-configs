#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
readonly caddy_root=${script_directory%/tests}
readonly inspector=$caddy_root/scripts/inspect-node-b-keepalived-dbus-postrollback-action20o-a.sh
readonly outer=$caddy_root/scripts/run-node-b-keepalived-dbus-postrollback-action20o-a-outer.sh
readonly state_hash=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa

fixture() {
    local action20oa_regression_mode=${1:-success}
    local action20oa_regression_label
    local action20oa_regression_first=true

    while IFS= read -r action20oa_regression_label; do
        if [[ "$action20oa_regression_mode" = reordered && "$action20oa_regression_first" = true ]]; then
            action20oa_regression_first=false
            continue
        fi
        if [[ "$action20oa_regression_mode" = query_failure && "$action20oa_regression_label" = ipv4_query_before_status ]]; then
            printf 'action_20o_a_check_%s=false\n' "$action20oa_regression_label"
        else
            printf 'action_20o_a_check_%s=true\n' "$action20oa_regression_label"
        fi
    done < <("$inspector" --expected-checks)
    if [[ "$action20oa_regression_mode" = reordered ]]; then
        printf 'action_20o_a_check_identity_root=true\n'
    fi
    for action20oa_regression_observation in ipv4_before ipv6_before dbus_before ipv4_after ipv6_after dbus_after; do
        action20oa_regression_status=0
        if [[ "$action20oa_regression_mode" = query_failure && "$action20oa_regression_observation" = ipv4_before ]]; then
            action20oa_regression_status=1
        fi
        printf 'action_20o_a_observation_%s_status=%s\n' "$action20oa_regression_observation" "$action20oa_regression_status"
        printf 'action_20o_a_observation_%s_classification=bounded_safe\n' "$action20oa_regression_observation"
    done
    printf '%s\n' \
        'action_20o_a_value_main_sha256=8b260315628888c937c6f7eaf21f63e73eb52cfd9cd6e9c0d9d90fa9cf9fbd3f' \
        "action_20o_a_value_before_state_sha256=$state_hash" \
        "action_20o_a_value_after_state_sha256=$state_hash" \
        'action_20o_a_check_count=63'
    if [[ "$action20oa_regression_mode" = query_failure ]]; then
        printf '%s\n' 'action_20o_a_failed_check_count=1' 'action_20o_a_first_failure=ipv4_query_before_status'
    else
        printf '%s\n' 'action_20o_a_failed_check_count=0' 'action_20o_a_first_failure=none'
    fi
    printf '%s\n' \
        'action_20o_a_read_only=true' 'action_20o_a_dbus_tree_invoked=false' \
        'action_20o_a_keepalived_reload=false' 'action_20o_a_keepalived_restart=false' \
        'action_20o_a_filesystem_mutations=false' 'action_20o_a_service_mutations=false' \
        'action_20o_a_vrrp_mutations=false' 'action_20o_a_vip_mutations=false' \
        'action_20o_a_remote_complete=true'
}
run_case() {
    local action20oa_regression_mode=$1
    local action20oa_regression_expected_status=$2
    local action20oa_regression_root
    local action20oa_regression_actual_status=0

    action20oa_regression_root=$(mktemp -d /tmp/caddy-action20o-a-regression.XXXXXX) || return 1
    trap 'rm -rf -- "$action20oa_regression_root"' RETURN
    fixture "$action20oa_regression_mode" >"$action20oa_regression_root/fixture"
    if [[ "$action20oa_regression_expected_status" -ne 0 ]]; then
        if /bin/bash "$outer" --validate-transcript "$action20oa_regression_root/fixture"; then
            return 1
        fi
        return 0
    fi
    cat >"$action20oa_regression_root/ssh" <<'MOCK'
#!/usr/bin/env bash
set -Eeuo pipefail
[[ "$#" -eq 7 ]] || exit 91
[[ "$1" = -T && "$2" = -o && "$3" = BatchMode=yes ]] || exit 92
[[ "$4" = -o && "$5" = ConnectTimeout=10 ]] || exit 93
[[ "$6" = pi@10.1.0.54 ]] || exit 94
[[ "$7" = 'cd / && sudo -n /bin/bash -s --' ]] || exit 95
payload_hash=$(sha256sum | awk '{ print $1 }')
[[ "$payload_hash" = "$ACTION20OA_EXPECTED_INSPECTOR_SHA256" ]] || exit 97
cat "$ACTION20OA_FIXTURE"
MOCK
    chmod 0755 "$action20oa_regression_root/ssh"
    CADDY_ACTION20OA_SSH_BIN=$action20oa_regression_root/ssh \
        ACTION20OA_FIXTURE=$action20oa_regression_root/fixture \
        ACTION20OA_EXPECTED_INSPECTOR_SHA256=$(sha256sum "$inspector" | awk '{ print $1 }') \
        /bin/bash "$outer" >"$action20oa_regression_root/stdout" \
        2>"$action20oa_regression_root/stderr" || action20oa_regression_actual_status=$?
    if [[ "$action20oa_regression_expected_status" = 0 ]]; then
        if [[ "$action20oa_regression_actual_status" -ne 0 ]]; then
            printf 'action_20o_a_regression_unexpected_status=%s\n' "$action20oa_regression_actual_status" >&2
            cat "$action20oa_regression_root/stdout" >&2
            cat "$action20oa_regression_root/stderr" >&2
            return 1
        fi
        if [[ -s "$action20oa_regression_root/stderr" ]]; then
            cat "$action20oa_regression_root/stderr" >&2
            return 1
        fi
        grep -Fqx 'action_20o_a_outer_complete=true' "$action20oa_regression_root/stdout" || return 1
    else
        [[ "$action20oa_regression_actual_status" -ne 0 ]] || return 1
    fi
}

run_case success 0 || exit 1
run_case query_failure 1 || exit 1
run_case reordered 1 || exit 1
printf '%s\n' \
    action_20o_a_regression_positive_path=true \
    action_20o_a_regression_query_failure_rejected=true \
    action_20o_a_regression_reordered_labels_rejected=true \
    action_20o_a_regression_complete=true
