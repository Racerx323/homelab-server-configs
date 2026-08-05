#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_20b_a
readonly inspector_sha256=dc0a52d807490ca71946f7a310a973712fe09a30f5355a879c5c977012206744
readonly expected_fragment_sha256=294d5ba44d903ba4ab3ab4330ae3ae05e0160e2b134d71e91a787b65dd96dc4d
readonly expected_backup_path=/var/backups/caddy-ha/action19a-node-b-keepalived-fragment.no5a5x
readonly expected_health_backup_path=/var/backups/caddy-ha/action20b-node-b-health-context.orvXY3
readonly expected_health_sha256=9bf531ab7cbb047f8f09ce5956b597d5c8b6ede397c166f0b040e2e92fe8bbab
readonly maximum_stream_bytes=1048576
readonly maximum_stream_lines=4096

script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
readonly caddy_root=${script_directory%/scripts}
readonly inspector="$script_directory/inspect-node-b-caddy-health-postinstall-action20b-a.sh"
readonly collision_checker="$caddy_root/tests/check-shell-readonly-local-collisions-v2.sh"
readonly ssh_binary=${CADDY_ACTION20BA_SSH_BINARY:-/usr/bin/ssh}

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }
line_count() { awk 'END { print NR }' "$1"; }

safe_stream() {
    local stream_path=$1

    [[ "$(wc -c <"$stream_path")" -le "$maximum_stream_bytes" ]] || return 1
    [[ "$(line_count "$stream_path")" -le "$maximum_stream_lines" ]] || return 1
    ! LC_ALL=C grep -n '[^[:print:][:space:]]' "$stream_path" >/dev/null || return 1
    ! grep -Eqi \
        'BEGIN [A-Z ]*PRIVATE KEY|CADDY_TLS_PRIVATE_KEY_PEM|PRIVATE_KEY=|DOPPLER_TOKEN|Authorization:[[:space:]]*Bearer' \
        "$stream_path"
}

emit_stream_metadata() {
    local stream_name=$1
    local stream_path=$2

    printf '%s_%s_bytes=%s\n' "$prefix" "$stream_name" "$(wc -c <"$stream_path")"
    printf '%s_%s_lines=%s\n' "$prefix" "$stream_name" "$(line_count "$stream_path")"
    printf '%s_%s_sha256=%s\n' "$prefix" "$stream_name" "$(file_hash "$stream_path")"
}

require_one() {
    local expected_line=$1
    local transcript_path=$2

    [[ "$(grep -Fxc "$expected_line" "$transcript_path")" -eq 1 ]]
}

validate_transcript() {
    local error_path=$1
    local output_path=$2
    local observed_remote_status=$3
    local contract_root
    local expected_count
    local failed_count
    local first_failure
    local observed_count
    local reported_count
    local reported_failed
    local before_hash
    local after_hash

    [[ ! -s "$error_path" ]] || return 97
    contract_root=$(mktemp -d /tmp/caddy-action20b-a-contract.XXXXXX) || return 97
    "$inspector" --expected-assertions | LC_ALL=C sort >"$contract_root/expected" ||
        {
            rm -rf -- "$contract_root"
            return 97
        }
    sed -n \
        "s/^${prefix}_assertion_\([a-z0-9_]*\)=\(true\|false\)$/\1/p" \
        "$output_path" | LC_ALL=C sort >"$contract_root/observed"
    expected_count=$(wc -l <"$contract_root/expected")
    observed_count=$(wc -l <"$contract_root/observed")
    if [[ "$expected_count" -eq 0 ||
        "$expected_count" -ne "$(LC_ALL=C sort -u "$contract_root/expected" | wc -l)" ||
        "$observed_count" -ne "$expected_count" ||
        "$observed_count" -ne "$(LC_ALL=C sort -u "$contract_root/observed" | wc -l)" ]] ||
        ! cmp -s "$contract_root/expected" "$contract_root/observed"; then
        rm -rf -- "$contract_root"
        return 97
    fi
    rm -rf -- "$contract_root"

    reported_count=$(sed -n "s/^${prefix}_assertion_count=//p" "$output_path")
    reported_failed=$(sed -n "s/^${prefix}_failed_assertion_count=//p" "$output_path")
    first_failure=$(sed -n "s/^${prefix}_first_failure=//p" "$output_path")
    [[ "$reported_count" =~ ^[0-9]+$ && "$reported_count" -eq "$expected_count" ]] ||
        return 97
    [[ "$reported_failed" =~ ^[0-9]+$ ]] || return 97
    failed_count=$(grep -Ec "^${prefix}_assertion_[a-z0-9_]+=false$" \
        "$output_path" || true)
    [[ "$reported_failed" -eq "$failed_count" ]] || return 97

    require_one "${prefix}_value_expected_assertion_count=$expected_count" "$output_path" ||
        return 97
    require_one "${prefix}_value_backup_path=$expected_backup_path" "$output_path" ||
        return 97
    require_one "${prefix}_value_backup_count=1" "$output_path" || return 97
    require_one "${prefix}_value_health_backup_path=$expected_health_backup_path" \
        "$output_path" || return 97
    require_one "${prefix}_value_health_backup_count=1" "$output_path" || return 97
    require_one "${prefix}_value_health_sha256=$expected_health_sha256" \
        "$output_path" || return 97
    require_one "${prefix}_value_fragment_sha256=$expected_fragment_sha256" \
        "$output_path" || return 97
    require_one "${prefix}_helper_execution=true" "$output_path" || return 97
    require_one "${prefix}_filesystem_mutations=false" "$output_path" || return 97
    require_one "${prefix}_service_mutations=false" "$output_path" || return 97
    require_one "${prefix}_vrrp_mutations=false" "$output_path" || return 97
    require_one "${prefix}_vip_mutations=false" "$output_path" || return 97
    require_one "${prefix}_persistent_mutations=false" "$output_path" || return 97
    require_one "${prefix}_remote_complete=true" "$output_path" || return 97

    before_hash=$(sed -n "s/^${prefix}_value_before_state_sha256=//p" "$output_path")
    after_hash=$(sed -n "s/^${prefix}_value_after_state_sha256=//p" "$output_path")
    [[ "$before_hash" =~ ^[0-9a-f]{64}$ && "$after_hash" = "$before_hash" ]] ||
        return 97

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

    expected_count=$("$inspector" --expected-assertions | wc -l)
    while IFS= read -r assertion_label; do
        printf '%s_assertion_%s=true\n' "$prefix" "$assertion_label"
    done < <("$inspector" --expected-assertions)
    printf '%s\n' \
        "${prefix}_value_expected_assertion_count=$expected_count" \
        "${prefix}_value_backup_path=$expected_backup_path" \
        "${prefix}_value_backup_count=1" \
        "${prefix}_value_health_backup_path=$expected_health_backup_path" \
        "${prefix}_value_health_backup_count=1" \
        "${prefix}_value_health_sha256=$expected_health_sha256" \
        "${prefix}_value_main_sha256=$state_hash" \
        "${prefix}_value_fragment_sha256=$expected_fragment_sha256" \
        "${prefix}_value_before_state_sha256=$state_hash" \
        "${prefix}_value_after_state_sha256=$state_hash" \
        "${prefix}_assertion_count=$expected_count" \
        "${prefix}_failed_assertion_count=0" \
        "${prefix}_first_failure=none" \
        "${prefix}_helper_execution=true" \
        "${prefix}_filesystem_mutations=false" \
        "${prefix}_service_mutations=false" \
        "${prefix}_vrrp_mutations=false" \
        "${prefix}_vip_mutations=false" \
        "${prefix}_persistent_mutations=false" \
        "${prefix}_remote_complete=true"
}

verify_sources() {
    [[ -f "$inspector" && ! -L "$inspector" && -x "$inspector" ]] || return 1
    [[ "$(file_hash "$inspector")" = "$inspector_sha256" ]] || return 1
    [[ -x "$collision_checker" ]] || return 1
    bash -n "$inspector" || return 1
    shellcheck "$inspector" || return 1
    "$collision_checker" "$inspector" >/dev/null || return 1
    "$inspector" --self-test >/dev/null || return 1
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
        contract_root=$(mktemp -d /tmp/caddy-action20b-a-runner-contract.XXXXXX)
        trap 'rm -rf -- "$contract_root"' EXIT
        : >"$contract_root/empty.err"
        write_contract_fixture >"$contract_root/valid.out"
        validate_transcript "$contract_root/empty.err" "$contract_root/valid.out" 0
        cp -- "$contract_root/valid.out" "$contract_root/missing.out"
        sed -i "/^${prefix}_assertion_fragment_hash_exact=/d" "$contract_root/missing.out"
        if validate_transcript "$contract_root/empty.err" "$contract_root/missing.out" 0; then
            exit 1
        fi
        cp -- "$contract_root/valid.out" "$contract_root/duplicate.out"
        printf '%s_assertion_fragment_hash_exact=true\n' "$prefix" \
            >>"$contract_root/duplicate.out"
        if validate_transcript "$contract_root/empty.err" "$contract_root/duplicate.out" 0; then
            exit 1
        fi
        printf '%s_runner_contract_test_complete=true\n' "$prefix"
        exit 0
        ;;
    "")
        [[ $# -eq 0 ]]
        ;;
    *)
        printf 'Usage: %s [--self-test|--contract-test]\n' "${0##*/}" >&2
        exit 64
        ;;
esac

verify_sources
[[ "$PWD" = /home/aaron/code/homelab-server-configs ]]
work_directory=$(mktemp -d /tmp/caddy-action20b-a-runner.XXXXXX)
readonly work_directory
# shellcheck disable=SC2317
cleanup() { rm -rf -- "$work_directory"; }
trap cleanup EXIT
readonly remote_stdout=$work_directory/remote.stdout
readonly remote_stderr=$work_directory/remote.stderr
: >"$remote_stdout"
: >"$remote_stderr"
chmod 0600 "$remote_stdout" "$remote_stderr"

remote_status=0
if [[ "${CADDY_ACTION20BA_INTERCEPTED_TEST:-}" = 1 ]]; then
    "$ssh_binary" -T -o BatchMode=yes -o IdentitiesOnly=no \
        -o StrictHostKeyChecking=yes -o HostKeyAlias=pihole00.local.theama.co \
        pi@10.1.0.54 'cd / && sudo -n /bin/bash -s --' <"$inspector" \
        >"$remote_stdout" 2>"$remote_stderr" || remote_status=$?
else
    /usr/bin/ssh -T -o BatchMode=yes -o IdentitiesOnly=no \
        -o StrictHostKeyChecking=yes -o HostKeyAlias=pihole00.local.theama.co \
        pi@10.1.0.54 'cd / && sudo -n /bin/bash -s --' <"$inspector" \
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
validate_transcript "$remote_stderr" "$remote_stdout" "$remote_status" ||
    validation_status=$?
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
