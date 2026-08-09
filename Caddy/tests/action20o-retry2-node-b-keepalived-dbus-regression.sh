#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_20o_retry2_regression

test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
readonly caddy_root=${test_directory%/tests}
readonly collision_checker=$test_directory/check-shell-readonly-local-collisions-v2.sh
readonly transaction=$caddy_root/scripts/activate-node-b-keepalived-dbus-action20o-retry2.sh
readonly outer=$caddy_root/scripts/run-node-b-keepalived-dbus-action20o-retry2-outer.sh

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }
record_check() {
    local action20o_retry2_regression_label=$1

    shift
    if "$@" >/dev/null; then
        printf '%s_check_%s=true\n' "$prefix" "$action20o_retry2_regression_label"
        return 0
    fi
    printf '%s_check_%s=false\n' "$prefix" "$action20o_retry2_regression_label" >&2
    return 1
}
write_success_fixture() {
    local action20o_retry2_fixture=$1
    local action20o_retry2_check
    local action20o_retry2_capture

    : >"$action20o_retry2_fixture"
    while IFS= read -r action20o_retry2_check; do
        printf 'action_20o_retry2_check_%s=true\n' "$action20o_retry2_check" >>"$action20o_retry2_fixture"
    done < <(/bin/bash "$transaction" --expected-checks)
    # Each iteration appends a distinct capture contract.
    # shellcheck disable=SC2129
    for action20o_retry2_capture in candidate_install candidate_rename reload reload_journal dbus_list dbus_tree dbus_ipv4_state dbus_ipv6_state; do
        printf 'action_20o_retry2_capture_%s_stdout_classification=bounded_safe\n' "$action20o_retry2_capture" >>"$action20o_retry2_fixture"
        printf 'action_20o_retry2_capture_%s_stderr_classification=bounded_safe\n' "$action20o_retry2_capture" >>"$action20o_retry2_fixture"
        printf 'action_20o_retry2_capture_%s_status=0\n' "$action20o_retry2_capture" >>"$action20o_retry2_fixture"
    done
    printf '%s\n' \
        'action_20o_retry2_value_expected_check_count=99' \
        'action_20o_retry2_value_main_sha256=8b260315628888c937c6f7eaf21f63e73eb52cfd9cd6e9c0d9d90fa9cf9fbd3f' \
        'action_20o_retry2_value_candidate_sha256=5480e6994994b65b0a498f42cb7943b5de86958416732a44983e341a93db1393' \
        'action_20o_retry2_value_rollback_main_sha256=8b260315628888c937c6f7eaf21f63e73eb52cfd9cd6e9c0d9d90fa9cf9fbd3f' \
        'action_20o_retry2_value_dbus_service=org.keepalived.Vrrp1' \
        'action_20o_retry2_value_before_main_pid=1234' \
        'action_20o_retry2_value_after_main_pid=1234' \
        'action_20o_retry2_check_count=99' \
        'action_20o_retry2_failed_check_count=0' \
        'action_20o_retry2_first_failure=none' \
        'action_20o_retry2_keepalived_reload=true' \
        'action_20o_retry2_keepalived_restart=false' \
        'action_20o_retry2_dbus_runtime_active=true' \
        'action_20o_retry2_filesystem_mutation=true' \
        'action_20o_retry2_vrrp_transition=false' \
        'action_20o_retry2_vip_mutation=false' \
        'action_20o_retry2_node_a_ssh_contacted=false' \
        'action_20o_retry2_node_a_continuity_verified=true' \
        'action_20o_retry2_complete=true' >>"$action20o_retry2_fixture"
}
run_outer() {
    local action20o_retry2_fixture=$1
    local action20o_retry2_stderr_fixture=$2
    local action20o_retry2_remote_status=$3
    local action20o_retry2_stdout=$4
    local action20o_retry2_stderr=$5

    CADDY_ACTION20O_TEST_MODE=1 \
        CADDY_ACTION20O_SSH_BIN=$mock_ssh \
        CADDY_ACTION20O_SOURCE_PATH=$source_fixture \
        CADDY_ACTION20O_MOCK_STDOUT=$action20o_retry2_fixture \
        CADDY_ACTION20O_MOCK_STDERR=$action20o_retry2_stderr_fixture \
        CADDY_ACTION20O_MOCK_STATUS=$action20o_retry2_remote_status \
        CADDY_ACTION20O_TEST_SKIP_LOCAL_GATES=1 \
        /bin/bash "$outer" >"$action20o_retry2_stdout" 2>"$action20o_retry2_stderr"
}
must_reject() {
    local action20o_retry2_fixture=$1
    local action20o_retry2_stderr_fixture=$2
    local action20o_retry2_remote_status=$3

    if run_outer "$action20o_retry2_fixture" "$action20o_retry2_stderr_fixture" \
        "$action20o_retry2_remote_status" "$case_stdout" "$case_stderr"; then
        return 1
    fi
}

regression_root=$(mktemp -d /tmp/caddy-action20o-retry2-regression.XXXXXX)
readonly regression_root
trap 'rm -rf -- "$regression_root"' EXIT
readonly mock_ssh=$regression_root/ssh
readonly source_fixture=$regression_root/keepalived-pihole00.conf
readonly success_fixture=$regression_root/success.stdout
readonly empty_stderr=$regression_root/empty.stderr
readonly positive_stdout=$regression_root/positive.outer.stdout
readonly positive_stderr=$regression_root/positive.outer.stderr
readonly case_stdout=$regression_root/case.outer.stdout
readonly case_stderr=$regression_root/case.outer.stderr
readonly collision_fixture=$regression_root/collision.sh
readonly collision_stdout=$regression_root/collision.stdout
readonly collision_stderr=$regression_root/collision.stderr

# The dollar-prefixed name is literal fixture source.
# shellcheck disable=SC2016
printf '%s\n' \
    '#!/usr/bin/env bash' \
    'readonly action20o_retry2_collision=value' \
    'collision() {' \
    '    local action20o_retry2_collision=other' \
    '    printf '\''%s\n'\'' "$action20o_retry2_collision"' \
    '}' >"$collision_fixture"
collision_status=0
/bin/bash "$collision_checker" "$collision_fixture" \
    >"$collision_stdout" 2>"$collision_stderr" || collision_status=$?
readonly collision_status
record_check dynamic_scope_collision_rejected test "$collision_status" -eq 1
record_check dynamic_scope_collision_labeled grep -Fq 'readonly_local_collision=' "$collision_stderr"
record_check collision_policy_clean /bin/bash "$collision_checker" "$transaction" "$outer" "$0"
record_check early_invalid_later_valid_rejected /bin/bash "$transaction" --self-test

# The quoted lines are the generated mock and expand only when it runs.
# shellcheck disable=SC2016
printf '%s\n' \
    '#!/usr/bin/env bash' \
    'set -Eeuo pipefail' \
    '[[ "${!#}" = "cd / && sudo -n /bin/bash -s --" ]] || exit 71' \
    'payload=$(mktemp /tmp/caddy-action20o-retry2-mock.XXXXXX)' \
    'trap '\''rm -f -- "$payload"'\'' EXIT' \
    'cat >"$payload"' \
    'grep -Fq '\''cd /'\'' "$payload" || exit 72' \
    'grep -Fq '\''ACTION20O_RETRY2_ARCHIVE'\'' "$payload" || exit 73' \
    'grep -Fq '\''/bin/bash "$bundle_stage/activate-node-b-keepalived-dbus-action20o-retry2.sh" --stage "$bundle_stage"'\'' "$payload" || exit 74' \
    'cat "$CADDY_ACTION20O_MOCK_STDOUT"' \
    'cat "$CADDY_ACTION20O_MOCK_STDERR" >&2' \
    'exit "$CADDY_ACTION20O_MOCK_STATUS"' >"$mock_ssh"
chmod 0755 "$mock_ssh"

printf '%s\n' \
    'global_defs {' \
    '    enable_dbus' \
    '}' >"$source_fixture"
write_success_fixture "$success_fixture"
: >"$empty_stderr"

record_check transaction_expected_count test "$(/bin/bash "$transaction" --expected-checks | wc -l)" -eq 99
record_check transaction_unique_labels test "$(/bin/bash "$transaction" --expected-checks | LC_ALL=C sort -u | wc -l)" -eq 99
record_check restored_main_pin grep -Fq 'expected_main_sha256=8b260315628888c937c6f7eaf21f63e73eb52cfd9cd6e9c0d9d90fa9cf9fbd3f' "$transaction"
record_check candidate_pin grep -Fq 'expected_candidate_sha256=5480e6994994b65b0a498f42cb7943b5de86958416732a44983e341a93db1393' "$transaction"
# These checks intentionally match literal production expressions.
# shellcheck disable=SC2016
record_check ipv4_query_exact grep -Fq 'ip -o "-$action20o_address_family" address show dev eth0' "$transaction"
# shellcheck disable=SC2016
record_check query_failure_propagated grep -Fq 'action20o_address_output=$(ip -o "-$action20o_address_family" address show dev eth0) || return 1' "$transaction"
# shellcheck disable=SC2016
record_check flat_tree_exact grep -Fq 'busctl --system --no-pager --list tree "$dbus_service"' "$transaction"
# shellcheck disable=SC2016
record_check exact_flat_object_match grep -Fq 'dbus_object_present "$transaction_root/dbus_tree.stdout" "$dbus_ipv4_object"' "$transaction"
record_check old_tree_absent test "$(grep -Fc 'busctl --system --no-pager tree' "$transaction" || true)" -eq 0
record_check candidate_install_present grep -Fq 'candidate_installed run_captured candidate_install install' "$transaction"
record_check candidate_rename_present grep -Fq 'candidate_renamed run_captured candidate_rename mv -fT' "$transaction"
if run_outer "$success_fixture" "$empty_stderr" 0 "$positive_stdout" "$positive_stderr"; then
    printf '%s_check_positive_production_path=true\n' "$prefix"
else
    printf '%s_check_positive_production_path=false\n' "$prefix" >&2
    exit 1
fi
record_check positive_stderr_empty test ! -s "$positive_stderr"
record_check positive_complete grep -Fqx 'action_20o_retry2_outer_complete=true' "$positive_stdout"

false_fixture=$regression_root/false.stdout
sed '0,/action_20o_retry2_check_dbus_service_present_after=true/s//action_20o_retry2_check_dbus_service_present_after=false/' "$success_fixture" >"$false_fixture"
record_check false_assertion_rejected must_reject "$false_fixture" "$empty_stderr" 0
missing_fixture=$regression_root/missing.stdout
sed '/action_20o_retry2_check_dbus_tree_ipv6_object=true/d' "$success_fixture" >"$missing_fixture"
record_check missing_assertion_rejected must_reject "$missing_fixture" "$empty_stderr" 0
duplicate_fixture=$regression_root/duplicate.stdout
cp "$success_fixture" "$duplicate_fixture"
printf 'action_20o_retry2_check_dbus_tree_ipv6_object=true\n' >>"$duplicate_fixture"
record_check duplicate_assertion_rejected must_reject "$duplicate_fixture" "$empty_stderr" 0
reordered_fixture=$regression_root/reordered.stdout
awk 'NR == 1 { first=$0; next } NR == 2 { print; print first; next } { print }' "$success_fixture" >"$reordered_fixture"
record_check reordered_assertion_rejected must_reject "$reordered_fixture" "$empty_stderr" 0
unsafe_stderr=$regression_root/unsafe.stderr
printf 'unexpected remote stderr\n' >"$unsafe_stderr"
record_check remote_stderr_rejected must_reject "$success_fixture" "$unsafe_stderr" 0
record_check nonzero_status_rejected must_reject "$success_fixture" "$empty_stderr" 1

printf '%s_complete=true\n' "$prefix"
