#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_20c
readonly expected_target=pi@10.1.0.53
readonly expected_host_alias=pihole0.local.theama.co
readonly candidate_sha256=9bf531ab7cbb047f8f09ce5956b597d5c8b6ede397c166f0b040e2e92fe8bbab
readonly baseline_sha256=bc1f5fc7dc9de385ba00e8f9868df6857306cc4268de6a899a73ccc7098c1ceb
readonly installer_sha256=de17f05035c79e679166c8d20ae510cc9b570cc61d65d7fffe1bdb7a65ce56a1
readonly maximum_stream_bytes=1048576
readonly maximum_stream_lines=4096

script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
readonly caddy_root=${script_directory%/scripts}
readonly candidate="$script_directory/check-caddy-action20b.sh"
readonly baseline="$script_directory/inspect-dual-node-caddy-postfailure-continuity-action20a-b.sh"
readonly installer="$script_directory/install-node-a-caddy-health-context-action20c.sh"
readonly collision_checker="$caddy_root/tests/check-shell-readonly-local-collisions-v2.sh"

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }
line_count() { awk 'END { print NR }' "$1"; }
require_source() {
    local expected_hash=$1
    local source_path=$2
    local source_identity

    source_identity="$(id -un):$(id -gn):755"
    [[ -f "$source_path" && ! -L "$source_path" && -x "$source_path" ]] || return 1
    [[ "$(stat -c '%U:%G:%a' "$source_path")" = "$source_identity" ]] || return 1
    [[ "$(file_hash "$source_path")" = "$expected_hash" ]] || return 1
}
working_directory_approved() {
    case "$PWD" in
        /home/aaron/code/homelab-server-configs) return 0 ;;
        /workspace/homelab-server-configs)
            [[ "${CADDY_VALIDATION_CONTAINER:-}" = 1 ]]
            ;;
        *) return 1 ;;
    esac
}
verify_sources() {
    require_source "$candidate_sha256" "$candidate" || return 1
    require_source "$baseline_sha256" "$baseline" || return 1
    require_source "$installer_sha256" "$installer" || return 1
    [[ -x "$collision_checker" ]] || return 1
    /bin/bash -n "$candidate" "$baseline" "$installer" || return 1
    /bin/bash "$collision_checker" "$candidate" "$baseline" "$installer" \
        >/dev/null || return 1
    /bin/bash "$installer" --self-test >/dev/null || return 1
    [[ "$(/bin/bash "$installer" --expected-check-count)" -eq 77 ]] || return 1
}
safe_stream() {
    local inspected_stream=$1

    [[ "$(wc -c <"$inspected_stream")" -le "$maximum_stream_bytes" ]] || return 1
    [[ "$(line_count "$inspected_stream")" -le "$maximum_stream_lines" ]] || return 1
    ! LC_ALL=C grep -n '[^[:print:][:space:]]' "$inspected_stream" >/dev/null || return 1
    ! grep -Eqi \
        'BEGIN [A-Z ]*PRIVATE KEY|CADDY_TLS_PRIVATE_KEY_PEM|PRIVATE_KEY=|DOPPLER_TOKEN|Authorization:[[:space:]]*Bearer' \
        "$inspected_stream"
}
emit_stream() {
    local stream_name=$1
    local stream_path=$2

    printf '%s_%s_bytes=%s\n' "$prefix" "$stream_name" "$(wc -c <"$stream_path")"
    printf '%s_%s_lines=%s\n' "$prefix" "$stream_name" "$(line_count "$stream_path")"
    printf '%s_%s_sha256=%s\n' "$prefix" "$stream_name" "$(file_hash "$stream_path")"
    if [[ ! -s "$stream_path" ]]; then
        printf '%s_%s_content_secured=empty\n' "$prefix" "$stream_name"
        return 0
    fi
    printf '%s_%s_begin\n' "$prefix" "$stream_name"
    cat "$stream_path"
    printf '%s_%s_end\n' "$prefix" "$stream_name"
}
require_exact_line() {
    local expected_line=$1
    local transcript_path=$2

    [[ "$(grep -Fxc "$expected_line" "$transcript_path")" -eq 1 ]]
}
validate_success() {
    local error_path=$1
    local output_path=$2
    local observed_status=$3
    local expected_count
    local observed_count
    local unique_count
    local required_marker

    [[ "$observed_status" -eq 0 ]] || return 1
    [[ ! -s "$error_path" ]] || return 1
    expected_count=$(/bin/bash "$installer" --expected-check-count) || return 1
    observed_count=$(grep -Ec "^${prefix}_check_[a-zA-Z0-9_]+=true$" \
        "$output_path" || true)
    unique_count=$(sed -n \
        "s/^\(${prefix}_check_[a-zA-Z0-9_]*\)=true$/\1/p" \
        "$output_path" | LC_ALL=C sort -u | wc -l)
    [[ "$observed_count" -eq "$expected_count" ]] || return 1
    [[ "$unique_count" -eq "$expected_count" ]] || return 1
    diff -u \
        <(/bin/bash "$installer" --expected-checks |
            sed "s/^/${prefix}_check_/" | LC_ALL=C sort) \
        <(sed -n \
            "s/^\(${prefix}_check_[a-zA-Z0-9_]*\)=true$/\1/p" \
            "$output_path" | LC_ALL=C sort) >/dev/null || return 1
    [[ "$(grep -Ec "^${prefix}_check_[a-zA-Z0-9_]+=false$" \
        "$output_path" || true)" -eq 0 ]] || return 1
    for required_marker in \
        "${prefix}_preflight_complete=true" \
        "${prefix}_mutation_started=true" \
        "${prefix}_helper_invoked_for_validation=true" \
        "${prefix}_fragment_mutated=false" \
        "${prefix}_keepalived_mutated=false" \
        "${prefix}_service_mutations=false" \
        "${prefix}_vrrp_mutated=false" \
        "${prefix}_vip_mutated=false" \
        "${prefix}_persistent_mutation_scope=health_helper,rollback_backup" \
        "${prefix}_install_complete=true"; do
        require_exact_line "$required_marker" "$output_path" || return 1
    done
    [[ "$(grep -Ec \
        "^${prefix}_backup_path=/var/backups/caddy-ha/action20c-node-a-health-context\.[A-Za-z0-9]+$" \
        "$output_path")" -eq 1 ]] || return 1
    ! grep -Eq "${prefix}_(rollback_|manual_intervention_required=true)" \
        "$output_path" "$error_path"
}
validate_failure() {
    local error_path=$1
    local output_path=$2
    local observed_status=$3

    [[ "$observed_status" -ne 0 ]] || return 1
    ! grep -Fq "${prefix}_manual_intervention_required=true" \
        "$output_path" "$error_path" || return 97
    ! grep -Fq "${prefix}_rollback_complete=false" \
        "$output_path" "$error_path" || return 97
    if grep -Fq "${prefix}_mutation_started=true" "$output_path"; then
        require_exact_line "${prefix}_rollback_started=true" "$error_path" || return 97
        require_exact_line "${prefix}_rollback_complete=true" "$error_path" || return 97
    fi
}
write_remote_bundle() {
    local archive_source=$1
    local remote_bundle_path=$2

    # Remote variables expand only on Node A.
    # shellcheck disable=SC2016
    {
        printf '%s\n' \
            '#!/usr/bin/env bash' \
            'set -Eeuo pipefail' \
            'set +x' \
            'umask 077' \
            'PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin' \
            'export PATH' \
            'cd /' \
            'bundle_stage=$(mktemp -d /run/caddy-action20c-stage.XXXXXX)' \
            'cleanup_bundle_stage() { rm -rf -- "$bundle_stage"; }' \
            'trap cleanup_bundle_stage EXIT' \
            'install -d -o root -g root -m 0700 "$bundle_stage/payload"' \
            'base64 -d >"$bundle_stage/payload.tar" <<'\''ACTION20C_ARCHIVE'\'''
        base64 "$archive_source"
        printf '%s\n' \
            'ACTION20C_ARCHIVE' \
            'tar --extract --file "$bundle_stage/payload.tar" --directory "$bundle_stage/payload" --no-same-owner --no-same-permissions' \
            'chown -R root:root "$bundle_stage/payload"' \
            'chmod 0700 "$bundle_stage/payload" "$bundle_stage/payload"/*' \
            'cd /' \
            '/bin/bash "$bundle_stage/payload/install-node-a-caddy-health-context-action20c.sh" --stage "$bundle_stage/payload"'
    } >"$remote_bundle_path"
    chmod 0600 "$remote_bundle_path"
    /bin/bash -n "$remote_bundle_path"
}
write_success_fixture() {
    local fixture_path=$1
    local fixture_label

    while IFS= read -r fixture_label; do
        printf '%s_check_%s=true\n' "$prefix" "$fixture_label"
    done < <(/bin/bash "$installer" --expected-checks) >"$fixture_path"
    printf '%s\n' \
        "${prefix}_preflight_complete=true" \
        "${prefix}_mutation_started=true" \
        "${prefix}_helper_invoked_for_validation=true" \
        "${prefix}_fragment_mutated=false" \
        "${prefix}_keepalived_mutated=false" \
        "${prefix}_service_mutations=false" \
        "${prefix}_vrrp_mutated=false" \
        "${prefix}_vip_mutated=false" \
        "${prefix}_backup_path=/var/backups/caddy-ha/action20c-node-a-health-context.ABC123" \
        "${prefix}_persistent_mutation_scope=health_helper,rollback_backup" \
        "${prefix}_install_complete=true" >>"$fixture_path"
}

case "${1:-}" in
    --self-test | --source-test)
        [[ $# -eq 1 ]] || exit 64
        verify_sources
        printf '%s_runner_%s_complete=true\n' "$prefix" "${1#--}"
        exit 0
        ;;
    --contract-test)
        [[ $# -eq 1 ]] || exit 64
        verify_sources
        contract_root=$(mktemp -d /tmp/caddy-action20c-contract.XXXXXX)
        readonly contract_root
        trap 'rm -rf -- "$contract_root"' EXIT
        : >"$contract_root/empty.err"
        write_success_fixture "$contract_root/success.out"
        validate_success "$contract_root/empty.err" "$contract_root/success.out" 0
        printf '%s_mutation_started=true\n' "$prefix" >"$contract_root/failure.out"
        printf '%s\n' "${prefix}_rollback_started=true" \
            "${prefix}_rollback_complete=true" >"$contract_root/failure.err"
        validate_failure "$contract_root/failure.err" "$contract_root/failure.out" 1
        printf '%s_runner_contract_test_complete=true\n' "$prefix"
        exit 0
        ;;
    "") [[ $# -eq 0 ]] || exit 64 ;;
    *)
        printf 'Usage: %s [--self-test|--source-test|--contract-test]\n' \
            "${0##*/}" >&2
        exit 64
        ;;
esac

verify_sources
working_directory_approved
work_directory=$(mktemp -d /tmp/caddy-action20c-runner.XXXXXX)
readonly work_directory
cleanup() {
    # shellcheck disable=SC2317
    rm -rf -- "$work_directory"
}
trap cleanup EXIT
readonly archive_path=$work_directory/payload.tar
readonly remote_script=$work_directory/remote.sh
readonly stdout_path=$work_directory/remote.stdout
readonly stderr_path=$work_directory/remote.stderr
: >"$stdout_path"
: >"$stderr_path"
chmod 0600 "$stdout_path" "$stderr_path"

tar --create --file "$archive_path" --directory "$script_directory" \
    check-caddy-action20b.sh \
    inspect-dual-node-caddy-postfailure-continuity-action20a-b.sh \
    install-node-a-caddy-health-context-action20c.sh
write_remote_bundle "$archive_path" "$remote_script"
remote_status=0
ssh -T \
    -o BatchMode=yes \
    -o ConnectTimeout=5 \
    -o ConnectionAttempts=1 \
    -o StrictHostKeyChecking=yes \
    -o IdentitiesOnly=no \
    -o HostKeyAlias="$expected_host_alias" \
    "$expected_target" 'sudo -n /bin/bash -s' \
    <"$remote_script" >"$stdout_path" 2>"$stderr_path" || remote_status=$?
readonly remote_status
if ! safe_stream "$stdout_path" || ! safe_stream "$stderr_path"; then
    printf '%s_stream_classification=unsafe_retained\n' "$prefix" >&2
    trap - EXIT
    printf '%s_protected_evidence=%s\n' "$prefix" "$work_directory" >&2
    exit 97
fi
printf '%s_stream_classification=bounded_safe\n' "$prefix"
emit_stream remote_stdout "$stdout_path"
emit_stream remote_stderr "$stderr_path"
if [[ "$remote_status" -eq 0 ]]; then
    validate_success "$stderr_path" "$stdout_path" "$remote_status"
else
    validate_failure "$stderr_path" "$stdout_path" "$remote_status"
fi
printf '%s_remote_status=%s\n' "$prefix" "$remote_status"
rm -rf -- "$work_directory"
trap - EXIT
printf '%s_runner_cleanup_complete=true\n' "$prefix"
exit "$remote_status"
