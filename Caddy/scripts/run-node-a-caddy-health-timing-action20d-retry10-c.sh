#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_20d_retry10_c_runner
readonly maximum_stream_bytes=16777216
readonly maximum_stream_lines=65536
script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
readonly diagnostic=$script_directory/inspect-node-a-caddy-health-timing-action20d-retry10-c.sh
readonly diagnostic_sha256=6d71149eaecbb629be2064d2eeea31b7a6416276568e884633173978b0819034
readonly ssh_binary=${CADDY_ACTION20D_RETRY10_C_SSH_BINARY:-/usr/bin/ssh}

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
emit_stream() {
    local runner_stream_label=$1
    local runner_stream_path=$2

    printf '%s_%s_bytes=%s\n' "$prefix" "$runner_stream_label" \
        "$(wc -c <"$runner_stream_path")"
    printf '%s_%s_lines=%s\n' "$prefix" "$runner_stream_label" \
        "$(line_count "$runner_stream_path")"
    printf '%s_%s_sha256=%s\n' "$prefix" "$runner_stream_label" \
        "$(file_hash "$runner_stream_path")"
    if ! safe_stream "$runner_stream_path"; then
        printf '%s_%s_classification=unsafe_retained\n' "$prefix" "$runner_stream_label" >&2
        return 97
    fi
    printf '%s_%s_classification=bounded_safe\n' "$prefix" "$runner_stream_label"
    if [[ -s "$runner_stream_path" ]]; then
        printf '%s_%s_begin\n' "$prefix" "$runner_stream_label"
        cat "$runner_stream_path"
        printf '%s_%s_end\n' "$prefix" "$runner_stream_label"
    else
        printf '%s_%s_content_secured=empty\n' "$prefix" "$runner_stream_label"
    fi
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
verify_source() {
    [[ -f "$diagnostic" && ! -L "$diagnostic" ]] || return 1
    [[ "$(file_hash "$diagnostic")" = "$diagnostic_sha256" ]] || return 1
}
validate_transcript() {
    local runner_transcript=$1
    local runner_expected_label

    while IFS= read -r runner_expected_label; do
        [[ "$(grep -Fxc "action_20d_retry10_c_assertion_${runner_expected_label}=true" \
            "$runner_transcript" || true)" -eq 1 ]] || return 1
        [[ "$(grep -Ec "^action_20d_retry10_c_assertion_${runner_expected_label}=" \
            "$runner_transcript" || true)" -eq 1 ]] || return 1
    done < <(/bin/bash "$diagnostic" --expected-assertions)
    [[ "$(grep -Ec '^action_20d_retry10_c_assertion_[a-z0-9_]+=true$' \
        "$runner_transcript" || true)" -eq "$(/bin/bash "$diagnostic" --expected-assertions | wc -l)" ]] || return 1
    [[ "$(grep -Fxc 'action_20d_retry10_c_complete_helper_invoked=false' \
        "$runner_transcript" || true)" -eq 1 ]] || return 1
    [[ "$(grep -Fxc 'action_20d_retry10_c_node_b_contacted=false' \
        "$runner_transcript" || true)" -eq 1 ]] || return 1
    [[ "$(grep -Fxc 'action_20d_retry10_c_service_mutations=false' \
        "$runner_transcript" || true)" -eq 1 ]] || return 1
    [[ "$(grep -Fxc 'action_20d_retry10_c_keepalived_mutations=false' \
        "$runner_transcript" || true)" -eq 1 ]] || return 1
    [[ "$(grep -Fxc 'action_20d_retry10_c_vrrp_mutations=false' \
        "$runner_transcript" || true)" -eq 1 ]] || return 1
    [[ "$(grep -Fxc 'action_20d_retry10_c_vip_mutations=false' \
        "$runner_transcript" || true)" -eq 1 ]] || return 1
    [[ "$(grep -Fxc 'action_20d_retry10_c_persistent_mutations=false' \
        "$runner_transcript" || true)" -eq 1 ]] || return 1
    [[ "$(grep -Fxc 'action_20d_retry10_c_remote_complete=true' \
        "$runner_transcript" || true)" -eq 1 ]] || return 1
}

case "${1:-}" in
    --self-test | --source-test | --contract-test)
        [[ $# -eq 1 ]] || exit 64
        verify_source
        working_directory_approved
        /bin/bash "$diagnostic" --self-test
        printf '%s_%s_complete=true\n' "$prefix" "${1#--}"
        exit 0
        ;;
    "") [[ $# -eq 0 ]] || exit 64 ;;
    *)
        printf 'Usage: %s [--self-test|--source-test|--contract-test]\n' "${0##*/}" >&2
        exit 64
        ;;
esac

verify_source
working_directory_approved
work_root=$(mktemp -d /tmp/caddy-action20d-retry10-c-runner.XXXXXX)
readonly work_root
# shellcheck disable=SC2317
cleanup() { rm -rf -- "$work_root"; }
trap cleanup EXIT INT TERM
readonly remote_stdout=$work_root/remote.stdout
readonly remote_stderr=$work_root/remote.stderr
: >"$remote_stdout"
: >"$remote_stderr"
chmod 0600 "$remote_stdout" "$remote_stderr"
remote_status=0
"$ssh_binary" -T -o BatchMode=yes -o IdentitiesOnly=no \
    -o StrictHostKeyChecking=yes -o HostKeyAlias=pihole0.local.theama.co \
    pi@10.1.0.53 'cd / && sudo -n /bin/bash -s --' <"$diagnostic" \
    >"$remote_stdout" 2>"$remote_stderr" || remote_status=$?
readonly remote_status
emit_stream remote_stdout "$remote_stdout" || {
    trap - EXIT
    printf '%s_protected_evidence=%s\n' "$prefix" "$work_root" >&2
    exit 97
}
emit_stream remote_stderr "$remote_stderr" || {
    trap - EXIT
    printf '%s_protected_evidence=%s\n' "$prefix" "$work_root" >&2
    exit 97
}
transcript_status=0
validate_transcript "$remote_stdout" || transcript_status=$?
readonly transcript_status
printf '%s_remote_status=%s\n' "$prefix" "$remote_status"
printf '%s_transcript_status=%s\n' "$prefix" "$transcript_status"
printf '%s_node_a_contacted=true\n' "$prefix"
printf '%s_node_b_contacted=false\n' "$prefix"
printf '%s_complete_helper_invoked=false\n' "$prefix"
printf '%s_cleanup_complete=true\n' "$prefix"
if [[ "$remote_status" -ne 0 ]]; then
    exit "$remote_status"
fi
exit "$transcript_status"
