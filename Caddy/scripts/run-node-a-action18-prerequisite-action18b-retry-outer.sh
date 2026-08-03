#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly action_prefix=action_18b_retry
readonly derivation_sha256=e72d7c5970ce7cbaf19d83adbf062f2717abf89b261aece807049c42722c7bea
readonly regression_sha256=c857a11a21c66be4fe6581d741c39278b42a292184a4264dc9087d246f36db06
readonly rendered_installer_sha256=f9e91d20bcb2be8b7791317fa1245b2b99848608b9d24c1b934881e4d45022df
readonly rendered_runner_sha256=c0908e27de47200bcca6ee037effd3f1765c5d71278048f0fcee3f026785aced
readonly receiver_sha256=a94c7a45531787055da622a0dac180f98e52bd0ba967424a4cf22a4852539d9e
readonly finalizer_sha256=15d858774a17369f31261f7f94bea72d575f269fdb3e8e991534f66dd4f4902d
readonly authorization_template_sha256=e64a603dc93bebbac065955031f36048d551cac295e19dd497c7c6ed9b8cec32
readonly collision_checker_sha256=ba1e769a3d00b5884421a8860f820e2dc8a3d8074837dab930630407f047886f
readonly maximum_stream_bytes=1048576
readonly maximum_stream_lines=4096

script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
readonly caddy_root=${script_directory%/scripts}
readonly derivation="$script_directory/derive-node-a-action18-prerequisite-action18b-retry.sh"
readonly regression="$caddy_root/tests/action18b-retry-node-a-prerequisite-regression.sh"
readonly receiver="$script_directory/caddy-sync-release-receiver-v2"
readonly finalizer="$script_directory/finalize-incoming-release-v2-stderr-safe-action17u.sh"
readonly authorization_template="$caddy_root/templates/authorized-key-receiver-finalized-v2.in"
readonly collision_checker="$caddy_root/tests/check-shell-readonly-local-collisions-v2.sh"

file_hash() {
    sha256sum "$1" | awk '{ print $1 }'
}

line_count() {
    awk 'END { print NR }' "$1"
}

require_source() {
    local expected_hash=$1
    local expected_mode=$2
    local source_path=$3

    [[ -f "$source_path" && ! -L "$source_path" ]] || return 1
    [[ "$(stat -c '%U:%G:%a' "$source_path")" == "aaron:aaron:$expected_mode" ]] || return 1
    [[ "$(file_hash "$source_path")" == "$expected_hash" ]] || return 1
}

verify_sources() {
    require_source "$derivation_sha256" 755 "$derivation" || return 1
    require_source "$regression_sha256" 755 "$regression" || return 1
    require_source "$receiver_sha256" 755 "$receiver" || return 1
    require_source "$finalizer_sha256" 755 "$finalizer" || return 1
    require_source "$authorization_template_sha256" 644 \
        "$authorization_template" || return 1
    require_source "$collision_checker_sha256" 755 \
        "$collision_checker" || return 1
}

stage_sources() {
    local stage_root=$1
    local rendered_installer_path
    local rendered_runner_path

    install -d -m 0700 \
        "$stage_root/Caddy/scripts" \
        "$stage_root/Caddy/templates" \
        "$stage_root/Caddy/tests" || return 1
    "$derivation" --output-directory "$stage_root/Caddy/scripts" >/dev/null ||
        return 1
    install -m 0755 "$receiver" "$finalizer" \
        "$stage_root/Caddy/scripts/" || return 1
    install -m 0644 "$authorization_template" \
        "$stage_root/Caddy/templates/" || return 1
    install -m 0755 "$collision_checker" "$stage_root/Caddy/tests/" ||
        return 1
    rendered_installer_path="$stage_root/Caddy/scripts/install-node-a-action18-prerequisite-action18b-retry.sh"
    rendered_runner_path="$stage_root/Caddy/scripts/run-node-a-action18-prerequisite-action18b-retry.sh"
    [[ "$(file_hash "$rendered_installer_path")" == "$rendered_installer_sha256" ]] || return 1
    [[ "$(file_hash "$rendered_runner_path")" == "$rendered_runner_sha256" ]] || return 1
    bash -n "$rendered_installer_path" "$rendered_runner_path" || return 1
    shellcheck "$rendered_installer_path" "$rendered_runner_path" || return 1
    "$collision_checker" "$rendered_installer_path" \
        "$rendered_runner_path" >/dev/null || return 1
    "$rendered_installer_path" --self-test >/dev/null || return 1
    "$rendered_runner_path" --self-test >/dev/null || return 1
    "$rendered_runner_path" --source-test >/dev/null || return 1
    "$rendered_runner_path" --contract-test >/dev/null || return 1
}

safe_stream() {
    local stream_path=$1

    [[ "$(wc -c <"$stream_path")" -le "$maximum_stream_bytes" ]] || return 1
    [[ "$(line_count "$stream_path")" -le "$maximum_stream_lines" ]] || return 1
    ! LC_ALL=C grep -n '[^[:print:][:space:]]' "$stream_path" >/dev/null ||
        return 1
    ! grep -Eqi \
        'BEGIN [A-Z ]*PRIVATE KEY|CADDY_TLS_PRIVATE_KEY_PEM|PRIVATE_KEY=|DOPPLER_TOKEN|Authorization:[[:space:]]*Bearer' \
        "$stream_path"
}

emit_stream_metadata() {
    local stream_name=$1
    local stream_path=$2

    printf '%s_%s_bytes=%s\n' "$action_prefix" "$stream_name" \
        "$(wc -c <"$stream_path")"
    printf '%s_%s_lines=%s\n' "$action_prefix" "$stream_name" \
        "$(line_count "$stream_path")"
    printf '%s_%s_sha256=%s\n' "$action_prefix" "$stream_name" \
        "$(file_hash "$stream_path")"
}

run_local_gates() {
    local gate_root

    gate_root=$(mktemp -d /tmp/caddy-action18b-retry-outer-gate.XXXXXX) ||
        return 1
    if ! stage_sources "$gate_root"; then
        rm -rf -- "$gate_root"
        return 1
    fi
    rm -rf -- "$gate_root"
    "$regression" >/dev/null || return 1
}

case "${1:-}" in
    --self-test | --source-test | --contract-test)
        [[ $# -eq 1 ]] || exit 64
        verify_sources
        run_local_gates
        printf '%s_outer_%s_complete=true\n' "$action_prefix" "${1#--}"
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

verify_sources
[[ "$PWD" == /home/aaron/code/homelab-server-configs ]]
run_local_gates
work_directory=$(mktemp -d /tmp/caddy-action18b-retry-outer.XXXXXX)
readonly work_directory
cleanup() {
    # shellcheck disable=SC2317
    rm -rf -- "$work_directory"
}
trap cleanup EXIT
stage_sources "$work_directory"
readonly rendered_runner="$work_directory/Caddy/scripts/run-node-a-action18-prerequisite-action18b-retry.sh"
readonly stdout_path="$work_directory/inner.stdout"
readonly stderr_path="$work_directory/inner.stderr"
: >"$stdout_path"
: >"$stderr_path"
chmod 0600 "$stdout_path" "$stderr_path"

inner_status=0
"$rendered_runner" >"$stdout_path" 2>"$stderr_path" || inner_status=$?
readonly inner_status
emit_stream_metadata inner_stdout "$stdout_path"
emit_stream_metadata inner_stderr "$stderr_path"
if safe_stream "$stdout_path" && safe_stream "$stderr_path"; then
    printf '%s_inner_stream_classification=bounded_safe\n' "$action_prefix"
    printf '%s_inner_stdout_begin\n' "$action_prefix"
    cat "$stdout_path"
    printf '%s_inner_stdout_end\n' "$action_prefix"
    if [[ -s "$stderr_path" ]]; then
        printf '%s_inner_stderr_begin\n' "$action_prefix" >&2
        cat "$stderr_path" >&2
        printf '%s_inner_stderr_end\n' "$action_prefix" >&2
    fi
else
    printf '%s_inner_stream_classification=unsafe_retained\n' \
        "$action_prefix" >&2
    trap - EXIT
    printf '%s_protected_evidence=%s\n' "$action_prefix" \
        "$work_directory" >&2
    exit 97
fi
printf '%s_inner_status=%s\n' "$action_prefix" "$inner_status"
rm -rf -- "$work_directory"
trap - EXIT
printf '%s_outer_cleanup_complete=true\n' "$action_prefix"
exit "$inner_status"
