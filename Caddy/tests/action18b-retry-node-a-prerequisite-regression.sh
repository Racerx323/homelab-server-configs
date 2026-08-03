#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly derivation_sha256=e72d7c5970ce7cbaf19d83adbf062f2717abf89b261aece807049c42722c7bea
readonly historical_regression_sha256=9493dc16753528703b3cfc8c620eb5491f7ade3d6e25f0d5356d651d97e860c0
readonly rendered_installer_sha256=f9e91d20bcb2be8b7791317fa1245b2b99848608b9d24c1b934881e4d45022df
readonly rendered_runner_sha256=c0908e27de47200bcca6ee037effd3f1765c5d71278048f0fcee3f026785aced
readonly sender_complete_sha256=e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855

test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
readonly caddy_root=${test_directory%/tests}
readonly derivation="$caddy_root/scripts/derive-node-a-action18-prerequisite-action18b-retry.sh"
readonly historical_regression="$test_directory/action18b-node-a-prerequisite-regression.sh"
readonly collision_checker="$test_directory/check-shell-readonly-local-collisions-v2.sh"
readonly receiver="$caddy_root/scripts/caddy-sync-release-receiver-v2"
readonly finalizer="$caddy_root/scripts/finalize-incoming-release-v2-stderr-safe-action17u.sh"
readonly authorization_template="$caddy_root/templates/authorized-key-receiver-finalized-v2.in"

file_hash() {
    sha256sum "$1" | awk '{ print $1 }'
}

require_hash() {
    local assertion_label=$1
    local assertion_path=$2
    local expected_hash=$3

    [[ "$(file_hash "$assertion_path")" == "$expected_hash" ]] || return 1
    printf 'action_18b_retry_regression_assertion_%s=true\n' "$assertion_label"
}

write_success_fixture() {
    local fixture_path=$1

    printf '%s\n' \
        action_18b_retry_preflight_complete=true \
        action_18b_retry_mutation_started=true \
        action_18b_retry_receiver_invoked=false \
        action_18b_retry_finalizer_invoked=false \
        action_18b_retry_release_mutated=false \
        action_18b_retry_lsyncd_enabled=false \
        action_18b_retry_reconciliation_enabled=false \
        action_18b_retry_service_mutations=false \
        action_18b_retry_backup_path=/var/backups/caddy-ha/action18b-retry-node-a-prerequisite.ABC123 \
        action_18b_retry_persistent_mutation_scope=receiver_v2,finalizer_v2,authorized_keys,rollback_backup \
        action_18b_retry_node_a_prerequisite_install_complete=true \
        >"$fixture_path"
}

write_fake_ssh() {
    local fake_ssh_path=$1

    # Variables expand only in the intercepted runner process.
    # shellcheck disable=SC2016
    printf '%s\n' \
        '#!/usr/bin/env bash' \
        'set -Eeuo pipefail' \
        'cat >"$ACTION18B_RETRY_CAPTURED_BUNDLE"' \
        'printf "%s\n" "$*" >"$ACTION18B_RETRY_SSH_ARGUMENTS"' \
        'cat "$ACTION18B_RETRY_FIXTURE_OUTPUT"' \
        'cat "$ACTION18B_RETRY_FIXTURE_ERROR" >&2' \
        'exit "$ACTION18B_RETRY_FIXTURE_STATUS"' >"$fake_ssh_path"
    chmod 0755 "$fake_ssh_path"
}

run_intercepted_case() {
    local case_error=$1
    local case_output=$2
    local case_root=$3
    local intercept_runner_path=$4
    local case_status=$5
    local case_suffix=$6

    intercepted_status=0
    ACTION18B_RETRY_CAPTURED_BUNDLE="$case_root/$case_suffix.bundle" \
        ACTION18B_RETRY_SSH_ARGUMENTS="$case_root/$case_suffix.arguments" \
        ACTION18B_RETRY_FIXTURE_OUTPUT="$case_output" \
        ACTION18B_RETRY_FIXTURE_ERROR="$case_error" \
        ACTION18B_RETRY_FIXTURE_STATUS="$case_status" \
        "$intercept_runner_path" >"$case_root/$case_suffix.out" \
        2>"$case_root/$case_suffix.err" || intercepted_status=$?
}

regression_root=$(mktemp -d /tmp/caddy-action18b-retry-regression.XXXXXX)
readonly regression_root
cleanup() {
    # shellcheck disable=SC2317
    rm -rf -- "$regression_root"
}
trap cleanup EXIT

require_hash derivation_hash_exact "$derivation" "$derivation_sha256"
require_hash historical_regression_hash_exact \
    "$historical_regression" "$historical_regression_sha256"

readonly staged_caddy="$regression_root/source/Caddy"
install -d -m 0700 \
    "$staged_caddy/scripts" "$staged_caddy/templates" "$staged_caddy/tests"
"$derivation" --output-directory "$staged_caddy/scripts" >/dev/null
install -m 0755 "$derivation" "$staged_caddy/scripts/"
install -m 0755 "$receiver" "$finalizer" "$staged_caddy/scripts/"
install -m 0644 "$authorization_template" "$staged_caddy/templates/"
install -m 0755 "$collision_checker" "$staged_caddy/tests/"
readonly installer="$staged_caddy/scripts/install-node-a-action18-prerequisite-action18b-retry.sh"
readonly runner="$staged_caddy/scripts/run-node-a-action18-prerequisite-action18b-retry.sh"

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

grep -Fq 'readonly expected_sender_complete_sha256=e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855' \
    "$installer"
# Literal variables must remain unexpanded in the production source.
grep -Fq 'validate_sender_complete retained_complete' "$installer"
# shellcheck disable=SC2016
grep -Fq '"$retained_release/.complete" caddy-sync:caddy-sync:440' "$installer"
grep -Fq 'validate_sender_complete retained_complete_still' "$installer"
if grep -Fq 'retained_complete_absent' "$installer" ||
    grep -Fq 'retained_complete_still_absent' "$installer"; then
    printf 'Action 18b retry retained obsolete marker semantics.\n' >&2
    exit 1
fi
printf 'action_18b_retry_regression_assertion_sender_marker_semantics_exact=true\n'

readonly function_source="$regression_root/validate-sender-complete.sh"
sed -n '/^validate_sender_complete() {$/,/^}$/p' "$installer" >"$function_source"
[[ "$(grep -Fxc 'validate_sender_complete() {' "$function_source")" -eq 1 ]]

run_marker_case() {
    local case_expected_hash=$1
    local case_expected_metadata=$2
    local case_expected_status=$3
    local case_marker=$4
    local case_status=0

    (
        expected_sender_complete_sha256=$case_expected_hash
        # Used by the dynamically sourced production function.
        # shellcheck disable=SC2034
        readonly expected_sender_complete_sha256
        # Called by the dynamically sourced production function.
        # shellcheck disable=SC2317
        file_hash() {
            sha256sum "$1" | awk '{ print $1 }'
        }
        # Called by the dynamically sourced production function.
        # shellcheck disable=SC2317
        require_check() {
            shift
            "$@"
        }
        # shellcheck disable=SC1090
        source "$function_source"
        validate_sender_complete fixture "$case_marker" \
            "$case_expected_metadata" >/dev/null
    ) || case_status=$?
    [[ "$case_status" -eq "$case_expected_status" ]]
}

readonly marker_fixture="$regression_root/sender.complete"
: >"$marker_fixture"
chmod 0440 "$marker_fixture"
marker_metadata=$(stat -c '%U:%G:%a' "$marker_fixture")
readonly marker_metadata
run_marker_case "$sender_complete_sha256" "$marker_metadata" 0 "$marker_fixture"
printf 'action_18b_retry_false_negative_valid_sender_marker_accepted=true\n'

chmod 0640 "$marker_fixture"
printf 'not-empty\n' >"$marker_fixture"
chmod 0440 "$marker_fixture"
run_marker_case "$sender_complete_sha256" "$marker_metadata" 1 "$marker_fixture"
printf 'action_18b_retry_false_positive_nonempty_sender_marker_rejected=true\n'

chmod 0640 "$marker_fixture"
: >"$marker_fixture"
run_marker_case "$sender_complete_sha256" "$marker_metadata" 1 "$marker_fixture"
printf 'action_18b_retry_false_positive_wrong_metadata_rejected=true\n'

chmod 0440 "$marker_fixture"
run_marker_case aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa \
    "$marker_metadata" 1 "$marker_fixture"
printf 'action_18b_retry_false_positive_wrong_hash_rejected=true\n'

ln -s "$marker_fixture" "$regression_root/sender.complete.link"
run_marker_case "$sender_complete_sha256" "$marker_metadata" 1 \
    "$regression_root/sender.complete.link"
printf 'action_18b_retry_false_positive_symlink_sender_marker_rejected=true\n'

run_marker_case "$sender_complete_sha256" "$marker_metadata" 1 \
    "$regression_root/missing.complete"
printf 'action_18b_retry_false_positive_missing_sender_marker_rejected=true\n'

readonly production_root="$regression_root/production"
install -d -m 0700 \
    "$production_root/Caddy/scripts" \
    "$production_root/Caddy/templates" \
    "$production_root/Caddy/tests" \
    "$production_root/bin"
"$derivation" --output-directory "$production_root/Caddy/scripts" >/dev/null
install -m 0755 "$receiver" "$finalizer" "$production_root/Caddy/scripts/"
install -m 0644 "$authorization_template" "$production_root/Caddy/templates/"
install -m 0755 "$collision_checker" "$production_root/Caddy/tests/"
readonly case_runner="$production_root/Caddy/scripts/run-node-a-action18-prerequisite-action18b-retry.sh"
write_fake_ssh "$production_root/bin/ssh"
sed -i "s|^PATH=/usr/bin:/bin$|PATH=$production_root/bin:/usr/bin:/bin|" \
    "$case_runner"
chmod 0755 "$case_runner"
: >"$production_root/empty.err"
write_success_fixture "$production_root/success.fixture"

run_intercepted_case "$production_root/empty.err" \
    "$production_root/success.fixture" "$production_root" \
    "$case_runner" 0 success
[[ "$intercepted_status" -eq 0 ]]
grep -Fxq action_18b_retry_runner_acceptance=true \
    "$production_root/success.out"
grep -Fxq action_18b_retry_workstation_cleanup_complete=true \
    "$production_root/success.out"
grep -Fq 'pi@10.1.0.53' "$production_root/success.arguments"
grep -Fq 'HostKeyAlias=pihole0.local.theama.co' \
    "$production_root/success.arguments"
grep -Fq ACTION18B_RETRY_ARCHIVE "$production_root/success.bundle"

awk '/<<.*ACTION18B_RETRY_ARCHIVE/ { capture = 1; next }
    capture && /^ACTION18B_RETRY_ARCHIVE$/ { exit }
    capture { print }' "$production_root/success.bundle" |
    base64 -d >"$production_root/payload.tar"
tar -xf "$production_root/payload.tar" -C "$production_root"
require_hash bundled_installer_hash_exact \
    "$production_root/install-node-a-action18-prerequisite-action18b-retry.sh" \
    "$rendered_installer_sha256"

cp "$production_root/success.fixture" "$production_root/contradiction.fixture"
printf 'action_18b_retry_finalizer_invoked=true\n' \
    >>"$production_root/contradiction.fixture"
run_intercepted_case "$production_root/empty.err" \
    "$production_root/contradiction.fixture" "$production_root" \
    "$case_runner" 0 contradiction
[[ "$intercepted_status" -eq 97 ]]

printf 'action_18b_retry_mutation_started=true\n' \
    >"$production_root/rollback.out.fixture"
printf '%s\n' \
    action_18b_retry_rollback_started=true \
    action_18b_retry_rollback_complete=true \
    >"$production_root/rollback.err.fixture"
run_intercepted_case "$production_root/rollback.err.fixture" \
    "$production_root/rollback.out.fixture" "$production_root" \
    "$case_runner" 1 rollback
[[ "$intercepted_status" -eq 1 ]]
grep -Fxq action_18b_retry_runner_acceptance=false \
    "$production_root/rollback.out"
printf 'action_18b_retry_false_negative_valid_success_accepted=true\n'
printf 'action_18b_retry_false_negative_complete_rollback_preserved=true\n'
printf 'action_18b_retry_false_positive_contradiction_rejected=true\n'
printf 'action_18b_retry_regression_assertion_intercepted_production_path=true\n'

printf 'action_18b_retry_production_path_network_contact=false\n'
printf 'action_18b_retry_node_a_prerequisite_regression_complete=true\n'
