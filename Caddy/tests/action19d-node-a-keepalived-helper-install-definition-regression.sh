#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_19d_definition_regression
readonly derivation_sha256=c46a1c9d028dcf84dbb6061bc0ee31f2527013ad4bd178a1d6fd10bc2dfa4a87
readonly inspector_sha256=57e3bf9d9ae61b4e2b6017118481f492bd29c5784e74710a367b620230e0bea9
readonly installer_sha256=5a6b6d5489db0374d57827c1d92c5a8a8f2ae27b7181a9c30795d5c0cc8cf88d
readonly labels_sha256=48ce4d7b87142372156e5ab14b1b6a6e153eada1f3e4ca1a5a2163037714801c
readonly runner_sha256=a91a94af9ce696c0f38bb0a95cc35033a78e178d16cade48805f74211a9dd0e4

test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
readonly caddy_root=${test_directory%/tests}
readonly repository_root=${caddy_root%/Caddy}
readonly derivation="$caddy_root/scripts/derive-node-a-keepalived-helper-install-action19d.sh"
readonly health_source="$caddy_root/scripts/check-caddy.sh"
readonly notification_source="$caddy_root/scripts/lsyncd-ha-failover-notify.sh"
readonly collision_checker="$test_directory/check-shell-readonly-local-collisions-v2.sh"

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }

require_gate() {
    local gate_label=$1

    shift
    if "$@"; then
        printf '%s_%s=true\n' "$prefix" "$gate_label"
        return 0
    fi
    printf '%s_%s=false\n' "$prefix" "$gate_label" >&2
    return 1
}

conditional_fixture_valid() {
    local fixture_path=$1

    # conditional-validator-explicit-failures-begin
    grep -Fxq 'first=valid' "$fixture_path" || return 1
    grep -Fxq 'second=valid' "$fixture_path" || return 1
    # conditional-validator-explicit-failures-end
    return 0
}

write_fake_ssh() {
    local fake_path=$1

    # shellcheck disable=SC2016
    printf '%s\n' \
        '#!/usr/bin/env bash' \
        'set -Eeuo pipefail' \
        'set +x' \
        'printf '\''%s\n'\'' "$@" >"$ACTION19D_SSH_ARGUMENTS"' \
        'cat >"$ACTION19D_CAPTURED_BUNDLE"' \
        'cat "$ACTION19D_FIXTURE_OUTPUT"' \
        'cat "$ACTION19D_FIXTURE_ERROR" >&2' \
        'exit "$ACTION19D_FIXTURE_STATUS"' >"$fake_path"
    chmod 0755 "$fake_path"
}

write_success_fixture() {
    local fixture_labels=$1
    local fixture_path=$2

    sed 's/$/=true/' "$fixture_labels" >"$fixture_path"
    printf '%s\n' \
        'action_19d_preflight_complete=true' \
        'action_19d_mutation_started=true' \
        'action_19d_helpers_invoked=false' \
        'action_19d_fragment_mutated=false' \
        'action_19d_keepalived_mutated=false' \
        'action_19d_vrrp_mutated=false' \
        'action_19d_vip_mutated=false' \
        'action_19d_service_mutations=false' \
        'action_19d_backup_path=/var/backups/caddy-ha/action19d-node-a-keepalived-helpers.ABC123' \
        'action_19d_persistent_mutation_scope=two_helpers,rollback_backup' \
        'action_19d_install_complete=true' >>"$fixture_path"
}

run_intercepted_case() {
    local case_error=$1
    local case_output=$2
    local case_root=$3
    local intercepted_runner_path=$4
    local case_status=$5
    local case_suffix=$6

    intercepted_status=0
    (
        cd -- "$repository_root"
        ACTION19D_CAPTURED_BUNDLE="$case_root/$case_suffix.bundle" \
            ACTION19D_SSH_ARGUMENTS="$case_root/$case_suffix.arguments" \
            ACTION19D_FIXTURE_OUTPUT="$case_output" \
            ACTION19D_FIXTURE_ERROR="$case_error" \
            ACTION19D_FIXTURE_STATUS="$case_status" \
            /bin/bash "$intercepted_runner_path"
    ) >"$case_root/$case_suffix.out" \
        2>"$case_root/$case_suffix.err" || intercepted_status=$?
}

require_gate self_collision_policy "$collision_checker" "${BASH_SOURCE[0]}"

regression_root=$(mktemp -d /tmp/caddy-action19d-definition.XXXXXX)
readonly regression_root
# shellcheck disable=SC2317
cleanup() { rm -rf -- "$regression_root"; }
trap cleanup EXIT

readonly collision_fixture="$regression_root/collision.sh"
printf '%s\n' \
    '#!/usr/bin/env bash' \
    'readonly collision_name=outer' \
    'collision_function() {' \
    '    local collision_name=inner' \
    '    :' \
    '}' \
    'collision_function' >"$collision_fixture"
chmod 0755 "$collision_fixture"
if "$collision_checker" "$collision_fixture" >/dev/null 2>&1; then
    printf '%s_dynamic_scope_collision_rejected=false\n' "$prefix" >&2
    exit 1
fi
printf '%s_dynamic_scope_collision_rejected=true\n' "$prefix"

readonly conditional_invalid="$regression_root/conditional-invalid.txt"
readonly conditional_valid="$regression_root/conditional-valid.txt"
printf '%s\n' first=invalid second=valid >"$conditional_invalid"
printf '%s\n' first=valid second=valid >"$conditional_valid"
if conditional_fixture_valid "$conditional_invalid"; then
    printf '%s_early_invalid_later_valid_rejected=false\n' "$prefix" >&2
    exit 1
fi
printf '%s_early_invalid_later_valid_rejected=true\n' "$prefix"
require_gate valid_conditional_fixture_accepted \
    conditional_fixture_valid "$conditional_valid"

readonly render_root="$regression_root/render"
install -d -m 0700 "$render_root/Caddy/scripts" "$render_root/Caddy/tests"
/bin/bash "$derivation" --output "$render_root/Caddy/scripts" >/dev/null
install -m 0755 "$health_source" "$notification_source" \
    "$render_root/Caddy/scripts/"
install -m 0755 "$collision_checker" "$render_root/Caddy/tests/"

readonly inspector="$render_root/Caddy/scripts/inspect-node-a-keepalived-prerequisite-action19c-a.sh"
readonly installer="$render_root/Caddy/scripts/install-node-a-keepalived-helpers-action19d.sh"
readonly labels="$render_root/Caddy/scripts/action19d-node-a-keepalived-helper-check-labels.txt"
readonly runner="$render_root/Caddy/scripts/run-node-a-keepalived-helper-install-action19d.sh"

require_gate derivation_hash_exact test "$(file_hash "$derivation")" = \
    "$derivation_sha256"
require_gate inspector_hash_exact test "$(file_hash "$inspector")" = \
    "$inspector_sha256"
require_gate installer_hash_exact test "$(file_hash "$installer")" = \
    "$installer_sha256"
require_gate labels_hash_exact test "$(file_hash "$labels")" = "$labels_sha256"
require_gate runner_hash_exact test "$(file_hash "$runner")" = "$runner_sha256"
require_gate rendered_syntax bash -n "$inspector" "$installer" "$runner"
require_gate rendered_shellcheck shellcheck "$inspector" "$installer" "$runner"
require_gate rendered_collision_policy "$collision_checker" \
    "$inspector" "$installer" "$runner"
require_gate installer_self_test /bin/bash "$installer" --self-test
require_gate runner_self_test /bin/bash "$runner" --self-test
require_gate runner_contract_test /bin/bash "$runner" --contract-test
require_gate exact_label_count test "$(wc -l <"$labels")" -eq 140
require_gate exact_label_inventory_unique test \
    "$(LC_ALL=C sort -u "$labels" | wc -l)" -eq 140
# The expression is a literal unsafe production pattern.
# shellcheck disable=SC2016
require_gate arbitrary_minimum_absent test \
    "$(grep -Ec '\[\[ "\$check_count" -ge [0-9]+' "$runner" || true)" -eq 0
require_gate synthetic_check_fixture_absent test \
    "$(grep -Ec 'check_fixture_|seq 1 [0-9]+' "$runner" || true)" -eq 0
# The following two expressions are literal production-source contracts.
# shellcheck disable=SC2016
require_gate producer_inventory_comparison_present grep -Fq \
    'cmp -s "$expected_labels"' "$runner"
# shellcheck disable=SC2016
require_gate node_a_hostname_exact grep -Fq \
    'hostname_node_a test "$(hostname)" = j1-svpihole0' "$installer"
require_gate node_a_target_exact grep -Fq \
    'readonly expected_target=pi@10.1.0.53' "$runner"
require_gate node_a_host_alias_exact grep -Fq \
    'readonly expected_host_alias=pihole0.local.theama.co' "$runner"
# Multiple source files require suppressing grep's filename-prefixed counts.
# shellcheck disable=SC2126
require_gate node_b_identity_absent test \
    "$(grep -Eih 'j1-svpihole00|10\.1\.0\.54|::54|pihole00\.' \
        "$installer" "$runner" | wc -l)" -eq 0
require_gate health_target_exact grep -Fq \
    'readonly health_target=/usr/local/libexec/check-caddy.sh' "$installer"
require_gate notification_target_exact grep -Fq \
    'readonly notification_target=/usr/local/libexec/lsyncd-ha-failover-notify.sh' \
    "$installer"
require_gate accepted_preflight_exact grep -Fq \
    'inspect-node-a-keepalived-prerequisite-action19c-a.sh' "$installer"
require_gate helpers_not_invoked grep -Fq \
    "printf '%s_helpers_invoked=false" "$installer"
require_gate mutation_scope_exact grep -Fq \
    'persistent_mutation_scope=two_helpers,rollback_backup' "$installer"
require_gate backup_namespace_exact grep -Fq \
    'action19d-node-a-keepalived-helpers.XXXXXX' "$installer"
require_gate fragment_install_absent test \
    "$(grep -Ec 'install .*caddy-ha\.conf|mv .*caddy-ha\.conf' "$installer" || true)" -eq 0
require_gate forbidden_live_service_command_absent test \
    "$(grep -Ec 'systemctl[[:space:]]+(start|stop|restart|reload|enable|disable|mask|unmask)' \
        "$installer" || true)" -eq 0
require_gate forbidden_ip_mutation_absent test \
    "$(grep -Ec 'ip[[:space:]]+(address|addr)[[:space:]]+(add|delete|del|replace)' \
        "$installer" || true)" -eq 0

readonly production_root="$regression_root/production"
install -d -m 0700 "$production_root/Caddy/scripts" \
    "$production_root/Caddy/tests" "$production_root/bin"
install -m 0755 "$health_source" "$notification_source" "$inspector" \
    "$installer" "$runner" "$production_root/Caddy/scripts/"
install -m 0644 "$labels" "$production_root/Caddy/scripts/"
install -m 0755 "$collision_checker" "$production_root/Caddy/tests/"
readonly case_runner="$production_root/Caddy/scripts/run-node-a-keepalived-helper-install-action19d.sh"
write_fake_ssh "$production_root/bin/ssh"
sed -i "s|^PATH=/usr/bin:/bin$|PATH=$production_root/bin:/usr/bin:/bin|" \
    "$case_runner"
chmod 0755 "$case_runner"
readonly empty_error="$production_root/empty.err"
readonly success_fixture="$production_root/success.fixture"
: >"$empty_error"
write_success_fixture "$labels" "$success_fixture"

run_intercepted_case "$empty_error" "$success_fixture" "$production_root" \
    "$case_runner" 0 success
require_gate valid_production_path_accepted test "$intercepted_status" -eq 0
require_gate valid_runner_acceptance grep -Fxq \
    'action_19d_runner_acceptance=true' "$production_root/success.out"
require_gate valid_cleanup_complete grep -Fxq \
    'action_19d_workstation_cleanup_complete=true' \
    "$production_root/success.out"
require_gate administrative_target_exact grep -Fxq 'pi@10.1.0.53' \
    "$production_root/success.arguments"
require_gate administrative_alias_exact grep -Fxq \
    'HostKeyAlias=pihole0.local.theama.co' \
    "$production_root/success.arguments"
require_gate pseudo_terminal_suppressed grep -Fxq -- '-T' \
    "$production_root/success.arguments"
require_gate remote_working_directory_root grep -Fq \
    "'cd / && sudo -n bash -s'" "$runner"
require_gate remote_bundle_uses_explicit_bash grep -Fq \
    '/bin/bash' "$production_root/success.bundle"

cp -- "$success_fixture" "$production_root/missing.fixture"
sed -i '/action_19d_check_identity_root=true/d' \
    "$production_root/missing.fixture"
run_intercepted_case "$empty_error" "$production_root/missing.fixture" \
    "$production_root" "$case_runner" 0 missing
require_gate false_positive_missing_label_rejected test "$intercepted_status" -eq 97

cp -- "$success_fixture" "$production_root/duplicate.fixture"
printf '%s\n' action_19d_check_identity_root=true \
    >>"$production_root/duplicate.fixture"
run_intercepted_case "$empty_error" "$production_root/duplicate.fixture" \
    "$production_root" "$case_runner" 0 duplicate
require_gate false_positive_duplicate_label_rejected test \
    "$intercepted_status" -eq 97

cp -- "$success_fixture" "$production_root/unexpected.fixture"
printf '%s\n' action_19d_check_unexpected=true \
    >>"$production_root/unexpected.fixture"
run_intercepted_case "$empty_error" "$production_root/unexpected.fixture" \
    "$production_root" "$case_runner" 0 unexpected
require_gate false_positive_unexpected_label_rejected test \
    "$intercepted_status" -eq 97

printf '%s\n' action_19d_mutation_started=true \
    >"$production_root/rollback.fixture"
printf '%s\n' action_19d_rollback_started=true \
    action_19d_rollback_complete=true >"$production_root/rollback.remote.err"
run_intercepted_case "$production_root/rollback.remote.err" \
    "$production_root/rollback.fixture" "$production_root" "$case_runner" \
    1 rollback
printf '%s_rollback_observed_status=%s\n' "$prefix" "$intercepted_status"
require_gate false_negative_complete_rollback_preserved test \
    "$intercepted_status" -eq 1

printf '%s\n' '-----BEGIN PRIVATE KEY-----' \
    >"$production_root/unsafe.err.fixture"
run_intercepted_case "$production_root/unsafe.err.fixture" "$success_fixture" \
    "$production_root" "$case_runner" 0 unsafe
require_gate unsafe_stream_rejected test "$intercepted_status" -eq 97
protected_path=$(sed -n \
    's/^action_19d_protected_evidence=//p' "$production_root/unsafe.err")
require_gate unsafe_stream_evidence_retained test -d "$protected_path"
rm -rf -- "$protected_path"

require_gate production_path_network_contact_false test \
    "$(find "$production_root" -name '*.arguments' | wc -l)" -eq 6
printf '%s_complete=true\n' "$prefix"
