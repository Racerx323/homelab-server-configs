#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_19e
readonly derivation_sha256=0453ed18dd4b6fe2c987bf2150cc4aca8e32792fea70b8f1470e8561c49203b5
readonly installer_sha256=8aa4eb3d6753b6028b196d623a98e48e2f3a0eb161825e3f1087d17c29608512
readonly runner_sha256=c332c6cc3b1afb0858dcf83f25dd0443882885a1d21d0fd194bf13a9df6a7ebb
readonly fragment_sha256=3a6f4c038d646bf12484d1a521a8f7fc01d05c56919ac8e6217ca50c2ab84bc5
readonly accepted_tree_sha256=dad64e4ac7fdbaab2db3454ccf79158b6f41e4973086f9937a7c6b737f0a2f66

test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
readonly caddy_root=${test_directory%/tests}
readonly repository_root=${caddy_root%/Caddy}
readonly derivation="$caddy_root/scripts/derive-node-a-keepalived-fragment-action19e.sh"
readonly renderer="$caddy_root/scripts/render-node-config.sh"
readonly template="$caddy_root/templates/keepalived-caddy-ha.conf.in"
readonly manifest="$caddy_root/manifests/deployment.yaml"
readonly collision_checker="$test_directory/check-shell-readonly-local-collisions-v2.sh"
readonly conditional_policy="$test_directory/conditional-validator-errexit-policy-regression.sh"
readonly host_suite="$test_directory/run.sh"
readonly integration_suite="$test_directory/integration.sh"

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

write_success_transcript() {
    local transcript_path=$1
    local expected_label

    : >"$transcript_path"
    while IFS= read -r expected_label; do
        printf '%s=true\n' "$expected_label"
    done < <("$installer" --expected-checks) >>"$transcript_path"
    printf '%s\n' \
        'action_19e_preflight_complete=true' \
        'action_19e_mutation_started=true' \
        'action_19e_fragment_installed=true' \
        'action_19e_main_configuration_mutated=false' \
        'action_19e_keepalived_reloaded=false' \
        'action_19e_keepalived_restarted=false' \
        'action_19e_vrrp_transition_requested=false' \
        'action_19e_vip_mutations=false' \
        'action_19e_service_mutations=false' \
        'action_19e_backup_path=/var/backups/caddy-ha/action19e-node-a-keepalived-fragment.FIXTURE' \
        'action_19e_persistent_mutation_scope=fragment,rollback_backup' \
        'action_19e_install_complete=true' >>"$transcript_path"
}

run_intercepted_case() {
    local case_directory=$1
    local expected_status=$2
    local transcript_path=$3
    local fake_ssh=$case_directory/fake-ssh
    local observed_status=0

    case_failure() {
        printf 'intercepted_case_failure=%s\n' "$1" >&2
        return 1
    }

    cat >"$fake_ssh" <<'FAKE_SSH'
#!/usr/bin/env bash
set -Eeuo pipefail
cat >"${ACTION19E_STDIN_CAPTURE:?}"
printf '%s\n' "$*" >"${ACTION19E_ARGS_CAPTURE:?}"
cat "${ACTION19E_TRANSCRIPT:?}"
FAKE_SSH
    chmod 0700 "$fake_ssh"
    (
        cd "$repository_root"
        CADDY_ACTION19E_INTERCEPTED_TEST=1 \
            CADDY_ACTION19E_SSH_BINARY="$fake_ssh" \
            ACTION19E_STDIN_CAPTURE="$case_directory/stdin" \
            ACTION19E_ARGS_CAPTURE="$case_directory/args" \
            ACTION19E_TRANSCRIPT="$transcript_path" \
            "$runner"
    ) >"$case_directory/stdout" 2>"$case_directory/stderr" ||
        observed_status=$?
    if [[ "$observed_status" -ne "$expected_status" ]]; then
        printf 'intercepted_expected_status=%s\n' "$expected_status" >&2
        printf 'intercepted_observed_status=%s\n' "$observed_status" >&2
        printf 'intercepted_stdout_begin\n' >&2
        cat "$case_directory/stdout" >&2
        printf 'intercepted_stdout_end\n' >&2
        printf 'intercepted_stderr_begin\n' >&2
        cat "$case_directory/stderr" >&2
        printf 'intercepted_stderr_end\n' >&2
        return 1
    fi
    [[ -s "$case_directory/stdin" ]] || {
        case_failure stdin_nonempty
        return 1
    }
    grep -Fq -- '-T -o BatchMode=yes' "$case_directory/args" ||
        {
            case_failure ssh_batch_mode
            return 1
        }
    grep -Fq -- '-o HostKeyAlias=pihole0.local.theama.co' \
        "$case_directory/args" || {
        case_failure ssh_host_alias
        return 1
    }
    grep -Fq 'pi@10.1.0.53 cd / && sudo -n /bin/bash -s' \
        "$case_directory/args" || {
        case_failure ssh_target_command
        return 1
    }
    grep -Fq '/bin/bash' "$case_directory/stdin" ||
        {
            case_failure staged_bash_invocation
            return 1
        }
    grep -Fq 'install-node-a-keepalived-fragment-action19e.sh' \
        "$case_directory/stdin" || {
        case_failure installer_in_bundle
        return 1
    }
    grep -Fq 'action_19e_remote_stdout_begin' "$case_directory/stdout" ||
        {
            case_failure remote_stdout_begin
            return 1
        }
    grep -Fq 'action_19e_workstation_cleanup_complete=true' \
        "$case_directory/stdout" || {
        case_failure workstation_cleanup
        return 1
    }
}

regression_root=$(mktemp -d /tmp/caddy-action19e-regression.XXXXXX)
readonly regression_root
trap 'rm -rf -- "$regression_root"' EXIT
readonly rendered_root=$regression_root/repository/Caddy
readonly rendered_scripts=$rendered_root/scripts
readonly rendered_tests=$rendered_root/tests
readonly rendered_templates=$rendered_root/templates
readonly rendered_manifests=$rendered_root/manifests
install -d -m 0700 "$rendered_scripts" "$rendered_tests" \
    "$rendered_templates" "$rendered_manifests"
install -m 0755 "$renderer" "$rendered_scripts/"
install -m 0644 "$template" "$rendered_templates/"
install -m 0644 "$caddy_root/templates/caddy-ha.env.in" \
    "$caddy_root/templates/lsyncd-caddy.lua.in" "$rendered_templates/"
install -m 0644 "$manifest" "$rendered_manifests/"
install -m 0755 "$collision_checker" "$rendered_tests/"
"$derivation" --output-directory "$rendered_scripts"
readonly installer=$rendered_scripts/install-node-a-keepalived-fragment-action19e.sh
readonly runner=$rendered_scripts/run-node-a-keepalived-fragment-install-action19e.sh
readonly expected_checks_path=$regression_root/expected-checks
"$installer" --expected-checks >"$expected_checks_path"

require_gate derivation_hash_exact test "$(file_hash "$derivation")" = \
    "$derivation_sha256"
require_gate installer_hash_exact test "$(file_hash "$installer")" = \
    "$installer_sha256"
require_gate runner_hash_exact test "$(file_hash "$runner")" = "$runner_sha256"
require_gate syntax_valid bash -n "$0" "$derivation" "$installer" "$runner"
require_gate shellcheck_clean shellcheck "$0" "$derivation" "$installer" "$runner"
require_gate collision_policy_clean "$collision_checker" "$0" "$derivation" \
    "$installer" "$runner"
require_gate conditional_validator_policy "$conditional_policy" >/dev/null
require_gate derivation_self_test "$derivation" --self-test
require_gate installer_self_test "$installer" --self-test
require_gate runner_self_test "$runner" --self-test
require_gate runner_contract_test "$runner" --contract-test
require_gate expected_check_count_exact test \
    "$(wc -l <"$expected_checks_path")" -eq 154
require_gate expected_check_inventory_unique test \
    "$(LC_ALL=C sort -u "$expected_checks_path" | wc -l)" -eq 154
require_gate mixed_case_service_labels_present grep -Fxq \
    action_19e_check_pre_keepalived_service_ActiveState_observed \
    "$expected_checks_path"
require_gate exact_fragment_hash_pin grep -Fq \
    "expected_fragment_sha256=$fragment_sha256" "$installer"
require_gate exact_accepted_tree_pin grep -Fq \
    "expected_keepalived_tree_sha256=$accepted_tree_sha256" "$installer"
require_gate node_a_priority grep -Fq "'priority 140'" "$installer"
require_gate node_a_ipv4_source grep -Fq "'unicast_src_ip 10.1.0.53'" \
    "$installer"
require_gate node_a_ipv6_source grep -Fq \
    "'unicast_src_ip fd36:5aa8:6971:1::53'" "$installer"
# The literal source expression is intentionally not expanded here.
# shellcheck disable=SC2016
require_gate exact_inventory_consumer grep -Fq \
    '"$installer" --expected-checks' "$runner"
# The child shell evaluates its positional parameter.
# shellcheck disable=SC2016
require_gate arbitrary_minimum_absent bash -c \
    '! grep -Eq "check_count.*-(ge|gt)[[:space:]]+[0-9]+" "$1"' _ "$runner"
# The child shell evaluates its positional parameter.
# shellcheck disable=SC2016
require_gate numbered_synthetic_fixture_absent bash -c \
    '! grep -Eq "seq 1 [0-9]+|check_fixture_[%0-9]" "$1"' _ "$runner"
require_gate keepalived_reload_prohibited grep -Fq \
    'keepalived_reloaded=false' "$installer"
require_gate keepalived_restart_prohibited grep -Fq \
    'keepalived_restarted=false' "$installer"
require_gate vrrp_transition_prohibited grep -Fq \
    'vrrp_transition_requested=false' "$installer"
require_gate vip_mutation_prohibited grep -Fq 'vip_mutations=false' "$installer"
require_gate service_mutation_prohibited grep -Fq \
    'service_mutations=false' "$installer"
# The child shell evaluates its positional parameter.
# shellcheck disable=SC2016
require_gate no_systemctl_mutation bash -c \
    '! grep -Eq "systemctl[[:space:]]+(reload|restart|start|stop|enable|disable|mask|unmask)" "$1"' \
    _ "$installer"
# The child shell evaluates its positional parameter.
# shellcheck disable=SC2016
require_gate no_ip_mutation bash -c \
    '! grep -Eq "(^|[[:space:]])ip[[:space:]].*address[[:space:]]+(add|del|replace)([[:space:]]|$)" "$1"' \
    _ "$installer"
require_gate host_suite_derivation_signature grep -Fq \
    'derive-node-a-keepalived-fragment-action19e.sh' "$host_suite"
require_gate host_suite_outer_signature grep -Fq \
    'run-node-a-keepalived-fragment-install-action19e-outer.sh' "$host_suite"
# The literal suite expression is intentionally not expanded here.
# shellcheck disable=SC2016
require_gate host_suite_source_context_signature grep -Fq -- \
    '--runner "$caddy_root/scripts/run-node-a-keepalived-fragment-install-action19e-outer.sh"' \
    "$host_suite"
require_gate host_suite_regression_signature grep -Fq \
    'action19e-node-a-keepalived-fragment-definition-regression.sh' "$host_suite"
require_gate integration_suite_derivation_signature grep -Fq \
    'derive-node-a-keepalived-fragment-action19e.sh' "$integration_suite"
require_gate integration_suite_outer_signature grep -Fq \
    'run-node-a-keepalived-fragment-install-action19e-outer.sh' \
    "$integration_suite"
require_gate integration_suite_regression_signature grep -Fq \
    'action19e-node-a-keepalived-fragment-definition-regression.sh' \
    "$integration_suite"

readonly collision_fixture=$regression_root/collision.sh
# The fixture shell expands its own collision variable.
# shellcheck disable=SC2016
printf '%s\n' \
    '#!/usr/bin/env bash' \
    'readonly collision_name=outer' \
    'collision_probe() {' \
    '    local collision_name=inner' \
    '    printf "%s\n" "$collision_name"' \
    '}' \
    'collision_probe' >"$collision_fixture"
chmod 0700 "$collision_fixture"
if "$collision_checker" "$collision_fixture" >/dev/null 2>&1; then
    printf '%s_regression_dynamic_collision_rejected=false\n' "$prefix" >&2
    exit 1
fi
printf '%s_regression_dynamic_collision_rejected=true\n' "$prefix"

for case_name in valid false missing duplicate; do
    install -d -m 0700 "$regression_root/$case_name"
    write_success_transcript "$regression_root/$case_name/transcript"
done
sed -i \
    's/action_19e_check_identity_root=true/action_19e_check_identity_root=false/' \
    "$regression_root/false/transcript"
sed -i '/action_19e_check_identity_root=true/d' \
    "$regression_root/missing/transcript"
printf 'action_19e_check_identity_root=true\n' >> \
    "$regression_root/duplicate/transcript"

require_gate intercepted_valid_production_path run_intercepted_case \
    "$regression_root/valid" 0 "$regression_root/valid/transcript"
printf '%s_false_negative_exact_producer_contract_accepted=true\n' "$prefix"
require_gate intercepted_early_invalid_later_valid run_intercepted_case \
    "$regression_root/false" 1 "$regression_root/false/transcript"
printf '%s_false_positive_early_invalid_later_valid_rejected=true\n' "$prefix"
require_gate intercepted_missing_label run_intercepted_case \
    "$regression_root/missing" 1 "$regression_root/missing/transcript"
printf '%s_false_positive_missing_label_rejected=true\n' "$prefix"
require_gate intercepted_duplicate_label run_intercepted_case \
    "$regression_root/duplicate" 1 "$regression_root/duplicate/transcript"
printf '%s_false_positive_duplicate_label_rejected=true\n' "$prefix"
printf '%s_production_path_network_contact=false\n' "$prefix"
printf '%s_regression_complete=true\n' "$prefix"
