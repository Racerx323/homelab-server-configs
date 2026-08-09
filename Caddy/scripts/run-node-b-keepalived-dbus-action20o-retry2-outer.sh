#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_20o_retry2_outer
readonly expected_target=pi@10.1.0.54
readonly expected_host_alias=10.1.0.54
readonly expected_main_sha256=8b260315628888c937c6f7eaf21f63e73eb52cfd9cd6e9c0d9d90fa9cf9fbd3f
readonly expected_candidate_sha256=5480e6994994b65b0a498f42cb7943b5de86958416732a44983e341a93db1393
readonly expected_source_sha256=9aa36b630f304bab674e31af96d96a1dbafb330728b01e2d8216c8dbab2df148
readonly expected_check_count=99
readonly transaction_sha256=3cd507078e91156122f2d0212686c66a99ca213f15061c3050f6930aa558342b
readonly regression_sha256=2af3eb9ffc4b3055b157e49fcaf44dda54d7d872307db3ead0215ac636b128b8
readonly maximum_stream_bytes=16777216
readonly maximum_stream_lines=65536

script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
readonly caddy_root=${script_directory%/scripts}
readonly repository_root=${caddy_root%/Caddy}
readonly workspace_root=${repository_root%/homelab-server-configs}
readonly transaction=$script_directory/activate-node-b-keepalived-dbus-action20o-retry2.sh
readonly default_source_configuration=$workspace_root/homelab-dns/Keepalived/configs/keepalived-pihole00.conf
readonly regression=$caddy_root/tests/action20o-retry2-node-b-keepalived-dbus-regression.sh
readonly shfmt_canonical=$caddy_root/tests/shfmt-canonical.sh

ssh_binary=/usr/bin/ssh
source_configuration=$default_source_configuration

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }
line_count() { awk 'END { print NR }' "$1"; }
working_directory_approved() {
    case "$PWD" in
        /home/aaron/code/homelab-server-configs) return 0 ;;
        /workspace/homelab-server-configs)
            [[ "${CADDY_VALIDATION_CONTAINER:-}" = 1 ]] || return 1
            return 0
            ;;
        *) return 1 ;;
    esac
}
require_hash() {
    local action20o_outer_expected_hash=$1
    local action20o_outer_path=$2

    [[ -f "$action20o_outer_path" && ! -L "$action20o_outer_path" ]] || return 1
    [[ "$(file_hash "$action20o_outer_path")" = "$action20o_outer_expected_hash" ]]
}
run_gate() {
    local action20o_outer_gate_label=$1

    shift
    if "$@" >/dev/null; then
        printf '%s_gate_%s=true\n' "$prefix" "$action20o_outer_gate_label"
        return 0
    fi
    printf '%s_gate_%s=false\n' "$prefix" "$action20o_outer_gate_label" >&2
    return 1
}
expected_local_gates() {
    printf '%s\n' \
        working_directory transaction_regular transaction_executable transaction_hash \
        source_regular source_not_symlink source_hash candidate_hash_contract \
        regression_regular regression_executable regression_hash syntax shellcheck \
        canonical_format collision_policy conditional_policy output_evidence_policy \
        multifile_grep_policy portable_awk_policy accepted_live_hash_policy \
        root_cwd_policy transaction_self_test regression
}
candidate_hash_contract() {
    {
        cat "$source_configuration"
        printf '\ninclude /etc/keepalived/conf.d/caddy-ha.conf\n'
    } | sha256sum | awk -v expected="$expected_candidate_sha256" '$1 == expected { valid=1 }
        END { exit(valid == 1 ? 0 : 1) }'
}
run_local_gates() {
    run_gate working_directory working_directory_approved || return 1
    run_gate transaction_regular test -f "$transaction" || return 1
    run_gate transaction_executable test -x "$transaction" || return 1
    run_gate transaction_hash require_hash "$transaction_sha256" "$transaction" || return 1
    run_gate source_regular test -f "$source_configuration" || return 1
    run_gate source_not_symlink test ! -L "$source_configuration" || return 1
    run_gate source_hash require_hash "$expected_source_sha256" "$source_configuration" || return 1
    run_gate candidate_hash_contract candidate_hash_contract || return 1
    run_gate regression_regular test -f "$regression" || return 1
    run_gate regression_executable test -x "$regression" || return 1
    run_gate regression_hash require_hash "$regression_sha256" "$regression" || return 1
    run_gate syntax /bin/bash -n "$transaction" "$regression" "$0" || return 1
    run_gate shellcheck shellcheck "$transaction" "$regression" "$0" || return 1
    run_gate canonical_format /bin/bash "$shfmt_canonical" --check \
        "$transaction" "$regression" "$0" || return 1
    run_gate collision_policy /bin/bash "$caddy_root/tests/check-shell-readonly-local-collisions-v2.sh" \
        "$transaction" "$regression" "$0" || return 1
    run_gate conditional_policy /bin/bash "$caddy_root/tests/conditional-validator-errexit-policy-regression.sh" || return 1
    run_gate output_evidence_policy /bin/bash "$caddy_root/tests/transaction-output-evidence-policy-regression.sh" || return 1
    run_gate multifile_grep_policy /bin/bash "$caddy_root/tests/multifile-grep-count-policy.sh" --check \
        "$transaction" "$regression" "$0" || return 1
    run_gate portable_awk_policy /bin/bash "$caddy_root/tests/portable-awk-policy.sh" --check \
        "$transaction" "$regression" "$0" || return 1
    run_gate accepted_live_hash_policy /bin/bash "$caddy_root/tests/accepted-live-hash-policy.sh" --check || return 1
    run_gate root_cwd_policy /bin/bash "$caddy_root/tests/remote-streamed-bash-cwd-precommit.sh" "$0" || return 1
    run_gate transaction_self_test /bin/bash "$transaction" --self-test || return 1
    if [[ "${CADDY_ACTION20O_TEST_MODE:-}" = 1 ]]; then
        run_gate regression true || return 1
    else
        run_gate regression /bin/bash "$regression" || return 1
    fi
}
safe_stream() {
    local action20o_outer_stream=$1

    [[ "$(wc -c <"$action20o_outer_stream")" -le "$maximum_stream_bytes" ]] || return 1
    [[ "$(line_count "$action20o_outer_stream")" -le "$maximum_stream_lines" ]] || return 1
    ! LC_ALL=C grep -n '[^[:print:][:space:]]' "$action20o_outer_stream" >/dev/null || return 1
    ! grep -Eqi 'BEGIN [A-Z ]*PRIVATE KEY|DOPPLER_TOKEN|Authorization:[[:space:]]*Bearer' "$action20o_outer_stream"
}
emit_stream() {
    local action20o_outer_stream_label=$1
    local action20o_outer_stream=$2

    printf '%s_%s_bytes=%s\n' "$prefix" "$action20o_outer_stream_label" "$(wc -c <"$action20o_outer_stream")"
    printf '%s_%s_lines=%s\n' "$prefix" "$action20o_outer_stream_label" "$(line_count "$action20o_outer_stream")"
    printf '%s_%s_sha256=%s\n' "$prefix" "$action20o_outer_stream_label" "$(file_hash "$action20o_outer_stream")"
    if ! safe_stream "$action20o_outer_stream"; then
        printf '%s_%s_classification=unsafe_retained\n' "$prefix" "$action20o_outer_stream_label" >&2
        return 97
    fi
    printf '%s_%s_classification=bounded_safe\n' "$prefix" "$action20o_outer_stream_label"
    if [[ -s "$action20o_outer_stream" ]]; then
        printf '%s_%s_begin\n' "$prefix" "$action20o_outer_stream_label"
        cat "$action20o_outer_stream"
        printf '%s_%s_end\n' "$prefix" "$action20o_outer_stream_label"
    else
        printf '%s_%s_content_secured=empty\n' "$prefix" "$action20o_outer_stream_label"
    fi
}
require_one() {
    local action20o_outer_line=$1
    local action20o_outer_transcript=$2

    [[ "$(grep -Fxc "$action20o_outer_line" "$action20o_outer_transcript" || true)" -eq 1 ]]
}
validate_assert() {
    local action20o_outer_assertion_label=$1

    shift
    if "$@"; then
        printf '%s_validation_%s=true\n' "$prefix" "$action20o_outer_assertion_label"
        return 0
    fi
    printf '%s_validation_%s=false\n' "$prefix" "$action20o_outer_assertion_label" >&2
    return 1
}
generate_expected_checks() {
    local action20o_outer_expected=$1

    /bin/bash "$transaction" --expected-checks >"$action20o_outer_expected"
}
capture_contract() {
    local action20o_outer_stdout=$1
    local action20o_outer_capture

    for action20o_outer_capture in candidate_install candidate_rename reload reload_journal dbus_list dbus_tree dbus_ipv4_state dbus_ipv6_state; do
        require_one "action_20o_retry2_capture_${action20o_outer_capture}_status=0" "$action20o_outer_stdout" || return 1
        require_one "action_20o_retry2_capture_${action20o_outer_capture}_stdout_classification=bounded_safe" "$action20o_outer_stdout" || return 1
        require_one "action_20o_retry2_capture_${action20o_outer_capture}_stderr_classification=bounded_safe" "$action20o_outer_stdout" || return 1
    done
}
validate_success() {
    local action20o_outer_stdout=$1
    local action20o_outer_stderr=$2
    local action20o_outer_status=$3
    local action20o_outer_expected=$4
    local action20o_outer_actual=$5

    # conditional-validator-explicit-failures-begin
    validate_assert status_zero test "$action20o_outer_status" -eq 0 || return 1
    validate_assert stderr_empty test ! -s "$action20o_outer_stderr" || return 1
    validate_assert expected_checks_generated generate_expected_checks "$action20o_outer_expected" || return 1
    validate_assert expected_check_count test "$(line_count "$action20o_outer_expected")" -eq "$expected_check_count" || return 1
    validate_assert false_checks_absent test "$(grep -Ec '^action_20o_retry2_check_[a-z0-9_]+=false$' "$action20o_outer_stdout" || true)" -eq 0 || return 1
    sed -n 's/^action_20o_retry2_check_\([a-z0-9_]*\)=true$/\1/p' "$action20o_outer_stdout" >"$action20o_outer_actual" || return 1
    validate_assert actual_check_count test "$(line_count "$action20o_outer_actual")" -eq "$expected_check_count" || return 1
    validate_assert unique_check_count test "$(LC_ALL=C sort -u "$action20o_outer_actual" | wc -l)" -eq "$expected_check_count" || return 1
    validate_assert ordered_check_contract diff -u "$action20o_outer_expected" "$action20o_outer_actual" || return 1
    validate_assert main_hash require_one "action_20o_retry2_value_main_sha256=$expected_main_sha256" "$action20o_outer_stdout" || return 1
    validate_assert candidate_hash require_one "action_20o_retry2_value_candidate_sha256=$expected_candidate_sha256" "$action20o_outer_stdout" || return 1
    validate_assert expected_count_value require_one 'action_20o_retry2_value_expected_check_count=99' "$action20o_outer_stdout" || return 1
    validate_assert check_count_value require_one 'action_20o_retry2_check_count=99' "$action20o_outer_stdout" || return 1
    validate_assert failed_count_zero require_one 'action_20o_retry2_failed_check_count=0' "$action20o_outer_stdout" || return 1
    validate_assert first_failure_none require_one 'action_20o_retry2_first_failure=none' "$action20o_outer_stdout" || return 1
    validate_assert reload_true require_one 'action_20o_retry2_keepalived_reload=true' "$action20o_outer_stdout" || return 1
    validate_assert restart_false require_one 'action_20o_retry2_keepalived_restart=false' "$action20o_outer_stdout" || return 1
    validate_assert dbus_active require_one 'action_20o_retry2_dbus_runtime_active=true' "$action20o_outer_stdout" || return 1
    validate_assert filesystem_mutation_true require_one 'action_20o_retry2_filesystem_mutation=true' "$action20o_outer_stdout" || return 1
    validate_assert vrrp_transition_false require_one 'action_20o_retry2_vrrp_transition=false' "$action20o_outer_stdout" || return 1
    validate_assert vip_mutation_false require_one 'action_20o_retry2_vip_mutation=false' "$action20o_outer_stdout" || return 1
    validate_assert node_a_ssh_false require_one 'action_20o_retry2_node_a_ssh_contacted=false' "$action20o_outer_stdout" || return 1
    validate_assert node_a_continuity_true require_one 'action_20o_retry2_node_a_continuity_verified=true' "$action20o_outer_stdout" || return 1
    validate_assert producer_complete require_one 'action_20o_retry2_complete=true' "$action20o_outer_stdout" || return 1
    validate_assert capture_contract capture_contract "$action20o_outer_stdout" || return 1
    validate_assert rollback_absent test "$(grep -Fc 'action_20o_retry2_rollback_' "$action20o_outer_stdout" || true)" -eq 0 || return 1
    # conditional-validator-explicit-failures-end
}
contract_self_test() {
    [[ "$(expected_local_gates | wc -l)" -eq 23 ]] || return 1
    [[ "$(expected_local_gates | LC_ALL=C sort -u | wc -l)" -eq 23 ]] || return 1
    [[ "$expected_target" = pi@10.1.0.54 ]] || return 1
    [[ "$expected_host_alias" = 10.1.0.54 ]] || return 1
}
write_remote_bundle() {
    local action20o_outer_archive=$1
    local action20o_outer_remote_script=$2

    # The quoted lines are a remote script and expand only on Node B.
    # shellcheck disable=SC2016
    {
        printf '%s\n' \
            '#!/usr/bin/env bash' \
            'set -Eeuo pipefail' \
            'set +x' \
            'umask 077' \
            'PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin' \
            'export PATH' \
            'cd /' \
            'bundle_stage=$(mktemp -d /run/caddy-action20o-retry2-bundle.XXXXXX)' \
            'cleanup_bundle_stage() { rm -rf -- "$bundle_stage"; }' \
            'trap cleanup_bundle_stage EXIT INT TERM' \
            'chown root:root "$bundle_stage"' \
            'chmod 0700 "$bundle_stage"' \
            'install -m 0600 /dev/null "$bundle_stage/payload.tar"' \
            'base64 -d >"$bundle_stage/payload.tar" <<'\''ACTION20O_RETRY2_ARCHIVE'\'''
        base64 "$action20o_outer_archive"
        printf '%s\n' \
            'ACTION20O_RETRY2_ARCHIVE' \
            'printf '\''%s\n'\'' activate-node-b-keepalived-dbus-action20o-retry2.sh keepalived-pihole00.conf >"$bundle_stage/expected-members"' \
            'tar -tf "$bundle_stage/payload.tar" | LC_ALL=C sort >"$bundle_stage/actual-members"' \
            'diff -u "$bundle_stage/expected-members" "$bundle_stage/actual-members" >/dev/null' \
            'tar --extract --file "$bundle_stage/payload.tar" --directory "$bundle_stage" --no-same-owner --no-same-permissions' \
            'chown root:root "$bundle_stage/activate-node-b-keepalived-dbus-action20o-retry2.sh" "$bundle_stage/keepalived-pihole00.conf"' \
            'chmod 0700 "$bundle_stage/activate-node-b-keepalived-dbus-action20o-retry2.sh"' \
            'chmod 0600 "$bundle_stage/keepalived-pihole00.conf"' \
            'cd /' \
            '/bin/bash "$bundle_stage/activate-node-b-keepalived-dbus-action20o-retry2.sh" --stage "$bundle_stage"'
    } >"$action20o_outer_remote_script" || return 1
    chmod 0600 "$action20o_outer_remote_script" || return 1
    /bin/bash -n "$action20o_outer_remote_script"
}

case "${1:-}" in
    --expected-local-gates)
        [[ $# -eq 1 ]] || exit 64
        expected_local_gates
        exit 0
        ;;
    --self-test)
        [[ $# -eq 1 ]] || exit 64
        contract_self_test
        run_local_gates
        printf '%s_self_test_complete=true\n' "$prefix"
        exit 0
        ;;
    '') ;;
    *) exit 64 ;;
esac

if [[ "${CADDY_ACTION20O_TEST_MODE:-}" = 1 ]]; then
    [[ -n "${CADDY_ACTION20O_SSH_BIN:-}" ]] || exit 64
    ssh_binary=$CADDY_ACTION20O_SSH_BIN
    [[ -n "${CADDY_ACTION20O_SOURCE_PATH:-}" ]] || exit 64
    source_configuration=$CADDY_ACTION20O_SOURCE_PATH
fi
readonly ssh_binary
readonly source_configuration
if [[ "${CADDY_ACTION20O_TEST_MODE:-}" = 1 &&
    "${CADDY_ACTION20O_TEST_SKIP_LOCAL_GATES:-}" = 1 ]]; then
    printf '%s_gate_test_local_gates_skipped=true\n' "$prefix"
else
    run_local_gates
fi

outer_root=$(mktemp -d /tmp/caddy-action20o-outer.XXXXXX)
readonly outer_root
trap 'rm -rf -- "$outer_root"' EXIT
readonly remote_stdout=$outer_root/remote.stdout
readonly remote_stderr=$outer_root/remote.stderr
readonly expected_checks_file=$outer_root/expected.checks
readonly actual_checks_file=$outer_root/actual.checks
readonly bundle_root=$outer_root/bundle
readonly bundle_archive=$outer_root/payload.tar
readonly remote_script=$outer_root/remote.sh
install -d -m 0700 "$bundle_root"
install -m 0700 "$transaction" "$bundle_root/activate-node-b-keepalived-dbus-action20o-retry2.sh"
install -m 0600 "$source_configuration" "$bundle_root/keepalived-pihole00.conf"
tar --create --file "$bundle_archive" --directory "$bundle_root" \
    activate-node-b-keepalived-dbus-action20o-retry2.sh keepalived-pihole00.conf
write_remote_bundle "$bundle_archive" "$remote_script"
for action20o_outer_capture_path in \
    "$remote_stdout" "$remote_stderr" "$expected_checks_file" "$actual_checks_file"; do
    install -m 0600 /dev/null "$action20o_outer_capture_path"
done

remote_status=0
"$ssh_binary" -T -o BatchMode=yes -o ConnectTimeout=10 -o ConnectionAttempts=1 \
    -o StrictHostKeyChecking=yes "$expected_target" \
    'cd / && sudo -n /bin/bash -s --' <"$remote_script" \
    >"$remote_stdout" 2>"$remote_stderr" || remote_status=$?
readonly remote_status

emit_stream remote_stdout "$remote_stdout"
emit_stream remote_stderr "$remote_stderr"
printf '%s_remote_status=%s\n' "$prefix" "$remote_status"
validate_success "$remote_stdout" "$remote_stderr" "$remote_status" \
    "$expected_checks_file" "$actual_checks_file"
printf '%s_node_b_contacted=true\n' "$prefix"
printf '%s_node_a_ssh_contacted=false\n' "$prefix"
printf '%s_keepalived_reload=true\n' "$prefix"
printf '%s_keepalived_restart=false\n' "$prefix"
printf '%s_dbus_runtime_activation=true\n' "$prefix"
printf '%s_vrrp_transition=false\n' "$prefix"
printf '%s_vip_mutation=false\n' "$prefix"
printf '%s_complete=true\n' "$prefix"
