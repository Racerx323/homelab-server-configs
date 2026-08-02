#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly expected_target=pi@10.1.0.54
readonly expected_host_alias=pihole00.local.theama.co
readonly receiver_sha256=a94c7a45531787055da622a0dac180f98e52bd0ba967424a4cf22a4852539d9e
readonly finalizer_sha256=a49dadcaa611e641a100e6a4f2b1836fcf9a790876f437ee02e37003d78ef30c
readonly authorization_template_sha256=e64a603dc93bebbac065955031f36048d551cac295e19dd497c7c6ed9b8cec32
readonly installer_sha256=a399417c2f3c9639b22691df10d179c066d52ac32de596417916574bd9eb4736
readonly node_a_public_key='ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIG3MEgLhf8tsImyjkCZpQU4H7X8Xdac+iOUCxRTMM0tA caddy-ha-sync'
readonly expected_authorization_sha256=54eeda8ae3c94e878a38d76ccade91642ba9ab193b5f416ea1bf308a500a1bc1

script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
caddy_root=$(cd -- "$script_directory/.." && pwd)
readonly caddy_root
readonly installer="$script_directory/install-node-b-protocol-v2-action17q.sh"
readonly receiver="$script_directory/caddy-sync-release-receiver-v2"
readonly finalizer="$script_directory/finalize-incoming-release-v2.sh"
readonly authorization_template="$caddy_root/templates/authorized-key-receiver-finalized-v2.in"

file_hash() {
    sha256sum "$1" | awk '{ print $1 }'
}

require_exact_line() {
    local expected_line=$1
    local transcript_path=$2

    [[ "$(grep -Fxc "$expected_line" "$transcript_path")" -eq 1 ]]
}

verify_source_file() {
    local expected_hash=$1
    local expected_mode=$2
    local source_path=$3

    [[ -f "$source_path" && ! -L "$source_path" ]]
    [[ "$(stat -c '%U:%G:%a' "$source_path")" == "aaron:aaron:$expected_mode" ]]
    [[ "$(file_hash "$source_path")" == "$expected_hash" ]]
}

verify_sources() {
    verify_source_file "$installer_sha256" 755 "$installer"
    verify_source_file "$receiver_sha256" 755 "$receiver"
    verify_source_file "$finalizer_sha256" 755 "$finalizer"
    verify_source_file \
        "$authorization_template_sha256" 644 "$authorization_template"
    bash -n "$installer" "$receiver" "$finalizer"
}

render_authorization() {
    local destination=$1

    sed \
        -e 's/@PEER_IPV4@/10.1.0.53/g' \
        -e 's/@PEER_IPV6@/fd36:5aa8:6971:1::53/g' \
        -e 's/@PEER_ROLE@/node-a/g' \
        "$authorization_template" |
        sed "s|\$| $node_a_public_key|" >"$destination"
    [[ "$(file_hash "$destination")" == "$expected_authorization_sha256" ]]
    [[ "$(wc -l <"$destination")" -eq 1 ]]
}

write_remote_bundle() {
    local archive_source=$1
    local bundle_destination=$2

    # Literal remote-script source must expand only after reaching Node B.
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
            'bundle_stage=$(mktemp -d /run/caddy-action17q-stage.XXXXXX)' \
            'cleanup_bundle_stage() {' \
            '    rm -rf -- "$bundle_stage"' \
            '}' \
            'trap cleanup_bundle_stage EXIT' \
            'install -d -o root -g root -m 0700 "$bundle_stage/payload"' \
            'base64 -d >"$bundle_stage/payload.tar" <<'\''ACTION17Q_ARCHIVE'\'''
        base64 "$archive_source"
        printf '%s\n' \
            'ACTION17Q_ARCHIVE' \
            'tar --extract --file "$bundle_stage/payload.tar" \' \
            '    --directory "$bundle_stage/payload" \' \
            '    --no-same-owner --no-same-permissions' \
            'chown -R root:root "$bundle_stage/payload"' \
            'chmod 0700 "$bundle_stage/payload"' \
            'chmod 0600 "$bundle_stage/payload"/*' \
            'chmod 0700 \' \
            '    "$bundle_stage/payload/install-node-b-protocol-v2-action17q.sh"' \
            'cd /' \
            '/bin/bash \' \
            '    "$bundle_stage/payload/install-node-b-protocol-v2-action17q.sh" \' \
            '    --stage "$bundle_stage/payload"'
    } >"$bundle_destination"
    chmod 0600 "$bundle_destination"
    bash -n "$bundle_destination"
}

validate_secret_free() {
    local error_transcript=$1
    local output_transcript=$2

    ! grep -Eq \
        'BEGIN [A-Z ]*PRIVATE KEY|CADDY_TLS_PRIVATE_KEY_PEM|DOPPLER_TOKEN|PRIVATE_KEY=' \
        "$output_transcript" "$error_transcript"
}

validate_success() {
    local error_transcript=$1
    local output_transcript=$2
    local ssh_status=$3
    local success_marker

    [[ "$ssh_status" -eq 0 ]]
    [[ ! -s "$error_transcript" ]]
    if grep -Eq \
        '^action_17q_check_[^=]+=false$|^action_17q_(receiver_invoked|finalizer_invoked|release_mutated|lsyncd_enabled|reconciliation_enabled|service_mutations)=true$' \
        "$output_transcript"; then
        return 1
    fi
    for success_marker in \
        action_17q_preflight_complete=true \
        action_17q_mutation_started=true \
        action_17q_receiver_invoked=false \
        action_17q_finalizer_invoked=false \
        action_17q_release_mutated=false \
        action_17q_lsyncd_enabled=false \
        action_17q_reconciliation_enabled=false \
        action_17q_service_mutations=false \
        action_17q_persistent_mutation_scope=receiver_v2,finalizer_v2,authorized_keys,rollback_backup \
        action_17q_node_b_protocol_v2_install_complete=true; do
        require_exact_line "$success_marker" "$output_transcript" || return 1
    done
    [[ "$(grep -Ec \
        '^action_17q_backup_path=/var/backups/caddy-ha/action17q-node-b-protocol-v2\.[A-Za-z0-9]+$' \
        "$output_transcript")" -eq 1 ]]
    if grep -Eq \
        'action_17q_rollback_|manual_intervention_required=true' \
        "$output_transcript" "$error_transcript"; then
        return 1
    fi
}

validate_failure() {
    local error_transcript=$1
    local output_transcript=$2
    local ssh_status=$3

    [[ "$ssh_status" -ne 0 ]]
    if grep -Fq 'manual_intervention_required=true' \
        "$output_transcript" "$error_transcript" ||
        grep -Fq 'action_17q_rollback_complete=false' \
            "$output_transcript" "$error_transcript"; then
        return 97
    fi
    if grep -Fq 'action_17q_mutation_started=true' "$output_transcript"; then
        require_exact_line \
            action_17q_rollback_started=true "$error_transcript" || return 97
        require_exact_line \
            action_17q_rollback_complete=true "$error_transcript" || return 97
    elif grep -Eq \
        'action_17q_rollback_' "$output_transcript" "$error_transcript"; then
        return 97
    fi
}

write_success_fixture() {
    local fixture_path=$1

    printf '%s\n' \
        action_17q_preflight_complete=true \
        action_17q_mutation_started=true \
        action_17q_receiver_invoked=false \
        action_17q_finalizer_invoked=false \
        action_17q_release_mutated=false \
        action_17q_lsyncd_enabled=false \
        action_17q_reconciliation_enabled=false \
        action_17q_service_mutations=false \
        action_17q_backup_path=/var/backups/caddy-ha/action17q-node-b-protocol-v2.ABC123 \
        action_17q_persistent_mutation_scope=receiver_v2,finalizer_v2,authorized_keys,rollback_backup \
        action_17q_node_b_protocol_v2_install_complete=true \
        >"$fixture_path"
}

case "${1:-}" in
    --self-test)
        [[ $# -eq 1 ]]
        [[ "$expected_target" == pi@10.1.0.54 ]]
        [[ "$expected_host_alias" == pihole00.local.theama.co ]]
        [[ "$installer_sha256" =~ ^[0-9a-f]{64}$ ]]
        [[ "$receiver_sha256" =~ ^[0-9a-f]{64}$ ]]
        [[ "$finalizer_sha256" =~ ^[0-9a-f]{64}$ ]]
        [[ "$authorization_template_sha256" =~ ^[0-9a-f]{64}$ ]]
        [[ "$expected_authorization_sha256" =~ ^[0-9a-f]{64}$ ]]
        printf 'action_17q_runner_self_test_complete=true\n'
        exit 0
        ;;
    --source-test)
        [[ $# -eq 1 ]]
        verify_sources
        printf 'action_17q_runner_source_test_complete=true\n'
        exit 0
        ;;
    --contract-test)
        [[ $# -eq 1 ]]
        contract_directory=$(mktemp -d /tmp/caddy-action17q-contract.XXXXXX)
        trap 'rm -rf -- "$contract_directory"' EXIT
        : >"$contract_directory/error"
        write_success_fixture "$contract_directory/output"
        validate_secret_free \
            "$contract_directory/error" "$contract_directory/output"
        validate_success \
            "$contract_directory/error" "$contract_directory/output" 0
        printf 'action_17q_finalizer_invoked=true\n' \
            >>"$contract_directory/output"
        if validate_success \
            "$contract_directory/error" "$contract_directory/output" 0; then
            printf 'Contradictory finalizer evidence was accepted.\n' >&2
            exit 1
        fi
        printf '%s\n' \
            action_17q_mutation_started=true \
            >"$contract_directory/rollback-output"
        printf '%s\n' \
            action_17q_rollback_started=true \
            action_17q_rollback_complete=true \
            >"$contract_directory/rollback-error"
        validate_failure \
            "$contract_directory/rollback-error" \
            "$contract_directory/rollback-output" 1
        printf 'action_17q_runner_contract_test_complete=true\n'
        exit 0
        ;;
    "") ;;
    *)
        printf 'Usage: %s [--self-test|--source-test|--contract-test]\n' \
            "${0##*/}" >&2
        exit 2
        ;;
esac

verify_sources
work_directory=$(mktemp -d /tmp/caddy-action17q.XXXXXX)
readonly work_directory
readonly payload_directory="$work_directory/payload"
readonly archive_path="$work_directory/payload.tar"
readonly bundle_path="$work_directory/remote-bundle.sh"
readonly output_path="$work_directory/remote.out"
readonly error_path="$work_directory/remote.err"

cleanup() {
    rm -rf -- "$work_directory"
}
trap cleanup EXIT

finish() {
    local finish_status=$1

    cleanup
    trap - EXIT
    if [[ -e "$work_directory" || -L "$work_directory" ]]; then
        printf 'action_17q_workstation_cleanup_complete=false\n' >&2
        exit 97
    fi
    printf 'action_17q_workstation_cleanup_complete=true\n'
    exit "$finish_status"
}

install -d -m 0700 "$payload_directory"
install -m 0700 "$installer" \
    "$payload_directory/install-node-b-protocol-v2-action17q.sh"
install -m 0600 "$receiver" \
    "$payload_directory/caddy-sync-release-receiver-v2"
install -m 0600 "$finalizer" \
    "$payload_directory/finalize-incoming-release-v2.sh"
render_authorization "$payload_directory/authorized_keys"
tar --create --file "$archive_path" --directory "$payload_directory" \
    install-node-b-protocol-v2-action17q.sh \
    caddy-sync-release-receiver-v2 \
    finalize-incoming-release-v2.sh \
    authorized_keys
write_remote_bundle "$archive_path" "$bundle_path"

ssh_status=0
ssh -T \
    -o BatchMode=yes \
    -o ConnectTimeout=5 \
    -o "HostKeyAlias=$expected_host_alias" \
    -o StrictHostKeyChecking=yes \
    "$expected_target" \
    'cd / && sudo -n /bin/bash -s --' \
    <"$bundle_path" >"$output_path" 2>"$error_path" || ssh_status=$?

cat "$output_path"
cat "$error_path" >&2
printf 'action_17q_ssh_status=%s\n' "$ssh_status"
if ! validate_secret_free "$error_path" "$output_path"; then
    printf 'Unsafe Action 17q output detected.\n' >&2
    finish 97
fi
if [[ "$ssh_status" -eq 0 ]]; then
    if ! validate_success "$error_path" "$output_path" "$ssh_status"; then
        printf 'Action 17q success contract failed.\n' >&2
        finish 97
    fi
    printf 'action_17q_runner_acceptance=true\n'
    finish 0
fi

set +e
validate_failure "$error_path" "$output_path" "$ssh_status"
failure_validation_status=$?
set -e
if [[ "$failure_validation_status" -eq 97 ]]; then
    printf 'Action 17q rollback evidence is incomplete.\n' >&2
    finish 97
fi
printf 'action_17q_runner_acceptance=false\n'
finish "$ssh_status"
