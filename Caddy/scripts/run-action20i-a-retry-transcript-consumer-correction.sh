#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_20i_a_retry_transcript_consumer_correction
readonly builder_sha256=d9eece3f68b3962cda15e88b733d29af72e7d7533dc29ac28f0ffcf569593c72
readonly immutable_executed_outer_sha256=6d5d6164af48896bf9827dff5414b6836698c83847f9fa4087ef5aabd2d5ec10
readonly fixture_sha256=29bf6526fa942e82031669be0e4d9c0e726afd01b909467a7fdc0e2cff289186
readonly fixture_bytes=7036
readonly fixture_lines=111
readonly generated_inspector_sha256=7497358ba86fa72fbf7b25fa699c7cfdb71b98be90e452674e4f403e56d19423
readonly generated_runner_sha256=120b185bf33dcf66ba9423c7ec14ef6bc99dcacf384ecdf699faf76ab8a768b4
readonly generated_regression_sha256=c088790fac87435500e3c3f8d75283b1bb7ef9d3d8135644e82ce19b7e7823a6
readonly maximum_stream_bytes=8388608
readonly maximum_stream_lines=32768

script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
readonly caddy_root=${script_directory%/scripts}
readonly builder=$script_directory/build-action20i-a-retry-transcript-consumer-correction.sh
readonly immutable_executed_outer=$script_directory/run-node-b-caddy-health-helper-postinstall-action20i-a-retry-outer.sh
readonly fixture=$caddy_root/tests/fixtures/action20i-a-retry-remote-stdout.txt

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }
line_count() { awk 'END { print NR }' "$1"; }
working_directory_approved() {
    case "$PWD" in
        /home/aaron/code/homelab-server-configs) return 0 ;;
        /workspace/homelab-server-configs)
            [[ "${CADDY_VALIDATION_CONTAINER:-}" = 1 ]]
            ;;
        *) return 1 ;;
    esac
}
source_exact() {
    local action20i_a_consumer_expected_hash=$1
    local action20i_a_consumer_source_path=$2

    [[ -f "$action20i_a_consumer_source_path" &&
        ! -L "$action20i_a_consumer_source_path" ]] || return 1
    [[ "$(file_hash "$action20i_a_consumer_source_path")" = "$action20i_a_consumer_expected_hash" ]] || return 1
}
executable_source_exact() {
    local action20i_a_consumer_expected_hash=$1
    local action20i_a_consumer_source_path=$2

    source_exact "$action20i_a_consumer_expected_hash" \
        "$action20i_a_consumer_source_path" || return 1
    [[ "$(stat -c '%a' "$action20i_a_consumer_source_path")" = 755 ]] || return 1
}
gate() {
    local action20i_a_consumer_gate_label=$1

    shift
    if "$@" >/dev/null; then
        printf '%s_gate_%s=true\n' "$prefix" "$action20i_a_consumer_gate_label"
        return 0
    fi
    printf '%s_gate_%s=false\n' "$prefix" \
        "$action20i_a_consumer_gate_label" >&2
    return 1
}
safe_stream() {
    local action20i_a_consumer_stream_path=$1

    [[ "$(wc -c <"$action20i_a_consumer_stream_path")" -le "$maximum_stream_bytes" ]] || return 1
    [[ "$(line_count "$action20i_a_consumer_stream_path")" -le "$maximum_stream_lines" ]] || return 1
    ! LC_ALL=C grep -n '[^[:print:][:space:]]' \
        "$action20i_a_consumer_stream_path" >/dev/null || return 1
    ! grep -Eqi \
        'BEGIN [A-Z ]*PRIVATE KEY|CADDY_TLS_PRIVATE_KEY_PEM|PRIVATE_KEY=|DOPPLER_TOKEN|Authorization:[[:space:]]*Bearer' \
        "$action20i_a_consumer_stream_path"
}
emit_stream() {
    local action20i_a_consumer_stream_label=$1
    local action20i_a_consumer_stream_path=$2

    printf '%s_%s_bytes=%s\n' "$prefix" "$action20i_a_consumer_stream_label" \
        "$(wc -c <"$action20i_a_consumer_stream_path")"
    printf '%s_%s_lines=%s\n' "$prefix" "$action20i_a_consumer_stream_label" \
        "$(line_count "$action20i_a_consumer_stream_path")"
    printf '%s_%s_sha256=%s\n' "$prefix" "$action20i_a_consumer_stream_label" \
        "$(file_hash "$action20i_a_consumer_stream_path")"
    if ! safe_stream "$action20i_a_consumer_stream_path"; then
        printf '%s_%s_classification=unsafe_retained\n' \
            "$prefix" "$action20i_a_consumer_stream_label" >&2
        return 97
    fi
    printf '%s_%s_classification=bounded_safe\n' \
        "$prefix" "$action20i_a_consumer_stream_label"
    if [[ -s "$action20i_a_consumer_stream_path" ]]; then
        printf '%s_%s_begin\n' "$prefix" "$action20i_a_consumer_stream_label"
        cat "$action20i_a_consumer_stream_path"
        printf '%s_%s_end\n' "$prefix" "$action20i_a_consumer_stream_label"
    else
        printf '%s_%s_content_secured=empty\n' \
            "$prefix" "$action20i_a_consumer_stream_label"
    fi
}
fixture_exact() {
    local action20i_a_consumer_fixture_path=$1

    source_exact "$fixture_sha256" "$action20i_a_consumer_fixture_path" || return 1
    [[ "$(wc -c <"$action20i_a_consumer_fixture_path")" -eq "$fixture_bytes" ]] || return 1
    [[ "$(line_count "$action20i_a_consumer_fixture_path")" -eq "$fixture_lines" ]] || return 1
}
generated_sources_exact() {
    local action20i_a_consumer_generated_root=$1

    executable_source_exact "$generated_inspector_sha256" \
        "$action20i_a_consumer_generated_root/scripts/inspect-node-b-caddy-health-helper-postinstall-action20i-a-retry.sh" || return 1
    executable_source_exact "$generated_runner_sha256" \
        "$action20i_a_consumer_generated_root/scripts/run-node-b-caddy-health-helper-postinstall-action20i-a-retry-consumer-corrected.sh" || return 1
    executable_source_exact "$generated_regression_sha256" \
        "$action20i_a_consumer_generated_root/tests/action20i-a-retry-consumer-correction-regression.sh" || return 1
}
fixture_order_negative_control() {
    local action20i_a_consumer_reordered=$1

    awk 'NR == 1 { first = $0; next } NR == 2 { print; print first; next } { print }' \
        "$fixture" >"$action20i_a_consumer_reordered" || return 1
    ! fixture_exact "$action20i_a_consumer_reordered"
}
run_capture() {
    local action20i_a_consumer_capture_label=$1
    local action20i_a_consumer_capture_stdout=$work_root/$action20i_a_consumer_capture_label.stdout
    local action20i_a_consumer_capture_stderr=$work_root/$action20i_a_consumer_capture_label.stderr

    shift
    install -m 0600 /dev/null "$action20i_a_consumer_capture_stdout"
    install -m 0600 /dev/null "$action20i_a_consumer_capture_stderr"
    capture_status=0
    "$@" >"$action20i_a_consumer_capture_stdout" \
        2>"$action20i_a_consumer_capture_stderr" || capture_status=$?
    emit_stream "${action20i_a_consumer_capture_label}_stdout" \
        "$action20i_a_consumer_capture_stdout" || return 97
    emit_stream "${action20i_a_consumer_capture_label}_stderr" \
        "$action20i_a_consumer_capture_stderr" || return 97
    printf '%s_%s_status=%s\n' "$prefix" \
        "$action20i_a_consumer_capture_label" "$capture_status"
}

case "${1:-}" in
    --self-test | --source-test | --contract-test)
        [[ $# -eq 1 ]] || exit 64
        readonly action20i_a_consumer_mode=${1#--}
        ;;
    "")
        [[ $# -eq 0 ]] || exit 64
        readonly action20i_a_consumer_mode=execute
        ;;
    *)
        printf 'Usage: %s [--self-test|--source-test|--contract-test]\n' \
            "${0##*/}" >&2
        exit 64
        ;;
esac

gate working_directory working_directory_approved
gate builder_source executable_source_exact "$builder_sha256" "$builder"
gate immutable_executed_outer executable_source_exact \
    "$immutable_executed_outer_sha256" "$immutable_executed_outer"
gate fixture_source fixture_exact "$fixture"
gate syntax /bin/bash -n "$builder" "$0"
gate shellcheck shellcheck "$builder" "$0"
gate canonical_format /bin/bash "$caddy_root/tests/shfmt-canonical.sh" --check \
    "$builder" "$0"
gate collision_policy /bin/bash \
    "$caddy_root/tests/check-shell-readonly-local-collisions-v2.sh" \
    "$builder" "$0"
gate conditional_policy /bin/bash \
    "$caddy_root/tests/conditional-validator-errexit-policy-regression.sh"
gate multifile_grep_policy /bin/bash \
    "$caddy_root/tests/multifile-grep-count-policy.sh" --check \
    "$builder" "$0"
gate portable_awk_policy /bin/bash \
    "$caddy_root/tests/portable-awk-policy-regression.sh"

work_root=$(mktemp -d /tmp/caddy-action20i-a-consumer-correction.XXXXXX)
readonly work_root
cleanup() { rm -rf -- "$work_root"; }
trap cleanup EXIT INT TERM
readonly generated_root=$work_root/generated
run_capture builder /bin/bash "$builder" --output "$generated_root"
[[ "$capture_status" -eq 0 ]] || exit "$capture_status"
gate builder_status true
gate generated_sources generated_sources_exact "$generated_root"
run_capture regression /bin/bash \
    "$generated_root/tests/action20i-a-retry-consumer-correction-regression.sh"
[[ "$capture_status" -eq 0 ]] || exit "$capture_status"
gate regression_status true
gate fixture_order fixture_exact "$fixture"
gate reordered_fixture_rejected fixture_order_negative_control \
    "$work_root/reordered.fixture"
install -m 0600 /dev/null "$work_root/empty.stderr"
run_capture transcript /bin/bash \
    "$generated_root/scripts/run-node-b-caddy-health-helper-postinstall-action20i-a-retry-consumer-corrected.sh" \
    --validate-transcript "$fixture" "$work_root/empty.stderr" 0
[[ "$capture_status" -eq 0 ]] || exit "$capture_status"
gate transcript_status true

printf '%s_mode=%s\n' "$prefix" "$action20i_a_consumer_mode"
printf '%s_assertion_controls_retained=true\n' "$prefix"
printf '%s_ordering_control_retained=true\n' "$prefix"
printf '%s_status_control_retained=true\n' "$prefix"
printf '%s_capture_controls_retained=true\n' "$prefix"
printf '%s_negative_controls_retained=true\n' "$prefix"
printf '%s_stale_hash_only_correction=true\n' "$prefix"
printf '%s_node_a_contacted=false\n' "$prefix"
printf '%s_node_b_contacted=false\n' "$prefix"
printf '%s_ssh_invoked=false\n' "$prefix"
printf '%s_live_action_executed=false\n' "$prefix"
printf '%s_persistent_mutations=false\n' "$prefix"
printf '%s_node_b_vrrp_activation=false\n' "$prefix"
printf '%s_complete=true\n' "$prefix"
