#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly action_prefix=action_18b
readonly derivation_sha256=8df318bb6af25a2891a431f90d4b970544901268c87a39dcec4258290643862c
readonly regression_sha256=9493dc16753528703b3cfc8c620eb5491f7ade3d6e25f0d5356d651d97e860c0
readonly rendered_installer_sha256=9c2743e553cc52e53e57a880e3d386aba130bd7a610879159b1d36db6bf87e97
readonly rendered_runner_sha256=44a57fbd90cf1c8dfb6d42b24e80df139d7e39132fe3914c187e8cdb0a27412e
readonly receiver_sha256=a94c7a45531787055da622a0dac180f98e52bd0ba967424a4cf22a4852539d9e
readonly finalizer_sha256=15d858774a17369f31261f7f94bea72d575f269fdb3e8e991534f66dd4f4902d
readonly authorization_template_sha256=e64a603dc93bebbac065955031f36048d551cac295e19dd497c7c6ed9b8cec32
readonly maximum_stream_bytes=1048576
readonly maximum_stream_lines=4096

outer_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly outer_directory
readonly caddy_root=${outer_directory%/scripts}
readonly derivation="$outer_directory/derive-node-a-action18-prerequisite-action18b.sh"
readonly regression="$caddy_root/tests/action18b-node-a-prerequisite-regression.sh"
readonly receiver="$outer_directory/caddy-sync-release-receiver-v2"
readonly finalizer="$outer_directory/finalize-incoming-release-v2-stderr-safe-action17u.sh"
readonly authorization_template="$caddy_root/templates/authorized-key-receiver-finalized-v2.in"

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
    require_source "$derivation_sha256" 755 "$derivation"
    require_source "$regression_sha256" 755 "$regression"
    require_source "$receiver_sha256" 755 "$receiver"
    require_source "$finalizer_sha256" 755 "$finalizer"
    require_source "$authorization_template_sha256" 644 \
        "$authorization_template"
}

stage_sources() {
    local stage_root=$1
    local stage_installer
    local stage_runner

    install -d -m 0700 \
        "$stage_root/Caddy/scripts" \
        "$stage_root/Caddy/templates" \
        "$stage_root/Caddy/tests"
    "$derivation" --output-directory "$stage_root/Caddy/scripts" >/dev/null
    install -m 0755 "$receiver" "$stage_root/Caddy/scripts/"
    install -m 0755 "$finalizer" "$stage_root/Caddy/scripts/"
    install -m 0644 "$authorization_template" "$stage_root/Caddy/templates/"
    stage_installer="$stage_root/Caddy/scripts/install-node-a-action18-prerequisite-action18b.sh"
    stage_runner="$stage_root/Caddy/scripts/run-node-a-action18-prerequisite-action18b.sh"
    [[ "$(file_hash "$stage_installer")" == "$rendered_installer_sha256" ]] || return 1
    [[ "$(file_hash "$stage_runner")" == "$rendered_runner_sha256" ]] || return 1
    bash -n "$stage_installer" "$stage_runner"
    "$stage_installer" --self-test >/dev/null
    "$stage_runner" --self-test >/dev/null
    "$stage_runner" --source-test >/dev/null
    "$stage_runner" --contract-test >/dev/null
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

case "${1:-}" in
    --self-test)
        [[ $# -eq 1 ]] || exit 64
        verify_sources
        printf '%s_outer_self_test_complete=true\n' "$action_prefix"
        exit 0
        ;;
    --source-test)
        [[ $# -eq 1 ]] || exit 64
        verify_sources
        printf '%s_outer_source_test_complete=true\n' "$action_prefix"
        exit 0
        ;;
    --contract-test)
        [[ $# -eq 1 ]] || exit 64
        verify_sources
        contract_directory=$(mktemp -d /tmp/caddy-action18b-outer-contract.XXXXXX)
        readonly contract_directory
        trap 'rm -rf -- "$contract_directory"' EXIT
        stage_sources "$contract_directory"
        "$regression" >/dev/null
        printf '%s_outer_contract_test_complete=true\n' "$action_prefix"
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
work_directory=$(mktemp -d /tmp/caddy-action18b-outer.XXXXXX)
readonly work_directory
cleanup() {
    # shellcheck disable=SC2317
    rm -rf -- "$work_directory"
}
trap cleanup EXIT
stage_sources "$work_directory"
"$regression" >/dev/null
readonly rendered_runner="$work_directory/Caddy/scripts/run-node-a-action18-prerequisite-action18b.sh"
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
