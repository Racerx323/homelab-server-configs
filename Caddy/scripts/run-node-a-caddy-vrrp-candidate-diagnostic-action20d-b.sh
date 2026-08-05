#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_20d_b
readonly inspector_sha256=c546175486f331423a239d263edf12edfd216eb47134e9c8c689d77140203f86
readonly maximum_stream_bytes=2097152
readonly maximum_stream_lines=8192
script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
readonly caddy_root=${script_directory%/scripts}
readonly inspector="$script_directory/diagnose-node-a-caddy-vrrp-candidate-action20d-b.sh"
readonly collision_checker="$caddy_root/tests/check-shell-readonly-local-collisions-v2.sh"
readonly ssh_binary=${CADDY_ACTION20DB_SSH_BINARY:-/usr/bin/ssh}

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }
line_count() { awk 'END { print NR }' "$1"; }
safe_stream() {
    local inspected_path=$1

    [[ "$(wc -c <"$inspected_path")" -le "$maximum_stream_bytes" ]] || return 1
    [[ "$(line_count "$inspected_path")" -le "$maximum_stream_lines" ]] || return 1
    ! LC_ALL=C grep -n '[^[:print:][:space:]]' "$inspected_path" >/dev/null || return 1
    ! grep -Eqi \
        'BEGIN [A-Z ]*PRIVATE KEY|CADDY_TLS_PRIVATE_KEY_PEM|PRIVATE_KEY=|DOPPLER_TOKEN|Authorization:[[:space:]]*Bearer' \
        "$inspected_path"
}
emit_stream_metadata() {
    local stream_label=$1
    local stream_path=$2

    printf '%s_%s_bytes=%s\n' "$prefix" "$stream_label" "$(wc -c <"$stream_path")"
    printf '%s_%s_lines=%s\n' "$prefix" "$stream_label" "$(line_count "$stream_path")"
    printf '%s_%s_sha256=%s\n' "$prefix" "$stream_label" "$(file_hash "$stream_path")"
}
working_directory_approved() {
    case "$PWD" in
        /home/aaron/code/homelab-server-configs) return 0 ;;
        /workspace/homelab-server-configs)
            [[ "${CADDY_VALIDATION_CONTAINER:-}" = 1 ]]
            ;;
        *) return 1 ;;
    esac
}
require_one() {
    local exact_line=$1
    local transcript_path=$2

    [[ "$(grep -Fxc "$exact_line" "$transcript_path")" -eq 1 ]]
}
classification_known() {
    case "$1" in
        config_valid | timeout_term | timeout_kill | terminated_sigterm | \
            config_error_or_command_failure | terminated_other_signal_or_wrapper) return 0 ;;
        *) return 1 ;;
    esac
}
verify_sources() {
    [[ -f "$inspector" && ! -L "$inspector" && -x "$inspector" ]] || return 1
    [[ "$(file_hash "$inspector")" = "$inspector_sha256" ]] || return 1
    /bin/bash -n "$inspector" || return 1
    shellcheck "$inspector" || return 1
    /bin/bash "$collision_checker" "$inspector" >/dev/null || return 1
    /bin/bash "$inspector" --self-test >/dev/null || return 1
}
validate_transcript() {
    local error_path=$1
    local output_path=$2
    local observed_remote_status=$3
    local contract_root
    local expected_count
    local observed_count
    local reported_count
    local reported_failed
    local failed_count
    local first_failure
    local before_hash
    local after_hash
    local exact_status
    local exact_classification
    local exact_duration
    local minimal_status
    local minimal_classification
    local minimal_duration

    [[ ! -s "$error_path" ]] || return 97
    contract_root=$(mktemp -d /tmp/caddy-action20d-b-contract.XXXXXX) || return 97
    /bin/bash "$inspector" --expected-assertions | LC_ALL=C sort >"$contract_root/expected" || {
        rm -rf -- "$contract_root"
        return 97
    }
    sed -n "s/^${prefix}_assertion_\([a-z0-9_]*\)=\(true\|false\)$/\1/p" \
        "$output_path" | LC_ALL=C sort >"$contract_root/observed"
    expected_count=$(wc -l <"$contract_root/expected")
    observed_count=$(wc -l <"$contract_root/observed")
    if [[ "$expected_count" -eq 0 ]] ||
        [[ "$expected_count" -ne "$(LC_ALL=C sort -u "$contract_root/expected" | wc -l)" ]] ||
        [[ "$observed_count" -ne "$expected_count" ]] ||
        [[ "$observed_count" -ne "$(LC_ALL=C sort -u "$contract_root/observed" | wc -l)" ]] ||
        ! cmp -s "$contract_root/expected" "$contract_root/observed"; then
        rm -rf -- "$contract_root"
        return 97
    fi
    rm -rf -- "$contract_root"

    reported_count=$(sed -n "s/^${prefix}_assertion_count=//p" "$output_path")
    reported_failed=$(sed -n "s/^${prefix}_failed_assertion_count=//p" "$output_path")
    first_failure=$(sed -n "s/^${prefix}_first_failure=//p" "$output_path")
    failed_count=$(grep -Ec "^${prefix}_assertion_[a-z0-9_]+=false$" "$output_path" || true)
    [[ "$reported_count" =~ ^[0-9]+$ && "$reported_count" -eq "$expected_count" ]] || return 97
    [[ "$reported_failed" =~ ^[0-9]+$ && "$reported_failed" -eq "$failed_count" ]] || return 97
    before_hash=$(sed -n "s/^${prefix}_value_before_state_sha256=//p" "$output_path")
    after_hash=$(sed -n "s/^${prefix}_value_after_state_sha256=//p" "$output_path")
    [[ "$before_hash" =~ ^[0-9a-f]{64}$ && "$after_hash" = "$before_hash" ]] || return 97
    exact_status=$(sed -n "s/^${prefix}_value_exact_status=//p" "$output_path")
    exact_classification=$(sed -n "s/^${prefix}_value_exact_classification=//p" "$output_path")
    exact_duration=$(sed -n "s/^${prefix}_value_exact_duration_ms=//p" "$output_path")
    minimal_status=$(sed -n "s/^${prefix}_value_minimal_status=//p" "$output_path")
    minimal_classification=$(sed -n "s/^${prefix}_value_minimal_classification=//p" "$output_path")
    minimal_duration=$(sed -n "s/^${prefix}_value_minimal_duration_ms=//p" "$output_path")
    [[ "$exact_status" =~ ^[0-9]+$ && "$minimal_status" =~ ^[0-9]+$ ]] || return 97
    classification_known "$exact_classification" || return 97
    classification_known "$minimal_classification" || return 97
    [[ "$exact_duration" =~ ^[0-9]+$ && "$exact_duration" -le 20000 ]] || return 97
    [[ "$minimal_duration" =~ ^[0-9]+$ && "$minimal_duration" -le 20000 ]] || return 97
    require_one "${prefix}_candidate_validation_invoked=true" "$output_path" || return 97
    require_one "${prefix}_candidate_installed=false" "$output_path" || return 97
    require_one "${prefix}_node_b_contacted=false" "$output_path" || return 97
    require_one "${prefix}_transient_filesystem_activity=true" "$output_path" || return 97
    require_one "${prefix}_persistent_filesystem_mutations=false" "$output_path" || return 97
    require_one "${prefix}_service_mutations=false" "$output_path" || return 97
    require_one "${prefix}_keepalived_service_mutations=false" "$output_path" || return 97
    require_one "${prefix}_vrrp_mutations=false" "$output_path" || return 97
    require_one "${prefix}_vip_mutations=false" "$output_path" || return 97
    require_one "${prefix}_remote_complete=true" "$output_path" || return 97
    if [[ "$failed_count" -eq 0 ]]; then
        [[ "$observed_remote_status" -eq 0 && "$first_failure" = none ]] || return 97
        return 0
    fi
    [[ "$observed_remote_status" -eq 1 ]] || return 97
    [[ "$first_failure" =~ ^[a-z0-9_]+$ ]] || return 97
    require_one "${prefix}_assertion_${first_failure}=false" "$output_path" || return 97
    return 1
}
write_contract_fixture() {
    local assertion_label
    local expected_count
    local state_hash=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
    local candidate_hash=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb

    expected_count=$(/bin/bash "$inspector" --expected-assertions | wc -l)
    while IFS= read -r assertion_label; do
        printf '%s_assertion_%s=true\n' "$prefix" "$assertion_label"
    done < <(/bin/bash "$inspector" --expected-assertions)
    printf '%s\n' \
        "${prefix}_value_before_state_sha256=$state_hash" \
        "${prefix}_value_after_state_sha256=$state_hash" \
        "${prefix}_value_candidate_sha256=$candidate_hash" \
        "${prefix}_value_exact_status=124" \
        "${prefix}_value_exact_classification=timeout_term" \
        "${prefix}_value_exact_duration_ms=15010" \
        "${prefix}_value_minimal_status=0" \
        "${prefix}_value_minimal_classification=config_valid" \
        "${prefix}_value_minimal_duration_ms=120" \
        "${prefix}_assertion_count=$expected_count" \
        "${prefix}_failed_assertion_count=0" \
        "${prefix}_first_failure=none" \
        "${prefix}_candidate_validation_invoked=true" \
        "${prefix}_candidate_installed=false" \
        "${prefix}_node_b_contacted=false" \
        "${prefix}_transient_filesystem_activity=true" \
        "${prefix}_persistent_filesystem_mutations=false" \
        "${prefix}_service_mutations=false" \
        "${prefix}_keepalived_service_mutations=false" \
        "${prefix}_vrrp_mutations=false" \
        "${prefix}_vip_mutations=false" \
        "${prefix}_remote_complete=true"
}

case "${1:-}" in
    --self-test)
        [[ $# -eq 1 ]]
        verify_sources
        printf '%s_runner_self_test_complete=true\n' "$prefix"
        exit 0
        ;;
    --contract-test)
        [[ $# -eq 1 ]]
        verify_sources
        contract_root=$(mktemp -d /tmp/caddy-action20d-b-runner-contract.XXXXXX)
        trap 'rm -rf -- "$contract_root"' EXIT
        : >"$contract_root/empty.err"
        write_contract_fixture >"$contract_root/valid.out"
        validate_transcript "$contract_root/empty.err" "$contract_root/valid.out" 0
        sed '/^action_20d_b_assertion_main_hash_exact=/d' "$contract_root/valid.out" >"$contract_root/missing.out"
        if validate_transcript "$contract_root/empty.err" "$contract_root/missing.out" 0; then exit 1; fi
        cp "$contract_root/valid.out" "$contract_root/duplicate.out"
        printf '%s_assertion_main_hash_exact=true\n' "$prefix" >>"$contract_root/duplicate.out"
        if validate_transcript "$contract_root/empty.err" "$contract_root/duplicate.out" 0; then exit 1; fi
        cp "$contract_root/valid.out" "$contract_root/unknown.out"
        sed -i 's/value_exact_classification=timeout_term/value_exact_classification=unknown/' "$contract_root/unknown.out"
        if validate_transcript "$contract_root/empty.err" "$contract_root/unknown.out" 0; then exit 1; fi
        printf '%s_runner_contract_test_complete=true\n' "$prefix"
        exit 0
        ;;
    "") [[ $# -eq 0 ]] ;;
    *)
        printf 'Usage: %s [--self-test|--contract-test]\n' "${0##*/}" >&2
        exit 64
        ;;
esac

verify_sources
working_directory_approved
work_directory=$(mktemp -d /tmp/caddy-action20d-b-runner.XXXXXX)
readonly work_directory
# shellcheck disable=SC2317
cleanup() { rm -rf -- "$work_directory"; }
trap cleanup EXIT
readonly remote_stdout=$work_directory/remote.stdout
readonly remote_stderr=$work_directory/remote.stderr
touch "$remote_stdout" "$remote_stderr"
chmod 0600 "$remote_stdout" "$remote_stderr"
remote_status=0
if [[ "${CADDY_ACTION20DB_INTERCEPTED_TEST:-}" = 1 ]]; then
    "$ssh_binary" -T -o BatchMode=yes -o IdentitiesOnly=no \
        -o StrictHostKeyChecking=yes -o HostKeyAlias=pihole0.local.theama.co \
        pi@10.1.0.53 'cd / && sudo -n /bin/bash -s --' <"$inspector" \
        >"$remote_stdout" 2>"$remote_stderr" || remote_status=$?
else
    [[ -z "${CADDY_ACTION20DB_SSH_BINARY:-}" ]]
    /usr/bin/ssh -T -o BatchMode=yes -o IdentitiesOnly=no \
        -o StrictHostKeyChecking=yes -o HostKeyAlias=pihole0.local.theama.co \
        pi@10.1.0.53 'cd / && sudo -n /bin/bash -s --' <"$inspector" \
        >"$remote_stdout" 2>"$remote_stderr" || remote_status=$?
fi
readonly remote_status
emit_stream_metadata remote_stdout "$remote_stdout"
emit_stream_metadata remote_stderr "$remote_stderr"
if safe_stream "$remote_stdout" && safe_stream "$remote_stderr"; then
    printf '%s_remote_stream_classification=bounded_safe\n' "$prefix"
    printf '%s_remote_stdout_begin\n' "$prefix"
    cat "$remote_stdout"
    printf '%s_remote_stdout_end\n' "$prefix"
    if [[ -s "$remote_stderr" ]]; then
        printf '%s_remote_stderr_begin\n' "$prefix" >&2
        cat "$remote_stderr" >&2
        printf '%s_remote_stderr_end\n' "$prefix" >&2
    else
        printf '%s_remote_stderr_content_secured=empty\n' "$prefix"
    fi
else
    printf '%s_remote_stream_classification=unsafe_retained\n' "$prefix" >&2
    trap - EXIT
    printf '%s_protected_evidence=%s\n' "$prefix" "$work_directory" >&2
    exit 97
fi
validation_status=0
validate_transcript "$remote_stderr" "$remote_stdout" "$remote_status" || validation_status=$?
readonly validation_status
printf '%s_remote_status=%s\n' "$prefix" "$remote_status"
printf '%s_validation_status=%s\n' "$prefix" "$validation_status"
if [[ "$validation_status" -eq 97 ]]; then
    trap - EXIT
    printf '%s_protected_evidence=%s\n' "$prefix" "$work_directory" >&2
    exit 97
fi
rm -rf -- "$work_directory"
trap - EXIT
printf '%s_runner_cleanup_complete=true\n' "$prefix"
exit "$validation_status"
