#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_19b_a
readonly expected_target=pi@10.1.0.54
readonly expected_host_alias=pihole00.local.theama.co
readonly expected_assertions=88
readonly baseline_sha256=162f153d116e53aba95775836c4a5cb6677ad7fd080c673ca6c5ac8fb0092a0f
readonly inspector_sha256=71159ea5e0fa7c62f984ebe47742d9d0f235d570d3be948406ed93ad20cfe544
readonly maximum_stream_bytes=1048576
readonly maximum_stream_lines=4096

script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
readonly caddy_root=${script_directory%/scripts}
readonly baseline="$script_directory/inspect-node-b-keepalived-helper-prerequisite-action19a-a.sh"
readonly inspector="$script_directory/inspect-node-b-action19b-postfailure-action19b-a.sh"
readonly collision_checker="$caddy_root/tests/check-shell-readonly-local-collisions-v2.sh"

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }
line_count() { awk 'END { print NR }' "$1"; }

require_source() {
    local expected_hash=$1
    local source_path=$2

    [[ -f "$source_path" && ! -L "$source_path" ]] || return 1
    [[ "$(stat -c '%U:%G:%a' "$source_path")" = "$(id -un):$(id -gn):755" ]] || return 1
    [[ "$(file_hash "$source_path")" = "$expected_hash" ]]
}

verify_sources() {
    require_source "$baseline_sha256" "$baseline" || return 1
    require_source "$inspector_sha256" "$inspector" || return 1
    [[ -x "$collision_checker" ]] || return 1
    bash -n "$baseline" "$inspector" || return 1
    "$collision_checker" "$baseline" "$inspector" >/dev/null || return 1
    "$inspector" --self-test "$baseline" >/dev/null || return 1
    "$inspector" --contract-test "$baseline" >/dev/null || return 1
}

working_directory_approved() {
    case "$PWD" in
        /home/aaron/code/homelab-server-configs) return 0 ;;
        /workspace/homelab-server-configs)
            [[ "${CADDY_VALIDATION_CONTAINER:-}" = 1 ]]
            return
            ;;
    esac
    return 1
}

safe_stream() {
    local stream_path=$1

    [[ "$(wc -c <"$stream_path")" -le "$maximum_stream_bytes" ]] || return 1
    [[ "$(line_count "$stream_path")" -le "$maximum_stream_lines" ]] || return 1
    ! LC_ALL=C grep -n '[^[:print:][:space:]]' "$stream_path" >/dev/null ||
        return 1
    ! grep -Eqi \
        'BEGIN [A-Z ]*PRIVATE KEY|CADDY_TLS_PRIVATE_KEY_PEM|PRIVATE_KEY=|DOPPLER_TOKEN|Authorization:[[:space:]]*Bearer' \
        "$stream_path"
}

emit_stream_metadata() {
    local stream_name=$1
    local stream_path=$2

    printf '%s_%s_bytes=%s\n' "$prefix" "$stream_name" \
        "$(wc -c <"$stream_path")"
    printf '%s_%s_lines=%s\n' "$prefix" "$stream_name" \
        "$(line_count "$stream_path")"
    printf '%s_%s_sha256=%s\n' "$prefix" "$stream_name" \
        "$(file_hash "$stream_path")"
}

validate_transcript() {
    local error_path=$1
    local output_path=$2
    local remote_status_value=$3
    local observed_count
    local unique_count
    local required_marker

    [[ "$remote_status_value" -eq 0 ]] || return 1
    [[ ! -s "$error_path" ]] || return 1
    [[ "$(grep -Ec "^${prefix}_assertion_[a-z0-9_]+=false$" \
        "$output_path" || true)" -eq 0 ]] || return 1
    observed_count=$(grep -Ec "^${prefix}_assertion_[a-z0-9_]+=true$" \
        "$output_path" || true)
    [[ "$observed_count" -eq "$expected_assertions" ]] || return 1
    unique_count=$(sed -n \
        "s/^\(${prefix}_assertion_[a-z0-9_]*\)=true$/\1/p" \
        "$output_path" | LC_ALL=C sort -u | wc -l)
    [[ "$unique_count" -eq "$expected_assertions" ]] || return 1
    for required_marker in \
        "${prefix}_assertion_count=${expected_assertions}" \
        "${prefix}_failed_assertion_count=0" \
        "${prefix}_first_failure=none" \
        "${prefix}_helper_invoked=false" \
        "${prefix}_filesystem_mutation=false" \
        "${prefix}_service_mutation=false" \
        "${prefix}_keepalived_mutation=false" \
        "${prefix}_vrrp_vip_mutation=false" \
        "${prefix}_persistent_mutation=false" \
        "${prefix}_inspection_complete=true"; do
        [[ "$(grep -Fxc "$required_marker" "$output_path")" -eq 1 ]] ||
            return 1
    done
}

write_fixture() {
    local fixture_path=$1
    local fixture_index

    for fixture_index in $(seq 1 "$expected_assertions"); do
        printf '%s_assertion_fixture_%03d=true\n' "$prefix" "$fixture_index"
    done >"$fixture_path"
    printf '%s\n' \
        "${prefix}_assertion_count=${expected_assertions}" \
        "${prefix}_failed_assertion_count=0" \
        "${prefix}_first_failure=none" \
        "${prefix}_helper_invoked=false" \
        "${prefix}_filesystem_mutation=false" \
        "${prefix}_service_mutation=false" \
        "${prefix}_keepalived_mutation=false" \
        "${prefix}_vrrp_vip_mutation=false" \
        "${prefix}_persistent_mutation=false" \
        "${prefix}_inspection_complete=true" >>"$fixture_path"
}

case "${1:-}" in
    --self-test | --source-test)
        [[ $# -eq 1 ]] || exit 64
        verify_sources
        printf '%s_runner_%s_complete=true\n' "$prefix" "${1#--}"
        exit 0
        ;;
    --contract-test)
        [[ $# -eq 1 ]] || exit 64
        verify_sources
        contract_root=$(mktemp -d /tmp/caddy-action19b-a-runner-contract.XXXXXX)
        readonly contract_root
        trap 'rm -rf -- "$contract_root"' EXIT
        : >"$contract_root/empty.err"
        write_fixture "$contract_root/valid"
        validate_transcript "$contract_root/empty.err" "$contract_root/valid" 0
        printf '%s_runner_contract_test_complete=true\n' "$prefix"
        exit 0
        ;;
    "") [[ $# -eq 0 ]] || exit 64 ;;
    *) exit 64 ;;
esac

verify_sources
working_directory_approved
work_directory=$(mktemp -d /tmp/caddy-action19b-a-runner.XXXXXX)
readonly work_directory
cleanup() {
    # shellcheck disable=SC2317
    rm -rf -- "$work_directory"
}
trap cleanup EXIT
readonly archive_path="$work_directory/payload.tar"
readonly remote_path="$work_directory/remote.sh"
readonly stdout_path="$work_directory/remote.stdout"
readonly stderr_path="$work_directory/remote.stderr"
: >"$stdout_path"
: >"$stderr_path"
chmod 0600 "$stdout_path" "$stderr_path"
tar -cf "$archive_path" -C "$script_directory" \
    "${baseline##*/}" "${inspector##*/}"
# Remote variables deliberately expand only on Node B.
# shellcheck disable=SC2016
{
    printf '%s\n' \
        '#!/usr/bin/env bash' 'set -Eeuo pipefail' 'set +x' 'umask 077' \
        'cd /' \
        'stage=$(mktemp -d /run/caddy-action19b-a-stage.XXXXXX)' \
        'cleanup() { rm -rf -- "$stage"; }' 'trap cleanup EXIT' \
        'base64 -d >"$stage/payload.tar" <<'\''ACTION19B_A_ARCHIVE'\'''
    base64 "$archive_path"
    printf '%s\n' 'ACTION19B_A_ARCHIVE' \
        'tar -xf "$stage/payload.tar" -C "$stage" --no-same-owner --no-same-permissions' \
        'chown root:root "$stage"/*' 'chmod 0700 "$stage"/*' 'cd /' \
        '/bin/bash "$stage/inspect-node-b-action19b-postfailure-action19b-a.sh" --baseline-inspector "$stage/inspect-node-b-keepalived-helper-prerequisite-action19a-a.sh"'
} >"$remote_path"
chmod 0600 "$remote_path"
bash -n "$remote_path"

remote_status=0
ssh -T -o BatchMode=yes -o ConnectTimeout=5 \
    -o "HostKeyAlias=$expected_host_alias" -o StrictHostKeyChecking=yes \
    "$expected_target" 'cd / && sudo -n bash -s' \
    <"$remote_path" >"$stdout_path" 2>"$stderr_path" || remote_status=$?
readonly remote_status
emit_stream_metadata remote_stdout "$stdout_path"
emit_stream_metadata remote_stderr "$stderr_path"
if safe_stream "$stdout_path" && safe_stream "$stderr_path"; then
    printf '%s_remote_stream_classification=bounded_safe\n' "$prefix"
    printf '%s_remote_stdout_begin\n' "$prefix"
    cat "$stdout_path"
    printf '%s_remote_stdout_end\n' "$prefix"
    if [[ -s "$stderr_path" ]]; then
        printf '%s_remote_stderr_begin\n' "$prefix" >&2
        cat "$stderr_path" >&2
        printf '%s_remote_stderr_end\n' "$prefix" >&2
    fi
else
    printf '%s_remote_stream_classification=unsafe_retained\n' "$prefix" >&2
    trap - EXIT
    printf '%s_protected_evidence=%s\n' "$prefix" "$work_directory" >&2
    exit 97
fi
if ! validate_transcript "$stderr_path" "$stdout_path" "$remote_status"; then
    printf '%s_runner_acceptance=false\n' "$prefix" >&2
    exit 97
fi
printf '%s_runner_acceptance=true\n' "$prefix"
rm -rf -- "$work_directory"
trap - EXIT
printf '%s_workstation_cleanup_complete=true\n' "$prefix"
