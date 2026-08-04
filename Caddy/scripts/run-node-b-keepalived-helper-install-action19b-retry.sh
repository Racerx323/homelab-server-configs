#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_19b_retry
readonly expected_target=pi@10.1.0.54
readonly expected_host_alias=pihole00.local.theama.co
readonly health_sha256=c3bc1c080cd148efc0a64440a2a411ec115d0ca83f8e6a66220d7bd201971414
readonly notification_sha256=5862b494301f972d039477d4ed93a7d56156b141cba31c41ccd61d7f843321d8
readonly inspector_sha256=162f153d116e53aba95775836c4a5cb6677ad7fd080c673ca6c5ac8fb0092a0f
readonly continuity_inspector_sha256=a9a92b4007e7b6a0798a76fd57bdd23771970e23d1e486e76b66f6408eb92c55
readonly installer_sha256=8e049e2177038c33cd7f0b8f6d6c77b02bb7117b13fa4b3a76f7022f8e3cbad9
readonly maximum_stream_bytes=1048576
readonly maximum_stream_lines=4096

script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
readonly caddy_root=${script_directory%/scripts}
readonly health_source="$script_directory/check-caddy.sh"
readonly notification_source="$script_directory/lsyncd-ha-failover-notify.sh"
readonly inspector="$script_directory/inspect-node-b-keepalived-helper-prerequisite-action19a-a.sh"
readonly continuity_inspector="$script_directory/inspect-node-b-action19b-postfailure-action19b-a-retry2.sh"
readonly installer="$script_directory/install-node-b-keepalived-helpers-action19b-retry.sh"
readonly collision_checker="$caddy_root/tests/check-shell-readonly-local-collisions-v2.sh"

file_hash() {
    sha256sum "$1" | awk '{ print $1 }'
}

line_count() {
    awk 'END { print NR }' "$1"
}

require_source() {
    local expected_hash=$1
    local source_path=$2
    local source_identity

    [[ -f "$source_path" && ! -L "$source_path" ]] || return 1
    source_identity="$(id -un):$(id -gn):755"
    [[ "$(stat -c '%U:%G:%a' "$source_path")" = "$source_identity" ]] ||
        return 1
    [[ "$(file_hash "$source_path")" = "$expected_hash" ]] || return 1
}

verify_sources() {
    require_source "$health_sha256" "$health_source" || return 1
    require_source "$notification_sha256" "$notification_source" || return 1
    require_source "$inspector_sha256" "$inspector" || return 1
    require_source "$continuity_inspector_sha256" "$continuity_inspector" ||
        return 1
    require_source "$installer_sha256" "$installer" || return 1
    [[ -x "$collision_checker" ]] || return 1
    bash -n "$health_source" "$notification_source" "$inspector" \
        "$continuity_inspector" "$installer" || return 1
    "$collision_checker" "$health_source" "$notification_source" \
        "$inspector" "$continuity_inspector" "$installer" >/dev/null ||
        return 1
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
    [[ "$(grep -Ec "^${prefix}_check_[a-zA-Z0-9_]+=false$" \
        "$output_path" || true)" -eq 0 ]] || return 1
    check_count=$(grep -Ec "^${prefix}_check_[a-zA-Z0-9_]+=true$" \
        "$output_path" || true)
    unique_count=$(sed -n \
        "s/^\(${prefix}_check_[a-zA-Z0-9_]*\)=true$/\1/p" \
        "$output_path" | LC_ALL=C sort -u | wc -l)
    [[ "$check_count" -ge 80 ]] || return 1
    [[ "$check_count" -eq "$unique_count" ]] || return 1
    if grep -Eq \
        "^${prefix}_(helpers_invoked|fragment_mutated|keepalived_mutated|vrrp_mutated|vip_mutated|service_mutations)=true$" \
        "$output_path"; then
        return 1
    fi
    for required_marker in \
        "${prefix}_preflight_complete=true" \
        "${prefix}_mutation_started=true" \
        "${prefix}_helpers_invoked=false" \
        "${prefix}_fragment_mutated=false" \
        "${prefix}_keepalived_mutated=false" \
        "${prefix}_vrrp_mutated=false" \
        "${prefix}_vip_mutated=false" \
        "${prefix}_service_mutations=false" \
        "${prefix}_persistent_mutation_scope=two_helpers,rollback_backup" \
        "${prefix}_install_complete=true"; do
        require_exact_line "$required_marker" "$output_path" || return 1
    done
    [[ "$(grep -Ec \
        "^${prefix}_backup_path=/var/backups/caddy-ha/action19b-retry-node-b-keepalived-helpers\.[A-Za-z0-9]+$" \
        "$output_path")" -eq 1 ]] || return 1
    ! grep -Eq "${prefix}_(rollback_|manual_intervention_required=true)" \
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
            'bundle_stage=$(mktemp -d /run/caddy-action19b-retry-stage.XXXXXX)' \
            'cleanup_bundle_stage() {' \
            '    rm -rf -- "$bundle_stage"' \
            '}' \
            'trap cleanup_bundle_stage EXIT' \
            'install -d -o root -g root -m 0700 "$bundle_stage/payload"' \
            'base64 -d >"$bundle_stage/payload.tar" <<'\''ACTION19B_ARCHIVE'\'''
        base64 "$bundle_archive_source"
        printf '%s\n' \
            'ACTION19B_ARCHIVE' \
            'tar --extract --file "$bundle_stage/payload.tar" \' \
            '    --directory "$bundle_stage/payload" \' \
            '    --no-same-owner --no-same-permissions' \
            'chown -R root:root "$bundle_stage/payload"' \
            'chmod 0700 "$bundle_stage/payload"' \
            'chmod 0700 "$bundle_stage/payload"/*' \
            'cd /' \
            '/bin/bash \' \
            '    "$bundle_stage/payload/install-node-b-keepalived-helpers-action19b-retry.sh" \' \
            '    --stage "$bundle_stage/payload"'
    } >"$bundle_output_path"
    chmod 0600 "$bundle_output_path"
    bash -n "$bundle_output_path"
}

write_success_fixture() {
    local fixture_path=$1
    local fixture_index

    for fixture_index in $(seq 1 80); do
        printf '%s_check_fixture_%03d=true\n' "$prefix" "$fixture_index"
    done >"$fixture_path"
    printf '%s\n' \
        "${prefix}_preflight_complete=true" \
        "${prefix}_mutation_started=true" \
        "${prefix}_helpers_invoked=false" \
        "${prefix}_fragment_mutated=false" \
        "${prefix}_keepalived_mutated=false" \
        "${prefix}_vrrp_mutated=false" \
        "${prefix}_vip_mutated=false" \
        "${prefix}_service_mutations=false" \
        "${prefix}_backup_path=/var/backups/caddy-ha/action19b-retry-node-b-keepalived-helpers.ABC123" \
        "${prefix}_persistent_mutation_scope=two_helpers,rollback_backup" \
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
        contract_root=$(mktemp -d /tmp/caddy-action19b-retry-contract.XXXXXX)
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
work_directory=$(mktemp -d /tmp/caddy-action19b-retry-runner.XXXXXX)
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
    check-caddy.sh \
    lsyncd-ha-failover-notify.sh \
    inspect-node-b-keepalived-helper-prerequisite-action19a-a.sh \
    inspect-node-b-action19b-postfailure-action19b-a-retry2.sh \
    install-node-b-keepalived-helpers-action19b-retry.sh
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
