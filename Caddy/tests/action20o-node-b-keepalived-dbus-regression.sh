#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_20o_regression

test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
readonly caddy_root=${test_directory%/tests}
readonly transaction=$caddy_root/scripts/activate-node-b-keepalived-dbus-action20o.sh
readonly outer=$caddy_root/scripts/run-node-b-keepalived-dbus-action20o-outer.sh

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }
record_check() {
    local action20o_regression_label=$1

    shift
    if "$@" >/dev/null; then
        printf '%s_check_%s=true\n' "$prefix" "$action20o_regression_label"
        return 0
    fi
    printf '%s_check_%s=false\n' "$prefix" "$action20o_regression_label" >&2
    return 1
}
write_success_fixture() {
    local action20o_regression_fixture=$1
    local action20o_regression_check
    local action20o_regression_capture

    : >"$action20o_regression_fixture"
    while IFS= read -r action20o_regression_check; do
        printf 'action_20o_check_%s=true\n' "$action20o_regression_check" >>"$action20o_regression_fixture"
    done < <(/bin/bash "$transaction" --expected-checks)
    {
        for action20o_regression_capture in reload reload_journal dbus_list dbus_tree dbus_ipv4_state dbus_ipv6_state; do
            printf 'action_20o_capture_%s_stdout_classification=bounded_safe\n' "$action20o_regression_capture"
            printf 'action_20o_capture_%s_stderr_classification=bounded_safe\n' "$action20o_regression_capture"
            printf 'action_20o_capture_%s_status=0\n' "$action20o_regression_capture"
        done
    } >>"$action20o_regression_fixture"
    printf '%s\n' \
        'action_20o_value_expected_check_count=77' \
        'action_20o_value_main_sha256=5480e6994994b65b0a498f42cb7943b5de86958416732a44983e341a93db1393' \
        'action_20o_value_rollback_main_sha256=8b260315628888c937c6f7eaf21f63e73eb52cfd9cd6e9c0d9d90fa9cf9fbd3f' \
        'action_20o_value_dbus_service=org.keepalived.Vrrp1' \
        'action_20o_value_before_main_pid=1234' \
        'action_20o_value_after_main_pid=1234' \
        'action_20o_check_count=77' \
        'action_20o_failed_check_count=0' \
        'action_20o_first_failure=none' \
        'action_20o_keepalived_reload=true' \
        'action_20o_keepalived_restart=false' \
        'action_20o_dbus_runtime_active=true' \
        'action_20o_filesystem_mutation=false' \
        'action_20o_vrrp_transition=false' \
        'action_20o_vip_mutation=false' \
        'action_20o_node_a_ssh_contacted=false' \
        'action_20o_node_a_continuity_verified=true' \
        'action_20o_complete=true' >>"$action20o_regression_fixture"
}
run_outer() {
    local action20o_regression_fixture=$1
    local action20o_regression_stderr_fixture=$2
    local action20o_regression_remote_status=$3
    local action20o_regression_stdout=$4
    local action20o_regression_stderr=$5
    local action20o_regression_skip_local_gates=${6:-0}

    CADDY_ACTION20O_TEST_MODE=1 \
        CADDY_ACTION20O_SSH_BIN=$mock_ssh \
        CADDY_ACTION20O_MOCK_STDOUT=$action20o_regression_fixture \
        CADDY_ACTION20O_MOCK_STDERR=$action20o_regression_stderr_fixture \
        CADDY_ACTION20O_MOCK_STATUS=$action20o_regression_remote_status \
        CADDY_ACTION20O_MOCK_PAYLOAD_HASH=$transaction_sha256 \
        CADDY_ACTION20O_TEST_SKIP_LOCAL_GATES=$action20o_regression_skip_local_gates \
        /bin/bash "$outer" >"$action20o_regression_stdout" \
        2>"$action20o_regression_stderr"
}
must_reject() {
    local action20o_regression_fixture=$1
    local action20o_regression_stderr_fixture=$2
    local action20o_regression_remote_status=$3

    if run_outer "$action20o_regression_fixture" "$action20o_regression_stderr_fixture" \
        "$action20o_regression_remote_status" "$case_stdout" "$case_stderr" 1; then
        return 1
    fi
}

regression_root=$(mktemp -d /tmp/caddy-action20o-regression.XXXXXX)
readonly regression_root
trap 'rm -rf -- "$regression_root"' EXIT
readonly mock_ssh=$regression_root/ssh
transaction_sha256=$(file_hash "$transaction")
readonly transaction_sha256
readonly success_fixture=$regression_root/success.stdout
readonly empty_stderr=$regression_root/empty.stderr
readonly positive_stdout=$regression_root/positive.outer.stdout
readonly positive_stderr=$regression_root/positive.outer.stderr
readonly case_stdout=$regression_root/case.outer.stdout
readonly case_stderr=$regression_root/case.outer.stderr

# The generated mock expands these expressions when it runs.
# shellcheck disable=SC2016
printf '%s\n' \
    '#!/usr/bin/env bash' \
    'set -Eeuo pipefail' \
    '[[ "${!#}" = "cd / && sudo -n /bin/bash -s --" ]] || exit 71' \
    'payload=$(mktemp /tmp/caddy-action20o-mock-payload.XXXXXX)' \
    'trap '\''rm -f -- "$payload"'\'' EXIT' \
    'cat >"$payload"' \
    '[[ "$(sha256sum "$payload" | awk '\''{ print $1 }'\'')" = "$CADDY_ACTION20O_MOCK_PAYLOAD_HASH" ]] || exit 72' \
    'cat "$CADDY_ACTION20O_MOCK_STDOUT"' \
    'cat "$CADDY_ACTION20O_MOCK_STDERR" >&2' \
    'exit "$CADDY_ACTION20O_MOCK_STATUS"' >"$mock_ssh"
chmod 0755 "$mock_ssh"

write_success_fixture "$success_fixture"
: >"$empty_stderr"

record_check transaction_expected_count test "$(/bin/bash "$transaction" --expected-checks | wc -l)" -eq 77
record_check transaction_unique_labels test "$(/bin/bash "$transaction" --expected-checks | LC_ALL=C sort -u | wc -l)" -eq 77
record_check outer_exact_remote_command grep -Fq "'cd / && sudo -n /bin/bash -s --'" "$outer"
# This assertion searches for a literal production expression.
# shellcheck disable=SC2016
record_check outer_streams_exact_transaction grep -Fq '<"$transaction"' "$outer"
record_check outer_node_b_target grep -Fq 'readonly expected_target=pi@10.1.0.54' "$outer"
if run_outer "$success_fixture" "$empty_stderr" 0 "$positive_stdout" "$positive_stderr" 0; then
    printf '%s_check_positive_production_path=true\n' "$prefix"
else
    printf '%s_check_positive_production_path=false\n' "$prefix" >&2
    printf '%s_positive_outer_stdout_begin\n' "$prefix" >&2
    sed "s/^/${prefix}_positive_outer_stdout_content=/" "$positive_stdout" >&2
    printf '%s_positive_outer_stdout_end\n' "$prefix" >&2
    printf '%s_positive_outer_stderr_begin\n' "$prefix" >&2
    sed "s/^/${prefix}_positive_outer_stderr_content=/" "$positive_stderr" >&2
    printf '%s_positive_outer_stderr_end\n' "$prefix" >&2
    exit 1
fi
record_check positive_stderr_empty test ! -s "$positive_stderr"
record_check positive_complete grep -Fqx 'action_20o_outer_complete=true' "$positive_stdout"
record_check positive_node_b_contact grep -Fqx 'action_20o_outer_node_b_contacted=true' "$positive_stdout"
record_check positive_node_a_ssh_absent grep -Fqx 'action_20o_outer_node_a_ssh_contacted=false' "$positive_stdout"

false_fixture=$regression_root/false.stdout
sed '0,/action_20o_check_dbus_service_present_after=true/s//action_20o_check_dbus_service_present_after=false/' "$success_fixture" >"$false_fixture"
record_check false_assertion_rejected must_reject "$false_fixture" "$empty_stderr" 0

missing_fixture=$regression_root/missing.stdout
sed '/action_20o_check_dbus_tree_ipv6_object=true/d' "$success_fixture" >"$missing_fixture"
record_check missing_assertion_rejected must_reject "$missing_fixture" "$empty_stderr" 0

duplicate_fixture=$regression_root/duplicate.stdout
cp "$success_fixture" "$duplicate_fixture"
printf 'action_20o_check_dbus_tree_ipv6_object=true\n' >>"$duplicate_fixture"
record_check duplicate_assertion_rejected must_reject "$duplicate_fixture" "$empty_stderr" 0

reordered_fixture=$regression_root/reordered.stdout
awk 'NR == 1 { first=$0; next } NR == 2 { print; print first; next } { print }' "$success_fixture" >"$reordered_fixture"
record_check reordered_assertion_rejected must_reject "$reordered_fixture" "$empty_stderr" 0

changed_hash_fixture=$regression_root/changed-hash.stdout
sed 's/5480e6994994b65b0a498f42cb7943b5de86958416732a44983e341a93db1393/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/' "$success_fixture" >"$changed_hash_fixture"
record_check changed_hash_rejected must_reject "$changed_hash_fixture" "$empty_stderr" 0

missing_capture_fixture=$regression_root/missing-capture.stdout
sed '/action_20o_capture_dbus_ipv6_state_status=0/d' "$success_fixture" >"$missing_capture_fixture"
record_check missing_capture_rejected must_reject "$missing_capture_fixture" "$empty_stderr" 0

rollback_fixture=$regression_root/rollback.stdout
cp "$success_fixture" "$rollback_fixture"
printf 'action_20o_rollback_started=true\n' >>"$rollback_fixture"
record_check rollback_on_success_rejected must_reject "$rollback_fixture" "$empty_stderr" 0

unsafe_stderr=$regression_root/unsafe.stderr
printf 'unexpected remote stderr\n' >"$unsafe_stderr"
record_check remote_stderr_rejected must_reject "$success_fixture" "$unsafe_stderr" 0
record_check nonzero_status_rejected must_reject "$success_fixture" "$empty_stderr" 1

printf '%s_complete=true\n' "$prefix"
