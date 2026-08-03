#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
readonly caddy_root=${test_directory%/tests}
readonly derivation="$caddy_root/scripts/derive-node-a-action18-prerequisite-action18b.sh"
readonly receiver="$caddy_root/scripts/caddy-sync-release-receiver-v2"
readonly finalizer="$caddy_root/scripts/finalize-incoming-release-v2-stderr-safe-action17u.sh"
readonly authorization_template="$caddy_root/templates/authorized-key-receiver-finalized-v2.in"
readonly collision_checker="$test_directory/check-shell-readonly-local-collisions-v2.sh"
readonly derivation_sha256=8df318bb6af25a2891a431f90d4b970544901268c87a39dcec4258290643862c
readonly rendered_installer_sha256=9c2743e553cc52e53e57a880e3d386aba130bd7a610879159b1d36db6bf87e97
readonly rendered_runner_sha256=44a57fbd90cf1c8dfb6d42b24e80df139d7e39132fe3914c187e8cdb0a27412e
readonly receiver_sha256=a94c7a45531787055da622a0dac180f98e52bd0ba967424a4cf22a4852539d9e
readonly finalizer_sha256=15d858774a17369f31261f7f94bea72d575f269fdb3e8e991534f66dd4f4902d
readonly expected_authorization_sha256=3df0ffaaf4d0f1007a9d7214eefc81f4f08df00ad840ea1d3f83e8b72b0e2331

file_hash() {
    sha256sum "$1" | awk '{ print $1 }'
}

require_hash() {
    local hash_label=$1
    local hash_path=$2
    local expected_hash=$3

    [[ "$(file_hash "$hash_path")" == "$expected_hash" ]] || {
        printf 'action_18b_regression_assertion_%s=false\n' "$hash_label" >&2
        return 1
    }
    printf 'action_18b_regression_assertion_%s=true\n' "$hash_label"
}

stage_sources() {
    local stage_root=$1

    install -d -m 0700 \
        "$stage_root/Caddy/scripts" \
        "$stage_root/Caddy/templates" \
        "$stage_root/Caddy/tests"
    "$derivation" --output-directory "$stage_root/Caddy/scripts" >/dev/null
    install -m 0755 "$receiver" "$stage_root/Caddy/scripts/"
    install -m 0755 "$finalizer" "$stage_root/Caddy/scripts/"
    install -m 0644 "$authorization_template" "$stage_root/Caddy/templates/"
    install -m 0755 "$collision_checker" "$stage_root/Caddy/tests/"
}

write_success_fixture() {
    local fixture_path=$1

    printf '%s\n' \
        action_18b_preflight_complete=true \
        action_18b_mutation_started=true \
        action_18b_receiver_invoked=false \
        action_18b_finalizer_invoked=false \
        action_18b_release_mutated=false \
        action_18b_lsyncd_enabled=false \
        action_18b_reconciliation_enabled=false \
        action_18b_service_mutations=false \
        action_18b_backup_path=/var/backups/caddy-ha/action18b-node-a-prerequisite.ABC123 \
        action_18b_persistent_mutation_scope=receiver_v2,finalizer_v2,authorized_keys,rollback_backup \
        action_18b_node_a_prerequisite_install_complete=true \
        >"$fixture_path"
}

write_fake_ssh() {
    local fake_ssh_path=$1

    # Variables expand only in the intercepted runner process.
    # shellcheck disable=SC2016
    printf '%s\n' \
        '#!/usr/bin/env bash' \
        'set -Eeuo pipefail' \
        'cat >"$ACTION18B_CAPTURED_BUNDLE"' \
        'printf "%s\n" "$*" >"$ACTION18B_SSH_ARGUMENTS"' \
        'cat "$ACTION18B_FIXTURE_OUTPUT"' \
        'cat "$ACTION18B_FIXTURE_ERROR" >&2' \
        'exit "$ACTION18B_FIXTURE_STATUS"' >"$fake_ssh_path"
    chmod 0755 "$fake_ssh_path"
}

run_intercepted_case() {
    local case_error=$1
    local case_output=$2
    local case_root=$3
    local case_runner=$4
    local case_status=$5
    local case_suffix=$6

    intercepted_status=0
    ACTION18B_CAPTURED_BUNDLE="$case_root/$case_suffix.bundle" \
        ACTION18B_SSH_ARGUMENTS="$case_root/$case_suffix.arguments" \
        ACTION18B_FIXTURE_OUTPUT="$case_output" \
        ACTION18B_FIXTURE_ERROR="$case_error" \
        ACTION18B_FIXTURE_STATUS="$case_status" \
        "$case_runner" >"$case_root/$case_suffix.out" \
        2>"$case_root/$case_suffix.err" || intercepted_status=$?
}

require_hash derivation_hash_exact "$derivation" "$derivation_sha256"
require_hash receiver_hash_exact "$receiver" "$receiver_sha256"
require_hash finalizer_hash_exact "$finalizer" "$finalizer_sha256"

regression_root=$(mktemp -d /tmp/caddy-action18b-regression.XXXXXX)
readonly regression_root
cleanup() {
    # shellcheck disable=SC2317
    rm -rf -- "$regression_root"
}
trap cleanup EXIT

stage_sources "$regression_root/source"
readonly installer="$regression_root/source/Caddy/scripts/install-node-a-action18-prerequisite-action18b.sh"
readonly runner="$regression_root/source/Caddy/scripts/run-node-a-action18-prerequisite-action18b.sh"
require_hash rendered_installer_hash_exact "$installer" "$rendered_installer_sha256"
require_hash rendered_runner_hash_exact "$runner" "$rendered_runner_sha256"

bash -n "$derivation" "$installer" "$runner"
shellcheck "$derivation" "$installer" "$runner"
"$collision_checker" "$derivation" "$installer" "$runner" >/dev/null
"$derivation" --self-test >/dev/null
"$installer" --self-test >/dev/null
"$runner" --self-test >/dev/null
"$runner" --source-test >/dev/null
"$runner" --contract-test >/dev/null

# shellcheck disable=SC2016
grep -Fq 'readonly retained_release="/var/lib/caddy-sync/outbound/$revision"' \
    "$installer"
grep -Fq 'readonly expected_active_release=/etc/caddy/releases/action16ar-retry-node-a-default-deny' \
    "$installer"
grep -Fq 'readonly expected_finalizer_v2_sha256=15d858774a17369f31261f7f94bea72d575f269fdb3e8e991534f66dd4f4902d' \
    "$installer"
grep -Fq 'readonly expected_old_authorization_sha256=6ef8d656053aba6508524aaebd3d215ef9036f8bb6fd1f56cd8b4a654649f968' \
    "$installer"
grep -Fq 'readonly expected_new_authorization_sha256=3df0ffaaf4d0f1007a9d7214eefc81f4f08df00ad840ea1d3f83e8b72b0e2331' \
    "$installer"
# shellcheck disable=SC2016
grep -Fq 'require_check hostname_node_a test "$(hostname)" = j1-svpihole0' \
    "$installer"
grep -Fq '! -name .complete.pending ! -name .finalize-request -print0' \
    "$installer"
grep -Fq 'readonly expected_target=pi@10.1.0.53' "$runner"
grep -Fq 'readonly expected_host_alias=pihole0.local.theama.co' "$runner"
grep -Fq "s/@PEER_IPV4@/10.1.0.54/g" "$runner"
grep -Fq "s/@PEER_IPV6@/fd36:5aa8:6971:1::54/g" "$runner"
grep -Fq "s/@PEER_ROLE@/node-b/g" "$runner"
grep -Fq 'conditional-validator-explicit-failures-begin' "$runner"
grep -Fq 'conditional-validator-explicit-failures-end' "$runner"

if grep -Eq 'systemctl[[:space:]]+(start|stop|restart|reload|enable|disable|mask|unmask|daemon-reload|reset-failed)' \
    "$installer" "$runner"; then
    printf 'Action 18b contains a service mutation.\n' >&2
    exit 1
fi
if grep -Eq '(^|[[:space:]])(rsync|scp|sftp)([[:space:]]|$)' \
    "$installer" "$runner"; then
    printf 'Action 18b contains a synchronization command.\n' >&2
    exit 1
fi
# shellcheck disable=SC2016
if grep -Eq '^[[:space:]]*"?\$(receiver_v2|finalizer_v2)"?[[:space:]]' \
    "$installer"; then
    printf 'Action 18b invokes an installed helper.\n' >&2
    exit 1
fi

case_root="$regression_root/production"
stage_sources "$case_root"
case_runner="$case_root/Caddy/scripts/run-node-a-action18-prerequisite-action18b.sh"
case_bin="$case_root/bin"
install -d -m 0700 "$case_bin"
write_fake_ssh "$case_bin/ssh"
sed -i "s|^PATH=/usr/bin:/bin$|PATH=$case_bin:/usr/bin:/bin|" "$case_runner"
chmod 0755 "$case_runner"
: >"$case_root/empty.err"
write_success_fixture "$case_root/success.fixture"

run_intercepted_case "$case_root/empty.err" "$case_root/success.fixture" \
    "$case_root" "$case_runner" 0 success
[[ "$intercepted_status" -eq 0 ]]
grep -Fxq action_18b_runner_acceptance=true "$case_root/success.out"
grep -Fxq action_18b_workstation_cleanup_complete=true "$case_root/success.out"
grep -Fq 'pi@10.1.0.53' "$case_root/success.arguments"
grep -Fq 'HostKeyAlias=pihole0.local.theama.co' "$case_root/success.arguments"
grep -Fq ACTION18B_ARCHIVE "$case_root/success.bundle"

awk '/<<.*ACTION18B_ARCHIVE/ { capture = 1; next }
    capture && /^ACTION18B_ARCHIVE$/ { exit }
    capture { print }' "$case_root/success.bundle" |
    base64 -d >"$case_root/payload.tar"
tar -xf "$case_root/payload.tar" -C "$case_root"
require_hash bundled_finalizer_hash_exact \
    "$case_root/finalize-incoming-release-v2.sh" "$finalizer_sha256"
require_hash bundled_authorization_hash_exact \
    "$case_root/authorized_keys" "$expected_authorization_sha256"
grep -Fxq \
    'from="10.1.0.54,fd36:5aa8:6971:1::54",restrict,command="/usr/local/libexec/caddy-sync-release-receiver-v2 --source-role node-b" ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBwBAlvUOqcazWjzfUOnwk1AHath8Xn8eoUDXBFQIG7e caddy-ha-sync' \
    "$case_root/authorized_keys"

cp "$case_root/success.fixture" "$case_root/contradiction.fixture"
printf 'action_18b_finalizer_invoked=true\n' \
    >>"$case_root/contradiction.fixture"
run_intercepted_case "$case_root/empty.err" "$case_root/contradiction.fixture" \
    "$case_root" "$case_runner" 0 contradiction
[[ "$intercepted_status" -eq 97 ]]

printf 'action_18b_mutation_started=true\n' >"$case_root/rollback.out.fixture"
printf '%s\n' \
    action_18b_rollback_started=true \
    action_18b_rollback_complete=true >"$case_root/rollback.err.fixture"
run_intercepted_case "$case_root/rollback.err.fixture" \
    "$case_root/rollback.out.fixture" "$case_root" "$case_runner" 1 rollback
[[ "$intercepted_status" -eq 1 ]]
grep -Fxq action_18b_runner_acceptance=false "$case_root/rollback.out"

printf 'action_18b_false_negative_valid_success_accepted=true\n'
printf 'action_18b_false_negative_complete_rollback_preserved=true\n'
printf 'action_18b_false_positive_contradiction_rejected=true\n'
printf 'action_18b_production_path_network_contact=false\n'
printf 'action_18b_node_a_prerequisite_regression_complete=true\n'
