#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_19b_a
readonly baseline_sha256=162f153d116e53aba95775836c4a5cb6677ad7fd080c673ca6c5ac8fb0092a0f
readonly inspector_sha256=71159ea5e0fa7c62f984ebe47742d9d0f235d570d3be948406ed93ad20cfe544
readonly runner_sha256=f865fc624d2fa10adb7c95d7dbc9570bef848dabb9281f31b78e4dd7595c72e5
readonly expected_assertions=88

script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
readonly caddy_root=${script_directory%/tests}
readonly repository_root=${caddy_root%/Caddy}
readonly baseline="$caddy_root/scripts/inspect-node-b-keepalived-helper-prerequisite-action19a-a.sh"
readonly inspector="$caddy_root/scripts/inspect-node-b-action19b-postfailure-action19b-a.sh"
readonly runner="$caddy_root/scripts/run-node-b-action19b-postfailure-action19b-a.sh"
readonly collision_checker="$script_directory/check-shell-readonly-local-collisions-v2.sh"
readonly host_suite="$script_directory/run.sh"
readonly integration_suite="$script_directory/integration.sh"

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }

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

write_fixture() {
    local fixture_path=$1
    local fixture_index

    for fixture_index in $(seq 1 "$expected_assertions"); do
        printf '%s_assertion_fixture_%03d=true\n' "$prefix" "$fixture_index"
    done >"$fixture_path"
    printf '%s\n' \
        "${prefix}_assertion_count=${expected_assertions}" \
        "${prefix}_failed_assertion_count=0" \
        "${prefix}_first_failure=none" \
        "${prefix}_helper_invoked=false" \
        "${prefix}_filesystem_mutation=false" \
        "${prefix}_service_mutation=false" \
        "${prefix}_keepalived_mutation=false" \
        "${prefix}_vrrp_vip_mutation=false" \
        "${prefix}_persistent_mutation=false" \
        "${prefix}_inspection_complete=true" >>"$fixture_path"
}

regression_root=$(mktemp -d /tmp/caddy-action19b-a-regression.XXXXXX)
readonly regression_root
cleanup() {
    # shellcheck disable=SC2317
    rm -rf -- "$regression_root"
}
trap cleanup EXIT

require_gate baseline_hash_exact test "$(file_hash "$baseline")" = \
    "$baseline_sha256"
require_gate inspector_hash_exact test "$(file_hash "$inspector")" = \
    "$inspector_sha256"
require_gate runner_hash_exact test "$(file_hash "$runner")" = "$runner_sha256"
require_gate syntax_valid bash -n "$baseline" "$inspector" "$runner"
require_gate shellcheck_clean shellcheck "$inspector" "$runner"
require_gate collision_policy_clean "$collision_checker" "$inspector" "$runner"
require_gate inspector_self_test "$inspector" --self-test "$baseline"
require_gate actual_producer_contract "$inspector" --contract-test "$baseline"
require_gate runner_self_test "$runner" --self-test
require_gate runner_contract_test "$runner" --contract-test
require_gate host_suite_inspector_self_test_signature grep -Fzq \
    $'"$caddy_root/scripts/inspect-node-b-action19b-postfailure-action19b-a.sh" \\\n    --self-test \\\n    "$caddy_root/scripts/inspect-node-b-keepalived-helper-prerequisite-action19a-a.sh"' \
    "$host_suite"
require_gate host_suite_inspector_contract_test_signature grep -Fzq \
    $'"$caddy_root/scripts/inspect-node-b-action19b-postfailure-action19b-a.sh" \\\n    --contract-test \\\n    "$caddy_root/scripts/inspect-node-b-keepalived-helper-prerequisite-action19a-a.sh"' \
    "$host_suite"
require_gate integration_suite_inspector_self_test_signature grep -Fzq \
    $'"$caddy_root/scripts/inspect-node-b-action19b-postfailure-action19b-a.sh" \\\n    --self-test \\\n    "$caddy_root/scripts/inspect-node-b-keepalived-helper-prerequisite-action19a-a.sh"' \
    "$integration_suite"
require_gate integration_suite_inspector_contract_test_signature grep -Fzq \
    $'"$caddy_root/scripts/inspect-node-b-action19b-postfailure-action19b-a.sh" \\\n    --contract-test \\\n    "$caddy_root/scripts/inspect-node-b-keepalived-helper-prerequisite-action19a-a.sh"' \
    "$integration_suite"
# These are literal producer-variable expressions in the production source.
# shellcheck disable=SC2016
require_gate producer_expected_labels_interface grep -Fq \
    '"$baseline_inspector" --expected-assertions' "$inspector"
# shellcheck disable=SC2016
require_gate actual_assertion_grammar_required grep -Fq \
    '^${baseline_prefix}_assertion_' "$inspector"
# shellcheck disable=SC2016
if grep -Fq '^${baseline_prefix}_check_' "$inspector"; then
    printf '%s_regression_invented_check_grammar_absent=false\n' "$prefix" >&2
    exit 1
fi
printf '%s_regression_invented_check_grammar_absent=true\n' "$prefix"
require_gate wrong_grammar_negative_control grep -Fq \
    "sed 's/_assertion_/_check_/'" "$inspector"
require_gate health_absence_check_present grep -Fq \
    'record_command health_target_absent' "$inspector"
require_gate notification_absence_check_present grep -Fq \
    'record_command notification_target_absent' "$inspector"
require_gate backup_absence_check_present grep -Fq \
    'record_command action19b_backup_absent' "$inspector"
require_gate health_stage_absence_check_present grep -Fq \
    'record_command action19b_health_install_stage_absent' "$inspector"
require_gate notification_stage_absence_check_present grep -Fq \
    'record_command action19b_notification_install_stage_absent' "$inspector"
require_gate remote_bundle_absence_check_present grep -Fq \
    'record_command action19b_remote_bundle_stage_absent' "$inspector"
if grep -Eq 'systemctl[[:space:]]+(start|stop|restart|reload|enable|disable|mask|unmask)|ip[[:space:]]+(address|addr)[[:space:]]+(add|delete|del)|(/etc|/usr/local|/var/backups)/[^[:space:]]+[[:space:]]*(>|>>)' \
    "$inspector"; then
    printf '%s_regression_static_read_only_scope=false\n' "$prefix" >&2
    exit 1
fi
printf '%s_regression_static_read_only_scope=true\n' "$prefix"

readonly production_root="$regression_root/production"
install -d -m 0700 "$production_root/Caddy/scripts" \
    "$production_root/Caddy/tests" "$production_root/bin"
install -m 0755 "$baseline" "$inspector" "$runner" \
    "$production_root/Caddy/scripts/"
install -m 0755 "$collision_checker" "$production_root/Caddy/tests/"
readonly production_runner="$production_root/Caddy/scripts/run-node-b-action19b-postfailure-action19b-a.sh"
cat >"$production_root/bin/ssh" <<'FAKE_SSH'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$@" >"$ACTION19B_A_SSH_ARGUMENTS"
cat >"$ACTION19B_A_CAPTURED_REMOTE"
cat "$ACTION19B_A_FIXTURE"
FAKE_SSH
chmod 0755 "$production_root/bin/ssh"
sed -i "s|^PATH=/usr/bin:/bin$|PATH=$production_root/bin:/usr/bin:/bin|" \
    "$production_runner"
chmod 0755 "$production_runner"
write_fixture "$production_root/valid.fixture"
production_status=0
(
    cd "$repository_root"
    ACTION19B_A_SSH_ARGUMENTS="$production_root/arguments" \
        ACTION19B_A_CAPTURED_REMOTE="$production_root/remote" \
        ACTION19B_A_FIXTURE="$production_root/valid.fixture" \
        "$production_runner"
) >"$production_root/stdout" 2>"$production_root/stderr" ||
    production_status=$?
require_gate production_path_accepted test "$production_status" -eq 0
require_gate production_path_stderr_empty test ! -s "$production_root/stderr"
require_gate production_target_exact grep -Fxq 'pi@10.1.0.54' \
    "$production_root/arguments"
require_gate production_host_alias_exact grep -Fxq \
    'HostKeyAlias=pihole00.local.theama.co' "$production_root/arguments"
require_gate production_network_contact_false test -s "$production_root/remote"

printf '%s_regression_complete=true\n' "$prefix"
