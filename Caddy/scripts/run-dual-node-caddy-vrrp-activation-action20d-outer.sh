#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_20d
readonly transaction_sha256=f20e90b0991bdb3aa5b1552496e25a2bfdb3e28a2746ce67eacec6fe603a7e79
readonly runner_sha256=f9df02166d9c92add920c188d2fddb68ab8bb803a9a77c185090adcb2e6f43d8
readonly regression_sha256=f2566670baf26ac2e2e813346b15167f75c16abe524bab382045f158bd53da00
readonly collision_checker_sha256=ba1e769a3d00b5884421a8860f820e2dc8a3d8074837dab930630407f047886f
readonly conditional_policy_sha256=68cd687916f9d8be78f50af7a410d376f457ca74ab906a8e459795de6c495455
readonly output_policy_sha256=84873a1ad3ee1745fe445f179f6a002c2ccee5b147b93cc3db0d6f17d54d4441
readonly maximum_stream_bytes=8388608
readonly maximum_stream_lines=32768

script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
readonly caddy_root=${script_directory%/scripts}
readonly transaction="$script_directory/activate-caddy-vrrp-node-action20d.sh"
readonly runner="$script_directory/run-dual-node-caddy-vrrp-activation-action20d.sh"
readonly regression="$caddy_root/tests/action20d-dual-node-caddy-vrrp-activation-regression.sh"
readonly collision_checker="$caddy_root/tests/check-shell-readonly-local-collisions-v2.sh"
readonly conditional_policy="$caddy_root/tests/conditional-validator-errexit-policy-regression.sh"
readonly output_policy="$caddy_root/tests/transaction-output-evidence-policy-regression.sh"

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }
line_count() { awk 'END { print NR }' "$1"; }
require_source() {
    local source_expected_hash=$1
    local source_path=$2
    local source_identity

    source_identity="$(id -un):$(id -gn):755"
    # conditional-validator-explicit-failures-begin
    if ! [[ -f "$source_path" && ! -L "$source_path" && -x "$source_path" ]]; then
        return 1
    fi
    if ! [[ "$(stat -c '%U:%G:%a' "$source_path")" = "$source_identity" ]]; then
        return 1
    fi
    [[ "$(file_hash "$source_path")" = "$source_expected_hash" ]] || return 1
    # conditional-validator-explicit-failures-end
}
verify_sources() {
    # conditional-validator-explicit-failures-begin
    require_source "$transaction_sha256" "$transaction" || return 1
    require_source "$runner_sha256" "$runner" || return 1
    require_source "$regression_sha256" "$regression" || return 1
    require_source "$collision_checker_sha256" "$collision_checker" || return 1
    require_source "$conditional_policy_sha256" "$conditional_policy" || return 1
    require_source "$output_policy_sha256" "$output_policy" || return 1
    /bin/bash -n "$transaction" "$runner" "$regression" || return 1
    # conditional-validator-explicit-failures-end
}
require_gate() {
    local gate_label=$1

    shift
    if "$@" >/dev/null; then
        printf '%s_outer_gate_%s=true\n' "$prefix" "$gate_label"
        return 0
    fi
    printf '%s_outer_gate_%s=false\n' "$prefix" "$gate_label" >&2
    return 1
}
run_local_gates() {
    if verify_sources; then
        printf '%s_outer_gate_sources_verified=true\n' "$prefix"
    else
        printf '%s_outer_gate_sources_verified=false\n' "$prefix" >&2
        return 1
    fi
    require_gate collision_policy /bin/bash "$collision_checker" \
        "$transaction" "$runner" "$regression" "$0" || return 1
    require_gate conditional_validator_policy /bin/bash \
        "$conditional_policy" || return 1
    require_gate transaction_output_evidence_policy /bin/bash \
        "$output_policy" || return 1
    require_gate transaction_self_test /bin/bash "$transaction" --self-test ||
        return 1
    require_gate runner_self_test /bin/bash "$runner" --self-test || return 1
    require_gate runner_contract_test /bin/bash "$runner" --contract-test ||
        return 1
    require_gate regression_production_path /bin/bash "$regression" || return 1
}
safe_stream() {
    local inspected_path=$1

    [[ "$(wc -c <"$inspected_path")" -le "$maximum_stream_bytes" ]] ||
        return 1
    [[ "$(line_count "$inspected_path")" -le "$maximum_stream_lines" ]] ||
        return 1
    ! LC_ALL=C grep -n '[^[:print:][:space:]]' "$inspected_path" >/dev/null ||
        return 1
    ! grep -Eqi \
        'BEGIN [A-Z ]*PRIVATE KEY|CADDY_TLS_PRIVATE_KEY_PEM|PRIVATE_KEY=|DOPPLER_TOKEN|Authorization:[[:space:]]*Bearer' \
        "$inspected_path"
}
emit_stream() {
    local outer_stream_label=$1
    local outer_stream_path=$2

    printf '%s_inner_%s_bytes=%s\n' "$prefix" "$outer_stream_label" \
        "$(wc -c <"$outer_stream_path")"
    printf '%s_inner_%s_lines=%s\n' "$prefix" "$outer_stream_label" \
        "$(line_count "$outer_stream_path")"
    printf '%s_inner_%s_sha256=%s\n' "$prefix" "$outer_stream_label" \
        "$(file_hash "$outer_stream_path")"
    if ! safe_stream "$outer_stream_path"; then
        printf '%s_inner_%s_classification=unsafe_retained\n' \
            "$prefix" "$outer_stream_label" >&2
        return 97
    fi
    printf '%s_inner_%s_classification=bounded_safe\n' \
        "$prefix" "$outer_stream_label"
    if [[ -s "$outer_stream_path" ]]; then
        printf '%s_inner_%s_begin\n' "$prefix" "$outer_stream_label"
        cat "$outer_stream_path"
        printf '%s_inner_%s_end\n' "$prefix" "$outer_stream_label"
    else
        printf '%s_inner_%s_content_secured=empty\n' \
            "$prefix" "$outer_stream_label"
    fi
}

case "${1:-}" in
    --expected-local-gates)
        [[ $# -eq 1 ]] || exit 64
        printf '%s\n' \
            sources_verified \
            collision_policy \
            conditional_validator_policy \
            transaction_output_evidence_policy \
            transaction_self_test \
            runner_self_test \
            runner_contract_test \
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

verify_sources
[[ "$PWD" = /home/aaron/code/homelab-server-configs ]]
[[ -z "${CADDY_ACTION20D_SSH_BINARY:-}" ]]
outer_work=$(mktemp -d /tmp/caddy-action20d-outer.XXXXXX)
readonly outer_work
# shellcheck disable=SC2317
cleanup() { rm -rf -- "$outer_work"; }
trap cleanup EXIT
: >"$outer_work/inner.stdout"
: >"$outer_work/inner.stderr"
chmod 0600 "$outer_work/inner.stdout" "$outer_work/inner.stderr"
inner_status=0
/bin/bash "$runner" >"$outer_work/inner.stdout" \
    2>"$outer_work/inner.stderr" || inner_status=$?
readonly inner_status
emit_stream stdout "$outer_work/inner.stdout" || {
    trap - EXIT
    printf '%s_protected_evidence=%s\n' "$prefix" "$outer_work" >&2
    exit 97
}
emit_stream stderr "$outer_work/inner.stderr" || {
    trap - EXIT
    printf '%s_protected_evidence=%s\n' "$prefix" "$outer_work" >&2
    exit 97
}
printf '%s_inner_status=%s\n' "$prefix" "$inner_status"
rm -rf -- "$outer_work"
trap - EXIT
printf '%s_outer_cleanup_complete=true\n' "$prefix"
exit "$inner_status"
