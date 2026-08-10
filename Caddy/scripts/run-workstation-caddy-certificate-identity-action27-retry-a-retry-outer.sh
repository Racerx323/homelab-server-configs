#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_27_retry_a_retry_outer
script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
readonly caddy_root=${script_directory%/scripts}
readonly immutable_outer=$script_directory/run-workstation-caddy-certificate-identity-action27-retry-a-outer.sh
readonly corrected_diagnostic=$script_directory/run-workstation-caddy-certificate-identity-action27-retry-a-retry.sh
readonly regression=$caddy_root/tests/action27-retry-a-retry-certificate-extraction-regression.sh
readonly immutable_outer_sha256=2eee3224eb68721592381f1c74e83a383c36ffb36eebe65b7635275cda9b6d17
readonly corrected_diagnostic_sha256=9cf305773633ab88e6b8f517879594bbf00466f63509d89d7431efe8a019ac2e
readonly regression_sha256=8de2dae492809a8b19218539d20d528f7ea1f9e51aa8f07fdc15b2f32816d496
action27_retry_a_retry_outer_root=

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }
line_count() { awk 'END { print NR }' "$1"; }
working_directory_approved() {
    case "$PWD" in
        /home/aaron/code/homelab-server-configs) return 0 ;;
        /workspace/homelab-server-configs)
            [[ "${CADDY_VALIDATION_CONTAINER:-}" = 1 ]] || return 1
            return 0
            ;;
        *) return 1 ;;
    esac
}
gate() {
    local action27_retry_a_retry_outer_gate_label=$1

    shift
    if "$@" >/dev/null; then
        printf '%s_gate_%s=true\n' "$prefix" "$action27_retry_a_retry_outer_gate_label"
        return 0
    fi
    printf '%s_gate_%s=false\n' "$prefix" "$action27_retry_a_retry_outer_gate_label" >&2
    return 1
}
expected_local_gates() {
    printf '%s\n' working_directory immutable_outer_hash corrected_diagnostic_hash regression_hash \
        syntax shellcheck canonical_format collision_policy conditional_policy \
        output_evidence_policy scalar_grep_policy portable_awk_policy regression
}
safe_stream() {
    local action27_retry_a_retry_outer_stream=$1

    [[ "$(wc -c <"$action27_retry_a_retry_outer_stream")" -le 131072 ]] || return 1
    [[ "$(line_count "$action27_retry_a_retry_outer_stream")" -le 2048 ]] || return 1
    ! LC_ALL=C grep -n '[^[:print:][:space:]]' "$action27_retry_a_retry_outer_stream" >/dev/null || return 1
    ! grep -Eqi 'BEGIN [A-Z ]*PRIVATE KEY|PRIVATE_KEY=|DOPPLER_TOKEN|Authorization:[[:space:]]*Bearer|Cookie:' \
        "$action27_retry_a_retry_outer_stream"
}
emit_stream() {
    local action27_retry_a_retry_outer_label=$1
    local action27_retry_a_retry_outer_stream=$2

    printf '%s_%s_bytes=%s\n' "$prefix" "$action27_retry_a_retry_outer_label" \
        "$(wc -c <"$action27_retry_a_retry_outer_stream")"
    printf '%s_%s_lines=%s\n' "$prefix" "$action27_retry_a_retry_outer_label" \
        "$(line_count "$action27_retry_a_retry_outer_stream")"
    printf '%s_%s_sha256=%s\n' "$prefix" "$action27_retry_a_retry_outer_label" \
        "$(file_hash "$action27_retry_a_retry_outer_stream")"
    safe_stream "$action27_retry_a_retry_outer_stream" || return 97
    printf '%s_%s_classification=bounded_safe\n' "$prefix" "$action27_retry_a_retry_outer_label"
    if [[ -s "$action27_retry_a_retry_outer_stream" ]]; then
        printf '%s_%s_begin\n' "$prefix" "$action27_retry_a_retry_outer_label"
        cat "$action27_retry_a_retry_outer_stream"
        printf '%s_%s_end\n' "$prefix" "$action27_retry_a_retry_outer_label"
    else
        printf '%s_%s_content=empty\n' "$prefix" "$action27_retry_a_retry_outer_label"
    fi
}
validate_transcript() {
    local action27_retry_a_retry_outer_stdout=$1
    local action27_retry_a_retry_outer_status=$2
    local action27_retry_a_retry_outer_stderr=$3
    local action27_retry_a_retry_outer_expected_correction=$action27_retry_a_retry_outer_root/expected-correction.labels
    local action27_retry_a_retry_outer_observed_correction=$action27_retry_a_retry_outer_root/observed-correction.labels
    local action27_retry_a_retry_outer_expected_diagnostic=$action27_retry_a_retry_outer_root/expected-diagnostic.labels
    local action27_retry_a_retry_outer_observed_diagnostic=$action27_retry_a_retry_outer_root/observed-diagnostic.labels

    [[ "$action27_retry_a_retry_outer_status" -eq 0 ]] || return 1
    [[ ! -s "$action27_retry_a_retry_outer_stderr" ]] || return 1
    /bin/bash "$corrected_diagnostic" --expected-checks >"$action27_retry_a_retry_outer_expected_correction" || return 1
    sed -n 's/^action_27_retry_a_retry_check_\([^=]*\)=true$/\1/p' "$action27_retry_a_retry_outer_stdout" \
        >"$action27_retry_a_retry_outer_observed_correction"
    cmp -s "$action27_retry_a_retry_outer_expected_correction" \
        "$action27_retry_a_retry_outer_observed_correction" || return 1
    /bin/bash "$corrected_diagnostic" --expected-diagnostic-checks \
        >"$action27_retry_a_retry_outer_expected_diagnostic" || return 1
    sed -n 's/^action_27_retry_a_check_\([^=]*\)=true$/\1/p' "$action27_retry_a_retry_outer_stdout" \
        >"$action27_retry_a_retry_outer_observed_diagnostic"
    cmp -s "$action27_retry_a_retry_outer_expected_diagnostic" \
        "$action27_retry_a_retry_outer_observed_diagnostic" || return 1
    [[ "$(grep -c '^action_27_retry_a_retry_check_.*=false$' "$action27_retry_a_retry_outer_stdout")" -eq 0 ]] || return 1
    [[ "$(grep -c '^action_27_retry_a_check_.*=false$' "$action27_retry_a_retry_outer_stdout")" -eq 0 ]] || return 1
    [[ "$(grep -c '^action_27_retry_a_retry_extraction_scope=explicit_begin_end_certificate_state$' "$action27_retry_a_retry_outer_stdout")" -eq 1 ]] || return 1
    [[ "$(grep -c '^action_27_retry_a_complete=true$' "$action27_retry_a_retry_outer_stdout")" -eq 1 ]] || return 1
    [[ "$(grep -c '^action_27_retry_a_raw_pem_emitted=false$' "$action27_retry_a_retry_outer_stdout")" -eq 1 ]] || return 1
    [[ "$(grep -c '^action_27_retry_a_persistent_mutation=false$' "$action27_retry_a_retry_outer_stdout")" -eq 1 ]] || return 1
    if grep -Fq -- '-----BEGIN CERTIFICATE-----' "$action27_retry_a_retry_outer_stdout"; then
        return 1
    fi
}
run_gates() {
    local action27_retry_a_retry_outer_skip_regression=$1

    gate working_directory working_directory_approved || return 1
    gate immutable_outer_hash test "$(file_hash "$immutable_outer")" = "$immutable_outer_sha256" || return 1
    gate corrected_diagnostic_hash test "$(file_hash "$corrected_diagnostic")" = \
        "$corrected_diagnostic_sha256" || return 1
    gate regression_hash test "$(file_hash "$regression")" = "$regression_sha256" || return 1
    gate syntax /bin/bash -n "$0" "$corrected_diagnostic" "$regression" || return 1
    gate shellcheck shellcheck "$0" "$corrected_diagnostic" "$regression" || return 1
    gate canonical_format /bin/bash "$caddy_root/tests/shfmt-canonical.sh" --check \
        "$0" "$corrected_diagnostic" "$regression" || return 1
    gate collision_policy /bin/bash "$caddy_root/tests/check-shell-readonly-local-collisions-v2.sh" \
        "$0" "$corrected_diagnostic" "$regression" || return 1
    gate conditional_policy /bin/bash "$caddy_root/tests/conditional-validator-errexit-policy-regression.sh" || return 1
    gate output_evidence_policy /bin/bash "$caddy_root/tests/transaction-output-evidence-policy-regression.sh" || return 1
    gate scalar_grep_policy /bin/bash "$caddy_root/tests/multifile-grep-count-policy.sh" --check \
        "$0" "$corrected_diagnostic" "$regression" || return 1
    gate portable_awk_policy /bin/bash "$caddy_root/tests/portable-awk-policy.sh" --check \
        "$0" "$corrected_diagnostic" "$regression" || return 1
    if [[ "$action27_retry_a_retry_outer_skip_regression" = true ]]; then
        gate regression test "$action27_retry_a_retry_outer_skip_regression" = true || return 1
    else
        gate regression /bin/bash "$regression" || return 1
    fi
}
cleanup() {
    local action27_retry_a_retry_outer_status=$?

    trap - EXIT INT TERM
    [[ -z "$action27_retry_a_retry_outer_root" ]] || rm -rf -- "$action27_retry_a_retry_outer_root"
    exit "$action27_retry_a_retry_outer_status"
}
run_action() {
    local action27_retry_a_retry_outer_stdout
    local action27_retry_a_retry_outer_stderr
    local action27_retry_a_retry_outer_status=0

    action27_retry_a_retry_outer_root=$(mktemp -d /tmp/caddy-action27-retry-a-retry-outer.XXXXXX)
    trap cleanup EXIT INT TERM
    run_gates "${CADDY_ACTION27_RETRY_A_RETRY_SKIP_REGRESSION:-false}" || return 1
    action27_retry_a_retry_outer_stdout=$action27_retry_a_retry_outer_root/diagnostic.stdout
    action27_retry_a_retry_outer_stderr=$action27_retry_a_retry_outer_root/diagnostic.stderr
    /bin/bash "$corrected_diagnostic" >"$action27_retry_a_retry_outer_stdout" \
        2>"$action27_retry_a_retry_outer_stderr" || action27_retry_a_retry_outer_status=$?
    emit_stream diagnostic_stdout "$action27_retry_a_retry_outer_stdout" || return $?
    emit_stream diagnostic_stderr "$action27_retry_a_retry_outer_stderr" || return $?
    validate_transcript "$action27_retry_a_retry_outer_stdout" \
        "$action27_retry_a_retry_outer_status" "$action27_retry_a_retry_outer_stderr" || return 1
    printf '%s_live_tls_probe=true\n' "$prefix"
    printf '%s_node_contact=false\n' "$prefix"
    printf '%s_persistent_mutation=false\n' "$prefix"
    printf '%s_complete=true\n' "$prefix"
}

case "${1:-}" in
    --expected-local-gates) expected_local_gates ;;
    --self-test)
        action27_retry_a_retry_outer_root=$(mktemp -d /tmp/caddy-action27-retry-a-retry-outer-selftest.XXXXXX)
        trap cleanup EXIT INT TERM
        CADDY_ACTION27_RETRY_A_RETRY_SKIP_REGRESSION=true run_gates true
        ;;
    "") run_action ;;
    *) exit 64 ;;
esac
