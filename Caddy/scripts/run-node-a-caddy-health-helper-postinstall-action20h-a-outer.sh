#!/usr/bin/env bash
# shellcheck disable=SC2317

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_20h_a_outer
readonly builder_sha256=dd59e60ebc384e25b4d4faabc718cface0044a079413a3954295d39c08ca3e3f
readonly generated_inspector_sha256=9bef62fec313eb8565abc148d9f6741c8ef2c4ac80c72e1f68a97ea80100b4cf
readonly generated_runner_sha256=728397374d6984a710b7de19f5800d4dca56b7239f5df69b3cc96b53fa860dc5
readonly generated_regression_sha256=1eb5c1dd507bd1081324093e96869ea71789e6e1c2b7722f559f3eacb6641c90
readonly accepted_transaction_outer_sha256=df3a496def5a0e65066933ac10ace0470c64f6742234bbd24d9e3c2bc90920c9
readonly maximum_stream_bytes=8388608
readonly maximum_stream_lines=32768

script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
readonly caddy_root=${script_directory%/scripts}
readonly builder=$script_directory/build-node-a-caddy-health-helper-postinstall-action20h-a.sh
readonly accepted_transaction_outer=$script_directory/run-node-a-caddy-health-helper-action20h-retry3-outer.sh
readonly governing_plan=$caddy_root/docs/caddy_plan-v1.1.md

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
    local action20h_a_outer_expected_hash=$1
    local action20h_a_outer_source_path=$2

    [[ -f "$action20h_a_outer_source_path" &&
        ! -L "$action20h_a_outer_source_path" ]] || return 1
    [[ "$(stat -c '%a' "$action20h_a_outer_source_path")" = 755 ]] || return 1
    [[ "$(file_hash "$action20h_a_outer_source_path")" = "$action20h_a_outer_expected_hash" ]] || return 1
}
gate() {
    local action20h_a_outer_gate_label=$1

    shift
    if "$@" >/dev/null; then
        printf '%s_gate_%s=true\n' "$prefix" "$action20h_a_outer_gate_label"
        return 0
    fi
    printf '%s_gate_%s=false\n' "$prefix" "$action20h_a_outer_gate_label" >&2
    return 1
}
safe_stream() {
    local action20h_a_outer_stream_path=$1

    [[ "$(wc -c <"$action20h_a_outer_stream_path")" -le "$maximum_stream_bytes" ]] || return 1
    [[ "$(line_count "$action20h_a_outer_stream_path")" -le "$maximum_stream_lines" ]] || return 1
    ! LC_ALL=C grep -n '[^[:print:][:space:]]' \
        "$action20h_a_outer_stream_path" >/dev/null || return 1
    ! grep -Eqi \
        'BEGIN [A-Z ]*PRIVATE KEY|CADDY_TLS_PRIVATE_KEY_PEM|PRIVATE_KEY=|DOPPLER_TOKEN|Authorization:[[:space:]]*Bearer' \
        "$action20h_a_outer_stream_path"
}
emit_stream() {
    local action20h_a_outer_stream_label=$1
    local action20h_a_outer_stream_path=$2

    printf '%s_%s_bytes=%s\n' "$prefix" "$action20h_a_outer_stream_label" \
        "$(wc -c <"$action20h_a_outer_stream_path")"
    printf '%s_%s_lines=%s\n' "$prefix" "$action20h_a_outer_stream_label" \
        "$(line_count "$action20h_a_outer_stream_path")"
    printf '%s_%s_sha256=%s\n' "$prefix" "$action20h_a_outer_stream_label" \
        "$(file_hash "$action20h_a_outer_stream_path")"
    if ! safe_stream "$action20h_a_outer_stream_path"; then
        printf '%s_%s_classification=unsafe_retained\n' \
            "$prefix" "$action20h_a_outer_stream_label" >&2
        return 97
    fi
    printf '%s_%s_classification=bounded_safe\n' \
        "$prefix" "$action20h_a_outer_stream_label"
    if [[ -s "$action20h_a_outer_stream_path" ]]; then
        printf '%s_%s_begin\n' "$prefix" "$action20h_a_outer_stream_label"
        cat "$action20h_a_outer_stream_path"
        printf '%s_%s_end\n' "$prefix" "$action20h_a_outer_stream_label"
    else
        printf '%s_%s_content_secured=empty\n' \
            "$prefix" "$action20h_a_outer_stream_label"
    fi
}
plan_baseline_exact() {
    grep -Fq \
        'Exact transactional Node A health-helper Action 20h third-retry execution' \
        "$governing_plan" || return 1
    grep -Fq \
        '/var/backups/caddy-ha/action20h-node-a-health-instrumentation.lfB0lj' \
        "$governing_plan" || return 1
    grep -Fq \
        '5cb42ba0...7fb3' "$governing_plan" || return 1
}
run_static_gates() {
    gate working_directory working_directory_approved || return 1
    gate builder_source source_exact "$builder_sha256" "$builder" || return 1
    gate accepted_transaction_source source_exact \
        "$accepted_transaction_outer_sha256" "$accepted_transaction_outer" || return 1
    gate governing_plan_baseline plan_baseline_exact || return 1
    gate syntax /bin/bash -n "$builder" "$0" || return 1
    gate shellcheck shellcheck "$builder" "$0" || return 1
    gate canonical_format /bin/bash "$caddy_root/tests/shfmt-canonical.sh" --check \
        "$builder" "$0" || return 1
    gate collision_policy /bin/bash \
        "$caddy_root/tests/check-shell-readonly-local-collisions-v2.sh" \
        "$builder" "$0" || return 1
    gate multifile_count_policy /bin/bash \
        "$caddy_root/tests/multifile-grep-count-policy.sh" --check \
        "$builder" "$0" || return 1
}
generated_sources_exact() {
    local action20h_a_outer_generated_root=$1

    source_exact "$generated_inspector_sha256" \
        "$action20h_a_outer_generated_root/scripts/inspect-node-a-caddy-health-helper-postinstall-action20h-a.sh" || return 1
    source_exact "$generated_runner_sha256" \
        "$action20h_a_outer_generated_root/scripts/run-node-a-caddy-health-helper-postinstall-action20h-a.sh" || return 1
    source_exact "$generated_regression_sha256" \
        "$action20h_a_outer_generated_root/tests/action20h-a-postinstall-regression.sh" || return 1
}

case "${1:-}" in
    --expected-local-gates)
        [[ $# -eq 1 ]] || exit 64
        printf '%s\n' \
            working_directory builder_source accepted_transaction_source \
            governing_plan_baseline syntax shellcheck canonical_format \
            collision_policy multifile_count_policy builder_status \
            generated_sources generated_regression
        exit 0
        ;;
    --self-test | --source-test | --contract-test)
        [[ $# -eq 1 ]] || exit 64
        readonly action20h_a_outer_mode=${1#--}
        ;;
    "")
        [[ $# -eq 0 ]] || exit 64
        readonly action20h_a_outer_mode=execute
        ;;
    *)
        printf 'Usage: %s [--expected-local-gates|--self-test|--source-test|--contract-test]\n' \
            "${0##*/}" >&2
        exit 64
        ;;
esac

run_static_gates
work_root=$(mktemp -d /tmp/caddy-action20h-a-outer.XXXXXX)
readonly work_root
cleanup() { rm -rf -- "$work_root"; }
trap cleanup EXIT INT TERM
readonly generated_root=$work_root/generated
readonly builder_stdout=$work_root/builder.stdout
readonly builder_stderr=$work_root/builder.stderr
install -m 0600 /dev/null "$builder_stdout"
install -m 0600 /dev/null "$builder_stderr"
builder_status=0
/bin/bash "$builder" --output "$generated_root" \
    >"$builder_stdout" 2>"$builder_stderr" || builder_status=$?
readonly builder_status
emit_stream builder_stdout "$builder_stdout" || {
    trap - EXIT INT TERM
    printf '%s_protected_evidence=%s\n' "$prefix" "$work_root" >&2
    exit 97
}
emit_stream builder_stderr "$builder_stderr" || {
    trap - EXIT INT TERM
    printf '%s_protected_evidence=%s\n' "$prefix" "$work_root" >&2
    exit 97
}
gate builder_status test "$builder_status" -eq 0 || exit "$builder_status"
gate generated_sources generated_sources_exact "$generated_root" || exit 1
gate generated_regression /bin/bash \
    "$generated_root/tests/action20h-a-postinstall-regression.sh" || exit 1

if [[ "$action20h_a_outer_mode" != execute ]]; then
    printf '%s_%s_complete=true\n' "$prefix" "$action20h_a_outer_mode"
    printf '%s_node_a_contacted=false\n' "$prefix"
    printf '%s_node_b_contacted=false\n' "$prefix"
    exit 0
fi

readonly runner=$generated_root/scripts/run-node-a-caddy-health-helper-postinstall-action20h-a.sh
readonly runner_stdout=$work_root/runner.stdout
readonly runner_stderr=$work_root/runner.stderr
install -m 0600 /dev/null "$runner_stdout"
install -m 0600 /dev/null "$runner_stderr"
runner_status=0
/bin/bash "$runner" >"$runner_stdout" 2>"$runner_stderr" || runner_status=$?
readonly runner_status
emit_stream runner_stdout "$runner_stdout" || {
    trap - EXIT INT TERM
    printf '%s_protected_evidence=%s\n' "$prefix" "$work_root" >&2
    exit 97
}
emit_stream runner_stderr "$runner_stderr" || {
    trap - EXIT INT TERM
    printf '%s_protected_evidence=%s\n' "$prefix" "$work_root" >&2
    exit 97
}
printf '%s_runner_status=%s\n' "$prefix" "$runner_status"
printf '%s_node_a_contacted=true\n' "$prefix"
printf '%s_node_b_contacted=false\n' "$prefix"
printf '%s_full_health_helper_invoked=false\n' "$prefix"
printf '%s_keepalived_reloaded=false\n' "$prefix"
printf '%s_vrrp_activation=false\n' "$prefix"
printf '%s_persistent_mutations=false\n' "$prefix"
printf '%s_cleanup_complete=true\n' "$prefix"
exit "$runner_status"
