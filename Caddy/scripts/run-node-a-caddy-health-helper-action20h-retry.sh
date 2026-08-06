#!/usr/bin/env bash
# shellcheck disable=SC2317

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_20h
readonly expected_target=pi@10.1.0.53
readonly expected_host_alias=pihole0.local.theama.co
readonly candidate_sha256=5cb42ba05b36fecd0c0cf5bc649741661b847e8f8dce94a19288d21874d87fb3
readonly installer_sha256=33a834270f8c468e24a573b7ab42cb106d2d25f2624ef783031964771c93874f
readonly stager_sha256=41ef10df5c02a058742b2e4c2d5183cd1c35c74ec63d103d1b5ff0ed8ba52e71
readonly maximum_stream_bytes=4194304
readonly maximum_stream_lines=16384

script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
readonly candidate=$script_directory/check-caddy-vrrp-action20h.sh
readonly installer=$script_directory/install-node-a-caddy-health-helper-action20h-retry.sh
readonly stager=$script_directory/stage-node-a-caddy-health-helper-action20h.sh
readonly ssh_binary=${CADDY_ACTION20H_SSH_BINARY:-/usr/bin/ssh}

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
verify_source() {
    local action20h_expected_hash=$1
    local action20h_source_path=$2

    [[ -f "$action20h_source_path" && ! -L "$action20h_source_path" ]] || return 1
    [[ "$(stat -c '%a' "$action20h_source_path")" = 755 ]] || return 1
    [[ "$(file_hash "$action20h_source_path")" = "$action20h_expected_hash" ]] || return 1
}
safe_stream() {
    local action20h_stream_path=$1

    [[ "$(wc -c <"$action20h_stream_path")" -le "$maximum_stream_bytes" ]] || return 1
    [[ "$(line_count "$action20h_stream_path")" -le "$maximum_stream_lines" ]] || return 1
    ! LC_ALL=C grep -n '[^[:print:][:space:]]' "$action20h_stream_path" >/dev/null || return 1
    ! grep -Eqi \
        'BEGIN [A-Z ]*PRIVATE KEY|CADDY_TLS_PRIVATE_KEY_PEM|PRIVATE_KEY=|DOPPLER_TOKEN|Authorization:[[:space:]]*Bearer' \
        "$action20h_stream_path"
}
emit_stream() {
    local action20h_stream_label=$1
    local action20h_stream_path=$2

    printf '%s_%s_bytes=%s\n' "$prefix" "$action20h_stream_label" \
        "$(wc -c <"$action20h_stream_path")"
    printf '%s_%s_lines=%s\n' "$prefix" "$action20h_stream_label" \
        "$(line_count "$action20h_stream_path")"
    printf '%s_%s_sha256=%s\n' "$prefix" "$action20h_stream_label" \
        "$(file_hash "$action20h_stream_path")"
    if ! safe_stream "$action20h_stream_path"; then
        printf '%s_%s_classification=unsafe_retained\n' "$prefix" "$action20h_stream_label" >&2
        return 97
    fi
    printf '%s_%s_classification=bounded_safe\n' "$prefix" "$action20h_stream_label"
    if [[ -s "$action20h_stream_path" ]]; then
        printf '%s_%s_begin\n' "$prefix" "$action20h_stream_label"
        cat "$action20h_stream_path"
        printf '%s_%s_end\n' "$prefix" "$action20h_stream_label"
    else
        printf '%s_%s_content_secured=empty\n' "$prefix" "$action20h_stream_label"
    fi
}
verify_sources() {
    verify_source "$candidate_sha256" "$candidate" || return 1
    verify_source "$installer_sha256" "$installer" || return 1
    verify_source "$stager_sha256" "$stager" || return 1
    /bin/bash -n "$candidate" "$installer" || return 1
    /bin/bash "$candidate" --self-test >/dev/null || return 1
    /bin/bash "$installer" --self-test >/dev/null || return 1
}
validate_success() {
    local action20h_output_path=$1
    local action20h_error_path=$2
    local action20h_remote_status=$3
    local action20h_expected_count
    local action20h_observed_count
    local action20h_unique_count
    local action20h_false_count
    local action20h_backup_count
    local action20h_required_marker

    # conditional-validator-explicit-failures-begin
    [[ "$action20h_remote_status" -eq 0 ]] || return 1
    [[ ! -s "$action20h_error_path" ]] || return 1
    action20h_expected_count=$(/bin/bash "$installer" --expected-checks | wc -l) || return 1
    action20h_observed_count=$(grep -Ec "^${prefix}_check_[a-zA-Z0-9_]+=true$" \
        "$action20h_output_path" || true)
    action20h_unique_count=$(sed -n \
        "s/^\(${prefix}_check_[a-zA-Z0-9_]*\)=true$/\1/p" \
        "$action20h_output_path" | LC_ALL=C sort -u | wc -l) || return 1
    [[ "$action20h_observed_count" -eq "$action20h_expected_count" ]] || return 1
    [[ "$action20h_unique_count" -eq "$action20h_expected_count" ]] || return 1
    diff -u \
        <(/bin/bash "$installer" --expected-checks | sed "s/^/${prefix}_check_/" | LC_ALL=C sort) \
        <(sed -n "s/^\(${prefix}_check_[a-zA-Z0-9_]*\)=true$/\1/p" \
            "$action20h_output_path" | LC_ALL=C sort) >/dev/null || return 1
    action20h_false_count=$(grep -Ec "^${prefix}_check_[a-zA-Z0-9_]+=false$" \
        "$action20h_output_path" || true)
    [[ "$action20h_false_count" -eq 0 ]] || return 1
    for action20h_required_marker in \
        "${prefix}_preflight_complete=true" \
        "${prefix}_mutation_started=true" \
        "${prefix}_helper_invoked_by_transaction=false" \
        "${prefix}_keepalived_reloaded=false" \
        "${prefix}_service_mutations=false" \
        "${prefix}_vrrp_mutations=false" \
        "${prefix}_vip_mutations=false" \
        "${prefix}_persistent_mutation_scope=health_helper,rollback_backup" \
        "${prefix}_install_complete=true"; do
        [[ "$(grep -Fxc "$action20h_required_marker" "$action20h_output_path")" -eq 1 ]] || return 1
    done
    action20h_backup_count=$(grep -Ec \
        "^${prefix}_backup_path=/var/backups/caddy-ha/action20h-node-a-health-helper\.[A-Za-z0-9]+$" \
        "$action20h_output_path" || true)
    [[ "$action20h_backup_count" -eq 1 ]] || return 1
    ! grep -Eq "${prefix}_(rollback_|manual_intervention_required=true)" \
        "$action20h_output_path" "$action20h_error_path" || return 1
    # conditional-validator-explicit-failures-end
    return 0
}
validate_failure() {
    local action20h_output_path=$1
    local action20h_error_path=$2
    local action20h_remote_status=$3

    # conditional-validator-explicit-failures-begin
    [[ "$action20h_remote_status" -ne 0 ]] || return 1
    ! grep -Fq "${prefix}_manual_intervention_required=true" \
        "$action20h_output_path" "$action20h_error_path" || return 97
    ! grep -Fq "${prefix}_rollback_complete=false" \
        "$action20h_output_path" "$action20h_error_path" || return 97
    if grep -Fq "${prefix}_mutation_started=true" "$action20h_output_path"; then
        [[ "$(grep -Fxc "${prefix}_rollback_started=true" "$action20h_error_path")" -eq 1 ]] || return 97
        [[ "$(grep -Fxc "${prefix}_rollback_complete=true" "$action20h_error_path")" -eq 1 ]] || return 97
    fi
    # conditional-validator-explicit-failures-end
    return 0
}
write_remote_bundle() {
    local action20h_archive_path=$1
    local action20h_remote_path=$2

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
            'payload_stage=$(mktemp -d /run/caddy-action20h-payload.XXXXXX)' \
            'candidate_stage=' \
            'cleanup_payload_stage() { rm -rf -- "$payload_stage"; [[ -z "$candidate_stage" ]] || rm -rf -- "$candidate_stage"; }' \
            'trap cleanup_payload_stage EXIT' \
            'candidate_stage=$(mktemp -d /run/caddy-action20h-candidate.XXXXXX)' \
            'install -d -o root -g root -m 0700 "$payload_stage/payload"' \
            'base64 -d >"$payload_stage/payload.tar" <<'\''ACTION20H_ARCHIVE'\'''
        base64 "$action20h_archive_path"
        printf '%s\n' \
            'ACTION20H_ARCHIVE' \
            'tar --extract --file "$payload_stage/payload.tar" --directory "$payload_stage/payload" --no-same-owner --no-same-permissions' \
            'chown -R root:root "$payload_stage/payload"' \
            'chmod 0700 "$payload_stage/payload" "$payload_stage/payload"/*' \
            '/bin/bash "$payload_stage/payload/stage-node-a-caddy-health-helper-action20h.sh" --adopt "$payload_stage/payload/check-caddy-vrrp-action20h.sh" "$candidate_stage" root caddy-tls /run root root' \
            'cd /' \
            '/bin/bash "$payload_stage/payload/install-node-a-caddy-health-helper-action20h-retry.sh" --stage "$candidate_stage"'
    } >"$action20h_remote_path"
    chmod 0600 "$action20h_remote_path"
    /bin/bash -n "$action20h_remote_path"
}

case "${1:-}" in
    --self-test | --source-test)
        [[ $# -eq 1 ]] || exit 64
        verify_sources
        working_directory_approved
        printf '%s_runner_%s_complete=true\n' "$prefix" "${1#--}"
        exit 0
        ;;
    --contract-test)
        [[ $# -eq 1 ]] || exit 64
        verify_sources
        working_directory_approved
        printf '%s_runner_contract_test_complete=true\n' "$prefix"
        exit 0
        ;;
    "") [[ $# -eq 0 ]] || exit 64 ;;
    *)
        printf 'Usage: %s [--self-test|--source-test|--contract-test]\n' "${0##*/}" >&2
        exit 64
        ;;
esac

verify_sources
working_directory_approved
work_directory=$(mktemp -d /tmp/caddy-action20h-runner.XXXXXX)
readonly work_directory
cleanup() { rm -rf -- "$work_directory"; }
trap cleanup EXIT INT TERM
readonly archive_path=$work_directory/payload.tar
readonly remote_path=$work_directory/remote.sh
readonly stdout_path=$work_directory/remote.stdout
readonly stderr_path=$work_directory/remote.stderr
: >"$stdout_path"
: >"$stderr_path"
chmod 0600 "$stdout_path" "$stderr_path"
tar --create --file "$archive_path" --directory "$script_directory" \
    stage-node-a-caddy-health-helper-action20h.sh \
    check-caddy-vrrp-action20h.sh \
    install-node-a-caddy-health-helper-action20h-retry.sh
write_remote_bundle "$archive_path" "$remote_path"
remote_status=0
"$ssh_binary" -T -o BatchMode=yes -o ConnectTimeout=5 -o ConnectionAttempts=1 \
    -o StrictHostKeyChecking=yes -o IdentitiesOnly=no \
    -o HostKeyAlias="$expected_host_alias" "$expected_target" \
    'cd / && sudo -n /bin/bash -s --' <"$remote_path" \
    >"$stdout_path" 2>"$stderr_path" || remote_status=$?
readonly remote_status
emit_stream remote_stdout "$stdout_path" || {
    trap - EXIT
    printf '%s_protected_evidence=%s\n' "$prefix" "$work_directory" >&2
    exit 97
}
emit_stream remote_stderr "$stderr_path" || {
    trap - EXIT
    printf '%s_protected_evidence=%s\n' "$prefix" "$work_directory" >&2
    exit 97
}
if [[ "$remote_status" -eq 0 ]]; then
    validate_success "$stdout_path" "$stderr_path" "$remote_status"
else
    validate_failure "$stdout_path" "$stderr_path" "$remote_status"
fi
printf '%s_remote_status=%s\n' "$prefix" "$remote_status"
printf '%s_node_a_contacted=true\n' "$prefix"
printf '%s_node_b_contacted=false\n' "$prefix"
printf '%s_runner_cleanup_complete=true\n' "$prefix"
exit "$remote_status"
