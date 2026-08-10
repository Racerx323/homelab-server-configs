#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_28a_outer
readonly expected_target=pi@10.1.0.53
readonly expected_host_alias=pihole0.local.theama.co
readonly publisher_sha256=e4a48f12a7324a885684a57070269a2d074d056c65d9e767db901408e0e86669
readonly driver_sha256=6e1580798f40e5d056018f52bc9346f0366326f21685810b906b60a66da2c8bd
readonly regression_sha256=1047406e88b2f2c1bb058d53adf75bea56e6a14d1a1f70586170440d36e6e455
readonly maximum_stream_bytes=2097152
readonly maximum_stream_lines=8192

script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
readonly caddy_root=${script_directory%/scripts}
readonly publisher=$script_directory/publish-release-v2.sh
readonly driver=$script_directory/install-node-a-protocol-v2-publisher-action28a.sh
readonly regression=$caddy_root/tests/action28a-node-a-publisher-install-regression.sh
readonly shfmt_canonical=$caddy_root/tests/shfmt-canonical.sh

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }
line_count() { awk 'END { print NR }' "$1"; }
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
require_source() {
    local action28a_outer_expected_hash=$1
    local action28a_outer_source=$2
    local action28a_outer_expected_owner=aaron:aaron

    if [[ "${CADDY_VALIDATION_CONTAINER:-}" == 1 ]]; then
        action28a_outer_expected_owner=root:root
    fi
    [[ -f "$action28a_outer_source" && ! -L "$action28a_outer_source" &&
        -x "$action28a_outer_source" ]] || return 1
    [[ "$(stat -c '%U:%G:%a' "$action28a_outer_source")" == "$action28a_outer_expected_owner:755" ]] || return 1
    [[ "$(file_hash "$action28a_outer_source")" == "$action28a_outer_expected_hash" ]]
}
run_gate() {
    local action28a_outer_gate_label=$1

    shift
    if "$@" >/dev/null; then
        printf '%s_gate_%s=true\n' "$prefix" "$action28a_outer_gate_label"
        return 0
    fi
    printf '%s_gate_%s=false\n' "$prefix" "$action28a_outer_gate_label" >&2
    return 1
}
expected_local_gates() {
    printf '%s\n' \
        working_directory publisher_regular publisher_executable publisher_hash \
        driver_regular driver_executable driver_hash regression_regular \
        regression_executable regression_hash syntax shellcheck canonical_format \
        collision_policy conditional_policy output_evidence_policy scalar_grep_policy \
        portable_awk_policy remote_cwd_policy driver_self_test regression
}
run_local_gates() {
    local action28a_outer_skip_regression=$1

    run_gate working_directory working_directory_approved || return 1
    run_gate publisher_regular test -f "$publisher" || return 1
    run_gate publisher_executable test -x "$publisher" || return 1
    run_gate publisher_hash require_source "$publisher_sha256" "$publisher" || return 1
    run_gate driver_regular test -f "$driver" || return 1
    run_gate driver_executable test -x "$driver" || return 1
    run_gate driver_hash require_source "$driver_sha256" "$driver" || return 1
    run_gate regression_regular test -f "$regression" || return 1
    run_gate regression_executable test -x "$regression" || return 1
    run_gate regression_hash require_source "$regression_sha256" "$regression" || return 1
    run_gate syntax /bin/bash -n "$publisher" "$driver" "$regression" "$0" || return 1
    run_gate shellcheck shellcheck "$publisher" "$driver" "$regression" "$0" || return 1
    run_gate canonical_format /bin/bash "$shfmt_canonical" --check \
        "$driver" "$regression" "$0" || return 1
    run_gate collision_policy /bin/bash \
        "$caddy_root/tests/check-shell-readonly-local-collisions-v2.sh" \
        "$driver" "$regression" "$0" || return 1
    run_gate conditional_policy /bin/bash \
        "$caddy_root/tests/conditional-validator-errexit-policy-regression.sh" || return 1
    run_gate output_evidence_policy /bin/bash \
        "$caddy_root/tests/transaction-output-evidence-policy-regression.sh" || return 1
    run_gate scalar_grep_policy /bin/bash \
        "$caddy_root/tests/multifile-grep-count-policy.sh" --check \
        "$driver" "$regression" "$0" || return 1
    run_gate portable_awk_policy /bin/bash \
        "$caddy_root/tests/portable-awk-policy.sh" --check \
        "$driver" "$regression" "$0" || return 1
    run_gate remote_cwd_policy /bin/bash \
        "$caddy_root/tests/remote-streamed-bash-cwd-policy.sh" --check "$0" || return 1
    run_gate driver_self_test /bin/bash "$driver" --self-test || return 1
    if [[ "$action28a_outer_skip_regression" == true ]]; then
        run_gate regression test "${CADDY_ACTION28A_TEST_MODE:-}" == 1 || return 1
    else
        run_gate regression /bin/bash "$regression" || return 1
    fi
}
safe_stream() {
    local action28a_outer_stream=$1

    [[ "$(wc -c <"$action28a_outer_stream")" -le "$maximum_stream_bytes" ]] || return 1
    [[ "$(line_count "$action28a_outer_stream")" -le "$maximum_stream_lines" ]] || return 1
    ! LC_ALL=C grep -n '[^[:print:][:space:]]' "$action28a_outer_stream" >/dev/null || return 1
    ! grep -Eqi \
        'BEGIN [A-Z ]*PRIVATE KEY|CADDY_TLS_PRIVATE_KEY_PEM|PRIVATE_KEY=|DOPPLER_TOKEN|Authorization:[[:space:]]*Bearer' \
        "$action28a_outer_stream"
}
emit_stream() {
    local action28a_outer_stream_label=$1
    local action28a_outer_stream=$2

    printf '%s_%s_bytes=%s\n' "$prefix" "$action28a_outer_stream_label" \
        "$(wc -c <"$action28a_outer_stream")"
    printf '%s_%s_lines=%s\n' "$prefix" "$action28a_outer_stream_label" \
        "$(line_count "$action28a_outer_stream")"
    printf '%s_%s_sha256=%s\n' "$prefix" "$action28a_outer_stream_label" \
        "$(file_hash "$action28a_outer_stream")"
    if safe_stream "$action28a_outer_stream"; then
        printf '%s_%s_classification=bounded_safe\n' "$prefix" "$action28a_outer_stream_label"
        if [[ -s "$action28a_outer_stream" ]]; then
            printf '%s_%s_begin\n' "$prefix" "$action28a_outer_stream_label"
            cat "$action28a_outer_stream"
            printf '%s_%s_end\n' "$prefix" "$action28a_outer_stream_label"
        else
            printf '%s_%s_content_secured=empty\n' "$prefix" "$action28a_outer_stream_label"
        fi
        return 0
    fi
    printf '%s_%s_classification=unsafe_retained\n' "$prefix" "$action28a_outer_stream_label" >&2
    return 97
}
require_one() {
    local action28a_outer_line=$1
    local action28a_outer_transcript=$2

    [[ "$(grep -Fxc "$action28a_outer_line" "$action28a_outer_transcript" || true)" -eq 1 ]]
}
valid_sha256() {
    [[ ${#1} -eq 64 ]] || return 1
    [[ "$1" != *[!0-9a-f]* ]]
}
validate_assert() {
    local action28a_outer_assertion_label=$1

    shift
    if "$@"; then
        printf '%s_validation_%s=true\n' "$prefix" "$action28a_outer_assertion_label"
        return 0
    fi
    printf '%s_validation_%s=false\n' "$prefix" "$action28a_outer_assertion_label" >&2
    return 1
}
extract_actual_checks() {
    local action28a_outer_stdout=$1
    local action28a_outer_actual=$2

    sed -n 's/^action_28a_check_\([a-zA-Z0-9_]*\)=true$/\1/p' \
        "$action28a_outer_stdout" >"$action28a_outer_actual"
}
validate_success() {
    local action28a_outer_stdout=$1
    local action28a_outer_stderr=$2
    local action28a_outer_status=$3
    local action28a_outer_expected=$4
    local action28a_outer_actual=$5
    local action28a_outer_expected_count
    local action28a_outer_observed_hash

    /bin/bash "$driver" --expected-checks >"$action28a_outer_expected" || return 1
    extract_actual_checks "$action28a_outer_stdout" "$action28a_outer_actual" || return 1
    action28a_outer_expected_count=$(line_count "$action28a_outer_expected") || return 1
    action28a_outer_observed_hash=$(sed -n \
        's/^action_28a_value_publisher_sha256=//p' "$action28a_outer_stdout") || return 1
    # conditional-validator-explicit-failures-begin
    validate_assert status_zero test "$action28a_outer_status" -eq 0 || return 1
    validate_assert stderr_empty test ! -s "$action28a_outer_stderr" || return 1
    validate_assert expected_count_positive test "$action28a_outer_expected_count" -gt 0 || return 1
    validate_assert expected_count_unique test \
        "$(LC_ALL=C sort -u "$action28a_outer_expected" | wc -l)" -eq \
        "$action28a_outer_expected_count" || return 1
    validate_assert actual_count_exact test \
        "$(line_count "$action28a_outer_actual")" -eq "$action28a_outer_expected_count" || return 1
    validate_assert actual_count_unique test \
        "$(LC_ALL=C sort -u "$action28a_outer_actual" | wc -l)" -eq \
        "$action28a_outer_expected_count" || return 1
    validate_assert ordered_checks diff -u "$action28a_outer_expected" "$action28a_outer_actual" || return 1
    validate_assert false_checks_absent test \
        "$(grep -Ec '^action_28a_check_[a-zA-Z0-9_]+=false$' "$action28a_outer_stdout" || true)" -eq 0 || return 1
    validate_assert check_count_value require_one "action_28a_check_count=$action28a_outer_expected_count" "$action28a_outer_stdout" || return 1 # conditional-validator-requires-return
    validate_assert failed_check_count require_one 'action_28a_failed_check_count=0' "$action28a_outer_stdout" || return 1                       # conditional-validator-requires-return
    validate_assert first_failure_none require_one 'action_28a_first_failure=none' "$action28a_outer_stdout" || return 1                         # conditional-validator-requires-return
    validate_assert publisher_hash_once test \
        "$(grep -Ec '^action_28a_value_publisher_sha256=' "$action28a_outer_stdout" || true)" -eq 1 || return 1
    validate_assert publisher_hash_valid valid_sha256 "$action28a_outer_observed_hash" || return 1
    validate_assert publisher_hash_exact test \
        "$action28a_outer_observed_hash" = "$publisher_sha256" || return 1
    validate_assert backup_path require_one 'action_28a_value_backup_path=/var/backups/caddy-ha/action28a-node-a-publisher' "$action28a_outer_stdout" || return 1 # conditional-validator-requires-return
    validate_assert publisher_pre_state require_one 'action_28a_value_publisher_pre_state=absent' "$action28a_outer_stdout" || return 1                           # conditional-validator-requires-return
    validate_assert mutation_started require_one 'action_28a_mutation_started=true' "$action28a_outer_stdout" || return 1                                         # conditional-validator-requires-return
    validate_assert rollback_not_invoked require_one 'action_28a_rollback_invoked=false' "$action28a_outer_stdout" || return 1                                    # conditional-validator-requires-return
    validate_assert publisher_not_invoked require_one 'action_28a_publisher_invoked=false' "$action28a_outer_stdout" || return 1                                  # conditional-validator-requires-return
    validate_assert release_not_mutated require_one 'action_28a_release_mutated=false' "$action28a_outer_stdout" || return 1                                      # conditional-validator-requires-return
    validate_assert services_not_mutated require_one 'action_28a_service_mutations=false' "$action28a_outer_stdout" || return 1                                   # conditional-validator-requires-return
    validate_assert synchronization_not_activated require_one 'action_28a_lsyncd_reconciliation_activation=false' "$action28a_outer_stdout" || return 1           # conditional-validator-requires-return
    validate_assert action28_not_rerun require_one 'action_28a_action_28_rerun=false' "$action28a_outer_stdout" || return 1                                       # conditional-validator-requires-return
    validate_assert acceptance require_one 'action_28a_acceptance=true' "$action28a_outer_stdout" || return 1                                                     # conditional-validator-requires-return
    # conditional-validator-explicit-failures-end
}
validate_failure() {
    local action28a_outer_stdout=$1
    local action28a_outer_stderr=$2
    local action28a_outer_status=$3

    # conditional-validator-explicit-failures-begin
    validate_assert failure_status_nonzero test "$action28a_outer_status" -ne 0 || return 1
    validate_assert failure_acceptance_absent test \
        "$(grep -Fxc 'action_28a_acceptance=true' "$action28a_outer_stdout" || true)" -eq 0 || return 1
    if grep -Fqx 'action_28a_mutation_started=true' "$action28a_outer_stdout"; then
        validate_assert rollback_started require_one 'action_28a_rollback_started=true' "$action28a_outer_stderr" || return 1   # conditional-validator-requires-return
        validate_assert rollback_complete require_one 'action_28a_rollback_complete=true' "$action28a_outer_stderr" || return 1 # conditional-validator-requires-return
        validate_assert manual_intervention_absent test \
            "$(grep -Fxc 'action_28a_manual_intervention_required=true' "$action28a_outer_stderr" || true)" -eq 0 || return 1
    else
        validate_assert preflight_rollback_absent test \
            "$(grep -Ec '^action_28a_rollback_' "$action28a_outer_stderr" || true)" -eq 0 || return 1
    fi
    # conditional-validator-explicit-failures-end
}
write_remote_bundle() {
    local action28a_outer_bundle=$1

    # The quoted variables belong to the remote bundle.
    # shellcheck disable=SC2016
    {
        printf '%s\n' \
            '#!/usr/bin/env bash' \
            'set -Eeuo pipefail' \
            'set +x' \
            'umask 077' \
            'PATH=/usr/sbin:/usr/bin:/sbin:/bin' \
            'export PATH' \
            'cd /' \
            'stage=$(mktemp -d /run/caddy-action28a-node-a-publisher.XXXXXX)' \
            'cleanup_stage() {' \
            '    rm -rf -- "$stage"' \
            '}' \
            'trap cleanup_stage EXIT' \
            'install -d -o root -g root -m 0700 "$stage/payload"' \
            'base64 -d >"$stage/payload/publish-release-v2.sh" <<'\''ACTION28A_PUBLISHER'\'''
        base64 "$publisher"
        printf '%s\n' \
            'ACTION28A_PUBLISHER' \
            'base64 -d >"$stage/payload/install-node-a-protocol-v2-publisher-action28a.sh" <<'\''ACTION28A_DRIVER'\'''
        base64 "$driver"
        printf '%s\n' \
            'ACTION28A_DRIVER' \
            'chown root:root "$stage/payload" "$stage/payload/"*' \
            'chmod 0700 "$stage/payload" "$stage/payload/"*' \
            'cd /' \
            '/bin/bash "$stage/payload/install-node-a-protocol-v2-publisher-action28a.sh" --stage "$stage/payload"'
    } >"$action28a_outer_bundle"
    chmod 0600 "$action28a_outer_bundle"
    /bin/bash -n "$action28a_outer_bundle"
}
cleanup() {
    local action28a_outer_cleanup_status=$?

    if [[ -n "${work_root:-}" && -d "$work_root" ]]; then
        rm -rf -- "$work_root"
    fi
    exit "$action28a_outer_cleanup_status"
}

case "${1:-}" in
    --source-test)
        [[ $# -eq 1 ]]
        working_directory_approved
        require_source "$publisher_sha256" "$publisher"
        require_source "$driver_sha256" "$driver"
        require_source "$regression_sha256" "$regression"
        grep -Fq '"cd / && sudo -n /bin/bash -s --"' "$0"
        printf '%s_source_test_complete=true\n' "$prefix"
        exit 0
        ;;
    --expected-local-gates)
        [[ $# -eq 1 ]]
        expected_local_gates
        exit 0
        ;;
    --self-test)
        [[ $# -eq 1 ]]
        run_local_gates false
        printf '%s_self_test_complete=true\n' "$prefix"
        exit 0
        ;;
    --test-transport)
        [[ $# -eq 1 && "${CADDY_ACTION28A_TEST_MODE:-}" == 1 ]] || exit 64
        test_transport=true
        ;;
    --test-validate)
        [[ $# -eq 4 && "${CADDY_ACTION28A_TEST_MODE:-}" == 1 ]] || exit 64
        validation_root=$(mktemp -d /tmp/caddy-action28a-validation.XXXXXX)
        readonly validation_root
        trap 'rm -rf -- "$validation_root"' EXIT
        if [[ "$4" -eq 0 ]]; then
            validate_success "$2" "$3" "$4" \
                "$validation_root/expected.checks" "$validation_root/actual.checks" || exit 97
            exit 0
        fi
        validate_failure "$2" "$3" "$4" || exit 97
        exit "$4"
        ;;
    *)
        [[ $# -eq 0 ]] || exit 64
        test_transport=false
        ;;
esac

run_local_gates "$test_transport"
work_root=$(mktemp -d /tmp/caddy-action28a-outer.XXXXXX)
readonly work_root
trap cleanup EXIT
readonly bundle=$work_root/remote.sh
readonly stdout_capture=$work_root/remote.stdout
readonly stderr_capture=$work_root/remote.stderr
readonly expected_checks=$work_root/expected.checks
readonly actual_checks=$work_root/actual.checks
write_remote_bundle "$bundle"
remote_status=0
ssh_binary=${CADDY_ACTION28A_SSH_BINARY:-ssh}
readonly ssh_binary
ssh_options=(
    -T -o BatchMode=yes -o ConnectTimeout=5 -o ConnectionAttempts=1
    -o StrictHostKeyChecking=yes -o "HostKeyAlias=$expected_host_alias"
)
if "$ssh_binary" "${ssh_options[@]}" "$expected_target" \
    "cd / && sudo -n /bin/bash -s --" \
    <"$bundle" >"$stdout_capture" 2>"$stderr_capture"; then
    remote_status=0
else
    remote_status=$?
fi
readonly remote_status
emit_stream remote_stdout "$stdout_capture" || exit $?
emit_stream remote_stderr "$stderr_capture" || exit $?
if [[ "$remote_status" -eq 0 ]]; then
    validate_success "$stdout_capture" "$stderr_capture" "$remote_status" \
        "$expected_checks" "$actual_checks" || exit 97
else
    validate_failure "$stdout_capture" "$stderr_capture" "$remote_status" || exit 97
    printf '%s_acceptance=false\n' "$prefix" >&2
    exit "$remote_status"
fi
printf '%s_ssh_status=%s\n' "$prefix" "$remote_status"
printf '%s_node_a_contacted=%s\n' "$prefix" \
    "$(if [[ "$test_transport" == true ]]; then printf false; else printf true; fi)"
printf '%s_node_b_contacted=false\n' "$prefix"
printf '%s_publisher_invoked=false\n' "$prefix"
printf '%s_release_transfer_started=false\n' "$prefix"
printf '%s_action_28_rerun=false\n' "$prefix"
printf '%s_acceptance=true\n' "$prefix"
printf '%s_complete=true\n' "$prefix"
