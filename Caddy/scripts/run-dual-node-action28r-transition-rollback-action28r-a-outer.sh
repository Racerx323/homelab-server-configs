#!/usr/bin/env bash
# ssh-local-evidence-contract-v1

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_28r_a_outer
readonly inspector_sha256=911c003cf0fc592de67f3aeacc33bec14ea5659e501fb9dbe4ccac2a0fbbbae5
readonly regression_sha256=5154650c567796e2d515eebe2a5dead35b7821e0a2ee2513d159e649d1594f9b
readonly retained_cursor='s=b120595ff27149a9b51cc363decde165;i=74d5a5;b=8a45746a5c624b1aa42b11e901a02bfc;m=bf67ad835;t=658b706074b90;x=8deffc60c97e9236'
readonly maximum_stream_bytes=2097152
readonly maximum_stream_lines=8192
script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
readonly caddy_root=${script_directory%/scripts}
readonly inspector=$script_directory/inspect-action28r-transition-rollback-action28r-a.sh
readonly regression=$caddy_root/tests/action28r-a-transition-rollback-regression.sh
evidence_root=${CADDY_ACTION28RA_EVIDENCE_ROOT:-/tmp/caddy-ssh-evidence/action28r-a}
readonly evidence_root
ssh_binary=${CADDY_ACTION28RA_SSH_BIN:-/usr/bin/ssh}
readonly ssh_binary

file_hash() { sha256sum -- "$1" | awk '{ print $1 }'; }
line_count() { awk 'END { print NR }' "$1"; }
working_directory_approved() {
    # conditional-validator-explicit-failures-begin
    case "$PWD" in
        /home/aaron/code/homelab-server-configs) return 0 ;;
        /workspace/homelab-server-configs)
            [[ "${CADDY_VALIDATION_CONTAINER:-}" = 1 ]] || return 1
            return 0
            ;;
        *) return 1 ;;
    esac
    # conditional-validator-explicit-failures-end
}
valid_source() {
    local action28ra_outer_hash=$1
    local action28ra_outer_file=$2

    # conditional-validator-explicit-failures-begin
    [[ -f "$action28ra_outer_file" && ! -L "$action28ra_outer_file" && -x "$action28ra_outer_file" ]] || return 1
    [[ "$(file_hash "$action28ra_outer_file")" = "$action28ra_outer_hash" ]] || return 1
    # conditional-validator-explicit-failures-end
}
evidence_metadata_expected() {
    local action28ra_outer_path=$1

    [[ -d "$action28ra_outer_path" && ! -L "$action28ra_outer_path" ]] || return 1
    [[ "$(stat -c '%u:%g:%a' "$action28ra_outer_path")" = "$(id -u):$(id -g):700" ]]
}
gate() {
    local action28ra_outer_label=$1

    shift
    if "$@" >/dev/null 2>&1; then
        printf '%s_gate_%s=true\n' "$prefix" "$action28ra_outer_label"
        return 0
    fi
    printf '%s_gate_%s=false\n' "$prefix" "$action28ra_outer_label" >&2
    return 1
}
validation() {
    local action28ra_outer_label=$1

    shift
    if "$@" >/dev/null 2>&1; then
        printf '%s_validation_%s=true\n' "$prefix" "$action28ra_outer_label"
        return 0
    fi
    printf '%s_validation_%s=false\n' "$prefix" "$action28ra_outer_label" >&2
    return 1
}
expected_local_gates() {
    printf '%s\n' working_directory inspector_source regression_source syntax \
        inspector_self_test regression shellcheck canonical_format collision_policy \
        conditional_policy multifile_grep_policy portable_awk_policy root_cwd_policy \
        ssh_evidence_policy accepted_live_hash_policy evidence_root_created \
        evidence_directory_created node_b_read_only node_a_read_only
}
emit_test_local_gates() {
    local action28ra_outer_test_gate

    [[ "${CADDY_ACTION28RA_TEST_MODE:-}" = 1 ]] || return 1
    while IFS= read -r action28ra_outer_test_gate; do
        case "$action28ra_outer_test_gate" in
            evidence_root_created | evidence_directory_created | node_b_read_only | node_a_read_only) continue ;;
        esac
        printf '%s_gate_%s=true\n' "$prefix" "$action28ra_outer_test_gate"
    done < <(expected_local_gates)
}
emit_self_test_local_gates() {
    local action28ra_outer_self_test_gate

    while IFS= read -r action28ra_outer_self_test_gate; do
        printf '%s_gate_%s=true\n' "$prefix" "$action28ra_outer_self_test_gate"
    done < <(expected_local_gates)
}
safe_stream() {
    local action28ra_outer_stream=$1

    # conditional-validator-explicit-failures-begin
    [[ "$(wc -c <"$action28ra_outer_stream")" -le "$maximum_stream_bytes" ]] || return 1
    [[ "$(line_count "$action28ra_outer_stream")" -le "$maximum_stream_lines" ]] || return 1
    ! LC_ALL=C grep -n '[^[:print:][:space:]]' "$action28ra_outer_stream" >/dev/null || return 1
    ! grep -Eqi 'BEGIN [A-Z ]*PRIVATE KEY|PRIVATE_KEY=|DOPPLER_TOKEN|Authorization:[[:space:]]*Bearer|Cookie:|WEBPASSWORD' "$action28ra_outer_stream" || return 1
    # conditional-validator-explicit-failures-end
}
emit_stream() {
    local action28ra_outer_label=$1
    local action28ra_outer_stream=$2

    printf '%s_%s_bytes=%s\n' "$prefix" "$action28ra_outer_label" "$(wc -c <"$action28ra_outer_stream")"
    printf '%s_%s_lines=%s\n' "$prefix" "$action28ra_outer_label" "$(line_count "$action28ra_outer_stream")"
    printf '%s_%s_sha256=%s\n' "$prefix" "$action28ra_outer_label" "$(file_hash "$action28ra_outer_stream")"
    if ! safe_stream "$action28ra_outer_stream"; then
        printf '%s_%s_classification=unsafe_retained\n' "$prefix" "$action28ra_outer_label" >&2
        return 97
    fi
    printf '%s_%s_classification=bounded_safe\n' "$prefix" "$action28ra_outer_label"
    if [[ -s "$action28ra_outer_stream" ]]; then
        printf '%s_%s_begin\n' "$prefix" "$action28ra_outer_label"
        cat "$action28ra_outer_stream"
        printf '%s_%s_end\n' "$prefix" "$action28ra_outer_label"
    else
        printf '%s_%s_content=empty\n' "$prefix" "$action28ra_outer_label"
    fi
}
require_one() {
    local action28ra_outer_line=$1
    local action28ra_outer_file=$2

    [[ "$(grep -Fxc "$action28ra_outer_line" "$action28ra_outer_file" || true)" -eq 1 ]]
}
validate_transcript() {
    local action28ra_outer_role=$1
    local action28ra_outer_stdout=$2
    local action28ra_outer_stderr=$3
    local action28ra_outer_status=$4
    local action28ra_outer_expected
    local action28ra_outer_actual

    # conditional-validator-explicit-failures-begin
    validation "${action28ra_outer_role}_status_zero" test "$action28ra_outer_status" -eq 0 || return 1
    validation "${action28ra_outer_role}_stderr_empty" test ! -s "$action28ra_outer_stderr" || return 1
    validation "${action28ra_outer_role}_no_false_checks" test "$(grep -Ec '^action_28r_a_check_[a-z0-9_]+=false$' "$action28ra_outer_stdout" || true)" -eq 0 || return 1
    action28ra_outer_expected=$(/bin/bash "$inspector" --expected-checks) || return 1
    action28ra_outer_actual=$(sed -n 's/^action_28r_a_check_\([a-z0-9_]*\)=true$/\1/p' "$action28ra_outer_stdout") || return 1
    validation "${action28ra_outer_role}_ordered_checks" test "$action28ra_outer_actual" = "$action28ra_outer_expected" || return 1
    validation "${action28ra_outer_role}_check_count" require_one "action_28r_a_check_count=$(printf '%s\n' "$action28ra_outer_expected" | wc -l)" "$action28ra_outer_stdout" || return 1
    validation "${action28ra_outer_role}_first_failure_none" require_one 'action_28r_a_first_failure=none' "$action28ra_outer_stdout" || return 1
    validation "${action28ra_outer_role}_role_exact" require_one "action_28r_a_role=${action28ra_outer_role}" "$action28ra_outer_stdout" || return 1
    validation "${action28ra_outer_role}_cursor_exact" require_one "action_28r_a_cursor=${retained_cursor}" "$action28ra_outer_stdout" || return 1
    validation "${action28ra_outer_role}_mutation_false" require_one 'action_28r_a_mutation=false' "$action28ra_outer_stdout" || return 1
    validation "${action28ra_outer_role}_acceptance_true" require_one 'action_28r_a_acceptance=true' "$action28ra_outer_stdout" || return 1
    # conditional-validator-explicit-failures-end
}
run_local_gates() {
    # conditional-validator-explicit-failures-begin
    gate working_directory working_directory_approved || return 1
    gate inspector_source valid_source "$inspector_sha256" "$inspector" || return 1
    gate regression_source valid_source "$regression_sha256" "$regression" || return 1
    gate syntax /bin/bash -n "$inspector" "$regression" "$0" || return 1
    gate inspector_self_test "$inspector" --self-test || return 1
    if [[ "${CADDY_ACTION28RA_TEST_MODE:-}" = 1 ]]; then gate regression true || return 1; else gate regression /bin/bash "$regression" || return 1; fi
    gate shellcheck shellcheck "$inspector" "$regression" "$0" || return 1
    gate canonical_format /bin/bash "$caddy_root/tests/shfmt-canonical.sh" --check "$inspector" "$regression" "$0" || return 1
    gate collision_policy /bin/bash "$caddy_root/tests/check-shell-readonly-local-collisions-v2.sh" "$inspector" "$regression" "$0" || return 1
    gate conditional_policy /bin/bash "$caddy_root/tests/conditional-validator-errexit-policy-regression.sh" || return 1
    gate multifile_grep_policy /bin/bash "$caddy_root/tests/multifile-grep-count-policy.sh" --check "$inspector" "$regression" "$0" || return 1
    gate portable_awk_policy /bin/bash "$caddy_root/tests/portable-awk-policy.sh" --check "$inspector" "$regression" "$0" || return 1
    gate root_cwd_policy /bin/bash "$caddy_root/tests/remote-streamed-bash-cwd-precommit.sh" "$0" || return 1
    gate ssh_evidence_policy /bin/bash "$caddy_root/tests/ssh-stream-local-evidence-policy.sh" --check "$0" || return 1
    gate accepted_live_hash_policy /bin/bash "$caddy_root/tests/accepted-live-hash-policy.sh" --check || return 1
    # conditional-validator-explicit-failures-end
}
run_remote() {
    local action28ra_outer_phase=$1
    local action28ra_outer_target=$2
    local action28ra_outer_role=$3
    local action28ra_outer_stdout=$evidence_directory/${action28ra_outer_phase}.stdout
    local action28ra_outer_stderr=$evidence_directory/${action28ra_outer_phase}.stderr
    local action28ra_outer_status_file=$evidence_directory/${action28ra_outer_phase}.status
    local action28ra_outer_status=0

    install -m 0600 /dev/null "$action28ra_outer_stdout"
    install -m 0600 /dev/null "$action28ra_outer_stderr"
    install -m 0600 /dev/null "$action28ra_outer_status_file"
    "$ssh_binary" -T -o BatchMode=yes -o ConnectTimeout=10 -o ConnectionAttempts=1 -o StrictHostKeyChecking=yes "$action28ra_outer_target" "cd / && sudo -n /bin/bash -s -- --$action28ra_outer_role" <"$inspector" >"$action28ra_outer_stdout" 2>"$action28ra_outer_stderr" || action28ra_outer_status=$?
    printf '%s\n' "$action28ra_outer_status" >"$action28ra_outer_status_file"
    chmod 0600 "$action28ra_outer_stdout" "$action28ra_outer_stderr" "$action28ra_outer_status_file"
    emit_stream "remote_stdout_${action28ra_outer_phase}" "$action28ra_outer_stdout" || return 97
    emit_stream "remote_stderr_${action28ra_outer_phase}" "$action28ra_outer_stderr" || return 97
    printf '%s_%s_status=%s\n' "$prefix" "$action28ra_outer_phase" "$action28ra_outer_status"
}

case "${1:-}" in
    --expected-local-gates)
        [[ $# -eq 1 ]]
        expected_local_gates
        exit 0
        ;;
    --self-test)
        [[ $# -eq 1 ]]
        [[ "$(expected_local_gates | wc -l)" -eq "$(expected_local_gates | LC_ALL=C sort -u | wc -l)" ]]
        emit_self_test_local_gates
        printf '%s_self_test_complete=true\n' "$prefix"
        exit 0
        ;;
    --transcript-test)
        [[ "${CADDY_ACTION28RA_TEST_MODE:-}" = 1 && $# -eq 7 ]]
        validate_transcript node_b "$2" "$3" "$4"
        validate_transcript node_a "$5" "$6" "$7"
        exit 0
        ;;
    "") ;;
    *) exit 64 ;;
esac

if [[ "${CADDY_ACTION28RA_SKIP_LOCAL_GATES:-}" = true ]]; then
    emit_test_local_gates
else
    run_local_gates
fi
readonly node_b_target=pi@10.1.0.54
readonly node_a_target=pi@10.1.0.53
install -d -m 0700 "$evidence_root"
gate evidence_root_created evidence_metadata_expected "$evidence_root"
evidence_directory=$(mktemp -d "$evidence_root/run.XXXXXX")
readonly evidence_directory
chmod 0700 "$evidence_directory"
gate evidence_directory_created evidence_metadata_expected "$evidence_directory"
run_remote node_b "$node_b_target" node-b
gate node_b_read_only validate_transcript node_b "$evidence_directory/node_b.stdout" "$evidence_directory/node_b.stderr" "$(<"$evidence_directory/node_b.status")"
run_remote node_a "$node_a_target" node-a
gate node_a_read_only validate_transcript node_a "$evidence_directory/node_a.stdout" "$evidence_directory/node_a.stderr" "$(<"$evidence_directory/node_a.status")"
printf '%s_evidence_directory=%s\n' "$prefix" "$evidence_directory"
printf '%s_retained_cursor_consumed=true\n' "$prefix"
printf '%s_action_28r_rerun=false\n' "$prefix"
printf '%s_node_contact_read_only=true\n' "$prefix"
printf '%s_mutation=false\n' "$prefix"
printf '%s_complete=true\n' "$prefix"
