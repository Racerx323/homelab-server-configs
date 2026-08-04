#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_19b_a_retry2
readonly derivation_sha256=4dd0f1d3ca710a5e2e6d0631abbfade5aa1f99a55740eb78b55a2a6569fd976b
readonly prior_derivation_sha256=56c28070d4ce346b9b8b7778edd7882a509018954e38670f7d58df75a474ab04
readonly prior_regression_sha256=8414636b0778aad073823282065470edbc0d2922d825822394b9ab09a24411b5
readonly prior_outer_sha256=3745ee49ab42a8b3409bba596d22dca2a9f87f9749b6de9f6029bacb76bcc60a
readonly producer_regression_sha256=2faab580c7d201d83333961d41b1278e36377757fe6222106c89f7dcb08e502e
readonly rendered_inspector_sha256=a9a92b4007e7b6a0798a76fd57bdd23771970e23d1e486e76b66f6408eb92c55
readonly rendered_runner_sha256=4f055690939d84fbb4c53772de867e9ba05729546669f5fbe4deb75d4fdba45a

script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
readonly caddy_root=${script_directory%/tests}
readonly derivation="$caddy_root/scripts/derive-node-b-action19b-postfailure-action19b-a-retry2.sh"
readonly prior_derivation="$caddy_root/scripts/derive-node-b-action19b-postfailure-action19b-a-retry.sh"
readonly prior_regression="$script_directory/action19b-a-retry-node-b-postfailure-regression.sh"
readonly prior_outer="$caddy_root/scripts/run-node-b-action19b-postfailure-action19b-a-retry-outer.sh"
readonly baseline="$caddy_root/scripts/inspect-node-b-keepalived-helper-prerequisite-action19a-a.sh"
readonly producer_regression="$script_directory/action19a-a-node-b-keepalived-helper-prerequisite-regression.sh"
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

regression_root=$(mktemp -d /tmp/caddy-action19b-a-retry2-regression.XXXXXX)
readonly regression_root
cleanup() {
    # shellcheck disable=SC2317
    rm -rf -- "$regression_root"
}
trap cleanup EXIT

require_gate derivation_hash_exact test "$(file_hash "$derivation")" = \
    "$derivation_sha256"
require_gate prior_derivation_immutable test "$(file_hash "$prior_derivation")" = \
    "$prior_derivation_sha256"
require_gate prior_regression_immutable test "$(file_hash "$prior_regression")" = \
    "$prior_regression_sha256"
require_gate prior_outer_immutable test "$(file_hash "$prior_outer")" = \
    "$prior_outer_sha256"
require_gate producer_regression_hash_exact test \
    "$(file_hash "$producer_regression")" = "$producer_regression_sha256"
require_gate sources_syntax bash -n "$derivation" "$producer_regression"
require_gate sources_shellcheck shellcheck "$derivation"
require_gate collision_policy "$collision_checker" "$derivation"
require_gate actual_producer_contract_regression "$producer_regression"
require_gate derivation_self_test "$derivation" --self-test

readonly render_root="$regression_root/render"
mapfile -t rendered_paths < <(
    "$derivation" --output-directory "$render_root"
)
readonly inspector=${rendered_paths[0]}
readonly runner=${rendered_paths[1]}
require_gate inspector_hash_exact test "$(file_hash "$inspector")" = \
    "$rendered_inspector_sha256"
require_gate runner_hash_exact test "$(file_hash "$runner")" = \
    "$rendered_runner_sha256"
require_gate rendered_syntax bash -n "$inspector" "$runner"
require_gate rendered_shellcheck shellcheck "$inspector" "$runner"
require_gate rendered_collision_policy "$collision_checker" "$inspector" \
    "$runner"
require_gate literal_plus_absent test \
    "$(grep -Ec '^\+[[:space:]]' "$inspector" || true)" -eq 0
# shellcheck disable=SC2016
require_gate real_state_marker_present grep -Fq \
    '${baseline_prefix}_assertion_state_unchanged=true' "$inspector"
# shellcheck disable=SC2016
require_gate real_helper_marker_present grep -Fq \
    '${baseline_prefix}_helper_execution=false' "$inspector"
# shellcheck disable=SC2016
require_gate real_persistent_marker_present grep -Fq \
    '${baseline_prefix}_persistent_mutations=false' "$inspector"
# shellcheck disable=SC2016
require_gate fabricated_state_marker_absent test \
    "$(grep -Fc '${baseline_prefix}_state_unchanged=true' "$inspector" || true)" \
    -eq 0
# shellcheck disable=SC2016
require_gate fabricated_helper_marker_absent test \
    "$(grep -Fc '${baseline_prefix}_helper_invoked=false' "$inspector" || true)" \
    -eq 0
# shellcheck disable=SC2016
require_gate fabricated_persistent_marker_absent test \
    "$(grep -Fc '${baseline_prefix}_persistent_mutation=false' "$inspector" || true)" \
    -eq 0
install -m 0644 "$baseline" "$regression_root/baseline.sh"
require_gate real_producer_fixture_contract /bin/bash "$inspector" \
    --contract-test "$regression_root/baseline.sh"

residue_block=$(sed -n \
    '/^record_command historical_action19b_a_remote_bundle_stage_absent /,/^$/p' \
    "$inspector")
readonly residue_block
require_gate residue_block_nonempty test -n "$residue_block"
readonly probe="$regression_root/residue-probe.sh"
{
    # shellcheck disable=SC2016
    printf '%s\n' '#!/usr/bin/env bash' 'set -Eeuo pipefail' \
        'record_command() { local label=$1; shift; if "$@"; then printf "%s=true\n" "$label"; else printf "%s=false\n" "$label"; return 1; fi; }'
    # shellcheck disable=SC2016
    printf '%s\n' "$residue_block" | sed \
        's#find /run #find "$ACTION19B_A_RESIDUE_ROOT" #'
} >"$probe"
chmod 0755 "$probe"
readonly absent_root="$regression_root/absent"
install -d -m 0700 "$absent_root"
absent_output=$(ACTION19B_A_RESIDUE_ROOT="$absent_root" /bin/bash "$probe")
readonly absent_output
require_gate exact_residue_command_absent_fixture grep -Fxq \
    'historical_action19b_a_remote_bundle_stage_absent=true' \
    <<<"$absent_output"
readonly present_root="$regression_root/present"
install -d -m 0700 "$present_root/caddy-action19b-a-stage.fixture"
present_status=0
present_output=$(ACTION19B_A_RESIDUE_ROOT="$present_root" \
    /bin/bash "$probe") || present_status=$?
readonly present_output present_status
require_gate exact_residue_command_present_status test "$present_status" -eq 1
require_gate exact_residue_command_present_fixture grep -Fxq \
    'historical_action19b_a_remote_bundle_stage_absent=false' \
    <<<"$present_output"
require_gate retry2_stage_namespace grep -Fq \
    'caddy-action19b-a-retry2-stage.XXXXXX' "$runner"
printf '%s_regression_complete=true\n' "$prefix"
