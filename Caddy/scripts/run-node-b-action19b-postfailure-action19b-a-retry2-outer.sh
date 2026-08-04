#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_19b_a_retry2
readonly derivation_sha256=4dd0f1d3ca710a5e2e6d0631abbfade5aa1f99a55740eb78b55a2a6569fd976b
readonly regression_sha256=4d88f027bc4063f5e781c33073312338189ac6e98a51ab2b63aff7ca02bab42d
readonly baseline_sha256=162f153d116e53aba95775836c4a5cb6677ad7fd080c673ca6c5ac8fb0092a0f
readonly rendered_inspector_sha256=a9a92b4007e7b6a0798a76fd57bdd23771970e23d1e486e76b66f6408eb92c55
readonly rendered_runner_sha256=4f055690939d84fbb4c53772de867e9ba05729546669f5fbe4deb75d4fdba45a
readonly collision_checker_sha256=ba1e769a3d00b5884421a8860f820e2dc8a3d8074837dab930630407f047886f
readonly maximum_stream_bytes=1048576
readonly maximum_stream_lines=4096

script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
readonly caddy_root=${script_directory%/scripts}
readonly derivation="$script_directory/derive-node-b-action19b-postfailure-action19b-a-retry2.sh"
readonly regression="$caddy_root/tests/action19b-a-retry2-node-b-postfailure-regression.sh"
readonly baseline="$script_directory/inspect-node-b-keepalived-helper-prerequisite-action19a-a.sh"
readonly collision_checker="$caddy_root/tests/check-shell-readonly-local-collisions-v2.sh"

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }
line_count() { awk 'END { print NR }' "$1"; }

require_source() {
    local expected_hash=$1
    local source_path=$2
    local expected_identity

    expected_identity="$(id -un):$(id -gn):755"
    [[ -f "$source_path" && ! -L "$source_path" ]] || return 1
    [[ -x "$source_path" ]] || return 1
    [[ "$(stat -c '%U:%G:%a' "$source_path")" = "$expected_identity" ]] ||
        return 1
    [[ "$(file_hash "$source_path")" = "$expected_hash" ]] || return 1
}

verify_sources() {
    require_source "$derivation_sha256" "$derivation" || return 1
    require_source "$regression_sha256" "$regression" || return 1
    require_source "$baseline_sha256" "$baseline" || return 1
    require_source "$collision_checker_sha256" "$collision_checker" ||
        return 1
    bash -n "$derivation" "$regression" || return 1
    shellcheck "$derivation" "$regression" || return 1
    "$collision_checker" "$derivation" "$regression" >/dev/null || return 1
}

render_stage() {
    local stage_root=$1
    local stage_scripts="$stage_root/Caddy/scripts"
    local stage_tests="$stage_root/Caddy/tests"
    local staged_inspector="$stage_scripts/inspect-node-b-action19b-postfailure-action19b-a-retry2.sh"
    local staged_runner="$stage_scripts/run-node-b-action19b-postfailure-action19b-a-retry2.sh"

    install -d -m 0700 "$stage_scripts" "$stage_tests" || return 1
    "$derivation" --output-directory "$stage_scripts" >/dev/null || return 1
    install -m 0755 "$baseline" "$stage_scripts/" || return 1
    install -m 0755 "$collision_checker" "$stage_tests/" || return 1
    [[ "$(file_hash "$staged_inspector")" = "$rendered_inspector_sha256" ]] ||
        return 1
    [[ "$(file_hash "$staged_runner")" = "$rendered_runner_sha256" ]] ||
        return 1
    bash -n "$staged_inspector" "$staged_runner" || return 1
    shellcheck "$staged_inspector" "$staged_runner" || return 1
    "$collision_checker" "$staged_inspector" "$staged_runner" >/dev/null ||
        return 1
    "$staged_inspector" --self-test "$stage_scripts/${baseline##*/}" \
        >/dev/null || return 1
    "$staged_inspector" --contract-test "$stage_scripts/${baseline##*/}" \
        >/dev/null || return 1
    "$staged_runner" --self-test >/dev/null || return 1
    "$staged_runner" --contract-test >/dev/null || return 1
    printf '%s\n' "$staged_runner"
}

run_local_gates() {
    local gate_root=$1

    "$derivation" --self-test >/dev/null || return 1
    "$regression" >/dev/null || return 1
    render_stage "$gate_root" >/dev/null || return 1
}

safe_stream() {
    local stream_path=$1

    [[ "$(wc -c <"$stream_path")" -le "$maximum_stream_bytes" ]] ||
        return 1
    [[ "$(line_count "$stream_path")" -le "$maximum_stream_lines" ]] ||
        return 1
    ! LC_ALL=C grep -n '[^[:print:][:space:]]' "$stream_path" >/dev/null ||
        return 1
    ! grep -Eqi \
        'BEGIN [A-Z ]*PRIVATE KEY|CADDY_TLS_PRIVATE_KEY_PEM|PRIVATE_KEY=|DOPPLER_TOKEN|Authorization:[[:space:]]*Bearer' \
        "$stream_path"
}

emit_stream_metadata() {
    local stream_name=$1
    local stream_path=$2

    printf '%s_outer_%s_bytes=%s\n' "$prefix" "$stream_name" \
        "$(wc -c <"$stream_path")"
    printf '%s_outer_%s_lines=%s\n' "$prefix" "$stream_name" \
        "$(line_count "$stream_path")"
    printf '%s_outer_%s_sha256=%s\n' "$prefix" "$stream_name" \
        "$(file_hash "$stream_path")"
}

case "${1:-}" in
    --self-test | --source-test | --contract-test)
        [[ $# -eq 1 ]] || exit 64
        verify_sources
        test_root=$(mktemp -d /tmp/caddy-action19b-a-retry2-outer-test.XXXXXX)
        readonly test_root
        trap 'rm -rf -- "$test_root"' EXIT
        run_local_gates "$test_root"
        printf '%s_outer_%s_complete=true\n' "$prefix" "${1#--}"
        exit 0
        ;;
    "") [[ $# -eq 0 ]] || exit 64 ;;
    *) exit 64 ;;
esac

verify_sources
[[ "$PWD" = /home/aaron/code/homelab-server-configs ]]
work_directory=$(mktemp -d /tmp/caddy-action19b-a-retry2-outer.XXXXXX)
readonly work_directory
cleanup() {
    # shellcheck disable=SC2317
    rm -rf -- "$work_directory"
}
trap cleanup EXIT
run_local_gates "$work_directory/local"
rendered_runner=$(render_stage "$work_directory/live")
readonly rendered_runner
readonly stdout_path="$work_directory/inner.stdout"
readonly stderr_path="$work_directory/inner.stderr"
: >"$stdout_path"
: >"$stderr_path"
chmod 0600 "$stdout_path" "$stderr_path"

inner_status=0
"$rendered_runner" >"$stdout_path" 2>"$stderr_path" || inner_status=$?
readonly inner_status
emit_stream_metadata stdout "$stdout_path"
emit_stream_metadata stderr "$stderr_path"
if safe_stream "$stdout_path" && safe_stream "$stderr_path"; then
    printf '%s_outer_stream_classification=bounded_safe\n' "$prefix"
    printf '%s_outer_stdout_begin\n' "$prefix"
    cat "$stdout_path"
    printf '%s_outer_stdout_end\n' "$prefix"
    if [[ -s "$stderr_path" ]]; then
        printf '%s_outer_stderr_begin\n' "$prefix" >&2
        cat "$stderr_path" >&2
        printf '%s_outer_stderr_end\n' "$prefix" >&2
    else
        printf '%s_outer_stderr_content_secured=empty\n' "$prefix"
    fi
else
    printf '%s_outer_stream_classification=unsafe_retained\n' "$prefix" >&2
    trap - EXIT
    printf '%s_protected_evidence=%s\n' "$prefix" "$work_directory" >&2
    exit 97
fi
printf '%s_outer_runner_status=%s\n' "$prefix" "$inner_status"
rm -rf -- "$work_directory"
trap - EXIT
printf '%s_outer_cleanup_complete=true\n' "$prefix"
exit "$inner_status"
