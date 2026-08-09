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
readonly inspector=$caddy_root/scripts/inspect-dual-node-keepalived-post-action20p-a.sh
readonly outer=$caddy_root/scripts/run-dual-node-keepalived-post-action20p-a-outer.sh
readonly collision_checker=$test_directory/check-shell-readonly-local-collisions-v2.sh
readonly state_hash=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa

record_check() {
    local action20pa_regression_label=$1

    shift
    if "$@"; then
        printf 'action_20p_a_regression_check_%s=true\n' "$action20pa_regression_label"
        return 0
    fi
    printf 'action_20p_a_regression_check_%s=false\n' "$action20pa_regression_label" >&2
    return 1
}
fixture() {
    local action20pa_regression_role=$1
    local action20pa_regression_mode=${2:-success}
    local action20pa_regression_node_label=${action20pa_regression_role//-/_}
    local action20pa_regression_prefix=action_20p_a_${action20pa_regression_node_label}
    local action20pa_regression_label
    local action20pa_regression_first=true
    local action20pa_regression_main
    local action20pa_regression_fragment
    local action20pa_regression_state
    local action20pa_regression_count
    local action20pa_regression_check_count

    action20pa_regression_check_count=$("$inspector" --expected-checks | wc -l) || return 1
    case "$action20pa_regression_role" in
        node-a)
            action20pa_regression_main=8fc9dcf8e079b7131f86a58038ae5543804a5158a02d53a4614452de212ce47c
            action20pa_regression_fragment=8117510587c79fa597ebd5e48da6ab4be8d8dfef6740d57b9b327037b70830be
            action20pa_regression_state=Master
            action20pa_regression_count=1
            ;;
        node-b)
            action20pa_regression_main=5480e6994994b65b0a498f42cb7943b5de86958416732a44983e341a93db1393
            action20pa_regression_fragment=0dd8ec0a5410bcd3c41db0d3fed74cf8bd75978f09b01a797468dd6266b4b518
            action20pa_regression_state=Backup
            action20pa_regression_count=0
            ;;
        *) return 1 ;;
    esac
    while IFS= read -r action20pa_regression_label; do
        if [[ "$action20pa_regression_mode" = missing && "$action20pa_regression_label" = identity_root ]]; then
            continue
        fi
        if [[ "$action20pa_regression_mode" = reordered && "$action20pa_regression_first" = true ]]; then
            action20pa_regression_first=false
            continue
        fi
        if [[ "$action20pa_regression_mode" = false_label &&
            "$action20pa_regression_label" = journal_ipv6_ttl_hl_quiet ]]; then
            printf '%s_check_%s=false\n' "$action20pa_regression_prefix" "$action20pa_regression_label"
        else
            printf '%s_check_%s=true\n' "$action20pa_regression_prefix" "$action20pa_regression_label"
        fi
    done < <("$inspector" --expected-checks)
    if [[ "$action20pa_regression_mode" = reordered ]]; then
        printf '%s_check_identity_root=true\n' "$action20pa_regression_prefix"
    fi
    if [[ "$action20pa_regression_mode" = duplicate ]]; then
        printf '%s_check_identity_root=true\n' "$action20pa_regression_prefix"
    fi
    printf '%s\n' \
        "${action20pa_regression_prefix}_observation_ttl_hl_quiet_window_status=0" \
        "${action20pa_regression_prefix}_observation_ttl_hl_quiet_window_classification=bounded_safe" \
        "${action20pa_regression_prefix}_value_expected_check_count=$action20pa_regression_check_count" \
        "${action20pa_regression_prefix}_value_main_sha256=$action20pa_regression_main" \
        "${action20pa_regression_prefix}_value_fragment_sha256=$action20pa_regression_fragment" \
        "${action20pa_regression_prefix}_value_health_sha256=5cb42ba05b36fecd0c0cf5bc649741661b847e8f8dce94a19288d21874d87fb3"
    if [[ "$action20pa_regression_mode" = altered_state ]]; then
        printf '%s_value_dbus_state=FAULT\n' "$action20pa_regression_prefix"
    else
        printf '%s_value_dbus_state=%s\n' "$action20pa_regression_prefix" "$action20pa_regression_state"
    fi
    printf '%s\n' \
        "${action20pa_regression_prefix}_value_caddy_ipv4_count=$action20pa_regression_count" \
        "${action20pa_regression_prefix}_value_caddy_ipv6_count=$action20pa_regression_count" \
        "${action20pa_regression_prefix}_value_before_state_sha256=$state_hash"
    if [[ "$action20pa_regression_mode" = changed_snapshot ]]; then
        printf '%s_value_after_state_sha256=%064d\n' "$action20pa_regression_prefix" 0
    else
        printf '%s_value_after_state_sha256=%s\n' "$action20pa_regression_prefix" "$state_hash"
    fi
    printf '%s_check_count=%s\n' "$action20pa_regression_prefix" "$action20pa_regression_check_count"
    if [[ "$action20pa_regression_mode" = false_label ]]; then
        printf '%s_failed_check_count=1\n' "$action20pa_regression_prefix"
        printf '%s_first_failure=journal_ipv6_ttl_hl_quiet\n' "$action20pa_regression_prefix"
    else
        printf '%s_failed_check_count=0\n' "$action20pa_regression_prefix"
        printf '%s_first_failure=none\n' "$action20pa_regression_prefix"
    fi
    printf '%s\n' \
        "${action20pa_regression_prefix}_read_only=true" \
        "${action20pa_regression_prefix}_keepalived_reload=false" \
        "${action20pa_regression_prefix}_keepalived_restart=false" \
        "${action20pa_regression_prefix}_filesystem_mutations=false" \
        "${action20pa_regression_prefix}_service_mutations=false" \
        "${action20pa_regression_prefix}_vrrp_mutations=false" \
        "${action20pa_regression_prefix}_vip_mutations=false" \
        "${action20pa_regression_prefix}_remote_complete=true"
}
expect_rejected() {
    local action20pa_regression_role=$1
    local action20pa_regression_mode=$2
    local action20pa_regression_fixture=$3

    fixture "$action20pa_regression_role" "$action20pa_regression_mode" >"$action20pa_regression_fixture" || return 1
    if /bin/bash "$outer" --validate-transcript "$action20pa_regression_fixture" "$action20pa_regression_role"; then
        return 1
    fi
}
production_path_test() {
    local action20pa_regression_work_root=$1
    local action20pa_regression_status=0

    fixture node-a success >"$action20pa_regression_work_root/node-a.fixture" || return 1
    fixture node-b success >"$action20pa_regression_work_root/node-b.fixture" || return 1
    cat >"$action20pa_regression_work_root/ssh" <<'MOCK'
#!/usr/bin/env bash
set -Eeuo pipefail
[[ "$#" -eq 7 ]] || exit 91
[[ "$1" = -T && "$2" = -o && "$3" = BatchMode=yes ]] || exit 92
[[ "$4" = -o && "$5" = ConnectTimeout=10 ]] || exit 93
payload_hash=$(sha256sum | awk '{ print $1 }')
[[ "$payload_hash" = "$ACTION20PA_EXPECTED_INSPECTOR_SHA256" ]] || exit 94
case "$6:$7" in
    'pi@10.1.0.53:cd / && sudo -n /bin/bash -s -- --node node-a') fixture=$ACTION20PA_NODE_A_FIXTURE ;;
    'pi@10.1.0.54:cd / && sudo -n /bin/bash -s -- --node node-b') fixture=$ACTION20PA_NODE_B_FIXTURE ;;
    *) exit 95 ;;
esac
if [[ "${ACTION20PA_SSH_MODE:-success}" = nonzero && "$6" = pi@10.1.0.53 ]]; then
    printf 'bounded remote failure\n' >&2
    exit 23
fi
cat "$fixture"
if [[ "${ACTION20PA_SSH_MODE:-success}" = stderr && "$6" = pi@10.1.0.54 ]]; then
    printf 'unexpected bounded stderr\n' >&2
fi
MOCK
    chmod 0755 "$action20pa_regression_work_root/ssh" || return 1
    CADDY_ACTION20PA_SSH_BIN=$action20pa_regression_work_root/ssh \
        ACTION20PA_NODE_A_FIXTURE=$action20pa_regression_work_root/node-a.fixture \
        ACTION20PA_NODE_B_FIXTURE=$action20pa_regression_work_root/node-b.fixture \
        ACTION20PA_EXPECTED_INSPECTOR_SHA256=$(sha256sum "$inspector" | awk '{ print $1 }') \
        /bin/bash "$outer" --transport-test >"$action20pa_regression_work_root/stdout" \
        2>"$action20pa_regression_work_root/stderr" || action20pa_regression_status=$?
    [[ "$action20pa_regression_status" -eq 0 ]] || return 1
    [[ ! -s "$action20pa_regression_work_root/stderr" ]] || return 1
    grep -Fqx 'action_20p_a_outer_complete=true' "$action20pa_regression_work_root/stdout" || return 1
    grep -Fqx 'action_20p_a_outer_single_caddy_ipv4_owner=true' "$action20pa_regression_work_root/stdout" || return 1
    grep -Fqx 'action_20p_a_outer_single_caddy_ipv6_owner=true' "$action20pa_regression_work_root/stdout" || return 1
    if CADDY_ACTION20PA_SSH_BIN=$action20pa_regression_work_root/ssh \
        ACTION20PA_NODE_A_FIXTURE=$action20pa_regression_work_root/node-a.fixture \
        ACTION20PA_NODE_B_FIXTURE=$action20pa_regression_work_root/node-b.fixture \
        ACTION20PA_EXPECTED_INSPECTOR_SHA256=$(sha256sum "$inspector" | awk '{ print $1 }') \
        ACTION20PA_SSH_MODE=nonzero /bin/bash "$outer" --transport-test \
        >"$action20pa_regression_work_root/nonzero.stdout" 2>"$action20pa_regression_work_root/nonzero.stderr"; then
        return 1
    fi
    if CADDY_ACTION20PA_SSH_BIN=$action20pa_regression_work_root/ssh \
        ACTION20PA_NODE_A_FIXTURE=$action20pa_regression_work_root/node-a.fixture \
        ACTION20PA_NODE_B_FIXTURE=$action20pa_regression_work_root/node-b.fixture \
        ACTION20PA_EXPECTED_INSPECTOR_SHA256=$(sha256sum "$inspector" | awk '{ print $1 }') \
        ACTION20PA_SSH_MODE=stderr /bin/bash "$outer" --transport-test \
        >"$action20pa_regression_work_root/stderr.stdout" 2>"$action20pa_regression_work_root/stderr.stderr"; then
        return 1
    fi
}
collision_negative_test() {
    local action20pa_regression_collision_root=$1

    # The dollar-prefixed name is literal fixture source.
    # shellcheck disable=SC2016
    printf '%s\n' \
        '#!/usr/bin/env bash' \
        'readonly action20pa_collision=value' \
        'collision_function() {' \
        '    local action20pa_collision=other' \
        '    printf '\''%s\n'\'' "$action20pa_collision"' \
        '}' >"$action20pa_regression_collision_root/collision.sh" || return 1
    if /bin/bash "$collision_checker" "$action20pa_regression_collision_root/collision.sh" >/dev/null 2>&1; then
        return 1
    fi
}

action20pa_regression_root=$(mktemp -d /tmp/caddy-action20p-a-regression.XXXXXX)
readonly action20pa_regression_root
trap 'rm -rf -- "$action20pa_regression_root"' EXIT INT TERM

record_check production_path production_path_test "$action20pa_regression_root" || exit 1
for action20pa_regression_mode in false_label missing duplicate reordered altered_state changed_snapshot; do
    record_check "node_a_${action20pa_regression_mode}_rejected" expect_rejected node-a \
        "$action20pa_regression_mode" "$action20pa_regression_root/node-a-$action20pa_regression_mode.fixture" || exit 1
    record_check "node_b_${action20pa_regression_mode}_rejected" expect_rejected node-b \
        "$action20pa_regression_mode" "$action20pa_regression_root/node-b-$action20pa_regression_mode.fixture" || exit 1
done
record_check collision_negative collision_negative_test "$action20pa_regression_root" || exit 1

printf '%s\n' \
    action_20p_a_regression_positive_production_path=true \
    action_20p_a_regression_both_node_transcripts_exact=true \
    action_20p_a_regression_false_labels_rejected=true \
    action_20p_a_regression_missing_labels_rejected=true \
    action_20p_a_regression_duplicate_labels_rejected=true \
    action_20p_a_regression_reordered_labels_rejected=true \
    action_20p_a_regression_altered_states_rejected=true \
    action_20p_a_regression_changed_snapshots_rejected=true \
    action_20p_a_regression_nonzero_status_rejected=true \
    action_20p_a_regression_stderr_rejected=true \
    action_20p_a_regression_dynamic_scope_collision_rejected=true \
    action_20p_a_regression_complete=true
