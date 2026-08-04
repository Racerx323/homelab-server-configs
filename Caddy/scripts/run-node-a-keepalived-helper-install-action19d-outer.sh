#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_19d
readonly derivation_sha256=c46a1c9d028dcf84dbb6061bc0ee31f2527013ad4bd178a1d6fd10bc2dfa4a87
readonly regression_sha256=79f920b14342ce236ed78215c16f2b1b1e0a014a0000eb34ee50f9a41de47fc4
readonly health_sha256=c3bc1c080cd148efc0a64440a2a411ec115d0ca83f8e6a66220d7bd201971414
readonly notification_sha256=5862b494301f972d039477d4ed93a7d56156b141cba31c41ccd61d7f843321d8
readonly inspector_sha256=57e3bf9d9ae61b4e2b6017118481f492bd29c5784e74710a367b620230e0bea9
readonly installer_sha256=5a6b6d5489db0374d57827c1d92c5a8a8f2ae27b7181a9c30795d5c0cc8cf88d
readonly labels_sha256=48ce4d7b87142372156e5ab14b1b6a6e153eada1f3e4ca1a5a2163037714801c
readonly runner_sha256=a91a94af9ce696c0f38bb0a95cc35033a78e178d16cade48805f74211a9dd0e4
readonly collision_checker_sha256=ba1e769a3d00b5884421a8860f820e2dc8a3d8074837dab930630407f047886f
readonly transcript_policy_sha256=99e0040d785e70a4f2e8d1796f8c6bf29675593d1ae5d13e54d9ac2dceebe44c
readonly conditional_policy_sha256=68cd687916f9d8be78f50af7a410d376f457ca74ab906a8e459795de6c495455
readonly maximum_stream_bytes=1048576
readonly maximum_stream_lines=4096

script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
readonly caddy_root=${script_directory%/scripts}
readonly derivation="$script_directory/derive-node-a-keepalived-helper-install-action19d.sh"
readonly regression="$caddy_root/tests/action19d-node-a-keepalived-helper-install-definition-regression.sh"
readonly health_source="$script_directory/check-caddy.sh"
readonly notification_source="$script_directory/lsyncd-ha-failover-notify.sh"
readonly collision_checker="$caddy_root/tests/check-shell-readonly-local-collisions-v2.sh"
readonly transcript_policy="$caddy_root/tests/transcript-contract-ratchet-policy-regression.sh"
readonly conditional_policy="$caddy_root/tests/conditional-validator-errexit-policy-regression.sh"

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }
line_count() { awk 'END { print NR }' "$1"; }

require_source() {
    local expected_hash=$1
    local source_path=$2
    local source_identity

    source_identity="$(id -un):$(id -gn):755"
    [[ -f "$source_path" && ! -L "$source_path" && -x "$source_path" ]] ||
        return 1
    [[ "$(stat -c '%U:%G:%a' "$source_path")" = "$source_identity" ]] ||
        return 1
    [[ "$(file_hash "$source_path")" = "$expected_hash" ]] || return 1
}

verify_sources() {
    require_source "$derivation_sha256" "$derivation" || return 1
    require_source "$regression_sha256" "$regression" || return 1
    require_source "$health_sha256" "$health_source" || return 1
    require_source "$notification_sha256" "$notification_source" || return 1
    require_source "$collision_checker_sha256" "$collision_checker" ||
        return 1
    require_source "$transcript_policy_sha256" "$transcript_policy" ||
        return 1
    require_source "$conditional_policy_sha256" "$conditional_policy" ||
        return 1
    bash -n "$derivation" "$regression" "$health_source" \
        "$notification_source" "$transcript_policy" "$conditional_policy" ||
        return 1
    shellcheck "$derivation" "$regression" || return 1
    "$collision_checker" "$derivation" "$regression" "$health_source" \
        "$notification_source" "$transcript_policy" \
        "$conditional_policy" >/dev/null || return 1
}

render_and_validate() {
    local stage_root=$1
    local stage_scripts="$stage_root/Caddy/scripts"
    local stage_tests="$stage_root/Caddy/tests"
    local inspector="$stage_scripts/inspect-node-a-keepalived-prerequisite-action19c-a.sh"
    local installer="$stage_scripts/install-node-a-keepalived-helpers-action19d.sh"
    local labels="$stage_scripts/action19d-node-a-keepalived-helper-check-labels.txt"
    local runner="$stage_scripts/run-node-a-keepalived-helper-install-action19d.sh"

    install -d -m 0700 "$stage_scripts" "$stage_tests" || return 1
    /bin/bash "$derivation" --output "$stage_scripts" >/dev/null || return 1
    install -m 0755 "$health_source" "$notification_source" \
        "$stage_scripts/" || return 1
    install -m 0755 "$collision_checker" "$stage_tests/" || return 1
    [[ "$(file_hash "$inspector")" = "$inspector_sha256" ]] || return 1
    [[ "$(file_hash "$installer")" = "$installer_sha256" ]] || return 1
    [[ "$(file_hash "$labels")" = "$labels_sha256" ]] || return 1
    [[ "$(file_hash "$runner")" = "$runner_sha256" ]] || return 1
    [[ "$(stat -c '%U:%G:%a' "$labels")" = "$(id -un):$(id -gn):644" ]] || return 1
    bash -n "$inspector" "$installer" "$runner" || return 1
    shellcheck "$inspector" "$installer" "$runner" || return 1
    "$collision_checker" "$inspector" "$installer" "$runner" >/dev/null ||
        return 1
    /bin/bash "$installer" --self-test >/dev/null || return 1
    /bin/bash "$runner" --self-test >/dev/null || return 1
    /bin/bash "$runner" --contract-test >/dev/null || return 1
}

run_local_gates() {
    local gate_root

    verify_sources || return 1
    /bin/bash "$derivation" --self-test >/dev/null || return 1
    /bin/bash "$transcript_policy" >/dev/null || return 1
    /bin/bash "$conditional_policy" >/dev/null || return 1
    /bin/bash "$regression" >/dev/null || return 1
    gate_root=$(mktemp -d /tmp/caddy-action19d-local-gates.XXXXXX) || return 1
    if ! render_and_validate "$gate_root"; then
        rm -rf -- "$gate_root"
        return 1
    fi
    rm -rf -- "$gate_root"
}

safe_stream() {
    local stream_path=$1

    [[ "$(wc -c <"$stream_path")" -le "$maximum_stream_bytes" ]] || return 1
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

    printf '%s_%s_bytes=%s\n' "$prefix" "$stream_name" \
        "$(wc -c <"$stream_path")"
    printf '%s_%s_lines=%s\n' "$prefix" "$stream_name" \
        "$(line_count "$stream_path")"
    printf '%s_%s_sha256=%s\n' "$prefix" "$stream_name" \
        "$(file_hash "$stream_path")"
}

case "${1:-}" in
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
        printf 'Usage: %s [--self-test|--source-test|--contract-test]\n' \
            "${0##*/}" >&2
        exit 64
        ;;
esac

run_local_gates
[[ "$PWD" = /home/aaron/code/homelab-server-configs ]]

work_directory=$(mktemp -d /tmp/caddy-action19d-outer.XXXXXX)
readonly work_directory
# shellcheck disable=SC2317
cleanup() { rm -rf -- "$work_directory"; }
trap cleanup EXIT

render_and_validate "$work_directory/rendered"
readonly execution_runner="$work_directory/rendered/Caddy/scripts/run-node-a-keepalived-helper-install-action19d.sh"
readonly stdout_path="$work_directory/runner.stdout"
readonly stderr_path="$work_directory/runner.stderr"
: >"$stdout_path"
: >"$stderr_path"
chmod 0600 "$stdout_path" "$stderr_path"

runner_status=0
/bin/bash "$execution_runner" >"$stdout_path" 2>"$stderr_path" ||
    runner_status=$?
readonly runner_status
emit_stream_metadata runner_stdout "$stdout_path"
emit_stream_metadata runner_stderr "$stderr_path"
if safe_stream "$stdout_path" && safe_stream "$stderr_path"; then
    printf '%s_runner_stream_classification=bounded_safe\n' "$prefix"
    printf '%s_runner_stdout_begin\n' "$prefix"
    cat "$stdout_path"
    printf '%s_runner_stdout_end\n' "$prefix"
    if [[ -s "$stderr_path" ]]; then
        printf '%s_runner_stderr_begin\n' "$prefix" >&2
        cat "$stderr_path" >&2
        printf '%s_runner_stderr_end\n' "$prefix" >&2
    else
        printf '%s_runner_stderr_content_secured=empty\n' "$prefix"
    fi
else
    printf '%s_runner_stream_classification=unsafe_retained\n' "$prefix" >&2
    trap - EXIT
    printf '%s_protected_evidence=%s\n' "$prefix" "$work_directory" >&2
    exit 97
fi
printf '%s_runner_status=%s\n' "$prefix" "$runner_status"
rm -rf -- "$work_directory"
trap - EXIT
printf '%s_outer_cleanup_complete=true\n' "$prefix"
exit "$runner_status"
