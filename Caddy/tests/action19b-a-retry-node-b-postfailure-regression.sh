#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_19b_a_retry
readonly derivation_sha256=56c28070d4ce346b9b8b7778edd7882a509018954e38670f7d58df75a474ab04
readonly base_inspector_sha256=71159ea5e0fa7c62f984ebe47742d9d0f235d570d3be948406ed93ad20cfe544
readonly base_runner_sha256=f865fc624d2fa10adb7c95d7dbc9570bef848dabb9281f31b78e4dd7595c72e5
readonly rendered_inspector_sha256=69389a69710ea1ab9cd017c3723373eb7bd485d79c0ea469b8e56e9941e1104f
readonly rendered_runner_sha256=490b34a563f0975e99cff5818b6dd7318b203ee6dab66993b68b31b14651b6f2

script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
readonly caddy_root=${script_directory%/tests}
readonly repository_root=${caddy_root%/Caddy}
readonly derivation="$caddy_root/scripts/derive-node-b-action19b-postfailure-action19b-a-retry.sh"
readonly base_inspector="$caddy_root/scripts/inspect-node-b-action19b-postfailure-action19b-a.sh"
readonly base_runner="$caddy_root/scripts/run-node-b-action19b-postfailure-action19b-a.sh"
readonly baseline="$caddy_root/scripts/inspect-node-b-keepalived-helper-prerequisite-action19a-a.sh"
readonly collision_checker="$script_directory/check-shell-readonly-local-collisions-v2.sh"

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

regression_root=$(mktemp -d /tmp/caddy-action19b-a-retry-regression.XXXXXX)
readonly regression_root
cleanup() {
    # shellcheck disable=SC2317
    rm -rf -- "$regression_root"
}
trap cleanup EXIT

require_gate base_inspector_hash_exact test "$(file_hash "$base_inspector")" = \
    "$base_inspector_sha256"
require_gate base_runner_hash_exact test "$(file_hash "$base_runner")" = \
    "$base_runner_sha256"
require_gate derivation_hash_exact test "$(file_hash "$derivation")" = \
    "$derivation_sha256"
require_gate historical_artifacts_immutable test \
    "$(file_hash "$base_inspector")|$(file_hash "$base_runner")" = \
    "$base_inspector_sha256|$base_runner_sha256"
require_gate derivation_syntax bash -n "$derivation"
require_gate derivation_shellcheck shellcheck "$derivation"
require_gate derivation_collision_policy "$collision_checker" "$derivation"
require_gate derivation_self_test "$derivation" --self-test

readonly render_root="$regression_root/render/Caddy/scripts"
install -d -m 0700 "$render_root"
mapfile -t rendered_paths < <(
    "$derivation" --output-directory "$render_root"
)
readonly rendered_inspector=${rendered_paths[0]}
readonly rendered_runner=${rendered_paths[1]}
require_gate rendered_inspector_hash_exact test \
    "$(file_hash "$rendered_inspector")" = "$rendered_inspector_sha256"
require_gate rendered_runner_hash_exact test \
    "$(file_hash "$rendered_runner")" = "$rendered_runner_sha256"
require_gate rendered_syntax bash -n "$rendered_inspector" "$rendered_runner"
require_gate rendered_shellcheck shellcheck "$rendered_inspector" "$rendered_runner"
require_gate rendered_collision_policy "$collision_checker" \
    "$rendered_inspector" "$rendered_runner"

readonly noexec_baseline="$regression_root/noexec-baseline.sh"
install -m 0644 "$baseline" "$noexec_baseline"
require_gate noexec_fixture_not_executable test ! -x "$noexec_baseline"
require_gate noexec_self_test_reaches_baseline /bin/bash "$rendered_inspector" \
    --self-test "$noexec_baseline"
require_gate noexec_contract_test_reaches_baseline /bin/bash \
    "$rendered_inspector" --contract-test "$noexec_baseline"
require_gate direct_staged_baseline_invocation_absent test \
    "$(grep -Ec '^[[:space:]]*"[$]baseline_inspector"' \
        "$rendered_inspector" || true)" -eq 0
# shellcheck disable=SC2016
require_gate explicit_bash_baseline_invocation_count test \
    "$(grep -Fc '/bin/bash "$baseline_inspector"' \
        "$rendered_inspector")" -eq 4
require_gate historical_residue_assertion_present grep -Fq \
    'record_command historical_action19b_a_remote_bundle_stage_absent' \
    "$rendered_inspector"
residue_line=$(grep -nF \
    'record_command historical_action19b_a_remote_bundle_stage_absent' \
    "$rendered_inspector" | cut -d: -f1)
# shellcheck disable=SC2016
baseline_live_line=$(grep -nF \
    '/bin/bash "$baseline_inspector" --expected-assertions >"$work_directory/labels"' \
    "$rendered_inspector" | cut -d: -f1)
readonly residue_line baseline_live_line
require_gate residue_check_precedes_baseline test "$residue_line" -lt \
    "$baseline_live_line"
require_gate retry_stage_namespace_exact grep -Fq \
    'caddy-action19b-a-retry-stage.XXXXXX' "$rendered_runner"
# shellcheck disable=SC2016
require_gate staged_inspector_invoked_with_bash grep -Fq \
    '/bin/bash "$stage/inspect-node-b-action19b-postfailure-action19b-a-retry.sh"' \
    "$rendered_runner"

readonly production_root="$regression_root/production/Caddy"
install -d -m 0700 "$production_root/scripts" "$production_root/tests" \
    "$regression_root/fake-bin"
install -m 0755 "$baseline" "$rendered_inspector" \
    "$production_root/scripts/"
install -m 0755 "$collision_checker" "$production_root/tests/"
awk -v fake_path="$regression_root/fake-bin" '
    /^PATH=\/usr\/bin:\/bin$/ { print "PATH=" fake_path ":/usr/bin:/bin"; next }
    { print }
' "$rendered_runner" >"$production_root/scripts/${rendered_runner##*/}"
chmod 0755 "$production_root/scripts/${rendered_runner##*/}"
cat >"$regression_root/fake-bin/ssh" <<'FAKE_SSH'
#!/usr/bin/env bash
cat >/dev/null
for fixture_index in $(seq 1 89); do
    printf 'action_19b_a_retry_assertion_fixture_%03d=true\n' "$fixture_index"
done
printf '%s\n' \
    action_19b_a_retry_assertion_count=89 \
    action_19b_a_retry_failed_assertion_count=0 \
    action_19b_a_retry_first_failure=none \
    action_19b_a_retry_helper_invoked=false \
    action_19b_a_retry_filesystem_mutation=false \
    action_19b_a_retry_service_mutation=false \
    action_19b_a_retry_keepalived_mutation=false \
    action_19b_a_retry_vrrp_vip_mutation=false \
    action_19b_a_retry_persistent_mutation=false \
    action_19b_a_retry_inspection_complete=true
FAKE_SSH
chmod 0755 "$regression_root/fake-bin/ssh"
production_output=$(cd -- "$repository_root" &&
    "$production_root/scripts/${rendered_runner##*/}")
readonly production_output
require_gate intercepted_production_path grep -Fq \
    'action_19b_a_retry_runner_acceptance=true' <<<"$production_output"
require_gate production_network_contact_false test -f \
    "$regression_root/fake-bin/ssh"
printf '%s_regression_complete=true\n' "$prefix"
