#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_24_outer
readonly inspector_sha256=58fe5c7bd9db5c8e49a4efac400913c4aa32de36ce6d7d5257a42c77a8f914a5
readonly regression_sha256=b6173b26b48f45eb2c22e4ae7fa1a06b906b97a304abdac059380bc063468d0c
readonly accepted_local_zone_sha256=fa9f4850386ab1328f323c7c88bd9fa9ad0d5a84994b3066b6874deb5beb569c
readonly maximum_stream_bytes=2097152
readonly maximum_stream_lines=8192

script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
readonly caddy_root=${script_directory%/scripts}
readonly inspector=$script_directory/inspect-dual-node-dns-record-families-action24.sh
readonly regression=$caddy_root/tests/action24-dual-node-dns-record-families-regression.sh
readonly shfmt_canonical=$caddy_root/tests/shfmt-canonical.sh

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }
line_count() { awk 'END { print NR }' "$1"; }
valid_sha256() {
    local action24_outer_hash_value=$1

    [[ ${#action24_outer_hash_value} -eq 64 ]] || return 1
    [[ "$action24_outer_hash_value" != *[!0-9a-f]* ]]
}
working_directory_approved() {
    case "$PWD" in
        /home/aaron/code/homelab-server-configs) return 0 ;;
        /workspace/homelab-server-configs)
            [[ "${CADDY_VALIDATION_CONTAINER:-}" == 1 ]] || return 1
            return 0
            ;;
        *) return 1 ;;
    esac
}
run_gate() {
    local action24_outer_gate_label=$1

    shift
    if "$@" >/dev/null; then
        printf '%s_gate_%s=true\n' "$prefix" "$action24_outer_gate_label"
        return 0
    fi
    printf '%s_gate_%s=false\n' "$prefix" "$action24_outer_gate_label" >&2
    return 1
}
expected_local_gates() {
    printf '%s\n' \
        working_directory inspector_regular inspector_executable inspector_hash \
        regression_regular regression_executable regression_hash syntax shellcheck \
        canonical_format collision_policy conditional_policy output_evidence_policy \
        scalar_grep_policy portable_awk_policy remote_cwd_policy read_only_contract \
        inspector_node_a_self_test inspector_node_b_self_test regression
}
read_only_contract() {
    ! grep -Eq \
        'systemctl[[:space:]]+(start|stop|restart|reload|enable|disable|mask|unmask)|unbound-control[[:space:]]+reload|pihole[[:space:]]+restartdns|(^|[[:space:]])(install|mv|rm)[[:space:]]' \
        "$inspector"
}
run_local_gates() {
    local action24_outer_skip_regression=$1

    run_gate working_directory working_directory_approved || return 1
    run_gate inspector_regular test -f "$inspector" || return 1
    run_gate inspector_executable test -x "$inspector" || return 1
    run_gate inspector_hash test "$(file_hash "$inspector")" = "$inspector_sha256" || return 1
    run_gate regression_regular test -f "$regression" || return 1
    run_gate regression_executable test -x "$regression" || return 1
    run_gate regression_hash test "$(file_hash "$regression")" = "$regression_sha256" || return 1
    run_gate syntax /bin/bash -n "$inspector" "$regression" "$0" || return 1
    run_gate shellcheck shellcheck "$inspector" "$regression" "$0" || return 1
    run_gate canonical_format /bin/bash "$shfmt_canonical" --check "$inspector" "$regression" "$0" || return 1
    run_gate collision_policy /bin/bash "$caddy_root/tests/check-shell-readonly-local-collisions-v2.sh" "$inspector" "$regression" "$0" || return 1
    run_gate conditional_policy /bin/bash "$caddy_root/tests/conditional-validator-errexit-policy-regression.sh" || return 1
    run_gate output_evidence_policy /bin/bash "$caddy_root/tests/transaction-output-evidence-policy-regression.sh" || return 1
    run_gate scalar_grep_policy /bin/bash "$caddy_root/tests/multifile-grep-count-policy.sh" --check "$inspector" "$regression" "$0" || return 1
    run_gate portable_awk_policy /bin/bash "$caddy_root/tests/portable-awk-policy.sh" --check "$inspector" "$regression" "$0" || return 1
    run_gate remote_cwd_policy /bin/bash "$caddy_root/tests/remote-streamed-bash-cwd-policy.sh" --check "$0" || return 1
    run_gate read_only_contract read_only_contract || return 1
    run_gate inspector_node_a_self_test /bin/bash "$inspector" --self-test-node node-a || return 1
    run_gate inspector_node_b_self_test /bin/bash "$inspector" --self-test-node node-b || return 1
    if [[ "$action24_outer_skip_regression" == true ]]; then
        run_gate regression test "$action24_outer_skip_regression" == true || return 1
    else
        run_gate regression /bin/bash "$regression" || return 1
    fi
}
safe_stream() {
    local action24_outer_stream=$1

    [[ "$(wc -c <"$action24_outer_stream")" -le "$maximum_stream_bytes" ]] || return 1
    [[ "$(line_count "$action24_outer_stream")" -le "$maximum_stream_lines" ]] || return 1
    ! LC_ALL=C grep -n '[^[:print:][:space:]]' "$action24_outer_stream" >/dev/null || return 1
    ! grep -Eqi \
        'BEGIN [A-Z ]*PRIVATE KEY|CADDY_TLS_PRIVATE_KEY_PEM|PRIVATE_KEY=|DOPPLER_TOKEN|Authorization:[[:space:]]*Bearer' \
        "$action24_outer_stream"
}
emit_stream() {
    local action24_outer_label=$1
    local action24_outer_stream=$2

    printf '%s_%s_bytes=%s\n' "$prefix" "$action24_outer_label" "$(wc -c <"$action24_outer_stream")"
    printf '%s_%s_lines=%s\n' "$prefix" "$action24_outer_label" "$(line_count "$action24_outer_stream")"
    printf '%s_%s_sha256=%s\n' "$prefix" "$action24_outer_label" "$(file_hash "$action24_outer_stream")"
    if safe_stream "$action24_outer_stream"; then
        printf '%s_%s_classification=bounded_safe\n' "$prefix" "$action24_outer_label"
        if [[ -s "$action24_outer_stream" ]]; then
            printf '%s_%s_begin\n' "$prefix" "$action24_outer_label"
            cat "$action24_outer_stream"
            printf '%s_%s_end\n' "$prefix" "$action24_outer_label"
        else
            printf '%s_%s_content=empty\n' "$prefix" "$action24_outer_label"
        fi
        return 0
    fi
    printf '%s_%s_classification=unsafe_retained\n' "$prefix" "$action24_outer_label" >&2
    return 97
}
require_one() {
    local action24_outer_line=$1
    local action24_outer_transcript=$2

    [[ "$(grep -Fxc "$action24_outer_line" "$action24_outer_transcript" || true)" -eq 1 ]]
}
validate_assert() {
    local action24_outer_assertion_label=$1

    shift
    if "$@"; then
        printf '%s_validation_%s=true\n' "$prefix" "$action24_outer_assertion_label"
        return 0
    fi
    printf '%s_validation_%s=false\n' "$prefix" "$action24_outer_assertion_label" >&2
    return 1
}
validate_node() {
    local action24_outer_role=$1
    local action24_outer_token=$2
    local action24_outer_expected_vrrp=$3
    local action24_outer_stdout=$4
    local action24_outer_stderr=$5
    local action24_outer_status=$6
    local action24_outer_expected=$7
    local action24_outer_actual=$8
    local action24_outer_expected_count
    local action24_outer_before_state
    local action24_outer_after_state

    /bin/bash "$inspector" --expected-checks "$action24_outer_role" >"$action24_outer_expected" || return 1
    sed -n "s/^action_24_${action24_outer_token}_check_\\([a-z0-9_]*\\)=true$/\\1/p" \
        "$action24_outer_stdout" >"$action24_outer_actual" || return 1
    action24_outer_expected_count=$(line_count "$action24_outer_expected") || return 1
    validate_assert "${action24_outer_token}_status_zero" test "$action24_outer_status" -eq 0 || return 1
    validate_assert "${action24_outer_token}_stderr_empty" test ! -s "$action24_outer_stderr" || return 1
    validate_assert "${action24_outer_token}_expected_count_positive" test "$action24_outer_expected_count" -gt 0 || return 1
    validate_assert "${action24_outer_token}_expected_count_unique" test \
        "$(LC_ALL=C sort -u "$action24_outer_expected" | wc -l)" -eq "$action24_outer_expected_count" || return 1
    validate_assert "${action24_outer_token}_actual_count_exact" test \
        "$(line_count "$action24_outer_actual")" -eq "$action24_outer_expected_count" || return 1
    validate_assert "${action24_outer_token}_actual_count_unique" test \
        "$(LC_ALL=C sort -u "$action24_outer_actual" | wc -l)" -eq "$action24_outer_expected_count" || return 1
    validate_assert "${action24_outer_token}_ordered_checks" diff -u "$action24_outer_expected" "$action24_outer_actual" || return 1
    validate_assert "${action24_outer_token}_false_checks_absent" test \
        "$(grep -Ec "^action_24_${action24_outer_token}_check_[a-z0-9_]+=false$" "$action24_outer_stdout" || true)" -eq 0 || return 1
    validate_assert "${action24_outer_token}_check_count" require_one \
        "action_24_${action24_outer_token}_check_count=$action24_outer_expected_count" "$action24_outer_stdout" || return 1
    validate_assert "${action24_outer_token}_local_zone_hash" require_one \
        "action_24_${action24_outer_token}_value_local_zone_sha256=$accepted_local_zone_sha256" "$action24_outer_stdout" || return 1
    validate_assert "${action24_outer_token}_vrrp_state" require_one \
        "action_24_${action24_outer_token}_value_vrrp_state=$action24_outer_expected_vrrp" "$action24_outer_stdout" || return 1
    for action24_outer_marker in filesystem_mutation service_mutation dns_mutation peer_ssh; do
        validate_assert "${action24_outer_token}_${action24_outer_marker}_false" require_one \
            "action_24_${action24_outer_token}_${action24_outer_marker}=false" "$action24_outer_stdout" || return 1
    done
    validate_assert "${action24_outer_token}_remote_complete" require_one \
        "action_24_${action24_outer_token}_remote_complete=true" "$action24_outer_stdout" || return 1
    action24_outer_before_state=$(sed -n "s/^action_24_${action24_outer_token}_value_before_state_sha256=//p" "$action24_outer_stdout") || return 1
    action24_outer_after_state=$(sed -n "s/^action_24_${action24_outer_token}_value_after_state_sha256=//p" "$action24_outer_stdout") || return 1
    validate_assert "${action24_outer_token}_before_state_valid" valid_sha256 "$action24_outer_before_state" || return 1
    validate_assert "${action24_outer_token}_after_state_valid" valid_sha256 "$action24_outer_after_state" || return 1
    validate_assert "${action24_outer_token}_state_unchanged" test \
        "$action24_outer_before_state" = "$action24_outer_after_state" || return 1
}
run_node() {
    local action24_outer_role=$1
    local action24_outer_target=$2
    local action24_outer_alias=$3
    local action24_outer_stdout=$4
    local action24_outer_stderr=$5
    local action24_outer_status_name=$6
    local action24_outer_ssh=${CADDY_ACTION24_SSH_BIN:-/usr/bin/ssh}

    if [[ "${CADDY_ACTION24_TEST_MODE:-}" == 1 ]]; then
        "$action24_outer_ssh" "$action24_outer_target" "$action24_outer_role" \
            <"$inspector" >"$action24_outer_stdout" 2>"$action24_outer_stderr" ||
            printf -v "$action24_outer_status_name" '%s' "$?"
        return 0
    fi
    "$action24_outer_ssh" -T -o BatchMode=yes -o ConnectTimeout=5 \
        -o "HostKeyAlias=$action24_outer_alias" -o StrictHostKeyChecking=yes \
        "$action24_outer_target" 'cd / && sudo -n /bin/bash -s -- --node' "$action24_outer_role" \
        <"$inspector" >"$action24_outer_stdout" 2>"$action24_outer_stderr" ||
        printf -v "$action24_outer_status_name" '%s' "$?"
}
run_action() (
    local action24_outer_node_a_status=0
    local action24_outer_node_b_status=0
    local action24_outer_root
    local action24_outer_skip_regression=false

    action24_outer_root=$(mktemp -d /tmp/caddy-action24-outer.XXXXXX) || return 1
    trap 'rm -rf -- "$action24_outer_root"' EXIT INT TERM
    for action24_outer_capture in node-a.stdout node-a.stderr node-b.stdout node-b.stderr node-a.expected node-a.actual node-b.expected node-b.actual; do
        install -m 0600 /dev/null "$action24_outer_root/$action24_outer_capture" || return 1
    done
    if [[ "${CADDY_ACTION24_TEST_MODE:-}" == 1 ]]; then
        action24_outer_skip_regression=true
    fi
    run_local_gates "$action24_outer_skip_regression" || return 1
    run_node node-a pi@10.1.0.53 pihole0.local.theama.co \
        "$action24_outer_root/node-a.stdout" "$action24_outer_root/node-a.stderr" action24_outer_node_a_status || return 1
    emit_stream node_a_stdout "$action24_outer_root/node-a.stdout" || return $?
    emit_stream node_a_stderr "$action24_outer_root/node-a.stderr" || return $?
    validate_node node-a node_a MASTER "$action24_outer_root/node-a.stdout" \
        "$action24_outer_root/node-a.stderr" "$action24_outer_node_a_status" \
        "$action24_outer_root/node-a.expected" "$action24_outer_root/node-a.actual" || return 1
    run_node node-b pi@10.1.0.54 pihole00.local.theama.co \
        "$action24_outer_root/node-b.stdout" "$action24_outer_root/node-b.stderr" action24_outer_node_b_status || return 1
    emit_stream node_b_stdout "$action24_outer_root/node-b.stdout" || return $?
    emit_stream node_b_stderr "$action24_outer_root/node-b.stderr" || return $?
    validate_node node-b node_b BACKUP "$action24_outer_root/node-b.stdout" \
        "$action24_outer_root/node-b.stderr" "$action24_outer_node_b_status" \
        "$action24_outer_root/node-b.expected" "$action24_outer_root/node-b.actual" || return 1
    printf '%s_node_a_contacted=true\n' "$prefix"
    printf '%s_node_b_contacted=true\n' "$prefix"
    printf '%s_read_only=true\n' "$prefix"
    printf '%s_dns_mutation=false\n' "$prefix"
    printf '%s_service_mutation=false\n' "$prefix"
    printf '%s_complete=true\n' "$prefix"
)
self_test() (
    local action24_outer_root

    action24_outer_root=$(mktemp -d /tmp/caddy-action24-self-test.XXXXXX) || return 1
    trap 'rm -rf -- "$action24_outer_root"' EXIT INT TERM
    run_local_gates true || return 1
    printf '%s_node_a_contacted=false\n' "$prefix"
    printf '%s_node_b_contacted=false\n' "$prefix"
    printf '%s_self_test_complete=true\n' "$prefix"
)
validate_fixture() (
    local action24_outer_fixture_role=$1
    local action24_outer_fixture_stdout=$2
    local action24_outer_fixture_stderr=$3
    local action24_outer_fixture_status=$4
    local action24_outer_fixture_token
    local action24_outer_fixture_vrrp
    local action24_outer_fixture_root

    case "$action24_outer_fixture_role" in
        node-a)
            action24_outer_fixture_token=node_a
            action24_outer_fixture_vrrp=MASTER
            ;;
        node-b)
            action24_outer_fixture_token=node_b
            action24_outer_fixture_vrrp=BACKUP
            ;;
        *) return 64 ;;
    esac
    action24_outer_fixture_root=$(mktemp -d /tmp/caddy-action24-fixture.XXXXXX) || return 1
    trap 'rm -rf -- "$action24_outer_fixture_root"' EXIT INT TERM
    validate_node "$action24_outer_fixture_role" "$action24_outer_fixture_token" \
        "$action24_outer_fixture_vrrp" "$action24_outer_fixture_stdout" \
        "$action24_outer_fixture_stderr" "$action24_outer_fixture_status" \
        "$action24_outer_fixture_root/expected" "$action24_outer_fixture_root/actual"
)

case "${1:-}" in
    --self-test) self_test ;;
    --expected-local-gates) expected_local_gates ;;
    --validate-fixture) validate_fixture "${2:-}" "${3:-}" "${4:-}" "${5:-}" ;;
    '') run_action ;;
    *) exit 64 ;;
esac
