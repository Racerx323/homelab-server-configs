#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_18c_publisher_prerequisite
readonly expected_target=pi@10.1.0.54
readonly expected_host_alias=pihole00.local.theama.co
readonly publisher_sha256=e4a48f12a7324a885684a57070269a2d074d056c65d9e767db901408e0e86669
readonly installer_sha256=b26eab687ed6dc19f118d532ae14dacf85b0aa9e8a39f031bf2ed2369fe7a0a5
readonly maximum_stream_bytes=1048576
readonly maximum_stream_lines=4096

script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
readonly caddy_root=${script_directory%/scripts}
readonly publisher="$script_directory/publish-release-v2.sh"
readonly installer="$script_directory/install-node-b-protocol-v2-publisher-action18c-prerequisite.sh"
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
    local source_identity

    [[ -f "$source_path" && ! -L "$source_path" ]] || return 1
    source_identity="$(id -un):$(id -gn):$expected_mode"
    [[ "$(stat -c '%U:%G:%a' "$source_path")" == "$source_identity" ]] ||
        return 1
    [[ "$(file_hash "$source_path")" == "$expected_hash" ]] || return 1
}

verify_sources() {
    require_source "$publisher_sha256" 755 "$publisher" || return 1
    require_source "$installer_sha256" 755 "$installer" || return 1
    [[ -x "$collision_checker" ]] || return 1
    bash -n "$publisher" "$installer" || return 1
    "$collision_checker" "$publisher" "$installer" >/dev/null || return 1
    "$installer" --self-test >/dev/null || return 1
}

working_directory_approved() {
    case "$PWD" in
        /home/aaron/code/homelab-server-configs)
            return 0
            ;;
        /workspace/homelab-server-configs)
            [[ "${CADDY_VALIDATION_CONTAINER:-}" = 1 ]]
            return
            ;;
    esac
    return 1
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

    printf '%s_%s_bytes=%s\n' "$prefix" "$stream_name" \
        "$(wc -c <"$stream_path")"
    printf '%s_%s_lines=%s\n' "$prefix" "$stream_name" \
        "$(line_count "$stream_path")"
    printf '%s_%s_sha256=%s\n' "$prefix" "$stream_name" \
        "$(file_hash "$stream_path")"
}

require_exact_line() {
    local expected_line=$1
    local transcript_path=$2

    [[ "$(grep -Fxc "$expected_line" "$transcript_path")" -eq 1 ]]
}

validate_success() {
    local error_path=$1
    local output_path=$2
    local observed_remote_status=$3
    local check_count
    local unique_count
    local required_marker

    [[ "$observed_remote_status" -eq 0 ]] || return 1
    [[ ! -s "$error_path" ]] || return 1
    [[ "$(grep -Ec "^${prefix}_check_[a-z0-9_]+=false$" \
        "$output_path" || true)" -eq 0 ]] || return 1
    check_count=$(grep -Ec "^${prefix}_check_[a-z0-9_]+=true$" \
        "$output_path" || true)
    unique_count=$(sed -n \
        "s/^\\(${prefix}_check_[a-z0-9_]*\\)=true$/\\1/p" \
        "$output_path" | LC_ALL=C sort -u | wc -l)
    [[ "$check_count" -ge 60 ]] || return 1
    [[ "$check_count" -eq "$unique_count" ]] || return 1
    if grep -Eq \
        "^${prefix}_(publisher_invoked|release_mutated|vrrp_mutated|lsyncd_reconciliation_activation|service_mutations)=true$" \
        "$output_path"; then
        return 1
    fi
    for required_marker in \
        "${prefix}_preflight_complete=true" \
        "${prefix}_mutation_started=true" \
        "${prefix}_publisher_invoked=false" \
        "${prefix}_release_mutated=false" \
        "${prefix}_vrrp_mutated=false" \
        "${prefix}_lsyncd_reconciliation_activation=false" \
        "${prefix}_service_mutations=false" \
        "${prefix}_persistent_mutation_scope=publisher_v2,rollback_backup" \
        "${prefix}_install_complete=true"; do
        require_exact_line "$required_marker" "$output_path" || return 1
    done
    [[ "$(grep -Ec \
        "^${prefix}_backup_path=/var/backups/caddy-ha/action18c-publisher-prerequisite\\.[A-Za-z0-9]+$" \
        "$output_path")" -eq 1 ]] || return 1
    ! grep -Eq \
        "${prefix}_(rollback_|manual_intervention_required=true)" \
        "$output_path" "$error_path"
}

validate_failure() {
    local error_path=$1
    local output_path=$2
    local observed_remote_status=$3

    [[ "$observed_remote_status" -ne 0 ]] || return 1
    if grep -Fq "${prefix}_manual_intervention_required=true" \
        "$output_path" "$error_path" ||
        grep -Fq "${prefix}_rollback_complete=false" \
            "$output_path" "$error_path"; then
        return 97
    fi
    if grep -Fq "${prefix}_mutation_started=true" "$output_path"; then
        require_exact_line "${prefix}_rollback_started=true" "$error_path" ||
            return 97
        require_exact_line "${prefix}_rollback_complete=true" "$error_path" ||
            return 97
    elif grep -Eq "${prefix}_rollback_" "$output_path" "$error_path"; then
        return 97
    fi
}

validate_transcript() {
    local error_path=$1
    local output_path=$2
    local observed_remote_status=$3

    if [[ "$observed_remote_status" -eq 0 ]]; then
        validate_success "$error_path" "$output_path" "$observed_remote_status"
        return
    fi
    validate_failure "$error_path" "$output_path" "$observed_remote_status"
}

write_remote_bundle() {
    local bundle_archive_source=$1
    local bundle_output_path=$2

    # Literal remote-script variables expand only after reaching Node B.
    # shellcheck disable=SC1003,SC2016
    {
        printf '%s\n' \
            '#!/usr/bin/env bash' \
            'set -Eeuo pipefail' \
            'set +x' \
            'umask 077' \
            'PATH=/usr/sbin:/usr/bin:/sbin:/bin' \
            'export PATH' \
            'cd /' \
            'bundle_stage=$(mktemp -d /run/caddy-action18c-publisher-prerequisite-stage.XXXXXX)' \
            'cleanup_bundle_stage() {' \
            '    rm -rf -- "$bundle_stage"' \
            '}' \
            'trap cleanup_bundle_stage EXIT' \
            'install -d -o root -g root -m 0700 "$bundle_stage/payload"' \
            'base64 -d >"$bundle_stage/payload.tar" <<'\''ACTION18C_PUBLISHER_ARCHIVE'\'''
        base64 "$bundle_archive_source"
        printf '%s\n' \
            'ACTION18C_PUBLISHER_ARCHIVE' \
            'tar --extract --file "$bundle_stage/payload.tar" \' \
            '    --directory "$bundle_stage/payload" \' \
            '    --no-same-owner --no-same-permissions' \
            'chown -R root:root "$bundle_stage/payload"' \
            'chmod 0700 "$bundle_stage/payload"' \
            'chmod 0700 "$bundle_stage/payload"/*' \
            'cd /' \
            '/bin/bash \' \
            '    "$bundle_stage/payload/install-node-b-protocol-v2-publisher-action18c-prerequisite.sh" \' \
            '    --stage "$bundle_stage/payload"'
    } >"$bundle_output_path"
    chmod 0600 "$bundle_output_path"
    bash -n "$bundle_output_path"
}

write_success_fixture() {
    local fixture_path=$1
    local fixture_index

    for fixture_index in $(seq 1 60); do
        printf '%s_check_fixture_%02d=true\n' "$prefix" "$fixture_index"
    done >"$fixture_path"
    printf '%s\n' \
        "${prefix}_preflight_complete=true" \
        "${prefix}_mutation_started=true" \
        "${prefix}_publisher_invoked=false" \
        "${prefix}_release_mutated=false" \
        "${prefix}_vrrp_mutated=false" \
        "${prefix}_lsyncd_reconciliation_activation=false" \
        "${prefix}_service_mutations=false" \
        "${prefix}_backup_path=/var/backups/caddy-ha/action18c-publisher-prerequisite.ABC123" \
        "${prefix}_persistent_mutation_scope=publisher_v2,rollback_backup" \
        "${prefix}_install_complete=true" >>"$fixture_path"
}

case "${1:-}" in
    --self-test)
        [[ $# -eq 1 ]] || exit 64
        verify_sources
        printf '%s_runner_self_test_complete=true\n' "$prefix"
        exit 0
        ;;
    --source-test)
        [[ $# -eq 1 ]] || exit 64
        verify_sources
        [[ "$(stat -c '%U:%G:%a' "$0")" = "$(id -un):$(id -gn):755" ]]
        printf '%s_runner_source_test_complete=true\n' "$prefix"
        exit 0
        ;;
    --contract-test)
        [[ $# -eq 1 ]] || exit 64
        verify_sources
        contract_root=$(mktemp -d /tmp/caddy-action18c-publisher-contract.XXXXXX)
        readonly contract_root
        trap 'rm -rf -- "$contract_root"' EXIT
        : >"$contract_root/empty.err"
        write_success_fixture "$contract_root/success.out"
        validate_success "$contract_root/empty.err" \
            "$contract_root/success.out" 0
        printf '%s_mutation_started=true\n' "$prefix" \
            >"$contract_root/failure.out"
        printf '%s\n' \
            "${prefix}_rollback_started=true" \
            "${prefix}_rollback_complete=true" \
            >"$contract_root/failure.err"
        validate_failure "$contract_root/failure.err" \
            "$contract_root/failure.out" 1
        printf '%s_runner_contract_test_complete=true\n' "$prefix"
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
working_directory_approved
work_directory=$(mktemp -d /tmp/caddy-action18c-publisher-runner.XXXXXX)
readonly work_directory
cleanup() {
    # shellcheck disable=SC2317
    rm -rf -- "$work_directory"
}
trap cleanup EXIT
readonly archive_path="$work_directory/payload.tar"
readonly bundle_path="$work_directory/remote.sh"
readonly stdout_path="$work_directory/remote.stdout"
readonly stderr_path="$work_directory/remote.stderr"
: >"$stdout_path"
: >"$stderr_path"
chmod 0600 "$stdout_path" "$stderr_path"

tar --create --file "$archive_path" --directory "$script_directory" \
    publish-release-v2.sh \
    install-node-b-protocol-v2-publisher-action18c-prerequisite.sh
write_remote_bundle "$archive_path" "$bundle_path"

remote_status=0
ssh -T -o BatchMode=yes -o ConnectTimeout=5 \
    -o "HostKeyAlias=$expected_host_alias" -o StrictHostKeyChecking=yes \
    "$expected_target" 'cd / && sudo -n bash -s' \
    <"$bundle_path" >"$stdout_path" 2>"$stderr_path" || remote_status=$?
readonly remote_status

emit_stream_metadata remote_stdout "$stdout_path"
emit_stream_metadata remote_stderr "$stderr_path"
if safe_stream "$stdout_path" && safe_stream "$stderr_path"; then
    printf '%s_remote_stream_classification=bounded_safe\n' "$prefix"
    printf '%s_remote_stdout_begin\n' "$prefix"
    cat "$stdout_path"
    printf '%s_remote_stdout_end\n' "$prefix"
    if [[ -s "$stderr_path" ]]; then
        printf '%s_remote_stderr_begin\n' "$prefix" >&2
        cat "$stderr_path" >&2
        printf '%s_remote_stderr_end\n' "$prefix" >&2
    fi
else
    printf '%s_remote_stream_classification=unsafe_retained\n' "$prefix" >&2
    trap - EXIT
    printf '%s_protected_evidence=%s\n' "$prefix" "$work_directory" >&2
    exit 97
fi

contract_status=0
validate_transcript "$stderr_path" "$stdout_path" "$remote_status" ||
    contract_status=$?
if [[ "$contract_status" -ne 0 ]]; then
    printf '%s_runner_acceptance=false\n' "$prefix" >&2
    exit 97
fi
if [[ "$remote_status" -eq 0 && "$contract_status" -eq 0 ]]; then
    printf '%s_runner_acceptance=true\n' "$prefix"
else
    printf '%s_runner_acceptance=false\n' "$prefix" >&2
fi
rm -rf -- "$work_directory"
trap - EXIT
printf '%s_workstation_cleanup_complete=true\n' "$prefix"
exit "$remote_status"
