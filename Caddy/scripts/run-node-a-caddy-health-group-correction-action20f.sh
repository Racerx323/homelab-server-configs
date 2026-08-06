#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_20f
readonly expected_target=pi@10.1.0.53
readonly expected_host_alias=pihole0.local.theama.co
readonly template_sha256=af384fc989eaf6581579ace9f09477d23c6612618fb8eca194c37db890992779
readonly installer_sha256=186dc4cc62e96bf2387e84fb4714618ebd57d31535181d17e46e1a69e76e59d0
readonly maximum_stream_bytes=2097152
readonly maximum_stream_lines=8192

script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
readonly caddy_root=${script_directory%/scripts}
readonly template=$caddy_root/templates/keepalived-caddy-ha-v2.conf.in
readonly installer=$script_directory/install-node-a-caddy-health-group-action20f.sh
readonly collision_checker=$caddy_root/tests/check-shell-readonly-local-collisions-v2.sh
readonly ssh_binary=${CADDY_ACTION20F_SSH_BINARY:-/usr/bin/ssh}

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }
line_count() { awk 'END { print NR }' "$1"; }
require_source() {
    local action20f_expected_hash=$1
    local action20f_expected_mode=$2
    local action20f_source_path=$3
    local action20f_expected_identity

    action20f_expected_identity="$(id -un):$(id -gn):$action20f_expected_mode"
    [[ -f "$action20f_source_path" && ! -L "$action20f_source_path" ]] || return 1
    [[ "$(stat -c '%U:%G:%a' "$action20f_source_path")" = "$action20f_expected_identity" ]] || return 1
    [[ "$(file_hash "$action20f_source_path")" = "$action20f_expected_hash" ]] || return 1
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
    require_source "$template_sha256" 644 "$template" || return 1
    require_source "$installer_sha256" 755 "$installer" || return 1
    [[ -x "$collision_checker" ]] || return 1
    /bin/bash -n "$installer" || return 1
    /bin/bash "$collision_checker" "$installer" "$0" >/dev/null || return 1
    /bin/bash "$installer" --self-test >/dev/null || return 1
    [[ "$(/bin/bash "$installer" --expected-checks | wc -l)" -eq 94 ]] || return 1
}
safe_stream() {
    local action20f_stream_path=$1

    [[ "$(wc -c <"$action20f_stream_path")" -le "$maximum_stream_bytes" ]] || return 1
    [[ "$(line_count "$action20f_stream_path")" -le "$maximum_stream_lines" ]] || return 1
    ! LC_ALL=C grep -n '[^[:print:][:space:]]' "$action20f_stream_path" >/dev/null || return 1
    ! grep -Eqi \
        'BEGIN [A-Z ]*PRIVATE KEY|CADDY_TLS_PRIVATE_KEY_PEM|PRIVATE_KEY=|DOPPLER_TOKEN|Authorization:[[:space:]]*Bearer' \
        "$action20f_stream_path" || return 1
}
emit_stream() {
    local action20f_stream_name=$1
    local action20f_stream_path=$2

    printf '%s_%s_bytes=%s\n' "$prefix" "$action20f_stream_name" \
        "$(wc -c <"$action20f_stream_path")"
    printf '%s_%s_lines=%s\n' "$prefix" "$action20f_stream_name" \
        "$(line_count "$action20f_stream_path")"
    printf '%s_%s_sha256=%s\n' "$prefix" "$action20f_stream_name" \
        "$(file_hash "$action20f_stream_path")"
    if [[ ! -s "$action20f_stream_path" ]]; then
        printf '%s_%s_content_secured=empty\n' "$prefix" "$action20f_stream_name"
        return 0
    fi
    printf '%s_%s_begin\n' "$prefix" "$action20f_stream_name"
    cat "$action20f_stream_path"
    printf '%s_%s_end\n' "$prefix" "$action20f_stream_name"
}
require_exact_line() {
    local action20f_expected_line=$1
    local action20f_transcript_path=$2

    [[ "$(grep -Fxc "$action20f_expected_line" "$action20f_transcript_path" || true)" -eq 1 ]]
}
validate_capture_contract() {
    local action20f_capture_label=$1
    local action20f_transcript_path=$2
    local action20f_capture_bytes

    [[ "$(grep -Ec "^${prefix}_capture_${action20f_capture_label}_bytes=[0-9]+$" "$action20f_transcript_path" || true)" -eq 1 ]] || return 1
    [[ "$(grep -Ec "^${prefix}_capture_${action20f_capture_label}_lines=[0-9]+$" "$action20f_transcript_path" || true)" -eq 1 ]] || return 1
    [[ "$(grep -Ec "^${prefix}_capture_${action20f_capture_label}_sha256=[0-9a-f]{64}$" "$action20f_transcript_path" || true)" -eq 1 ]] || return 1
    require_exact_line "${prefix}_capture_${action20f_capture_label}_classification=bounded_safe" \
        "$action20f_transcript_path" || return 1
    action20f_capture_bytes=$(sed -n \
        "s/^${prefix}_capture_${action20f_capture_label}_bytes=//p" \
        "$action20f_transcript_path")
    if [[ "$action20f_capture_bytes" -eq 0 ]]; then
        require_exact_line "${prefix}_capture_${action20f_capture_label}_content_secured=empty" \
            "$action20f_transcript_path" || return 1
    else
        require_exact_line "${prefix}_capture_${action20f_capture_label}_begin" \
            "$action20f_transcript_path" || return 1
        require_exact_line "${prefix}_capture_${action20f_capture_label}_end" \
            "$action20f_transcript_path" || return 1
    fi
}
validate_success() {
    local action20f_error_path=$1
    local action20f_output_path=$2
    local action20f_observed_status=$3
    local action20f_contract_root
    local action20f_expected_path
    local action20f_observed_path
    local action20f_marker
    local action20f_capture

    [[ "$action20f_observed_status" -eq 0 ]] || return 1
    [[ ! -s "$action20f_error_path" ]] || return 1
    action20f_contract_root=$(mktemp -d /tmp/caddy-action20f-contract.XXXXXX) || return 97
    action20f_expected_path=$action20f_contract_root/expected
    action20f_observed_path=$action20f_contract_root/observed
    /bin/bash "$installer" --expected-checks | sed "s/^/${prefix}_check_/" | LC_ALL=C sort \
        >"$action20f_expected_path" || return 97
    sed -n "s/^\(${prefix}_check_[a-z0-9_]*\)=true$/\1/p" \
        "$action20f_output_path" | LC_ALL=C sort >"$action20f_observed_path"
    [[ "$(wc -l <"$action20f_expected_path")" -eq 94 ]] || return 97
    [[ "$(wc -l <"$action20f_observed_path")" -eq 94 ]] || return 1
    [[ "$(LC_ALL=C sort -u "$action20f_observed_path" | wc -l)" -eq 94 ]] || return 1
    cmp -s "$action20f_expected_path" "$action20f_observed_path" || return 1
    rm -rf -- "$action20f_contract_root"
    ! grep -Eq "^${prefix}_check_[a-z0-9_]+=false$" "$action20f_output_path" || return 1
    for action20f_capture in \
        candidate_context_caddy_validate_stdout candidate_context_caddy_validate_stderr \
        candidate_context_curl_stdout candidate_context_curl_stderr \
        candidate_context_full_helper_stdout candidate_context_full_helper_stderr \
        installed_context_caddy_validate_stdout installed_context_caddy_validate_stderr \
        installed_context_curl_stdout installed_context_curl_stderr \
        installed_context_full_helper_stdout installed_context_full_helper_stderr; do
        validate_capture_contract "$action20f_capture" "$action20f_output_path" || return 97
    done
    for action20f_marker in \
        "${prefix}_preflight_complete=true" \
        "${prefix}_mutation_started=true" \
        "${prefix}_fragment_installed=true" \
        "${prefix}_main_configuration_mutated=false" \
        "${prefix}_keepalived_reloaded=false" \
        "${prefix}_keepalived_restarted=false" \
        "${prefix}_health_context_validated=true" \
        "${prefix}_service_mutations=false" \
        "${prefix}_vrrp_transition_requested=false" \
        "${prefix}_vip_mutations=false" \
        "${prefix}_node_b_contacted=false" \
        "${prefix}_persistent_mutation_scope=fragment,rollback_backup" \
        "${prefix}_install_complete=true"; do
        require_exact_line "$action20f_marker" "$action20f_output_path" || return 1
    done
    [[ "$(grep -Ec "^${prefix}_backup_path=/var/backups/caddy-ha/action20f-node-a-health-group\.[A-Za-z0-9]+$" "$action20f_output_path" || true)" -eq 1 ]] || return 1
    ! grep -Eq "${prefix}_(rollback_|manual_intervention_required=true)" \
        "$action20f_output_path" "$action20f_error_path" || return 1
}
validate_failure() {
    local action20f_error_path=$1
    local action20f_output_path=$2
    local action20f_observed_status=$3

    [[ "$action20f_observed_status" -ne 0 ]] || return 1
    ! grep -Fq "${prefix}_manual_intervention_required=true" \
        "$action20f_output_path" "$action20f_error_path" || return 97
    ! grep -Fq "${prefix}_rollback_complete=false" \
        "$action20f_output_path" "$action20f_error_path" || return 97
    if grep -Fq "${prefix}_mutation_started=true" "$action20f_output_path"; then
        require_exact_line "${prefix}_rollback_started=true" "$action20f_error_path" || return 97
        require_exact_line "${prefix}_rollback_complete=true" "$action20f_error_path" || return 97
    fi
}
write_remote_bundle() {
    local action20f_archive_source=$1
    local action20f_remote_bundle_path=$2

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
            'bundle_stage=$(mktemp -d /run/caddy-action20f-stage.XXXXXX)' \
            'cleanup_bundle_stage() { rm -rf -- "$bundle_stage"; }' \
            'trap cleanup_bundle_stage EXIT' \
            'install -d -o root -g root -m 0700 "$bundle_stage/payload"' \
            'base64 -d >"$bundle_stage/payload.tar" <<'\''ACTION20F_ARCHIVE'\'''
        base64 "$action20f_archive_source"
        printf '%s\n' \
            'ACTION20F_ARCHIVE' \
            'tar --extract --file "$bundle_stage/payload.tar" --directory "$bundle_stage/payload" --no-same-owner --no-same-permissions' \
            'chown -R root:root "$bundle_stage/payload"' \
            'chmod 0700 "$bundle_stage/payload"' \
            'chmod 0700 "$bundle_stage/payload/install-node-a-caddy-health-group-action20f.sh"' \
            'chmod 0600 "$bundle_stage/payload/keepalived-caddy-ha-v2.conf.in"' \
            'cd /' \
            '/bin/bash "$bundle_stage/payload/install-node-a-caddy-health-group-action20f.sh" --stage "$bundle_stage/payload"'
    } >"$action20f_remote_bundle_path"
    chmod 0600 "$action20f_remote_bundle_path"
    /bin/bash -n "$action20f_remote_bundle_path"
}
write_success_fixture() {
    local action20f_fixture_path=$1

    /bin/bash "$installer" --success-fixture >"$action20f_fixture_path"
}

case "${1:-}" in
    --self-test | --source-test)
        [[ $# -eq 1 ]] || exit 64
        verify_sources
        action20f_test_kind=${1#--}
        action20f_test_kind=${action20f_test_kind//-/_}
        printf '%s_runner_%s_complete=true\n' "$prefix" "$action20f_test_kind"
        exit 0
        ;;
    --contract-test)
        [[ $# -eq 1 ]] || exit 64
        verify_sources
        action20f_contract_test_root=$(mktemp -d /tmp/caddy-action20f-runner-contract.XXXXXX)
        readonly action20f_contract_test_root
        trap 'rm -rf -- "$action20f_contract_test_root"' EXIT
        : >"$action20f_contract_test_root/empty.err"
        write_success_fixture "$action20f_contract_test_root/success.out"
        validate_success "$action20f_contract_test_root/empty.err" \
            "$action20f_contract_test_root/success.out" 0
        printf '%s_mutation_started=true\n' "$prefix" >"$action20f_contract_test_root/failure.out"
        printf '%s\n' "${prefix}_rollback_started=true" \
            "${prefix}_rollback_complete=true" >"$action20f_contract_test_root/failure.err"
        validate_failure "$action20f_contract_test_root/failure.err" \
            "$action20f_contract_test_root/failure.out" 1
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
work_directory=$(mktemp -d /tmp/caddy-action20f-runner.XXXXXX)
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
    install-node-a-caddy-health-group-action20f.sh \
    --directory "$caddy_root/templates" keepalived-caddy-ha-v2.conf.in
write_remote_bundle "$archive_path" "$remote_script"
remote_status=0
"$ssh_binary" -T \
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
