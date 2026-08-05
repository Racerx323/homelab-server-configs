#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_20c
readonly candidate_sha256=9bf531ab7cbb047f8f09ce5956b597d5c8b6ede397c166f0b040e2e92fe8bbab
readonly installer_sha256=de17f05035c79e679166c8d20ae510cc9b570cc61d65d7fffe1bdb7a65ce56a1
readonly runner_sha256=328ea6ace824e191129b8703143ae99c1f1ee971671dc1f7423889b1e4d95e82
readonly regression_sha256=b5b18b91a03edf2694995686e039b3583859c7fc2803c75dafd8017e271198f1
readonly collision_sha256=ba1e769a3d00b5884421a8860f820e2dc8a3d8074837dab930630407f047886f
readonly conditional_sha256=68cd687916f9d8be78f50af7a410d376f457ca74ab906a8e459795de6c495455
readonly transcript_sha256=99e0040d785e70a4f2e8d1796f8c6bf29675593d1ae5d13e54d9ac2dceebe44c
readonly output_evidence_sha256=84873a1ad3ee1745fe445f179f6a002c2ccee5b147b93cc3db0d6f17d54d4441
readonly maximum_stream_bytes=2097152
readonly maximum_stream_lines=8192

script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
readonly caddy_root=${script_directory%/scripts}
readonly candidate="$script_directory/check-caddy-action20b.sh"
readonly installer="$script_directory/install-node-a-caddy-health-context-action20c.sh"
readonly runner="$script_directory/run-node-a-caddy-health-context-correction-action20c.sh"
readonly regression="$caddy_root/tests/action20c-node-a-caddy-health-context-correction-regression.sh"
readonly collision_checker="$caddy_root/tests/check-shell-readonly-local-collisions-v2.sh"
readonly conditional_policy="$caddy_root/tests/conditional-validator-errexit-policy-regression.sh"
readonly transcript_policy="$caddy_root/tests/transcript-contract-ratchet-policy-regression.sh"
readonly output_evidence_policy="$caddy_root/tests/transaction-output-evidence-policy-regression.sh"

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }
line_count() { awk 'END { print NR }' "$1"; }
require_quiet_bash_gate() {
    local local_gate_label=$1
    local local_gate_script=$2

    shift 2
    if /bin/bash "$local_gate_script" "$@" >/dev/null; then
        printf '%s_outer_gate_%s=true\n' "$prefix" "$local_gate_label"
        return 0
    fi
    printf '%s_outer_gate_%s=false\n' "$prefix" "$local_gate_label" >&2
    return 1
}
require_source() {
    local expected_hash=$1
    local source_path=$2
    local source_identity

    source_identity="$(id -un):$(id -gn):755"
    [[ -f "$source_path" && ! -L "$source_path" && -x "$source_path" ]] || return 1
    [[ "$(stat -c '%U:%G:%a' "$source_path")" = "$source_identity" ]] || return 1
    [[ "$(file_hash "$source_path")" = "$expected_hash" ]] || return 1
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
verify_sources() {
    require_source "$candidate_sha256" "$candidate" || return 1
    require_source "$installer_sha256" "$installer" || return 1
    require_source "$runner_sha256" "$runner" || return 1
    require_source "$regression_sha256" "$regression" || return 1
    require_source "$collision_sha256" "$collision_checker" || return 1
    require_source "$conditional_sha256" "$conditional_policy" || return 1
    require_source "$transcript_sha256" "$transcript_policy" || return 1
    require_source "$output_evidence_sha256" "$output_evidence_policy" || return 1
    /bin/bash -n "$candidate" "$installer" "$runner" "$regression" || return 1
    shellcheck "$candidate" "$installer" "$runner" "$regression" || return 1
    /bin/bash "$collision_checker" "$candidate" "$installer" "$runner" \
        "$regression" >/dev/null || return 1
}
run_local_gates() {
    if verify_sources; then
        printf '%s_outer_gate_sources_verified=true\n' "$prefix"
    else
        printf '%s_outer_gate_sources_verified=false\n' "$prefix" >&2
        return 1
    fi
    require_quiet_bash_gate conditional_validator_policy \
        "$conditional_policy" || return 1
    require_quiet_bash_gate transcript_contract_policy \
        "$transcript_policy" || return 1
    require_quiet_bash_gate transaction_output_evidence_policy \
        "$output_evidence_policy" || return 1
    require_quiet_bash_gate regression_self_test \
        "$regression" --self-test || return 1
    require_quiet_bash_gate regression_production_path \
        "$regression" || return 1
}
safe_stream() {
    local inspected_stream=$1

    [[ "$(wc -c <"$inspected_stream")" -le "$maximum_stream_bytes" ]] || return 1
    [[ "$(line_count "$inspected_stream")" -le "$maximum_stream_lines" ]] || return 1
    ! LC_ALL=C grep -n '[^[:print:][:space:]]' "$inspected_stream" >/dev/null || return 1
    ! grep -Eqi \
        'BEGIN [A-Z ]*PRIVATE KEY|CADDY_TLS_PRIVATE_KEY_PEM|PRIVATE_KEY=|DOPPLER_TOKEN|Authorization:[[:space:]]*Bearer' \
        "$inspected_stream"
}
emit_stream() {
    local stream_name=$1
    local stream_path=$2

    printf '%s_%s_bytes=%s\n' "$prefix" "$stream_name" "$(wc -c <"$stream_path")"
    printf '%s_%s_lines=%s\n' "$prefix" "$stream_name" "$(line_count "$stream_path")"
    printf '%s_%s_sha256=%s\n' "$prefix" "$stream_name" "$(file_hash "$stream_path")"
    if [[ ! -s "$stream_path" ]]; then
        printf '%s_%s_content_secured=empty\n' "$prefix" "$stream_name"
        return 0
    fi
    printf '%s_%s_begin\n' "$prefix" "$stream_name"
    cat "$stream_path"
    printf '%s_%s_end\n' "$prefix" "$stream_name"
}

case "${1:-}" in
    --expected-local-gates)
        [[ $# -eq 1 ]] || exit 64
        printf '%s\n' \
            sources_verified \
            conditional_validator_policy \
            transcript_contract_policy \
            transaction_output_evidence_policy \
            regression_self_test \
            regression_production_path
        exit 0
        ;;
    --self-test | --source-test | --contract-test)
        [[ $# -eq 1 ]] || exit 64
        run_local_gates
        printf '%s_outer_%s_complete=true\n' "$prefix" "${1#--}"
        exit 0
        ;;
    "") [[ $# -eq 0 ]] || exit 64 ;;
    *)
        printf 'Usage: %s [--expected-local-gates|--self-test|--source-test|--contract-test]\n' \
            "${0##*/}" >&2
        exit 64
        ;;
esac

run_local_gates
working_directory_approved
work_directory=$(mktemp -d /tmp/caddy-action20c-outer.XXXXXX)
readonly work_directory
cleanup() {
    # shellcheck disable=SC2317
    rm -rf -- "$work_directory"
}
trap cleanup EXIT
readonly stdout_path=$work_directory/runner.stdout
readonly stderr_path=$work_directory/runner.stderr
: >"$stdout_path"
: >"$stderr_path"
chmod 0600 "$stdout_path" "$stderr_path"
runner_status=0
/bin/bash "$runner" >"$stdout_path" 2>"$stderr_path" || runner_status=$?
readonly runner_status
if ! safe_stream "$stdout_path" || ! safe_stream "$stderr_path"; then
    printf '%s_outer_stream_classification=unsafe_retained\n' "$prefix" >&2
    trap - EXIT
    printf '%s_outer_protected_evidence=%s\n' "$prefix" "$work_directory" >&2
    exit 97
fi
printf '%s_outer_stream_classification=bounded_safe\n' "$prefix"
emit_stream runner_stdout "$stdout_path"
emit_stream runner_stderr "$stderr_path"
printf '%s_runner_status=%s\n' "$prefix" "$runner_status"
rm -rf -- "$work_directory"
trap - EXIT
printf '%s_outer_cleanup_complete=true\n' "$prefix"
exit "$runner_status"
