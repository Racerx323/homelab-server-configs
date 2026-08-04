#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_19b_retry
readonly health_sha256=c3bc1c080cd148efc0a64440a2a411ec115d0ca83f8e6a66220d7bd201971414
readonly notification_sha256=5862b494301f972d039477d4ed93a7d56156b141cba31c41ccd61d7f843321d8
readonly inspector_sha256=162f153d116e53aba95775836c4a5cb6677ad7fd080c673ca6c5ac8fb0092a0f
readonly continuity_inspector_sha256=a9a92b4007e7b6a0798a76fd57bdd23771970e23d1e486e76b66f6408eb92c55
readonly continuity_regression_sha256=4d88f027bc4063f5e781c33073312338189ac6e98a51ab2b63aff7ca02bab42d
readonly installer_sha256=8e049e2177038c33cd7f0b8f6d6c77b02bb7117b13fa4b3a76f7022f8e3cbad9
readonly runner_sha256=ce889307caf1370145153a5eeee1ee2837f46784d61c518627e72f44596355ad
readonly historical_installer_sha256=d9c99084b6c36c962d310b2072e0194aab891e6db140fedffa9d2942eb4e00ff
readonly historical_runner_sha256=5e3d776766747aad602613c587a49f281f19ae87a7609eb25b904e9c30a0812b
readonly historical_outer_sha256=dc6df0735496581c2586fda5387377ffc5e80ac246e7140354ac80c5f2f5d66d
readonly historical_regression_sha256=36521cd047dfdfedab47fb1a6faa819ea96a31e9435129fc2a1ce81c6c8e27f3

script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
readonly caddy_root=${script_directory%/tests}
readonly repository_root=${caddy_root%/Caddy}
readonly health_source="$caddy_root/scripts/check-caddy.sh"
readonly notification_source="$caddy_root/scripts/lsyncd-ha-failover-notify.sh"
readonly inspector="$caddy_root/scripts/inspect-node-b-keepalived-helper-prerequisite-action19a-a.sh"
readonly continuity_inspector="$caddy_root/scripts/inspect-node-b-action19b-postfailure-action19b-a-retry2.sh"
readonly continuity_regression="$script_directory/action19b-a-retry2-node-b-postfailure-regression.sh"
readonly installer="$caddy_root/scripts/install-node-b-keepalived-helpers-action19b-retry.sh"
readonly runner="$caddy_root/scripts/run-node-b-keepalived-helper-install-action19b-retry.sh"
readonly historical_installer="$caddy_root/scripts/install-node-b-keepalived-helpers-action19b.sh"
readonly historical_runner="$caddy_root/scripts/run-node-b-keepalived-helper-install-action19b.sh"
readonly historical_outer="$caddy_root/scripts/run-node-b-keepalived-helper-install-action19b-outer.sh"
readonly historical_regression="$script_directory/action19b-node-b-keepalived-helper-install-regression.sh"
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

write_fake_ssh() {
    local fake_path=$1

    # The fake captures the production remote script and returns fixtures.
    # shellcheck disable=SC2016
    printf '%s\n' \
        '#!/usr/bin/env bash' \
        'set -euo pipefail' \
        'printf '\''%s\n'\'' "$@" >"$ACTION19B_SSH_ARGUMENTS"' \
        'cat >"$ACTION19B_CAPTURED_BUNDLE"' \
        'cat "$ACTION19B_FIXTURE_OUTPUT"' \
        'cat "$ACTION19B_FIXTURE_ERROR" >&2' \
        'exit "$ACTION19B_FIXTURE_STATUS"' >"$fake_path"
    chmod 0755 "$fake_path"
}

run_intercepted_case() {
    local case_error=$1
    local case_output=$2
    local case_root=$3
    local intercepted_runner=$4
    local case_status=$5
    local case_suffix=$6

    intercepted_status=0
    (
        cd -- "$repository_root"
        ACTION19B_CAPTURED_BUNDLE="$case_root/$case_suffix.bundle" \
            ACTION19B_SSH_ARGUMENTS="$case_root/$case_suffix.arguments" \
            ACTION19B_FIXTURE_OUTPUT="$case_output" \
            ACTION19B_FIXTURE_ERROR="$case_error" \
            ACTION19B_FIXTURE_STATUS="$case_status" \
            "$intercepted_runner"
    ) >"$case_root/$case_suffix.out" \
        2>"$case_root/$case_suffix.err" || intercepted_status=$?
}

regression_root=$(mktemp -d /tmp/caddy-action19b-retry-regression.XXXXXX)
readonly regression_root
cleanup() {
    # shellcheck disable=SC2317
    rm -rf -- "$regression_root"
}
trap cleanup EXIT

require_gate health_source_hash_exact test "$(file_hash "$health_source")" = \
    "$health_sha256"
require_gate notification_source_hash_exact \
    test "$(file_hash "$notification_source")" = "$notification_sha256"
require_gate inspector_hash_exact test "$(file_hash "$inspector")" = \
    "$inspector_sha256"
require_gate continuity_inspector_hash_exact \
    test "$(file_hash "$continuity_inspector")" = \
    "$continuity_inspector_sha256"
require_gate continuity_regression_hash_exact \
    test "$(file_hash "$continuity_regression")" = \
    "$continuity_regression_sha256"
require_gate installer_hash_exact test "$(file_hash "$installer")" = \
    "$installer_sha256"
require_gate runner_hash_exact test "$(file_hash "$runner")" = "$runner_sha256"
require_gate historical_installer_immutable \
    test "$(file_hash "$historical_installer")" = \
    "$historical_installer_sha256"
require_gate historical_runner_immutable \
    test "$(file_hash "$historical_runner")" = "$historical_runner_sha256"
require_gate historical_outer_immutable \
    test "$(file_hash "$historical_outer")" = "$historical_outer_sha256"
require_gate historical_regression_immutable \
    test "$(file_hash "$historical_regression")" = \
    "$historical_regression_sha256"
require_gate sources_syntax bash -n "$health_source" "$notification_source" \
    "$inspector" "$continuity_inspector" "$installer" "$runner" \
    "$continuity_regression"
require_gate sources_shellcheck shellcheck "$continuity_inspector" "$installer" \
    "$runner" "$continuity_regression"
require_gate readonly_local_collision_absent \
    "$collision_checker" "$continuity_inspector" "$installer" "$runner" \
    "$continuity_regression"
require_gate accepted_continuity_regression "$continuity_regression"
require_gate installer_self_test "$installer" --self-test
require_gate runner_self_test "$runner" --self-test
require_gate runner_contract_test "$runner" --contract-test

require_gate health_target_exact grep -Fq \
    'readonly health_target=/usr/local/libexec/check-caddy.sh' "$installer"
require_gate notification_target_exact grep -Fq \
    'readonly notification_target=/usr/local/libexec/lsyncd-ha-failover-notify.sh' \
    "$installer"
require_gate health_absence_precondition grep -Fq \
    'action19b_a_retry2_status_zero' "$installer"
require_gate accepted_continuity_invocation_exact grep -Fq \
    'inspect-node-b-action19b-postfailure-action19b-a-retry2.sh' "$installer"
# The following three strings are literal producer-source expressions.
# shellcheck disable=SC2016
require_gate actual_producer_assertion_grammar grep -Fq \
    '${baseline_prefix}_assertion_state_unchanged=true' \
    "$continuity_inspector"
# shellcheck disable=SC2016
require_gate actual_producer_helper_marker grep -Fq \
    '${baseline_prefix}_helper_execution=false' "$continuity_inspector"
# shellcheck disable=SC2016
require_gate actual_producer_persistent_marker grep -Fq \
    '${baseline_prefix}_persistent_mutations=false' "$continuity_inspector"
require_gate invented_producer_check_grammar_absent test \
    "$(grep -Ec 'action_19a_a_check_' "$installer" || true)" -eq 0
# These assertions deliberately match literal production-source variables.
# shellcheck disable=SC2016
require_gate baseline_assertion_count_exact grep -Fq \
    'test "$assertion_count" -eq 89' "$installer"
# shellcheck disable=SC2016
require_gate health_hash_postcondition grep -Fq \
    'validate_installed_helper "$expected_health_sha256" health' "$installer"
# shellcheck disable=SC2016
require_gate notification_hash_postcondition grep -Fq \
    'validate_installed_helper "$expected_notification_sha256" notification' \
    "$installer"
require_gate helper_invocation_prohibited grep -Fq \
    "printf '%s_helpers_invoked=false" "$installer"
require_gate fragment_mutation_prohibited grep -Fq \
    "printf '%s_fragment_mutated=false" "$installer"
require_gate keepalived_mutation_prohibited grep -Fq \
    "printf '%s_keepalived_mutated=false" "$installer"
require_gate vrrp_mutation_prohibited grep -Fq \
    "printf '%s_vrrp_mutated=false" "$installer"
require_gate vip_mutation_prohibited grep -Fq \
    "printf '%s_vip_mutated=false" "$installer"
require_gate service_mutation_prohibited grep -Fq \
    "printf '%s_service_mutations=false" "$installer"
require_gate mutation_scope_exact grep -Fq \
    "printf '%s_persistent_mutation_scope=two_helpers,rollback_backup" \
    "$installer"
require_gate retry_backup_namespace_exact grep -Fq \
    'action19b-retry-node-b-keepalived-helpers.XXXXXX' "$installer"
require_gate retry_health_stage_namespace_exact grep -Fq \
    '.check-caddy.action19b-retry.XXXXXX' "$installer"
require_gate retry_notification_stage_namespace_exact grep -Fq \
    '.lsyncd-ha-failover-notify.action19b-retry.XXXXXX' "$installer"
require_gate retry_remote_bundle_namespace_exact grep -Fq \
    'caddy-action19b-retry-stage.XXXXXX' "$runner"
# Dollar-prefixed names are literal production-source references.
# shellcheck disable=SC2016
require_gate health_target_reference_count_exact \
    test "$(grep -Foc '$health_target' "$installer")" -eq 4
# shellcheck disable=SC2016
require_gate notification_target_reference_count_exact \
    test "$(grep -Foc '$notification_target' "$installer")" -eq 5
if grep -Eq 'systemctl[[:space:]]+(start|stop|restart|reload|enable|disable|mask|unmask)|keepalived[[:space:]]+(-t|--config-test)|ip[[:space:]]+(address|addr)[[:space:]]+(add|delete|del)' \
    "$installer"; then
    printf '%s_regression_forbidden_live_command_absent=false\n' "$prefix" >&2
    exit 1
fi
printf '%s_regression_forbidden_live_command_absent=true\n' "$prefix"

preflight_line=$(grep -n "printf '%s_preflight_complete=true" "$installer" |
    cut -d: -f1)
mutation_line=$(grep -n "printf '%s_mutation_started=true" "$installer" |
    cut -d: -f1)
# Literal production-source variables must not expand in this regression.
# shellcheck disable=SC2016
health_move_line=$(grep -n 'mv -- "$health_install_stage" "$health_target"' \
    "$installer" | cut -d: -f1)
# shellcheck disable=SC2016
notification_move_line=$(grep -n \
    'mv -- "$notification_install_stage" "$notification_target"' \
    "$installer" | cut -d: -f1)
complete_line=$(grep -n "printf '%s_install_complete=true" "$installer" |
    cut -d: -f1)
require_gate transaction_preflight_before_mutation \
    test "$preflight_line" -lt "$mutation_line"
require_gate mutation_before_health_install \
    test "$mutation_line" -lt "$health_move_line"
require_gate health_before_notification_install \
    test "$health_move_line" -lt "$notification_move_line"
require_gate installs_before_completion \
    test "$notification_move_line" -lt "$complete_line"

readonly production_root="$regression_root/production"
install -d -m 0700 "$production_root/Caddy/scripts" \
    "$production_root/Caddy/tests" "$production_root/bin"
install -m 0755 "$health_source" "$notification_source" "$inspector" \
    "$continuity_inspector" "$installer" "$runner" \
    "$production_root/Caddy/scripts/"
install -m 0755 "$collision_checker" "$continuity_regression" \
    "$production_root/Caddy/tests/"
readonly case_runner="$production_root/Caddy/scripts/run-node-b-keepalived-helper-install-action19b-retry.sh"
write_fake_ssh "$production_root/bin/ssh"
sed -i "s|^PATH=/usr/bin:/bin$|PATH=$production_root/bin:/usr/bin:/bin|" \
    "$case_runner"
chmod 0755 "$case_runner"
: >"$production_root/empty.err"
write_success_fixture "$production_root/success.fixture"

run_intercepted_case "$production_root/empty.err" \
    "$production_root/success.fixture" "$production_root" "$case_runner" \
    0 success
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
require_gate remote_working_directory_root grep -Fq \
    "'cd / && sudo -n bash -s'" "$runner"
require_gate bundle_stage_cleanup_armed grep -Fq \
    'trap cleanup_bundle_stage EXIT' "$production_root/success.bundle"

awk '/<<.*ACTION19B_ARCHIVE/ { capture = 1; next }
    capture && /^ACTION19B_ARCHIVE$/ { exit }
    capture { print }' "$production_root/success.bundle" |
    base64 -d >"$production_root/payload.tar"
tar -xf "$production_root/payload.tar" -C "$production_root"
require_gate bundled_health_hash_exact \
    test "$(file_hash "$production_root/check-caddy.sh")" = "$health_sha256"
require_gate bundled_notification_hash_exact \
    test "$(file_hash "$production_root/lsyncd-ha-failover-notify.sh")" = \
    "$notification_sha256"
require_gate bundled_inspector_hash_exact \
    test "$(file_hash "$production_root/inspect-node-b-keepalived-helper-prerequisite-action19a-a.sh")" = \
    "$inspector_sha256"
require_gate bundled_continuity_inspector_hash_exact \
    test "$(file_hash \
        "$production_root/inspect-node-b-action19b-postfailure-action19b-a-retry2.sh")" = \
    "$continuity_inspector_sha256"
require_gate bundled_installer_hash_exact \
    test "$(file_hash "$production_root/install-node-b-keepalived-helpers-action19b-retry.sh")" = \
    "$installer_sha256"

cp "$production_root/success.fixture" "$production_root/contradiction.fixture"
printf '%s_helpers_invoked=true\n' "$prefix" \
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

cp "$production_root/success.fixture" "$production_root/duplicate.fixture"
printf '%s_install_complete=true\n' "$prefix" \
    >>"$production_root/duplicate.fixture"
run_intercepted_case "$production_root/empty.err" \
    "$production_root/duplicate.fixture" "$production_root" \
    "$case_runner" 0 duplicate
require_gate false_positive_duplicate_marker_rejected \
    test "$intercepted_status" -eq 97

printf '%s_mutation_started=true\n' "$prefix" \
    >"$production_root/rollback.fixture"
printf '%s\n' "${prefix}_rollback_started=true" \
    "${prefix}_rollback_complete=true" \
    >"$production_root/rollback.stderr.fixture"
run_intercepted_case "$production_root/rollback.stderr.fixture" \
    "$production_root/rollback.fixture" "$production_root" "$case_runner" \
    1 rollback
require_gate false_negative_complete_rollback_preserved \
    test "$intercepted_status" -eq 1

printf '%s\n' "${prefix}_rollback_started=true" \
    "${prefix}_rollback_complete=false" \
    "${prefix}_manual_intervention_required=true" \
    >"$production_root/incomplete-rollback.stderr.fixture"
run_intercepted_case "$production_root/incomplete-rollback.stderr.fixture" \
    "$production_root/rollback.fixture" "$production_root" "$case_runner" \
    125 incomplete-rollback
require_gate false_positive_incomplete_rollback_rejected \
    test "$intercepted_status" -eq 97

printf '%s\n' '-----BEGIN PRIVATE KEY-----' \
    >"$production_root/unsafe.stderr.fixture"
run_intercepted_case "$production_root/unsafe.stderr.fixture" \
    "$production_root/success.fixture" "$production_root" "$case_runner" \
    0 unsafe
require_gate unsafe_stream_rejected test "$intercepted_status" -eq 97
protected_path=$(sed -n \
    "s/^${prefix}_protected_evidence=//p" "$production_root/unsafe.err")
require_gate unsafe_stream_evidence_retained test -d "$protected_path"
rm -rf -- "$protected_path"

printf '%s_regression_complete=true\n' "$prefix"
