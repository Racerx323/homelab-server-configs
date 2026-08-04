#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_19a
readonly expected_target=pi@10.1.0.54
readonly expected_host_alias=pihole00.local.theama.co
readonly expected_fragment_sha256=294d5ba44d903ba4ab3ab4330ae3ae05e0160e2b134d71e91a787b65dd96dc4d
readonly renderer_sha256=d7fa1c57a4d74edd966b78cf66d79e534f49c09a7265c2ad326f00018fa4c1c2
readonly template_sha256=ebc60650edd4cb384000604b402ce1e99153b50d505c7e13289b6b33d7abdd09
readonly manifest_sha256=ee58ae3d2af19c6b5fd45b8c87d9c4866450d1a2d737c277c26442db36ebcfd0
readonly installer_sha256=142eac9d91eb30c3ce2103cc98ef1d9dddd288fedb632398c589bade6c252db6
readonly maximum_stream_bytes=1048576
readonly maximum_stream_lines=4096

script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
readonly caddy_root=${script_directory%/scripts}
readonly renderer="$script_directory/render-node-config.sh"
readonly template="$caddy_root/templates/keepalived-caddy-ha.conf.in"
readonly manifest="$caddy_root/manifests/deployment.yaml"
readonly installer="$script_directory/install-node-b-keepalived-fragment-action19a.sh"
readonly collision_checker="$caddy_root/tests/check-shell-readonly-local-collisions-v2.sh"
readonly ssh_binary=${CADDY_ACTION19A_SSH_BINARY:-ssh}

file_hash() {
    sha256sum "$1" | awk '{ print $1 }'
}

line_count() {
    awk 'END { print NR }' "$1"
}

require_local_check() {
    local check_label=$1

    shift
    if "$@"; then
        printf '%s_local_check_%s=true\n' "$prefix" "$check_label"
        return 0
    fi
    printf '%s_local_check_%s=false\n' "$prefix" "$check_label" >&2
    return 1
}

validate_source() {
    local source_label=$1
    local expected_hash=$2
    local expected_mode=$3
    local source_path=$4
    local source_identity

    require_local_check "${source_label}_regular" test -f "$source_path" ||
        return 1
    require_local_check "${source_label}_not_symlink" test ! -L "$source_path" ||
        return 1
    source_identity="$(id -un):$(id -gn):$expected_mode"
    require_local_check "${source_label}_metadata" \
        test "$(stat -c '%U:%G:%a' "$source_path")" = "$source_identity" ||
        return 1
    require_local_check "${source_label}_hash_exact" \
        test "$(file_hash "$source_path")" = "$expected_hash" || return 1
}

verify_sources() {
    validate_source renderer "$renderer_sha256" 755 "$renderer" || return 1
    validate_source template "$template_sha256" 644 "$template" || return 1
    validate_source manifest "$manifest_sha256" 644 "$manifest" || return 1
    validate_source installer "$installer_sha256" 755 "$installer" || return 1
    require_local_check collision_checker_executable \
        test -x "$collision_checker" || return 1
    require_local_check sources_syntax bash -n "$renderer" "$installer" ||
        return 1
    require_local_check collision_policy \
        "$collision_checker" "$renderer" "$installer" >/dev/null || return 1
    require_local_check installer_self_test \
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

require_exact_line() {
    local expected_line=$1
    local transcript_path=$2

    [[ "$(grep -Fxc "$expected_line" "$transcript_path")" -eq 1 ]]
}

validate_success() {
    local output_path=$1
    local observed_remote_status=$2
    local check_count
    local unique_count
    local required_marker

    [[ "$observed_remote_status" -eq 0 ]] || return 1
    [[ "$(grep -Ec "^${prefix}_check_[a-z0-9_]+=false$" \
        "$output_path" || true)" -eq 0 ]] || return 1
    check_count=$(grep -Ec "^${prefix}_check_[a-z0-9_]+=true$" \
        "$output_path" || true) || return 1
    unique_count=$(sed -n \
        "s/^\\(${prefix}_check_[a-z0-9_]*\\)=true$/\\1/p" \
        "$output_path" | LC_ALL=C sort -u | wc -l) || return 1
    [[ "$check_count" -ge 90 ]] || return 1
    [[ "$check_count" -eq "$unique_count" ]] || return 1
    for required_marker in \
        "${prefix}_preflight_complete=true" \
        "${prefix}_mutation_started=true" \
        "${prefix}_fragment_installed=true" \
        "${prefix}_main_configuration_mutated=false" \
        "${prefix}_keepalived_reloaded=false" \
        "${prefix}_keepalived_restarted=false" \
        "${prefix}_vrrp_transition_requested=false" \
        "${prefix}_vip_mutations=false" \
        "${prefix}_service_mutations=false" \
        "${prefix}_persistent_mutation_scope=fragment,rollback_backup" \
        "${prefix}_install_complete=true"; do
        require_exact_line "$required_marker" "$output_path" || return 1
    done
    [[ "$(grep -Ec \
        "^${prefix}_backup_path=/var/backups/caddy-ha/action19a-node-b-keepalived-fragment\\.[A-Za-z0-9]+$" \
        "$output_path")" -eq 1 ]] || return 1
    ! grep -Eq "^${prefix}_(rollback_|manual_intervention_required=true)" \
        "$output_path"
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
        validate_success "$output_path" "$observed_remote_status"
        return
    fi
    validate_failure "$error_path" "$output_path" "$observed_remote_status"
}

render_fragment() {
    local output_directory=$1

    "$renderer" --node node-b --output "$output_directory" >/dev/null ||
        return 1
    [[ -f "$output_directory/keepalived-caddy-ha.conf" ]] || return 1
    [[ ! -L "$output_directory/keepalived-caddy-ha.conf" ]] || return 1
    [[ "$(file_hash "$output_directory/keepalived-caddy-ha.conf")" = "$expected_fragment_sha256" ]] || return 1
}

write_remote_bundle() {
    local bundle_archive_path=$1
    local bundle_path=$2

    # Literal remote variables expand only after the script reaches Node B.
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
            'bundle_stage=$(mktemp -d /run/caddy-action19a-stage.XXXXXX)' \
            'cleanup_bundle_stage() {' \
            '    rm -rf -- "$bundle_stage"' \
            '}' \
            'trap cleanup_bundle_stage EXIT' \
            'install -d -o root -g root -m 0700 "$bundle_stage/payload"' \
            'base64 -d >"$bundle_stage/payload.tar" <<'\''ACTION19A_ARCHIVE'\'''
        base64 "$bundle_archive_path"
        printf '%s\n' \
            'ACTION19A_ARCHIVE' \
            'tar --extract --file "$bundle_stage/payload.tar" \' \
            '    --directory "$bundle_stage/payload" \' \
            '    --no-same-owner --no-same-permissions' \
            'chown -R root:root "$bundle_stage/payload"' \
            'chmod 0700 "$bundle_stage/payload"' \
            'chmod 0700 "$bundle_stage/payload/install-node-b-keepalived-fragment-action19a.sh"' \
            'chmod 0644 "$bundle_stage/payload/keepalived-caddy-ha.conf"' \
            'cd /' \
            '/bin/bash \' \
            '    "$bundle_stage/payload/install-node-b-keepalived-fragment-action19a.sh" \' \
            '    --stage "$bundle_stage/payload"'
    } >"$bundle_path"
    chmod 0600 "$bundle_path"
    bash -n "$bundle_path"
}

write_success_fixture() {
    local fixture_path=$1
    local fixture_index

    for fixture_index in $(seq 1 90); do
        printf '%s_check_fixture_%03d=true\n' "$prefix" "$fixture_index"
    done >"$fixture_path"
    printf '%s\n' \
        "${prefix}_preflight_complete=true" \
        "${prefix}_mutation_started=true" \
        "${prefix}_fragment_installed=true" \
        "${prefix}_main_configuration_mutated=false" \
        "${prefix}_keepalived_reloaded=false" \
        "${prefix}_keepalived_restarted=false" \
        "${prefix}_vrrp_transition_requested=false" \
        "${prefix}_vip_mutations=false" \
        "${prefix}_service_mutations=false" \
        "${prefix}_backup_path=/var/backups/caddy-ha/action19a-node-b-keepalived-fragment.FIXTURE" \
        "${prefix}_persistent_mutation_scope=fragment,rollback_backup" \
        "${prefix}_install_complete=true" >>"$fixture_path"
}

case "${1:-}" in
    --self-test)
        [[ $# -eq 1 ]] || exit 64
        verify_sources
        [[ "$expected_target" = pi@10.1.0.54 ]]
        [[ "$expected_host_alias" = pihole00.local.theama.co ]]
        printf '%s_runner_self_test_complete=true\n' "$prefix"
        exit 0
        ;;
    --contract-test)
        [[ $# -eq 1 ]] || exit 64
        contract_directory=$(mktemp -d /tmp/caddy-action19a-contract.XXXXXX)
        trap 'rm -rf -- "$contract_directory"' EXIT
        success_fixture=$contract_directory/success.stdout
        empty_error=$contract_directory/success.stderr
        write_success_fixture "$success_fixture"
        : >"$empty_error"
        validate_transcript "$empty_error" "$success_fixture" 0
        printf '%s_check_fixture_001=false\n' "$prefix" >>"$success_fixture"
        if validate_transcript "$empty_error" "$success_fixture" 0; then
            exit 1
        fi
        printf '%s_runner_contract_test_complete=true\n' "$prefix"
        exit 0
        ;;
    "")
        [[ $# -eq 0 ]] || exit 64
        ;;
    *)
        printf 'Usage: %s [--self-test|--contract-test]\n' "${0##*/}" >&2
        exit 64
        ;;
esac

verify_sources
require_local_check working_directory_approved working_directory_approved
if [[ "$ssh_binary" != ssh ]]; then
    require_local_check intercepted_test_explicit \
        test "${CADDY_ACTION19A_INTERCEPTED_TEST:-}" = 1
else
    require_local_check production_ssh_binary_exact test "$ssh_binary" = ssh
fi
work_directory=$(mktemp -d /tmp/caddy-action19a-runner.XXXXXX)
readonly work_directory
cleanup() {
    # shellcheck disable=SC2317
    rm -rf -- "$work_directory"
}
trap cleanup EXIT
readonly render_directory="$work_directory/render-node-b"
readonly archive_root="$work_directory/archive-root"
readonly archive_path="$work_directory/payload.tar"
readonly remote_bundle="$work_directory/remote.sh"
readonly remote_stdout="$work_directory/remote.stdout"
readonly remote_stderr="$work_directory/remote.stderr"
install -d -m 0750 "$render_directory"
install -d -m 0700 "$archive_root"
: >"$remote_stdout"
: >"$remote_stderr"
chmod 0600 "$remote_stdout" "$remote_stderr"

require_local_check rendered_fragment_exact render_fragment "$render_directory"
install -m 0700 "$installer" \
    "$archive_root/install-node-b-keepalived-fragment-action19a.sh"
install -m 0644 "$render_directory/keepalived-caddy-ha.conf" \
    "$archive_root/keepalived-caddy-ha.conf"
tar --create --file "$archive_path" --directory "$archive_root" \
    install-node-b-keepalived-fragment-action19a.sh \
    keepalived-caddy-ha.conf
write_remote_bundle "$archive_path" "$remote_bundle"

remote_status=0
"$ssh_binary" -T \
    -o BatchMode=yes \
    -o ConnectTimeout=10 \
    -o ConnectionAttempts=1 \
    -o StrictHostKeyChecking=yes \
    "$expected_target" \
    'cd / && sudo -n /bin/bash -s' \
    <"$remote_bundle" >"$remote_stdout" 2>"$remote_stderr" || remote_status=$?
readonly remote_status

emit_stream_metadata remote_stdout "$remote_stdout"
emit_stream_metadata remote_stderr "$remote_stderr"
if safe_stream "$remote_stdout" && safe_stream "$remote_stderr"; then
    printf '%s_stream_classification=bounded_safe\n' "$prefix"
    printf '%s_remote_stdout_begin\n' "$prefix"
    cat "$remote_stdout"
    printf '%s_remote_stdout_end\n' "$prefix"
    if [[ -s "$remote_stderr" ]]; then
        printf '%s_remote_stderr_begin\n' "$prefix" >&2
        cat "$remote_stderr" >&2
        printf '%s_remote_stderr_end\n' "$prefix" >&2
    fi
else
    printf '%s_stream_classification=unsafe_retained\n' "$prefix" >&2
    trap - EXIT
    printf '%s_protected_evidence=%s\n' "$prefix" "$work_directory" >&2
    exit 97
fi

validation_status=0
validate_transcript "$remote_stderr" "$remote_stdout" "$remote_status" ||
    validation_status=$?
printf '%s_remote_status=%s\n' "$prefix" "$remote_status"
printf '%s_validation_status=%s\n' "$prefix" "$validation_status"
if [[ "$validation_status" -eq 97 ]]; then
    exit 97
fi
if [[ "$remote_status" -ne 0 || "$validation_status" -ne 0 ]]; then
    exit 1
fi
rm -rf -- "$work_directory"
trap - EXIT
printf '%s_workstation_cleanup_complete=true\n' "$prefix"
