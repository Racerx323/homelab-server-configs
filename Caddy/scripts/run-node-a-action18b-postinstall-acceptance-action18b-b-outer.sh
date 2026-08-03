#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly action_prefix=action_18b_b
readonly derivation_sha256=f0b59c6373df1f4104c93db3f8af47f33f8528c493428bea2113885e8a717662
readonly regression_sha256=63bc3ad5f5933abf3b1d1f7151b625d1aa51bee039bfc7b1bc95bb319a4aad7d
readonly rendered_inspector_sha256=f2b69e4bc7fb5f611227a48b5897808c85756c82b75eb99643865a07bf48d139
readonly rendered_runner_sha256=eb6c0343d68376acaa47716231b146da853859a58f04707c647d4d5ed359db30
readonly collision_checker_sha256=ba1e769a3d00b5884421a8860f820e2dc8a3d8074837dab930630407f047886f
readonly maximum_stream_bytes=1048576
readonly maximum_stream_lines=4096

script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
readonly caddy_root=${script_directory%/scripts}
readonly derivation="$script_directory/derive-node-a-action18b-postinstall-acceptance-action18b-b.sh"
readonly regression="$caddy_root/tests/action18b-b-node-a-postinstall-acceptance-regression.sh"
readonly collision_checker="$caddy_root/tests/check-shell-readonly-local-collisions-v2.sh"

file_hash() {
    sha256sum "$1" | awk '{ print $1 }'
}

line_count() {
    awk 'END { print NR }' "$1"
}

require_source() {
    local expected_hash=$1
    local expected_mode=$2
    local source_path=$3
    local expected_owner_group=aaron:aaron

    if [[ "${CADDY_VALIDATION_CONTAINER:-}" == 1 ]]; then
        [[ "$caddy_root" == /workspace/homelab-server-configs/Caddy ]] ||
            return 1
        expected_owner_group=root:root
    fi

    [[ -f "$source_path" && ! -L "$source_path" ]] || return 1
    [[ "$(stat -c '%U:%G:%a' "$source_path")" == "$expected_owner_group:$expected_mode" ]] ||
        return 1
    [[ "$(file_hash "$source_path")" == "$expected_hash" ]] || return 1
}

verify_sources() {
    require_source "$derivation_sha256" 755 "$derivation" || return 1
    require_source "$regression_sha256" 755 "$regression" || return 1
    require_source "$collision_checker_sha256" 755 \
        "$collision_checker" || return 1
}

stage_sources() {
    local stage_root=$1
    local staged_inspector
    local staged_runner

    install -d -m 0700 "$stage_root/Caddy/scripts" "$stage_root/Caddy/tests" ||
        return 1
    "$derivation" --output-directory "$stage_root/Caddy/scripts" >/dev/null ||
        return 1
    install -m 0755 "$collision_checker" \
        "$stage_root/Caddy/tests/check-shell-readonly-local-collisions.sh" ||
        return 1
    staged_inspector="$stage_root/Caddy/scripts/inspect-node-a-action18b-postinstall-acceptance-action18b-b.sh"
    staged_runner="$stage_root/Caddy/scripts/run-node-a-action18b-postinstall-acceptance-action18b-b.sh"
    [[ "$(file_hash "$staged_inspector")" == "$rendered_inspector_sha256" ]] ||
        return 1
    [[ "$(file_hash "$staged_runner")" == "$rendered_runner_sha256" ]] ||
        return 1
    bash -n "$staged_inspector" "$staged_runner" || return 1
    shellcheck "$staged_inspector" "$staged_runner" || return 1
    "$collision_checker" "$staged_inspector" "$staged_runner" >/dev/null ||
        return 1
    "$staged_inspector" --self-test >/dev/null || return 1
    "$staged_runner" --self-test >/dev/null || return 1
    if [[ "${CADDY_VALIDATION_CONTAINER:-}" == 1 ]]; then
        [[ "$(stat -c '%U:%G:%a' "$staged_inspector")" == root:root:755 ]] ||
            return 1
        [[ "$(stat -c '%U:%G:%a' "$staged_runner")" == root:root:755 ]] ||
            return 1
    else
        "$staged_runner" --source-test >/dev/null || return 1
    fi
    "$staged_runner" --contract-test >/dev/null || return 1
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

    printf '%s_%s_bytes=%s\n' "$action_prefix" "$stream_name" \
        "$(wc -c <"$stream_path")"
    printf '%s_%s_lines=%s\n' "$action_prefix" "$stream_name" \
        "$(line_count "$stream_path")"
    printf '%s_%s_sha256=%s\n' "$action_prefix" "$stream_name" \
        "$(file_hash "$stream_path")"
}

run_local_gates() {
    local gate_root

    gate_root=$(mktemp -d /tmp/caddy-action18b-b-outer-gate.XXXXXX) ||
        return 1
    if ! stage_sources "$gate_root"; then
        rm -rf -- "$gate_root"
        return 1
    fi
    rm -rf -- "$gate_root"
    "$regression" >/dev/null || return 1
}

case "${1:-}" in
    --self-test | --source-test | --contract-test)
        [[ $# -eq 1 ]] || exit 64
        verify_sources
        run_local_gates
        printf '%s_outer_%s_complete=true\n' "$action_prefix" "${1#--}"
        exit 0
        ;;
    "")
        [[ $# -eq 0 ]] || exit 64
        ;;
    *)
        printf 'Usage: %s [--self-test|--source-test|--contract-test]\n' \
            "${0##*/}" >&2
        exit 64
        ;;
esac

verify_sources
[[ "$PWD" == /home/aaron/code/homelab-server-configs ]]
run_local_gates
work_directory=$(mktemp -d /tmp/caddy-action18b-b-outer.XXXXXX)
readonly work_directory
cleanup() {
    # shellcheck disable=SC2317
    rm -rf -- "$work_directory"
}
trap cleanup EXIT
stage_sources "$work_directory"
readonly rendered_runner="$work_directory/Caddy/scripts/run-node-a-action18b-postinstall-acceptance-action18b-b.sh"
readonly stdout_path="$work_directory/inner.stdout"
readonly stderr_path="$work_directory/inner.stderr"
: >"$stdout_path"
: >"$stderr_path"
chmod 0600 "$stdout_path" "$stderr_path"

inner_status=0
"$rendered_runner" >"$stdout_path" 2>"$stderr_path" || inner_status=$?
readonly inner_status
emit_stream_metadata inner_stdout "$stdout_path"
emit_stream_metadata inner_stderr "$stderr_path"
if safe_stream "$stdout_path" && safe_stream "$stderr_path"; then
    printf '%s_inner_stream_classification=bounded_safe\n' "$action_prefix"
    printf '%s_inner_stdout_begin\n' "$action_prefix"
    cat "$stdout_path"
    printf '%s_inner_stdout_end\n' "$action_prefix"
    if [[ -s "$stderr_path" ]]; then
        printf '%s_inner_stderr_begin\n' "$action_prefix" >&2
        cat "$stderr_path" >&2
        printf '%s_inner_stderr_end\n' "$action_prefix" >&2
    fi
else
    printf '%s_inner_stream_classification=unsafe_retained\n' \
        "$action_prefix" >&2
    trap - EXIT
    printf '%s_protected_evidence=%s\n' "$action_prefix" \
        "$work_directory" >&2
    exit 97
fi
printf '%s_inner_status=%s\n' "$action_prefix" "$inner_status"
rm -rf -- "$work_directory"
trap - EXIT
printf '%s_outer_cleanup_complete=true\n' "$action_prefix"
exit "$inner_status"
