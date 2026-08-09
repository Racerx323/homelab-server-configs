#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/local/go/bin:/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_26_outer
script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
readonly caddy_root=${script_directory%/scripts}
readonly core=$script_directory/run-workstation-caddy-protocols-action26.sh
readonly regression=$caddy_root/tests/action26-protocol-negotiation-regression.sh
readonly go_module=$caddy_root/tools/http3-probe/go.mod
readonly go_sum=$caddy_root/tools/http3-probe/go.sum
readonly go_source=$caddy_root/tools/http3-probe/main.go
readonly go_test_source=$caddy_root/tools/http3-probe/main_test.go
readonly core_sha256=f72ceb374f4a8c07f820dc720266458af6f2ae70b4287f84e778f8387b08c046
readonly regression_sha256=a358580a9ee04cd16be48eb20388a66ececfd33080360d4dfddf1bf4d85005d5
readonly go_module_sha256=49abe4ff921b27a9fbf6dfcd2f4aa183187385454ff00a8bdf098eafb90588b3
readonly go_sum_sha256=9211990e6b4889fa47deae4ee7d1de254e9e53307bcc55e7e36448ac5412b882
readonly go_source_sha256=e4e3d9390f13e080d3de742c7e247587a07c156a0f0083b3974100950c349f75
readonly go_test_source_sha256=22a1a7b52fc8d2c2da9ca6fd6e5263588a7e6e850444931571b8419a8179fdef
readonly maximum_stream_bytes=131072
readonly maximum_stream_lines=2000
action26_outer_work_root=

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
run_gate() {
    local action26_outer_gate_label=$1

    shift
    if "$@" >/dev/null; then
        printf '%s_gate_%s=true\n' "$prefix" "$action26_outer_gate_label"
        return 0
    fi
    printf '%s_gate_%s=false\n' "$prefix" "$action26_outer_gate_label" >&2
    return 1
}
expected_local_gates() {
    printf '%s\n' \
        working_directory core_regular core_executable core_hash \
        regression_regular regression_executable regression_hash \
        go_module_hash go_sum_hash go_source_hash go_test_source_hash \
        syntax shellcheck canonical_format gofmt go_test collision_policy \
        conditional_policy output_evidence_policy scalar_grep_policy \
        portable_awk_policy accepted_live_hash_policy regression
}
run_go_test() {
    (
        cd -- "$caddy_root/tools/http3-probe"
        GOCACHE=$action26_outer_work_root/go-cache GOTOOLCHAIN=local GOPROXY=off GOSUMDB=off \
            go test -mod=readonly ./...
    )
}
run_local_gates() {
    local action26_outer_skip_regression=$1

    run_gate working_directory working_directory_approved || return 1
    run_gate core_regular test -f "$core" || return 1
    run_gate core_executable test -x "$core" || return 1
    run_gate core_hash test "$(file_hash "$core")" = "$core_sha256" || return 1
    run_gate regression_regular test -f "$regression" || return 1
    run_gate regression_executable test -x "$regression" || return 1
    run_gate regression_hash test "$(file_hash "$regression")" = "$regression_sha256" || return 1
    run_gate go_module_hash test "$(file_hash "$go_module")" = "$go_module_sha256" || return 1
    run_gate go_sum_hash test "$(file_hash "$go_sum")" = "$go_sum_sha256" || return 1
    run_gate go_source_hash test "$(file_hash "$go_source")" = "$go_source_sha256" || return 1
    run_gate go_test_source_hash test "$(file_hash "$go_test_source")" = "$go_test_source_sha256" || return 1
    run_gate syntax /bin/bash -n "$core" "$regression" "$0" || return 1
    run_gate shellcheck shellcheck "$core" "$regression" "$0" || return 1
    run_gate canonical_format /bin/bash "$caddy_root/tests/shfmt-canonical.sh" --check \
        "$core" "$regression" "$0" || return 1
    if [[ "${CADDY_ACTION26_CONTAINER_NO_GO_TOOLCHAIN:-false}" == true ]]; then
        run_gate gofmt test "$CADDY_ACTION26_CONTAINER_NO_GO_TOOLCHAIN" = true || return 1
        run_gate go_test test "$CADDY_ACTION26_CONTAINER_NO_GO_TOOLCHAIN" = true || return 1
    else
        run_gate gofmt test -z "$(gofmt -l "$go_source" "$go_test_source")" || return 1
        run_gate go_test run_go_test || return 1
    fi
    run_gate collision_policy /bin/bash "$caddy_root/tests/check-shell-readonly-local-collisions-v2.sh" \
        "$core" "$regression" "$0" || return 1
    run_gate conditional_policy /bin/bash "$caddy_root/tests/conditional-validator-errexit-policy-regression.sh" || return 1
    run_gate output_evidence_policy /bin/bash "$caddy_root/tests/transaction-output-evidence-policy-regression.sh" || return 1
    run_gate scalar_grep_policy /bin/bash "$caddy_root/tests/multifile-grep-count-policy.sh" --check \
        "$core" "$regression" "$0" || return 1
    run_gate portable_awk_policy /bin/bash "$caddy_root/tests/portable-awk-policy.sh" --check \
        "$core" "$regression" "$0" || return 1
    run_gate accepted_live_hash_policy /bin/bash "$caddy_root/tests/accepted-live-hash-policy.sh" --check || return 1
    if [[ "$action26_outer_skip_regression" == true ]]; then
        run_gate regression test "$action26_outer_skip_regression" = true || return 1
    else
        run_gate regression /bin/bash "$regression" || return 1
    fi
}
safe_stream() {
    local action26_outer_stream=$1

    [[ "$(wc -c <"$action26_outer_stream")" -le "$maximum_stream_bytes" ]] || return 1
    [[ "$(line_count "$action26_outer_stream")" -le "$maximum_stream_lines" ]] || return 1
    ! LC_ALL=C grep -n '[^[:print:][:space:]]' "$action26_outer_stream" >/dev/null || return 1
    ! grep -Eqi \
        'BEGIN [A-Z ]*PRIVATE KEY|PRIVATE_KEY=|DOPPLER_TOKEN|Authorization:[[:space:]]*Bearer|Cookie:' \
        "$action26_outer_stream"
}
emit_stream() {
    local action26_outer_stream_label=$1
    local action26_outer_stream=$2

    printf '%s_%s_bytes=%s\n' "$prefix" "$action26_outer_stream_label" "$(wc -c <"$action26_outer_stream")"
    printf '%s_%s_lines=%s\n' "$prefix" "$action26_outer_stream_label" "$(line_count "$action26_outer_stream")"
    printf '%s_%s_sha256=%s\n' "$prefix" "$action26_outer_stream_label" "$(file_hash "$action26_outer_stream")"
    if safe_stream "$action26_outer_stream"; then
        printf '%s_%s_classification=bounded_safe\n' "$prefix" "$action26_outer_stream_label"
        if [[ -s "$action26_outer_stream" ]]; then
            printf '%s_%s_begin\n' "$prefix" "$action26_outer_stream_label"
            cat "$action26_outer_stream"
            printf '%s_%s_end\n' "$prefix" "$action26_outer_stream_label"
        else
            printf '%s_%s_content=empty\n' "$prefix" "$action26_outer_stream_label"
        fi
        return 0
    fi
    printf '%s_%s_classification=unsafe_retained\n' "$prefix" "$action26_outer_stream_label" >&2
    return 97
}
validation_check() {
    local action26_outer_validation_label=$1

    shift
    if "$@" >/dev/null; then
        printf '%s_validation_%s=true\n' "$prefix" "$action26_outer_validation_label"
        return 0
    fi
    printf '%s_validation_%s=false\n' "$prefix" "$action26_outer_validation_label" >&2
    return 1
}
validate_observed_probe() {
    local action26_outer_probe_label=$1
    local action26_outer_protocol=$2
    local action26_outer_ip=$3
    local action26_outer_transcript=$4

    validation_check "${action26_outer_probe_label}_command_status" grep -Fqx \
        "action_26_observed_${action26_outer_probe_label}_command_status=0" "$action26_outer_transcript" || return 1
    validation_check "${action26_outer_probe_label}_protocol" grep -Fqx \
        "action_26_observed_${action26_outer_probe_label}_protocol=$action26_outer_protocol" \
        "$action26_outer_transcript" || return 1
    validation_check "${action26_outer_probe_label}_status" grep -Fqx \
        "action_26_observed_${action26_outer_probe_label}_status=204" \
        "$action26_outer_transcript" || return 1
    validation_check "${action26_outer_probe_label}_remote_ip" grep -Fqx \
        "action_26_observed_${action26_outer_probe_label}_remote_ip=$action26_outer_ip" \
        "$action26_outer_transcript" || return 1
    validation_check "${action26_outer_probe_label}_body" grep -Fqx \
        "action_26_observed_${action26_outer_probe_label}_body_bytes=0" \
        "$action26_outer_transcript" || return 1
    validation_check "${action26_outer_probe_label}_redirect" grep -Fqx \
        "action_26_observed_${action26_outer_probe_label}_redirects=0" \
        "$action26_outer_transcript" || return 1
}
validate_transcript() {
    local action26_outer_transcript=$1
    local action26_outer_status=$2
    local action26_outer_stderr=$3
    local action26_outer_expected_text
    local action26_outer_actual_text
    local action26_outer_expected_count
    local action26_outer_actual_count
    local action26_outer_false_count

    # conditional-validator-explicit-failures-begin
    validation_check status_zero test "$action26_outer_status" -eq 0 || return 1
    validation_check stderr_empty test ! -s "$action26_outer_stderr" || return 1
    action26_outer_expected_text=$(/bin/bash "$core" --expected-checks) || return 1
    action26_outer_actual_text=$(sed -n 's/^action_26_check_\([^=]*\)=true$/\1/p' \
        "$action26_outer_transcript") || return 1
    validation_check ordered_checks test "$action26_outer_actual_text" = "$action26_outer_expected_text" || return 1
    action26_outer_expected_count=$(printf '%s\n' "$action26_outer_expected_text" | wc -l) || return 1
    action26_outer_actual_count=$(grep -Ec '^action_26_check_.*=(true|false)$' \
        "$action26_outer_transcript" || true) || return 1
    validation_check check_count_exact test "$action26_outer_actual_count" -eq "$action26_outer_expected_count" || return 1
    validation_check declared_check_count grep -Fqx "action_26_check_count=$action26_outer_expected_count" \
        "$action26_outer_transcript" || return 1
    action26_outer_false_count=$(grep -Ec '^action_26_check_.*=false$' "$action26_outer_transcript" || true) || return 1
    validation_check false_checks_absent test "$action26_outer_false_count" -eq 0 || return 1
    validate_observed_probe h1_ipv4 1.1 10.1.0.56 "$action26_outer_transcript" || return 1
    validate_observed_probe h1_ipv6 1.1 fd36:5aa8:6971:1::56 "$action26_outer_transcript" || return 1
    validate_observed_probe h2_ipv4 2 10.1.0.56 "$action26_outer_transcript" || return 1
    validate_observed_probe h2_ipv6 2 fd36:5aa8:6971:1::56 "$action26_outer_transcript" || return 1
    validate_observed_probe h3_ipv4 HTTP/3.0 10.1.0.56 "$action26_outer_transcript" || return 1
    validate_observed_probe h3_ipv6 HTTP/3.0 fd36:5aa8:6971:1::56 "$action26_outer_transcript" || return 1
    validation_check endpoint_count grep -Fqx 'action_26_endpoint_count=6' "$action26_outer_transcript" || return 1
    validation_check workstation_only grep -Fqx 'action_26_workstation_only=true' "$action26_outer_transcript" || return 1
    validation_check node_ssh_false grep -Fqx 'action_26_node_ssh=false' "$action26_outer_transcript" || return 1
    validation_check filesystem_mutation_false grep -Fqx 'action_26_filesystem_mutation=false' \
        "$action26_outer_transcript" || return 1
    validation_check service_mutation_false grep -Fqx 'action_26_service_mutation=false' \
        "$action26_outer_transcript" || return 1
    validation_check dns_mutation_false grep -Fqx 'action_26_dns_mutation=false' "$action26_outer_transcript" || return 1
    validation_check complete grep -Fqx 'action_26_protocol_validation_complete=true' \
        "$action26_outer_transcript" || return 1
    # conditional-validator-explicit-failures-end
}
cleanup() {
    local action26_outer_cleanup_status=$?

    trap - EXIT INT TERM
    if [[ -n "$action26_outer_work_root" ]]; then
        rm -rf -- "$action26_outer_work_root"
    fi
    exit "$action26_outer_cleanup_status"
}
run_action() {
    local action26_outer_core_status=0
    local action26_outer_stdout
    local action26_outer_stderr

    action26_outer_work_root=$(mktemp -d /tmp/caddy-action26-outer.XXXXXX)
    trap cleanup EXIT INT TERM
    action26_outer_stdout=$action26_outer_work_root/core.stdout
    action26_outer_stderr=$action26_outer_work_root/core.stderr
    run_local_gates "${CADDY_ACTION26_SKIP_REGRESSION:-false}" || return 1
    /bin/bash "$core" >"$action26_outer_stdout" 2>"$action26_outer_stderr" || action26_outer_core_status=$?
    emit_stream core_stdout "$action26_outer_stdout" || return $?
    emit_stream core_stderr "$action26_outer_stderr" || return $?
    validate_transcript "$action26_outer_stdout" "$action26_outer_core_status" "$action26_outer_stderr" || return 1
    printf '%s_workstation_network_contact=true\n' "$prefix"
    printf '%s_node_ssh=false\n' "$prefix"
    printf '%s_read_only=true\n' "$prefix"
    printf '%s_complete=true\n' "$prefix"
}

case "${1:-}" in
    --expected-local-gates) expected_local_gates ;;
    --validate-transcript) validate_transcript "${2:?}" "${3:?}" "${4:?}" ;;
    --self-test)
        action26_outer_work_root=$(mktemp -d /tmp/caddy-action26-outer-selftest.XXXXXX)
        trap cleanup EXIT INT TERM
        CADDY_ACTION26_SKIP_REGRESSION=true run_local_gates true
        ;;
    '') run_action ;;
    *) exit 64 ;;
esac
