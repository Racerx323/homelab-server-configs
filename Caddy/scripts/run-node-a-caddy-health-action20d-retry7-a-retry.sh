#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_20d_retry7_a_retry
readonly diagnostic_sha256=1a5a08ad5220eb9e9ffa6e336664bd167c63f6ca4d3b463a744028401be88645
readonly maximum_stream_bytes=1048576
readonly maximum_stream_lines=8192
script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
readonly diagnostic="$script_directory/diagnose-node-a-caddy-health-action20d-retry7-a-retry.sh"
readonly ssh_binary=${CADDY_ACTION20D_RETRY7_A_RETRY_SSH_BINARY:-/usr/bin/ssh}

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }
line_count() { awk 'END { print NR }' "$1"; }
safe_stream() {
    local runner_stream_path=$1

    [[ "$(wc -c <"$runner_stream_path")" -le "$maximum_stream_bytes" ]] || return 1
    [[ "$(line_count "$runner_stream_path")" -le "$maximum_stream_lines" ]] || return 1
    ! LC_ALL=C grep -n '[^[:print:][:space:]]' "$runner_stream_path" >/dev/null || return 1
    ! grep -Eqi \
        'BEGIN [A-Z ]*PRIVATE KEY|CADDY_TLS_PRIVATE_KEY_PEM|PRIVATE_KEY=|DOPPLER_TOKEN|Authorization:[[:space:]]*Bearer' \
        "$runner_stream_path"
}
require_one() {
    local runner_expected_line=$1
    local runner_transcript_path=$2

    [[ "$(grep -Fxc "$runner_expected_line" "$runner_transcript_path" || true)" -eq 1 ]]
}
verify_source() {
    [[ -f "$diagnostic" && ! -L "$diagnostic" && -x "$diagnostic" ]] || return 1
    [[ "$(file_hash "$diagnostic")" = "$diagnostic_sha256" ]] || return 1
    /bin/bash -n "$diagnostic" || return 1
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
validate_transcript() {
    local runner_stderr_path=$1
    local runner_stdout_path=$2
    local runner_remote_status=$3
    local runner_contract_root
    local runner_expected_count
    local runner_observed_count
    local runner_reported_count
    local runner_reported_failed
    local runner_actual_failed
    local runner_first_failure
    local runner_before_hash
    local runner_after_hash
    local runner_validate_status
    local runner_ancestry_failed
    local runner_classification

    [[ ! -s "$runner_stderr_path" ]] || return 97
    runner_contract_root=$(mktemp -d /tmp/caddy-action20d-retry7-a-retry-contract.XXXXXX) || return 97
    /bin/bash "$diagnostic" --expected-assertions | LC_ALL=C sort \
        >"$runner_contract_root/expected" || {
        rm -rf -- "$runner_contract_root"
        return 97
    }
    sed -n "s/^${prefix}_assertion_\([a-z0-9_]*\)=\(true\|false\)$/\1/p" \
        "$runner_stdout_path" | LC_ALL=C sort >"$runner_contract_root/observed"
    runner_expected_count=$(wc -l <"$runner_contract_root/expected")
    runner_observed_count=$(wc -l <"$runner_contract_root/observed")
    [[ "$runner_expected_count" -gt 0 ]] || {
        rm -rf -- "$runner_contract_root"
        return 97
    }
    [[ "$runner_observed_count" -eq "$runner_expected_count" ]] || {
        rm -rf -- "$runner_contract_root"
        return 97
    }
    [[ "$runner_observed_count" -eq "$(LC_ALL=C sort -u "$runner_contract_root/observed" | wc -l)" ]] || {
        rm -rf -- "$runner_contract_root"
        return 97
    }
    cmp -s "$runner_contract_root/expected" "$runner_contract_root/observed" || {
        rm -rf -- "$runner_contract_root"
        return 97
    }
    rm -rf -- "$runner_contract_root"

    runner_reported_count=$(sed -n "s/^${prefix}_assertion_count=//p" "$runner_stdout_path")
    runner_reported_failed=$(sed -n "s/^${prefix}_failed_assertion_count=//p" "$runner_stdout_path")
    runner_actual_failed=$(grep -Ec "^${prefix}_assertion_[a-z0-9_]+=false$" "$runner_stdout_path" || true)
    runner_first_failure=$(sed -n "s/^${prefix}_first_failure=//p" "$runner_stdout_path")
    runner_before_hash=$(sed -n "s/^${prefix}_value_before_state_sha256=//p" "$runner_stdout_path")
    runner_after_hash=$(sed -n "s/^${prefix}_value_after_state_sha256=//p" "$runner_stdout_path")
    runner_validate_status=$(sed -n "s/^${prefix}_value_validate_status=//p" "$runner_stdout_path")
    runner_ancestry_failed=$(sed -n "s/^${prefix}_value_ancestry_failed_count=//p" "$runner_stdout_path")
    runner_classification=$(sed -n "s/^${prefix}_value_classification=//p" "$runner_stdout_path")
    [[ "$runner_reported_count" =~ ^[0-9]+$ && "$runner_reported_count" -eq "$runner_expected_count" ]] || return 97
    [[ "$runner_reported_failed" =~ ^[0-9]+$ && "$runner_reported_failed" -eq "$runner_actual_failed" ]] || return 97
    [[ "$runner_before_hash" =~ ^[0-9a-f]{64}$ && "$runner_after_hash" = "$runner_before_hash" ]] || return 97
    [[ "$runner_validate_status" =~ ^[0-9]+$ || "$runner_validate_status" = not_run ]] || return 97
    [[ "$runner_ancestry_failed" =~ ^[0-9]+$ ]] || return 97
    [[ "$runner_classification" =~ ^(ancestry_gate_failed|caddy_validate_passed_after_searchable_ancestry|caddy_validate_failed_after_searchable_ancestry)$ ]] || return 97
    require_one "${prefix}_health_helper_invoked=false" "$runner_stdout_path" || return 97
    require_one "${prefix}_notification_invoked=false" "$runner_stdout_path" || return 97
    require_one "${prefix}_node_b_contacted=false" "$runner_stdout_path" || return 97
    require_one "${prefix}_service_mutations=false" "$runner_stdout_path" || return 97
    require_one "${prefix}_keepalived_mutations=false" "$runner_stdout_path" || return 97
    require_one "${prefix}_vrrp_mutations=false" "$runner_stdout_path" || return 97
    require_one "${prefix}_vip_mutations=false" "$runner_stdout_path" || return 97
    require_one "${prefix}_persistent_mutations=false" "$runner_stdout_path" || return 97
    require_one "${prefix}_remote_complete=true" "$runner_stdout_path" || return 97
    if [[ "$runner_ancestry_failed" -gt 0 ]]; then
        [[ "$runner_validate_status" = not_run ]] || return 97
        [[ "$runner_classification" = ancestry_gate_failed ]] || return 97
        require_one "${prefix}_caddy_validate_invoked=false" "$runner_stdout_path" || return 97
    else
        [[ "$runner_validate_status" =~ ^[0-9]+$ ]] || return 97
        [[ "$runner_classification" != ancestry_gate_failed ]] || return 97
        require_one "${prefix}_caddy_validate_invoked=true" "$runner_stdout_path" || return 97
    fi
    if [[ "$runner_actual_failed" -eq 0 ]]; then
        [[ "$runner_remote_status" -eq 0 && "$runner_first_failure" = none ]] || return 97
        [[ "$runner_ancestry_failed" -eq 0 ]] || return 97
        [[ "$runner_classification" != ancestry_gate_failed ]] || return 97
        return 0
    fi
    [[ "$runner_remote_status" -eq 1 ]] || return 97
    [[ "$runner_first_failure" =~ ^[a-z0-9_]+$ ]] || return 97
    require_one "${prefix}_assertion_${runner_first_failure}=false" "$runner_stdout_path" || return 97
    return 1
}
write_contract_fixture() {
    local runner_fixture_label
    local runner_fixture_count

    runner_fixture_count=$(/bin/bash "$diagnostic" --expected-assertions | wc -l)
    while IFS= read -r runner_fixture_label; do
        printf '%s_assertion_%s=true\n' "$prefix" "$runner_fixture_label"
    done < <(/bin/bash "$diagnostic" --expected-assertions)
    printf '%s\n' \
        "${prefix}_value_validate_status=0" \
        "${prefix}_value_before_state_sha256=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" \
        "${prefix}_value_after_state_sha256=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" \
        "${prefix}_value_ancestry_failed_count=0" \
        "${prefix}_value_classification=caddy_validate_passed_after_searchable_ancestry" \
        "${prefix}_assertion_count=$runner_fixture_count" \
        "${prefix}_failed_assertion_count=0" \
        "${prefix}_first_failure=none" \
        "${prefix}_caddy_validate_invoked=true" \
        "${prefix}_health_helper_invoked=false" \
        "${prefix}_notification_invoked=false" \
        "${prefix}_node_b_contacted=false" \
        "${prefix}_service_mutations=false" \
        "${prefix}_keepalived_mutations=false" \
        "${prefix}_vrrp_mutations=false" \
        "${prefix}_vip_mutations=false" \
        "${prefix}_persistent_mutations=false" \
        "${prefix}_remote_complete=true"
}

case "${1:-}" in
    --self-test)
        [[ $# -eq 1 ]] || exit 64
        verify_source
        printf '%s_runner_self_test_complete=true\n' "$prefix"
        exit 0
        ;;
    --contract-test)
        [[ $# -eq 1 ]] || exit 64
        verify_source
        contract_test_root=$(mktemp -d /tmp/caddy-action20d-retry7-a-retry-runner-contract.XXXXXX)
        trap 'rm -rf -- "$contract_test_root"' EXIT
        : >"$contract_test_root/empty.stderr"
        write_contract_fixture >"$contract_test_root/valid.stdout"
        validate_transcript "$contract_test_root/empty.stderr" \
            "$contract_test_root/valid.stdout" 0
        sed '/^action_20d_retry7_a_retry_assertion_ancestry_tmp_searchable=/d' \
            "$contract_test_root/valid.stdout" >"$contract_test_root/missing.stdout"
        if validate_transcript "$contract_test_root/empty.stderr" \
            "$contract_test_root/missing.stdout" 0; then
            exit 1
        fi
        sed \
            -e 's/assertion_ancestry_work_searchable=true/assertion_ancestry_work_searchable=false/' \
            -e 's/assertion_ancestry_gate_complete=true/assertion_ancestry_gate_complete=false/' \
            -e 's/assertion_validate_probe_captured=true/assertion_validate_probe_captured=false/' \
            -e 's/assertion_validate_status_numeric=true/assertion_validate_status_numeric=false/' \
            -e 's/value_validate_status=0/value_validate_status=not_run/' \
            -e 's/value_ancestry_failed_count=0/value_ancestry_failed_count=1/' \
            -e 's/value_classification=caddy_validate_passed_after_searchable_ancestry/value_classification=ancestry_gate_failed/' \
            -e 's/failed_assertion_count=0/failed_assertion_count=4/' \
            -e 's/first_failure=none/first_failure=ancestry_work_searchable/' \
            -e 's/caddy_validate_invoked=true/caddy_validate_invoked=false/' \
            "$contract_test_root/valid.stdout" >"$contract_test_root/ancestry-blocked.stdout"
        ancestry_blocked_status=0
        validate_transcript "$contract_test_root/empty.stderr" \
            "$contract_test_root/ancestry-blocked.stdout" 1 || ancestry_blocked_status=$?
        [[ "$ancestry_blocked_status" -eq 1 ]]
        printf '%s_runner_contract_test_complete=true\n' "$prefix"
        exit 0
        ;;
    "") [[ $# -eq 0 ]] || exit 64 ;;
    *)
        printf 'Usage: %s [--self-test|--contract-test]\n' "${0##*/}" >&2
        exit 64
        ;;
esac

verify_source
working_directory_approved
work_directory=$(mktemp -d /tmp/caddy-action20d-retry7-a-retry-runner.XXXXXX)
readonly work_directory
# shellcheck disable=SC2317
cleanup() { rm -rf -- "$work_directory"; }
trap cleanup EXIT
readonly remote_stdout=$work_directory/remote.stdout
readonly remote_stderr=$work_directory/remote.stderr
touch "$remote_stdout" "$remote_stderr"
chmod 0600 "$remote_stdout" "$remote_stderr"
remote_status=0
"$ssh_binary" -T -o BatchMode=yes -o IdentitiesOnly=no \
    -o StrictHostKeyChecking=yes -o HostKeyAlias=pihole0.local.theama.co \
    pi@10.1.0.53 'cd / && sudo -n /bin/bash -s --' <"$diagnostic" \
    >"$remote_stdout" 2>"$remote_stderr" || remote_status=$?
readonly remote_status
printf '%s_remote_stdout_bytes=%s\n' "$prefix" "$(wc -c <"$remote_stdout")"
printf '%s_remote_stdout_lines=%s\n' "$prefix" "$(line_count "$remote_stdout")"
printf '%s_remote_stdout_sha256=%s\n' "$prefix" "$(file_hash "$remote_stdout")"
printf '%s_remote_stderr_bytes=%s\n' "$prefix" "$(wc -c <"$remote_stderr")"
printf '%s_remote_stderr_lines=%s\n' "$prefix" "$(line_count "$remote_stderr")"
printf '%s_remote_stderr_sha256=%s\n' "$prefix" "$(file_hash "$remote_stderr")"
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
