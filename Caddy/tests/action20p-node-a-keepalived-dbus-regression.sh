#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_20p_regression
test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
readonly caddy_root=${test_directory%/tests}
readonly transaction=$caddy_root/scripts/activate-node-a-keepalived-dbus-action20p.sh
readonly observer=$caddy_root/scripts/inspect-node-b-node-a-dbus-peer-action20p.sh
readonly outer=$caddy_root/scripts/run-node-a-keepalived-dbus-action20p-outer.sh
readonly collision_checker=$test_directory/check-shell-readonly-local-collisions-v2.sh

record_check() {
    local action20p_regression_label=$1

    shift
    if "$@"; then
        printf '%s_check_%s=true\n' "$prefix" "$action20p_regression_label"
        return 0
    fi
    printf '%s_check_%s=false\n' "$prefix" "$action20p_regression_label" >&2
    return 1
}
production_assert() {
    local action20p_regression_assertion=$1

    shift
    if "$@"; then
        printf '%s_production_assert_%s=true\n' "$prefix" "$action20p_regression_assertion"
        return 0
    fi
    printf '%s_production_assert_%s=false\n' "$prefix" "$action20p_regression_assertion" >&2
    return 1
}
observer_fixture() {
    local action20p_regression_phase=$1
    local action20p_regression_mode=${2:-success}
    local action20p_regression_label

    while IFS= read -r action20p_regression_label; do
        if [[ "$action20p_regression_mode" = false_label &&
            "$action20p_regression_label" = dbus_ipv6_state_backup ]]; then
            printf 'action_20p_peer_check_%s=false\n' "$action20p_regression_label"
        else
            printf 'action_20p_peer_check_%s=true\n' "$action20p_regression_label"
        fi
    done < <(/bin/bash "$observer" --expected-checks "$action20p_regression_phase")
    printf '%s\n' \
        "action_20p_peer_value_phase=$action20p_regression_phase" \
        'action_20p_peer_value_main_sha256=5480e6994994b65b0a498f42cb7943b5de86958416732a44983e341a93db1393' \
        'action_20p_peer_value_fragment_sha256=0dd8ec0a5410bcd3c41db0d3fed74cf8bd75978f09b01a797468dd6266b4b518' \
        'action_20p_peer_value_health_sha256=5cb42ba05b36fecd0c0cf5bc649741661b847e8f8dce94a19288d21874d87fb3' \
        "action_20p_peer_value_check_count=$(/bin/bash "$observer" --expected-checks "$action20p_regression_phase" | wc -l)" \
        'action_20p_peer_read_only=true' \
        'action_20p_peer_complete=true'
}
transaction_fixture() {
    local action20p_regression_mode=${1:-success}
    local action20p_regression_label

    while IFS= read -r action20p_regression_label; do
        if [[ "$action20p_regression_mode" = false_label &&
            "$action20p_regression_label" = dbus_ipv6_state_master ]]; then
            printf 'action_20p_check_%s=false\n' "$action20p_regression_label"
        else
            printf 'action_20p_check_%s=true\n' "$action20p_regression_label"
        fi
    done < <(/bin/bash "$transaction" --expected-checks)
    printf '%s\n' \
        'action_20p_value_main_sha256=8fc9dcf8e079b7131f86a58038ae5543804a5158a02d53a4614452de212ce47c' \
        'action_20p_value_fragment_sha256=8117510587c79fa597ebd5e48da6ab4be8d8dfef6740d57b9b327037b70830be' \
        'action_20p_value_health_sha256=5cb42ba05b36fecd0c0cf5bc649741661b847e8f8dce94a19288d21874d87fb3' \
        'action_20p_value_dbus_service=org.keepalived.Vrrp1' \
        'action_20p_value_unicast_ttl=255' \
        "action_20p_value_check_count=$(/bin/bash "$transaction" --expected-checks | wc -l)" \
        'action_20p_keepalived_reload=true' \
        'action_20p_dbus_runtime_active=true' \
        'action_20p_unicast_ttl_runtime_activation=true' \
        'action_20p_node_b_contacted=false' \
        'action_20p_complete=true'
}
production_path_test() {
    local action20p_regression_root=$1
    local action20p_regression_status=0

    cat >"$action20p_regression_root/ssh" <<'MOCK'
#!/usr/bin/env bash
set -Eeuo pipefail
[[ "$#" -eq 7 ]] || exit 91
[[ "$1" = -T && "$2" = -o && "$3" = BatchMode=yes ]] || exit 92
[[ "$4" = -o && "$5" = ConnectTimeout=10 ]] || exit 93
[[ "$7" = 'cd / && sudo -n /bin/bash -s --' ]] || exit 94
payload=$(mktemp)
trap 'rm -f -- "$payload"' EXIT INT TERM
cat >"$payload"
assignment=$(sed -n '1p' "$payload")
printf '%s|%s\n' "$6" "$assignment" >>"$ACTION20P_CALL_LOG"
case "$6|$assignment" in
    'pi@10.1.0.54|ACTION20P_PHASE=pre') cat "$ACTION20P_PRE_FIXTURE" ;;
    'pi@10.1.0.53|ACTION20P_MODE=activate') cat "$ACTION20P_TRANSACTION_FIXTURE" ;;
    'pi@10.1.0.54|ACTION20P_PHASE=post')
        if [[ "${ACTION20P_MOCK_MODE:-success}" = post_failure ]]; then
            printf 'bounded post observer failure\n' >&2
            exit 23
        fi
        cat "$ACTION20P_POST_FIXTURE"
        ;;
    'pi@10.1.0.53|ACTION20P_MODE=rollback_only')
        printf 'action_20p_rollback_only_complete=true\n'
        ;;
    *) exit 95 ;;
esac
MOCK
    chmod 0755 "$action20p_regression_root/ssh"
    observer_fixture pre >"$action20p_regression_root/pre.fixture"
    observer_fixture post >"$action20p_regression_root/post.fixture"
    transaction_fixture >"$action20p_regression_root/transaction.fixture"
    : >"$action20p_regression_root/calls"
    CADDY_ACTION20P_TEST_MODE=1 \
        CADDY_ACTION20P_SSH_BIN="$action20p_regression_root/ssh" \
        ACTION20P_PRE_FIXTURE="$action20p_regression_root/pre.fixture" \
        ACTION20P_POST_FIXTURE="$action20p_regression_root/post.fixture" \
        ACTION20P_TRANSACTION_FIXTURE="$action20p_regression_root/transaction.fixture" \
        ACTION20P_CALL_LOG="$action20p_regression_root/calls" \
        /bin/bash "$outer" --transport-test >"$action20p_regression_root/stdout" \
        2>"$action20p_regression_root/stderr" || action20p_regression_status=$?
    if [[ "$action20p_regression_status" -ne 0 ]]; then
        printf '%s_production_status=%s\n' "$prefix" "$action20p_regression_status" >&2
        sed 's/^/action_20p_regression_production_stdout=/' \
            "$action20p_regression_root/stdout" >&2
        sed 's/^/action_20p_regression_production_stderr=/' \
            "$action20p_regression_root/stderr" >&2
        return 1
    fi
    production_assert stderr_empty test ! -s "$action20p_regression_root/stderr" || return 1
    production_assert call_count test "$(wc -l <"$action20p_regression_root/calls")" -eq 3 || return 1
    production_assert ttl_active grep -Fqx \
        'action_20p_outer_node_a_unicast_ttl_active=true' \
        "$action20p_regression_root/stdout" || return 1
    production_assert peer_quiet grep -Fqx \
        'action_20p_outer_node_b_ttl_hl_quiet_window=true' \
        "$action20p_regression_root/stdout" || return 1
    production_assert rollback_absent test \
        "$(grep -Fc 'ACTION20P_MODE=rollback_only' "$action20p_regression_root/calls" || true)" -eq 0 || return 1
    production_assert rollback_mode_contract grep -Fq \
        "build_payload 'ACTION20P_MODE=rollback_only'" "$outer" || return 1
    production_assert rollback_cleanup_contract grep -Fq \
        'rollback_node_a || action20p_outer_cleanup_status=125' "$outer" || return 1
    production_assert rollback_live_guard grep -Fq \
        "if [[ \"\$node_a_activated\" = true ]]" "$outer" || return 1
}
negative_fixture_test() {
    local action20p_regression_root=$1

    observer_fixture post false_label >"$action20p_regression_root/observer-false.fixture"
    grep -Fqx 'action_20p_peer_check_dbus_ipv6_state_backup=false' \
        "$action20p_regression_root/observer-false.fixture" || return 1
    transaction_fixture false_label >"$action20p_regression_root/transaction-false.fixture"
    grep -Fqx 'action_20p_check_dbus_ipv6_state_master=false' \
        "$action20p_regression_root/transaction-false.fixture" || return 1
}
collision_negative_test() {
    local action20p_regression_root=$1

    # shellcheck disable=SC2016
    printf '%s\n' '#!/usr/bin/env bash' 'readonly collision=value' \
        'f() {' '    local collision=other' \
        '    printf '\''%s\n'\'' "$collision"' '}' \
        >"$action20p_regression_root/collision.sh"
    if /bin/bash "$collision_checker" "$action20p_regression_root/collision.sh" >/dev/null 2>&1; then
        return 1
    fi
}

regression_root=$(mktemp -d /tmp/caddy-action20p-regression.XXXXXX)
readonly regression_root
trap 'rm -rf -- "$regression_root"' EXIT INT TERM

record_check transaction_self_test /bin/bash "$transaction" --self-test
record_check observer_self_test /bin/bash "$observer" --self-test
record_check production_path production_path_test "$regression_root"
record_check false_positive_negative_fixtures negative_fixture_test "$regression_root"
record_check collision_negative collision_negative_test "$regression_root"

printf '%s_complete=true\n' "$prefix"
