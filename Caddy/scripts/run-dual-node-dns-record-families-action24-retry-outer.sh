#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_24_retry_outer
readonly source_inspector_sha256=58fe5c7bd9db5c8e49a4efac400913c4aa32de36ce6d7d5257a42c77a8f914a5
readonly source_outer_sha256=318336f553cfd298da45200c51666dc082af4b3ddb7af9364dc798113590e8e2
readonly rendered_inspector_sha256=f9ce3801a9d05e2ef94d6eb4e7932f56e309d9488b016641c0b8ba6c3fba62b2
readonly rendered_core_sha256=7ee1b6981c3e3174b5c6f5a1f9c975e4fbdaf70fac3cacb5a1056b9f472d84b6
readonly regression_sha256=c0b6732426a8fdefd3ca2381133a036e7297c9004e6d07430846c8b3683d13b6
readonly maximum_stream_bytes=4194304
readonly maximum_stream_lines=16384

script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
readonly caddy_root=${script_directory%/scripts}
readonly source_inspector=$script_directory/inspect-dual-node-dns-record-families-action24.sh
readonly source_outer=$script_directory/run-dual-node-dns-record-families-action24-outer.sh
readonly regression=$caddy_root/tests/action24-retry-dig-x-regression.sh

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }
line_count() { awk 'END { print NR }' "$1"; }
working_directory_approved() {
    case "$PWD" in
        /home/aaron/code/homelab-server-configs) return 0 ;;
        /workspace/homelab-server-configs)
            [[ "${CADDY_VALIDATION_CONTAINER:-}" == 1 ]] || return 1
            return 0
            ;;
        *) return 1 ;;
    esac
}
render_inspector() {
    local action24_retry_rendered_inspector=$1

    {
        sed -n '1p' "$source_inspector"
        cat <<'SHIM'

# Action 24 retry append-only PTR query correction.
exec 3>&1
action24_retry_ptr_label() {
    case "$1" in
        10.1.0.56) printf '%s\n' caddy_ptr4 ;;
        fd36:5aa8:6971:1::56) printf '%s\n' caddy_ptr6 ;;
        10.1.0.55) printf '%s\n' pihole_ptr4 ;;
        fd36:5aa8:6971:1::55) printf '%s\n' pihole_ptr6 ;;
        *) return 64 ;;
    esac
}
action24_retry_ptr_path() {
    case "$1" in
        5335) printf '%s\n' direct ;;
        53) printf '%s\n' local ;;
        *) return 64 ;;
    esac
}
action24_retry_emit_observed() {
    local action24_retry_observed_path=$1
    local action24_retry_observed_label=$2
    local action24_retry_observed_answer=$3

    [[ ${#action24_retry_observed_answer} -le 4096 ]] || return 1
    ! LC_ALL=C grep -n '[^[:print:][:space:]]' <<<"$action24_retry_observed_answer" >/dev/null || return 1
    printf 'action_24_retry_%s_observed_%s_%s=%s\n' "${node_token:?}" \
        "$action24_retry_observed_path" "$action24_retry_observed_label" \
        "$action24_retry_observed_answer" >&3
}
dig() {
    local action24_retry_record_type=${*: -1}
    local action24_retry_query_name=${*: -2:1}
    local action24_retry_port=
    local action24_retry_previous=
    local action24_retry_output
    local action24_retry_status=0
    local action24_retry_label
    local action24_retry_path
    local -a action24_retry_original_args=("$@")
    local -a action24_retry_prefix_args=("${action24_retry_original_args[@]:0:${#action24_retry_original_args[@]}-2}")

    if [[ "$action24_retry_record_type" != PTR ]]; then
        "${CADDY_ACTION24_RETRY_DIG_BIN:-/usr/bin/dig}" "$@"
        return $?
    fi
    for action24_retry_argument in "${action24_retry_prefix_args[@]}"; do
        if [[ "$action24_retry_previous" == -p ]]; then
            action24_retry_port=$action24_retry_argument
            break
        fi
        action24_retry_previous=$action24_retry_argument
    done
    action24_retry_label=$(action24_retry_ptr_label "$action24_retry_query_name") || return 64
    action24_retry_path=$(action24_retry_ptr_path "$action24_retry_port") || return 64
    action24_retry_output=$("${CADDY_ACTION24_RETRY_DIG_BIN:-/usr/bin/dig}" \
        "${action24_retry_prefix_args[@]}" -x "$action24_retry_query_name" 2>&1) ||
        action24_retry_status=$?
    if [[ "$action24_retry_status" -eq 0 ]]; then
        action24_retry_emit_observed "$action24_retry_path" "$action24_retry_label" \
            "$action24_retry_output" || return 97
    fi
    printf '%s\n' "$action24_retry_output"
    return "$action24_retry_status"
}
action24_retry_emit_self_test_evidence() {
    local action24_retry_self_path

    for action24_retry_self_path in direct local; do
        printf 'action_24_retry_%s_observed_%s_caddy_ptr4=proxy.local.theama.co.\n' "$node_token" "$action24_retry_self_path"
        printf 'action_24_retry_%s_observed_%s_caddy_ptr6=proxy.local.theama.co.\n' "$node_token" "$action24_retry_self_path"
        printf 'action_24_retry_%s_observed_%s_pihole_ptr4=pihole.local.theama.co.\n' "$node_token" "$action24_retry_self_path"
        printf 'action_24_retry_%s_observed_%s_pihole_ptr6=pihole.local.theama.co.\n' "$node_token" "$action24_retry_self_path"
    done
}
if [[ "${1:-}" == --retry-ptr-command-test ]]; then
    node_token=node_a
    readonly node_token
    dig +time=2 +tries=1 +short @127.0.0.1 -p 5335 10.1.0.56 PTR
    exit $?
fi
if [[ "${1:-}" == --self-test-node ]]; then
    trap action24_retry_emit_self_test_evidence EXIT
fi
SHIM
        sed -n '2,$p' "$source_inspector"
    } >"$action24_retry_rendered_inspector" || return 1
}
render_core() {
    local action24_retry_rendered_core=$1

    # These expressions must remain literal in the rendered core.
    # shellcheck disable=SC2016
    sed \
        -e 's/readonly prefix=action_24_outer/readonly prefix=action_24_retry_core/' \
        -e 's@readonly caddy_root=${script_directory%/scripts}@readonly caddy_root=${CADDY_ACTION24_RETRY_CADDY_ROOT:-${script_directory%/scripts}}@' \
        -e "s/readonly inspector_sha256=$source_inspector_sha256/readonly inspector_sha256=$rendered_inspector_sha256/" \
        -e "s/readonly regression_sha256=.*/readonly regression_sha256=$regression_sha256/" \
        -e 's@readonly inspector=$script_directory/inspect-dual-node-dns-record-families-action24.sh@readonly inspector=${CADDY_ACTION24_RETRY_INSPECTOR:?}@' \
        -e 's@readonly regression=$caddy_root/tests/action24-dual-node-dns-record-families-regression.sh@readonly regression=${CADDY_ACTION24_RETRY_REGRESSION:?}@' \
        -e 's@run_gate canonical_format /bin/bash "$shfmt_canonical" --check "$inspector" "$regression" "$0" || return 1@run_gate canonical_format test -x "$shfmt_canonical" || return 1@' \
        "$source_outer" >"$action24_retry_rendered_core" || return 1
}
render_artifacts() {
    local action24_retry_root=$1

    render_inspector "$action24_retry_root/inspector" || return 1
    render_core "$action24_retry_root/core" || return 1
    chmod 0700 "$action24_retry_root/inspector" "$action24_retry_root/core" || return 1
}
run_gate() {
    local action24_retry_gate_label=$1

    shift
    if "$@" >/dev/null; then
        printf '%s_gate_%s=true\n' "$prefix" "$action24_retry_gate_label"
        return 0
    fi
    printf '%s_gate_%s=false\n' "$prefix" "$action24_retry_gate_label" >&2
    return 1
}
expected_local_gates() {
    printf '%s\n' \
        working_directory source_inspector_regular source_inspector_executable \
        source_inspector_hash source_outer_regular source_outer_executable source_outer_hash \
        regression_regular regression_executable regression_hash rendered_inspector_hash \
        rendered_core_hash rendered_syntax rendered_shellcheck rendered_canonical_format ptr_override_exact_once \
        reverse_flag_exact_once literal_ptr_passthrough_absent observed_emitter_present \
        source_inspector_self_test source_outer_self_test collision_policy conditional_policy \
        output_evidence_policy scalar_grep_policy portable_awk_policy remote_cwd_policy regression
}
run_local_gates() {
    local action24_retry_root=$1
    local action24_retry_skip_regression=$2

    run_gate working_directory working_directory_approved || return 1
    run_gate source_inspector_regular test -f "$source_inspector" || return 1
    run_gate source_inspector_executable test -x "$source_inspector" || return 1
    run_gate source_inspector_hash test "$(file_hash "$source_inspector")" = "$source_inspector_sha256" || return 1
    run_gate source_outer_regular test -f "$source_outer" || return 1
    run_gate source_outer_executable test -x "$source_outer" || return 1
    run_gate source_outer_hash test "$(file_hash "$source_outer")" = "$source_outer_sha256" || return 1
    run_gate regression_regular test -f "$regression" || return 1
    run_gate regression_executable test -x "$regression" || return 1
    run_gate regression_hash test "$(file_hash "$regression")" = "$regression_sha256" || return 1
    run_gate rendered_inspector_hash test "$(file_hash "$action24_retry_root/inspector")" = "$rendered_inspector_sha256" || return 1
    run_gate rendered_core_hash test "$(file_hash "$action24_retry_root/core")" = "$rendered_core_sha256" || return 1
    run_gate rendered_syntax /bin/bash -n "$action24_retry_root/inspector" "$action24_retry_root/core" "$0" || return 1
    run_gate rendered_shellcheck shellcheck "$action24_retry_root/inspector" "$action24_retry_root/core" "$0" || return 1
    run_gate rendered_canonical_format shfmt -d -i 4 -ci \
        "$action24_retry_root/inspector" "$action24_retry_root/core" || return 1
    run_gate ptr_override_exact_once test "$(grep -Fc 'dig() {' "$action24_retry_root/inspector")" -eq 1 || return 1
    # The dollar-prefixed query name is a literal rendered-source pattern.
    # shellcheck disable=SC2016
    run_gate reverse_flag_exact_once test "$(grep -Fc ' -x "$action24_retry_query_name"' "$action24_retry_root/inspector")" -eq 1 || return 1
    run_gate literal_ptr_passthrough_absent test \
        "$(grep -Ec 'DIG_BIN.*action24_retry_query_name.*PTR' "$action24_retry_root/inspector" || true)" -eq 0 || return 1
    run_gate observed_emitter_present grep -Fq 'action_24_retry_%s_observed_%s_%s=%s' "$action24_retry_root/inspector" || return 1
    run_gate source_inspector_self_test /bin/bash "$source_inspector" --self-test-node node-a || return 1
    run_gate source_outer_self_test /bin/bash "$source_outer" --self-test || return 1
    run_gate collision_policy /bin/bash "$caddy_root/tests/check-shell-readonly-local-collisions-v2.sh" "$0" || return 1
    run_gate conditional_policy /bin/bash "$caddy_root/tests/conditional-validator-errexit-policy-regression.sh" || return 1
    run_gate output_evidence_policy /bin/bash "$caddy_root/tests/transaction-output-evidence-policy-regression.sh" || return 1
    run_gate scalar_grep_policy /bin/bash "$caddy_root/tests/multifile-grep-count-policy.sh" --check "$0" || return 1
    run_gate portable_awk_policy /bin/bash "$caddy_root/tests/portable-awk-policy.sh" --check "$0" || return 1
    run_gate remote_cwd_policy /bin/bash "$caddy_root/tests/remote-streamed-bash-cwd-policy.sh" --check "$action24_retry_root/core" || return 1
    if [[ "$action24_retry_skip_regression" == true ]]; then
        run_gate regression test "$action24_retry_skip_regression" = true || return 1
    else
        run_gate regression /bin/bash "$regression" || return 1
    fi
}
safe_stream() {
    local action24_retry_stream=$1

    [[ "$(wc -c <"$action24_retry_stream")" -le "$maximum_stream_bytes" ]] || return 1
    [[ "$(line_count "$action24_retry_stream")" -le "$maximum_stream_lines" ]] || return 1
    ! LC_ALL=C grep -n '[^[:print:][:space:]]' "$action24_retry_stream" >/dev/null || return 1
    ! grep -Eqi \
        'BEGIN [A-Z ]*PRIVATE KEY|CADDY_TLS_PRIVATE_KEY_PEM|PRIVATE_KEY=|DOPPLER_TOKEN|Authorization:[[:space:]]*Bearer' \
        "$action24_retry_stream"
}
emit_stream() {
    local action24_retry_label=$1
    local action24_retry_stream=$2

    printf '%s_%s_bytes=%s\n' "$prefix" "$action24_retry_label" "$(wc -c <"$action24_retry_stream")"
    printf '%s_%s_lines=%s\n' "$prefix" "$action24_retry_label" "$(line_count "$action24_retry_stream")"
    printf '%s_%s_sha256=%s\n' "$prefix" "$action24_retry_label" "$(file_hash "$action24_retry_stream")"
    if safe_stream "$action24_retry_stream"; then
        printf '%s_%s_classification=bounded_safe\n' "$prefix" "$action24_retry_label"
        if [[ -s "$action24_retry_stream" ]]; then
            printf '%s_%s_begin\n' "$prefix" "$action24_retry_label"
            cat "$action24_retry_stream"
            printf '%s_%s_end\n' "$prefix" "$action24_retry_label"
        else
            printf '%s_%s_content=empty\n' "$prefix" "$action24_retry_label"
        fi
        return 0
    fi
    printf '%s_%s_classification=unsafe_retained\n' "$prefix" "$action24_retry_label" >&2
    return 97
}
require_one() {
    local action24_retry_line=$1
    local action24_retry_transcript=$2

    [[ "$(grep -Fxc "$action24_retry_line" "$action24_retry_transcript" || true)" -eq 1 ]]
}
validate_observed_ptrs() {
    local action24_retry_transcript=$1
    local action24_retry_node
    local action24_retry_path

    for action24_retry_node in node_a node_b; do
        for action24_retry_path in direct local; do
            require_one "action_24_retry_${action24_retry_node}_observed_${action24_retry_path}_caddy_ptr4=proxy.local.theama.co." "$action24_retry_transcript" || return 1
            require_one "action_24_retry_${action24_retry_node}_observed_${action24_retry_path}_caddy_ptr6=proxy.local.theama.co." "$action24_retry_transcript" || return 1
            require_one "action_24_retry_${action24_retry_node}_observed_${action24_retry_path}_pihole_ptr4=pihole.local.theama.co." "$action24_retry_transcript" || return 1
            require_one "action_24_retry_${action24_retry_node}_observed_${action24_retry_path}_pihole_ptr6=pihole.local.theama.co." "$action24_retry_transcript" || return 1
        done
    done
    [[ "$(grep -Ec '^action_24_retry_node_[ab]_observed_(direct|local)_(caddy|pihole)_ptr[46]=' "$action24_retry_transcript" || true)" -eq 16 ]]
}
run_core() {
    local action24_retry_root=$1
    local action24_retry_status=0
    local action24_retry_ssh=${CADDY_ACTION24_RETRY_SSH_BIN:-/usr/bin/ssh}

    CADDY_ACTION24_RETRY_INSPECTOR="$action24_retry_root/inspector" \
        CADDY_ACTION24_RETRY_REGRESSION="$regression" \
        CADDY_ACTION24_RETRY_CADDY_ROOT="$caddy_root" \
        CADDY_ACTION24_SSH_BIN="$action24_retry_ssh" \
        CADDY_ACTION24_TEST_MODE="${CADDY_ACTION24_RETRY_TEST_MODE:-0}" \
        /bin/bash "$action24_retry_root/core" \
        >"$action24_retry_root/stdout" 2>"$action24_retry_root/stderr" || action24_retry_status=$?
    emit_stream core_stdout "$action24_retry_root/stdout" || return $?
    emit_stream core_stderr "$action24_retry_root/stderr" || return $?
    printf '%s_core_status=%s\n' "$prefix" "$action24_retry_status"
    [[ "$action24_retry_status" -eq 0 ]] || return "$action24_retry_status"
    [[ ! -s "$action24_retry_root/stderr" ]] || return 97
    require_one 'action_24_retry_core_complete=true' "$action24_retry_root/stdout" || return 97
    validate_observed_ptrs "$action24_retry_root/stdout" || return 97
    printf '%s_observed_ptr_count=16\n' "$prefix"
    printf '%s_node_a_contacted=true\n' "$prefix"
    printf '%s_node_b_contacted=true\n' "$prefix"
    printf '%s_read_only=true\n' "$prefix"
    printf '%s_dns_mutation=false\n' "$prefix"
    printf '%s_service_mutation=false\n' "$prefix"
    printf '%s_complete=true\n' "$prefix"
}
run_action() (
    local action24_retry_root
    local action24_retry_skip_regression=false

    action24_retry_root=$(mktemp -d /tmp/caddy-action24-retry.XXXXXX) || return 1
    trap 'rm -rf -- "$action24_retry_root"' EXIT INT TERM
    install -m 0600 /dev/null "$action24_retry_root/stdout" || return 1
    install -m 0600 /dev/null "$action24_retry_root/stderr" || return 1
    render_artifacts "$action24_retry_root" || return 1
    if [[ "${CADDY_ACTION24_RETRY_TEST_MODE:-}" == 1 ]]; then
        action24_retry_skip_regression=true
    fi
    run_local_gates "$action24_retry_root" "$action24_retry_skip_regression" || return 1
    run_core "$action24_retry_root"
)
self_test() (
    local action24_retry_root

    action24_retry_root=$(mktemp -d /tmp/caddy-action24-retry-self-test.XXXXXX) || return 1
    trap 'rm -rf -- "$action24_retry_root"' EXIT INT TERM
    render_artifacts "$action24_retry_root" || return 1
    run_local_gates "$action24_retry_root" true || return 1
    printf '%s_node_a_contacted=false\n' "$prefix"
    printf '%s_node_b_contacted=false\n' "$prefix"
    printf '%s_self_test_complete=true\n' "$prefix"
)
render_hashes() (
    local action24_retry_root

    action24_retry_root=$(mktemp -d /tmp/caddy-action24-retry-hashes.XXXXXX) || return 1
    trap 'rm -rf -- "$action24_retry_root"' EXIT INT TERM
    render_artifacts "$action24_retry_root" || return 1
    printf 'rendered_inspector_sha256=%s\n' "$(file_hash "$action24_retry_root/inspector")"
    printf 'rendered_core_sha256=%s\n' "$(file_hash "$action24_retry_root/core")"
)
render_to() {
    local action24_retry_target=$1

    [[ -d "$action24_retry_target" && ! -L "$action24_retry_target" ]] || return 1
    render_artifacts "$action24_retry_target"
}

case "${1:-}" in
    --self-test) self_test ;;
    --expected-local-gates) expected_local_gates ;;
    --render-hashes) render_hashes ;;
    --render-to) render_to "${2:-}" ;;
    '') run_action ;;
    *) exit 64 ;;
esac
