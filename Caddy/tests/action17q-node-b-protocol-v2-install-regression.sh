#!/usr/bin/env bash

set -Eeuo pipefail
set +x
PATH=/usr/bin:/bin
export PATH
readonly PATH

script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
caddy_root=$(cd -- "$script_directory/.." && pwd)
readonly caddy_root
readonly installer="$caddy_root/scripts/install-node-b-protocol-v2-action17q.sh"
readonly runner="$caddy_root/scripts/run-node-b-protocol-v2-install-action17q.sh"
readonly receiver="$caddy_root/scripts/caddy-sync-release-receiver-v2"
readonly finalizer="$caddy_root/scripts/finalize-incoming-release-v2.sh"
readonly authorization_template="$caddy_root/templates/authorized-key-receiver-finalized-v2.in"
readonly collision_checker="$caddy_root/tests/check-shell-readonly-local-collisions.sh"
readonly source_context_policy="$caddy_root/tests/run-source-test-in-context.sh"
readonly installer_sha256=a399417c2f3c9639b22691df10d179c066d52ac32de596417916574bd9eb4736
readonly runner_sha256=1c078b5bba0299ae7a6c01cb6cd782c39be30d0738946a83757284bb63e0cad5
readonly receiver_sha256=a94c7a45531787055da622a0dac180f98e52bd0ba967424a4cf22a4852539d9e
readonly finalizer_sha256=a49dadcaa611e641a100e6a4f2b1836fcf9a790876f437ee02e37003d78ef30c
readonly authorization_template_sha256=e64a603dc93bebbac065955031f36048d551cac295e19dd497c7c6ed9b8cec32

file_hash() {
    sha256sum "$1" | awk '{ print $1 }'
}

assert_hash() {
    local expected_hash=$1
    local source_path=$2

    [[ "$(file_hash "$source_path")" == "$expected_hash" ]]
}

# The static policy intentionally matches literal production shell source.
# shellcheck disable=SC2016
assert_static_policy() {
    if grep -Eq \
        'systemctl[[:space:]]+(start|stop|restart|reload|enable|disable|mask|unmask|daemon-reload|reset-failed)' \
        "$installer" "$runner"; then
        printf 'Action 17q contains a service mutation.\n' >&2
        return 1
    fi
    if grep -Eq \
        '(^|[[:space:]])(rsync|scp|sftp)([[:space:]]|$)' \
        "$installer" "$runner"; then
        printf 'Action 17q contains a synchronization command.\n' >&2
        return 1
    fi
    if grep -Eq \
        '^[[:space:]]*"?\$receiver_v2"?[[:space:]]' "$installer"; then
        printf 'Action 17q invokes the installed receiver.\n' >&2
        return 1
    fi
    if grep -Eq \
        '^[[:space:]]*"?\$finalizer_v2"?[[:space:]]' "$installer"; then
        printf 'Action 17q invokes the installed finalizer.\n' >&2
        return 1
    fi
    if grep -Eq \
        'ACTION17Q_(SUCCESS|FIXTURE|CAPTURED|SSH_ARGUMENTS)' "$runner"; then
        printf 'Production Action 17q runner contains a fixture bypass.\n' >&2
        return 1
    fi
    grep -Fq 'action_17q_receiver_invoked=false' "$installer"
    grep -Fq 'action_17q_finalizer_invoked=false' "$installer"
    grep -Fq 'action_17q_release_mutated=false' "$installer"
    grep -Fq 'action_17q_lsyncd_enabled=false' "$installer"
    grep -Fq 'action_17q_reconciliation_enabled=false' "$installer"
    grep -Fq 'retained_tree_before=$(retained_tree_digest)' "$installer"
    grep -Fq 'test "$(retained_tree_digest)" = "$retained_tree_before"' \
        "$installer"
    grep -Fq 'test ! -e "$retained_release/.complete"' "$installer"
    grep -Fq 'test ! -e "$retained_release/.complete.pending"' "$installer"
    grep -Fq 'test ! -e "$retained_release/.finalize-request"' "$installer"
    grep -Fq 'test ! -e "$lsyncd_config"' "$installer"
    grep -Fq 'validate_service_continuity' "$installer"
    grep -Fq 'action_17q_rollback_complete=true' "$installer"
    grep -Fq 'manual_intervention_required=true' "$installer"
}

write_fake_ssh() {
    local fake_ssh_path=$1

    # shellcheck disable=SC2016
    {
        printf '%s\n' '#!/usr/bin/env bash'
        printf '%s\n' 'set -Eeuo pipefail'
        printf '%s\n' 'cat >"$ACTION17Q_CAPTURED_BUNDLE"'
        printf '%s\n' 'printf "%s\n" "$*" >"$ACTION17Q_SSH_ARGUMENTS"'
        printf '%s\n' 'cat "$ACTION17Q_SUCCESS_FIXTURE"'
    } >"$fake_ssh_path"
    chmod 0755 "$fake_ssh_path"
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

run_production_path_regression() {
    local case_bin
    local case_root
    local case_runner
    local false_status

    case_root=$(mktemp -d /tmp/caddy-action17q-regression.XXXXXX)
    trap 'rm -rf -- "$case_root"' RETURN
    case_bin="$case_root/bin"
    install -d -m 0700 \
        "$case_bin" \
        "$case_root/Caddy/scripts" \
        "$case_root/Caddy/templates" \
        "$case_root/Caddy/tests"
    cp -- \
        "$installer" "$runner" "$receiver" "$finalizer" \
        "$case_root/Caddy/scripts/"
    cp -- "$authorization_template" "$case_root/Caddy/templates/"
    write_fake_ssh "$case_bin/ssh"
    write_success_fixture "$case_root/success.fixture"
    case_runner="$case_root/Caddy/scripts/run-node-b-protocol-v2-install-action17q.sh"
    sed -i "s|^PATH=/usr/bin:/bin$|PATH=$case_bin:/usr/bin:/bin|" \
        "$case_runner"
    chmod 0755 "$case_runner"

    ACTION17Q_CAPTURED_BUNDLE="$case_root/bundle" \
        ACTION17Q_SSH_ARGUMENTS="$case_root/ssh-arguments" \
        ACTION17Q_SUCCESS_FIXTURE="$case_root/success.fixture" \
        "$case_runner" >"$case_root/output" 2>"$case_root/error"
    [[ ! -s "$case_root/error" ]]
    grep -Fxq action_17q_runner_acceptance=true "$case_root/output"
    grep -Fxq action_17q_workstation_cleanup_complete=true \
        "$case_root/output"
    grep -Fq 'pi@10.1.0.54' "$case_root/ssh-arguments"
    grep -Fq 'HostKeyAlias=pihole00.local.theama.co' \
        "$case_root/ssh-arguments"
    grep -Fq ACTION17Q_ARCHIVE "$case_root/bundle"
    bash -n "$case_root/bundle"

    cp -- "$case_root/success.fixture" "$case_root/false.fixture"
    printf 'action_17q_release_mutated=true\n' >>"$case_root/false.fixture"
    set +e
    ACTION17Q_CAPTURED_BUNDLE="$case_root/false-bundle" \
        ACTION17Q_SSH_ARGUMENTS="$case_root/false-ssh-arguments" \
        ACTION17Q_SUCCESS_FIXTURE="$case_root/false.fixture" \
        "$case_runner" >"$case_root/false-output" \
        2>"$case_root/false-error"
    false_status=$?
    set -e
    [[ "$false_status" -eq 97 ]]
    grep -Fq 'Action 17q success contract failed.' \
        "$case_root/false-error"

    printf 'action_17q_false_negative_valid_production_path_accepted=true\n'
    printf 'action_17q_false_positive_contradictory_evidence_rejected=true\n'
    printf 'action_17q_production_path_network_contact=false\n'
}

if [[ "${1:-}" != --self-test || $# -ne 1 ]]; then
    printf 'Usage: %s --self-test\n' "${0##*/}" >&2
    exit 2
fi

assert_hash "$installer_sha256" "$installer"
assert_hash "$runner_sha256" "$runner"
assert_hash "$receiver_sha256" "$receiver"
assert_hash "$finalizer_sha256" "$finalizer"
assert_hash "$authorization_template_sha256" "$authorization_template"
bash -n "$installer" "$runner"
shellcheck "$installer" "$runner"
"$collision_checker" "$installer" "$runner" >/dev/null
"$installer" --self-test >/dev/null
"$runner" --self-test >/dev/null
"$runner" --contract-test >/dev/null
"$source_context_policy" --runner "$runner" >/dev/null
assert_static_policy
if [[ "${CADDY_VALIDATION_CONTAINER:-}" == 1 ]]; then
    [[ "$caddy_root" == /workspace/homelab-server-configs/Caddy ]]
    printf 'action_17q_container_projection_validated=true\n'
else
    run_production_path_regression
fi

printf 'action_17q_node_b_protocol_v2_install_regression_complete=true\n'
