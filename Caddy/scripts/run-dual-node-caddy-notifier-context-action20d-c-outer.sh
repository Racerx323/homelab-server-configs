#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_20d_c
readonly probe_sha256=defff2a76889c084b9903c2012b3fe16fdb8dd581882e4acb7dd62d6f625524d
readonly runner_sha256=a492843c8439339a95cc996c437a2dfc7ce7710057940cf82b7dcde25ffad77c
readonly regression_sha256=2dc6886e747e18d1dc699954977fae9c0cc701c8aac73bd34e9d825471bb1a9e
readonly collision_checker_sha256=ba1e769a3d00b5884421a8860f820e2dc8a3d8074837dab930630407f047886f
readonly conditional_policy_sha256=68cd687916f9d8be78f50af7a410d376f457ca74ab906a8e459795de6c495455
readonly transcript_policy_sha256=99e0040d785e70a4f2e8d1796f8c6bf29675593d1ae5d13e54d9ac2dceebe44c
readonly output_policy_sha256=84873a1ad3ee1745fe445f179f6a002c2ccee5b147b93cc3db0d6f17d54d4441
readonly maximum_stream_bytes=4194304
readonly maximum_stream_lines=16384

script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
readonly caddy_root=${script_directory%/scripts}
readonly probe="$script_directory/inspect-caddy-notifier-context-action20d-c.sh"
readonly runner="$script_directory/run-dual-node-caddy-notifier-context-action20d-c.sh"
readonly regression="$caddy_root/tests/action20d-c-dual-node-notifier-context-regression.sh"
readonly collision_checker="$caddy_root/tests/check-shell-readonly-local-collisions-v2.sh"
readonly conditional_policy="$caddy_root/tests/conditional-validator-errexit-policy-regression.sh"
readonly transcript_policy="$caddy_root/tests/transcript-contract-ratchet-policy-regression.sh"
readonly output_policy="$caddy_root/tests/transaction-output-evidence-policy-regression.sh"

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }
line_count() { awk 'END { print NR }' "$1"; }
require_source() {
    local expected_hash=$1
    local source_path=$2
    local expected_identity

    expected_identity="$(id -un):$(id -gn):755"
    [[ -f "$source_path" && ! -L "$source_path" && -x "$source_path" ]] || return 1
    [[ "$(stat -c '%U:%G:%a' "$source_path")" = "$expected_identity" ]] || return 1
    [[ "$(file_hash "$source_path")" = "$expected_hash" ]] || return 1
}
require_local_gate() {
    local local_gate_label=$1

    shift
    if /bin/bash "$@" >/dev/null; then
        printf '%s_outer_gate_%s=true\n' "$prefix" "$local_gate_label"
        return 0
    fi
    printf '%s_outer_gate_%s=false\n' "$prefix" "$local_gate_label" >&2
    return 1
}
verify_sources() {
    require_source "$probe_sha256" "$probe" || return 1
    require_source "$runner_sha256" "$runner" || return 1
    require_source "$regression_sha256" "$regression" || return 1
    require_source "$collision_checker_sha256" "$collision_checker" || return 1
    require_source "$conditional_policy_sha256" "$conditional_policy" || return 1
    require_source "$transcript_policy_sha256" "$transcript_policy" || return 1
    require_source "$output_policy_sha256" "$output_policy" || return 1
    bash -n "$probe" "$runner" "$regression" || return 1
    shellcheck "$probe" "$runner" "$regression" || return 1
    /bin/bash "$collision_checker" "$0" "$probe" "$runner" "$regression" \
        "$conditional_policy" "$transcript_policy" "$output_policy" \
        >/dev/null || return 1
}
run_local_gates() {
    if verify_sources; then
        printf '%s_outer_gate_sources_verified=true\n' "$prefix"
    else
        printf '%s_outer_gate_sources_verified=false\n' "$prefix" >&2
        return 1
    fi
    require_local_gate conditional_validator_policy "$conditional_policy" || return 1
    require_local_gate transcript_contract_policy "$transcript_policy" || return 1
    require_local_gate output_evidence_policy "$output_policy" || return 1
    require_local_gate probe_self_test "$probe" --self-test || return 1
    require_local_gate runner_self_test "$runner" --self-test || return 1
    require_local_gate runner_contract_test "$runner" --contract-test || return 1
    require_local_gate regression_production_path "$regression" || return 1
}
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

case "${1:-}" in
    --expected-local-gates)
        [[ $# -eq 1 ]] || exit 64
        printf '%s\n' sources_verified conditional_validator_policy \
            transcript_contract_policy output_evidence_policy probe_self_test \
            runner_self_test runner_contract_test regression_production_path
        exit 0
        ;;
    --self-test | --source-test | --contract-test)
        [[ $# -eq 1 ]] || exit 64
        run_local_gates
        printf '%s_outer_%s_complete=true\n' "$prefix" "${1#--}"
        exit 0
        ;;
    "")
        [[ $# -eq 0 ]] || exit 64
        ;;
    *)
        printf 'Usage: %s [--expected-local-gates|--self-test|--source-test|--contract-test]\n' \
            "${0##*/}" >&2
        exit 64
        ;;
esac

run_local_gates
[[ "$PWD" = /home/aaron/code/homelab-server-configs ]]
work_directory=$(mktemp -d /tmp/caddy-action20d-c-outer.XXXXXX)
readonly work_directory
# shellcheck disable=SC2317
cleanup() { rm -rf -- "$work_directory"; }
trap cleanup EXIT
readonly stdout_path=$work_directory/inner.stdout
readonly stderr_path=$work_directory/inner.stderr
: >"$stdout_path"
: >"$stderr_path"
chmod 0600 "$stdout_path" "$stderr_path"

inner_status=0
/bin/bash "$runner" >"$stdout_path" 2>"$stderr_path" || inner_status=$?
readonly inner_status
emit_stream_metadata inner_stdout "$stdout_path"
emit_stream_metadata inner_stderr "$stderr_path"
if safe_stream "$stdout_path" && safe_stream "$stderr_path"; then
    printf '%s_inner_stream_classification=bounded_safe\n' "$prefix"
    if [[ -s "$stdout_path" ]]; then
        printf '%s_inner_stdout_begin\n' "$prefix"
        cat "$stdout_path"
        printf '%s_inner_stdout_end\n' "$prefix"
    else
        printf '%s_inner_stdout_content_secured=empty\n' "$prefix"
    fi
    if [[ -s "$stderr_path" ]]; then
        printf '%s_inner_stderr_begin\n' "$prefix" >&2
        cat "$stderr_path" >&2
        printf '%s_inner_stderr_end\n' "$prefix" >&2
    else
        printf '%s_inner_stderr_content_secured=empty\n' "$prefix"
    fi
else
    printf '%s_inner_stream_classification=unsafe_retained\n' "$prefix" >&2
    trap - EXIT
    printf '%s_protected_evidence=%s\n' "$prefix" "$work_directory" >&2
    exit 97
fi
printf '%s_inner_status=%s\n' "$prefix" "$inner_status"
rm -rf -- "$work_directory"
trap - EXIT
printf '%s_outer_cleanup_complete=true\n' "$prefix"
exit "$inner_status"
