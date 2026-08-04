#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_18c_publisher_prerequisite
readonly publisher_sha256=e4a48f12a7324a885684a57070269a2d074d056c65d9e767db901408e0e86669
readonly installer_sha256=b26eab687ed6dc19f118d532ae14dacf85b0aa9e8a39f031bf2ed2369fe7a0a5

script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
readonly caddy_root=${script_directory%/tests}
readonly repository_root=${caddy_root%/Caddy}
readonly publisher="$caddy_root/scripts/publish-release-v2.sh"
readonly installer="$caddy_root/scripts/install-node-b-protocol-v2-publisher-action18c-prerequisite.sh"
readonly runner="$caddy_root/scripts/run-node-b-protocol-v2-publisher-install-action18c-prerequisite.sh"
readonly collision_checker="$script_directory/check-shell-readonly-local-collisions-v2.sh"

file_hash() {
    sha256sum "$1" | awk '{ print $1 }'
}

require_gate() {
    local gate_label=$1

    shift
    if "$@"; then
        printf '%s_regression_%s=true\n' "$prefix" "$gate_label"
        return 0
    fi
    printf '%s_regression_%s=false\n' "$prefix" "$gate_label" >&2
    return 1
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

write_fake_ssh() {
    local fake_path=$1

    cat >"$fake_path" <<'FAKE_SSH'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$@" >"$ACTION18C_PUBLISHER_SSH_ARGUMENTS"
cat >"$ACTION18C_PUBLISHER_CAPTURED_BUNDLE"
cat "$ACTION18C_PUBLISHER_FIXTURE_OUTPUT"
cat "$ACTION18C_PUBLISHER_FIXTURE_ERROR" >&2
exit "$ACTION18C_PUBLISHER_FIXTURE_STATUS"
FAKE_SSH
    chmod 0755 "$fake_path"
}

run_intercepted_case() {
    local case_error=$1
    local case_output=$2
    local case_root=$3
    local intercept_runner_path=$4
    local case_status=$5
    local case_suffix=$6

    intercepted_status=0
    (
        cd -- "$repository_root"
        ACTION18C_PUBLISHER_CAPTURED_BUNDLE="$case_root/$case_suffix.bundle" \
            ACTION18C_PUBLISHER_SSH_ARGUMENTS="$case_root/$case_suffix.arguments" \
            ACTION18C_PUBLISHER_FIXTURE_OUTPUT="$case_output" \
            ACTION18C_PUBLISHER_FIXTURE_ERROR="$case_error" \
            ACTION18C_PUBLISHER_FIXTURE_STATUS="$case_status" \
            "$intercept_runner_path"
    ) >"$case_root/$case_suffix.out" \
        2>"$case_root/$case_suffix.err" || intercepted_status=$?
}

regression_root=$(mktemp -d /tmp/caddy-action18c-publisher-regression.XXXXXX)
readonly regression_root
cleanup() {
    # shellcheck disable=SC2317
    rm -rf -- "$regression_root"
}
trap cleanup EXIT

require_gate publisher_hash_exact test "$(file_hash "$publisher")" = \
    "$publisher_sha256"
require_gate installer_hash_exact test "$(file_hash "$installer")" = \
    "$installer_sha256"
require_gate sources_syntax bash -n "$publisher" "$installer" "$runner"
require_gate sources_shellcheck shellcheck "$installer" "$runner"
require_gate readonly_local_collision_absent \
    "$collision_checker" "$installer" "$runner"
require_gate installer_self_test "$installer" --self-test
require_gate runner_self_test "$runner" --self-test
require_gate runner_contract_test "$runner" --contract-test

require_gate publisher_target_exact grep -Fq \
    'readonly publisher=/usr/local/libexec/publish-release-v2.sh' "$installer"
require_gate publisher_absence_precondition grep -Fq \
    'require_check live_publisher_absent' "$installer"
require_gate publisher_hash_postcondition grep -Fq \
    'require_check live_publisher_hash_exact' "$installer"
require_gate emergency_gate_validated grep -Fq \
    'Node B publishing requires --emergency.' "$installer"
require_gate master_gate_validated grep -Fq \
    'Node B may publish only while CADDY_DUALSTACK is MASTER.' "$installer"
require_gate publisher_invocation_prohibited grep -Fq \
    "printf '%s_publisher_invoked=false" "$installer"
require_gate release_mutation_prohibited grep -Fq \
    "printf '%s_release_mutated=false" "$installer"
require_gate vrrp_mutation_prohibited grep -Fq \
    "printf '%s_vrrp_mutated=false" "$installer"
require_gate service_mutation_prohibited grep -Fq \
    "printf '%s_service_mutations=false" "$installer"
require_gate mutation_scope_exact grep -Fq \
    "printf '%s_persistent_mutation_scope=publisher_v2,rollback_backup" \
    "$installer"
if grep -Eq 'systemctl[[:space:]]+(start|stop|restart|reload|enable|disable|mask|unmask)|keepalived[[:space:]]|publish-release-v2\.sh[[:space:]]+--' \
    "$installer"; then
    printf '%s_regression_forbidden_live_command_absent=false\n' "$prefix" >&2
    exit 1
fi
printf '%s_regression_forbidden_live_command_absent=true\n' "$prefix"

preflight_line=$(grep -n "printf '%s_preflight_complete=true" "$installer" |
    cut -d: -f1)
mutation_line=$(grep -n "printf '%s_mutation_started=true" "$installer" |
    cut -d: -f1)
# shellcheck disable=SC2016
install_line=$(grep -n 'mv -- "$publisher_install_stage" "$publisher"' \
    "$installer" | cut -d: -f1)
complete_line=$(grep -n "printf '%s_install_complete=true" "$installer" |
    cut -d: -f1)
require_gate transaction_phase_order \
    test "$preflight_line" -lt "$mutation_line"
require_gate mutation_precedes_install \
    test "$mutation_line" -lt "$install_line"
require_gate install_precedes_completion \
    test "$install_line" -lt "$complete_line"

readonly production_root="$regression_root/production"
install -d -m 0700 \
    "$production_root/Caddy/scripts" \
    "$production_root/Caddy/tests" \
    "$production_root/bin"
install -m 0755 "$publisher" "$installer" \
    "$production_root/Caddy/scripts/"
install -m 0755 "$collision_checker" "$production_root/Caddy/tests/"
install -m 0755 "$runner" "$production_root/Caddy/scripts/"
readonly case_runner="$production_root/Caddy/scripts/run-node-b-protocol-v2-publisher-install-action18c-prerequisite.sh"
write_fake_ssh "$production_root/bin/ssh"
sed -i "s|^PATH=/usr/bin:/bin$|PATH=$production_root/bin:/usr/bin:/bin|" \
    "$case_runner"
chmod 0755 "$case_runner"
: >"$production_root/empty.err"
write_success_fixture "$production_root/success.fixture"

run_intercepted_case "$production_root/empty.err" \
    "$production_root/success.fixture" "$production_root" \
    "$case_runner" 0 success
require_gate valid_production_path_accepted test "$intercepted_status" -eq 0
require_gate valid_runner_acceptance grep -Fxq \
    "${prefix}_runner_acceptance=true" "$production_root/success.out"
require_gate valid_cleanup_complete grep -Fxq \
    "${prefix}_workstation_cleanup_complete=true" \
    "$production_root/success.out"
require_gate administrative_target_exact grep -Fxq 'pi@10.1.0.54' \
    "$production_root/success.arguments"
require_gate administrative_host_alias_exact grep -Fxq \
    'HostKeyAlias=pihole00.local.theama.co' \
    "$production_root/success.arguments"
require_gate pseudo_terminal_suppressed grep -Fxq -- '-T' \
    "$production_root/success.arguments"
require_gate identities_only_admin_absent test \
    "$(grep -Fxc 'IdentitiesOnly=yes' \
        "$production_root/success.arguments" || true)" -eq 0
require_gate remote_working_directory_root grep -Fq \
    "'cd / && sudo -n bash -s'" "$runner"
require_gate bundle_stage_cleanup_armed grep -Fq \
    'trap cleanup_bundle_stage EXIT' "$production_root/success.bundle"

awk '/<<.*ACTION18C_PUBLISHER_ARCHIVE/ { capture = 1; next }
    capture && /^ACTION18C_PUBLISHER_ARCHIVE$/ { exit }
    capture { print }' "$production_root/success.bundle" |
    base64 -d >"$production_root/payload.tar"
tar -xf "$production_root/payload.tar" -C "$production_root"
require_gate bundled_publisher_hash_exact test \
    "$(file_hash "$production_root/publish-release-v2.sh")" = \
    "$publisher_sha256"
require_gate bundled_installer_hash_exact test \
    "$(file_hash "$production_root/install-node-b-protocol-v2-publisher-action18c-prerequisite.sh")" = \
    "$installer_sha256"

cp "$production_root/success.fixture" \
    "$production_root/contradiction.fixture"
printf '%s_publisher_invoked=true\n' "$prefix" \
    >>"$production_root/contradiction.fixture"
run_intercepted_case "$production_root/empty.err" \
    "$production_root/contradiction.fixture" "$production_root" \
    "$case_runner" 0 contradiction
require_gate false_positive_contradiction_rejected \
    test "$intercepted_status" -eq 97

grep -Fv "${prefix}_install_complete=true" \
    "$production_root/success.fixture" \
    >"$production_root/missing-marker.fixture"
run_intercepted_case "$production_root/empty.err" \
    "$production_root/missing-marker.fixture" "$production_root" \
    "$case_runner" 0 missing-marker
require_gate false_positive_missing_marker_rejected \
    test "$intercepted_status" -eq 97

printf '%s_mutation_started=true\n' "$prefix" \
    >"$production_root/rollback.fixture"
printf '%s\n' \
    "${prefix}_rollback_started=true" \
    "${prefix}_rollback_complete=true" \
    >"$production_root/rollback.stderr.fixture"
run_intercepted_case "$production_root/rollback.stderr.fixture" \
    "$production_root/rollback.fixture" "$production_root" \
    "$case_runner" 1 rollback
require_gate false_negative_complete_rollback_preserved \
    test "$intercepted_status" -eq 1

printf '%s\n' \
    "${prefix}_rollback_started=true" \
    "${prefix}_rollback_complete=false" \
    "${prefix}_manual_intervention_required=true" \
    >"$production_root/incomplete-rollback.stderr.fixture"
run_intercepted_case "$production_root/incomplete-rollback.stderr.fixture" \
    "$production_root/rollback.fixture" "$production_root" \
    "$case_runner" 125 incomplete-rollback
require_gate false_positive_incomplete_rollback_rejected \
    test "$intercepted_status" -eq 97

printf '%s\n' '-----BEGIN PRIVATE KEY-----' \
    >"$production_root/unsafe.stderr.fixture"
run_intercepted_case "$production_root/unsafe.stderr.fixture" \
    "$production_root/success.fixture" "$production_root" \
    "$case_runner" 0 unsafe
require_gate unsafe_stream_rejected test "$intercepted_status" -eq 97
protected_path=$(sed -n \
    "s/^${prefix}_protected_evidence=//p" \
    "$production_root/unsafe.err")
require_gate unsafe_evidence_path_reported test -n "$protected_path"
require_gate unsafe_evidence_retained test -d "$protected_path"
rm -rf -- "$protected_path"

printf '%s_regression_complete=true\n' "$prefix"
