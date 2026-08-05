#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH
readonly PATH

readonly prefix=action_20a_b_regression
readonly probe_sha256=bc1f5fc7dc9de385ba00e8f9868df6857306cc4268de6a899a73ccc7098c1ceb
readonly runner_sha256=624f9b7351eb24a7e624914c4a511faa1e905ac099ea21e42917a240e7d6be1b
readonly historical_probe_sha256=68d7812760c0c663b74c4bb54ed71ec79f9ae9d102dc40511e222b6aca01aac2
readonly historical_runner_sha256=9f78d047044cb40895f45afbf48426a2c1e25024ac7711c38b15797d8196a185
readonly historical_regression_sha256=5a472919220e3c90688bdbc43701b170f9c0426f68dea4b53395a556b20b7a6f
readonly historical_outer_sha256=45d7d18ed79ad09277a6962efc9e7bc7a87ff28bc6687de4dd7c93ad32e0b2b6

test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
readonly caddy_root=${test_directory%/tests}
readonly repository_root=${caddy_root%/Caddy}
readonly probe="$caddy_root/scripts/inspect-dual-node-caddy-postfailure-continuity-action20a-b.sh"
readonly runner="$caddy_root/scripts/run-dual-node-caddy-postfailure-continuity-action20a-b.sh"
readonly historical_probe="$caddy_root/scripts/inspect-dual-node-caddy-health-context-action20a-a.sh"
readonly historical_runner="$caddy_root/scripts/run-dual-node-caddy-health-context-action20a-a.sh"
readonly historical_regression="$test_directory/action20a-a-dual-node-caddy-health-context-regression.sh"
readonly historical_outer="$caddy_root/scripts/run-dual-node-caddy-health-context-action20a-a-outer.sh"
readonly collision_checker="$test_directory/check-shell-readonly-local-collisions-v2.sh"
readonly conditional_policy="$test_directory/conditional-validator-errexit-policy-regression.sh"
readonly transcript_policy="$test_directory/transcript-contract-ratchet-policy-regression.sh"
readonly output_policy="$test_directory/transaction-output-evidence-policy-regression.sh"

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
write_probe_contract() {
    local fixture_path=$1
    local fixture_role=$2
    local fixture_label
    local fixture_component
    local fixture_hash=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa

    {
        while IFS= read -r fixture_label; do
            printf 'action_20a_b_probe_assertion_%s=true\n' "$fixture_label"
        done < <(/bin/bash "$probe" --expected-assertions)
        while IFS= read -r fixture_component; do
            printf 'action_20a_b_probe_value_before_%s=fixture-%s\n' \
                "$fixture_component" "$fixture_component"
            printf 'action_20a_b_probe_value_after_%s=fixture-%s\n' \
                "$fixture_component" "$fixture_component"
        done < <(/bin/bash "$probe" --snapshot-components)
        printf '%s\n' \
            "action_20a_b_probe_value_node_role=$fixture_role" \
            'action_20a_b_probe_value_dns_ipv4_vip_count=1' \
            'action_20a_b_probe_value_dns_ipv6_vip_count=1' \
            "action_20a_b_probe_value_before_state_sha256=$fixture_hash" \
            "action_20a_b_probe_value_after_state_sha256=$fixture_hash" \
            'action_20a_b_probe_assertion_count=79' \
            'action_20a_b_probe_failed_assertion_count=0' \
            'action_20a_b_probe_first_failure=none' \
            'action_20a_b_probe_installed_health_helper_invoked=false' \
            'action_20a_b_probe_caddy_validation_invoked=false' \
            'action_20a_b_probe_transient_filesystem_activity=true' \
            'action_20a_b_probe_service_mutations=false' \
            'action_20a_b_probe_vrrp_mutations=false' \
            'action_20a_b_probe_vip_mutations=false' \
            'action_20a_b_probe_persistent_mutations=false' \
            'action_20a_b_probe_remote_cleanup_complete=true' \
            'action_20a_b_probe_remote_complete=true'
    } >"$fixture_path"
}
run_intercepted_case() {
    local case_root=$1
    local expected_status=$2
    local fake_ssh=$case_root/fake-ssh
    local observed_status=0

    install -d -m 0700 "$case_root"
    cat >"$fake_ssh" <<'FAKE_SSH'
#!/usr/bin/env bash
set -Eeuo pipefail
cat >"${ACTION20AB_STDIN_CAPTURE:?}"
printf '%s\n' "$*" >>"${ACTION20AB_SSH_ARGS_CAPTURE:?}"
case "$*" in
    *pihole0.local.theama.co*) cat "${ACTION20AB_NODE_A_TRANSCRIPT:?}" ;;
    *pihole00.local.theama.co*) cat "${ACTION20AB_NODE_B_TRANSCRIPT:?}" ;;
    *) exit 64 ;;
esac
FAKE_SSH
    chmod 0700 "$fake_ssh"
    : >"$case_root/ssh.args"
    (
        cd "$repository_root" || exit 1
        CADDY_ACTION20AB_INTERCEPTED_TEST=1 \
            CADDY_ACTION20AB_SSH_BINARY="$fake_ssh" \
            ACTION20AB_STDIN_CAPTURE="$case_root/stdin" \
            ACTION20AB_SSH_ARGS_CAPTURE="$case_root/ssh.args" \
            ACTION20AB_NODE_A_TRANSCRIPT="${ACTION20AB_NODE_A_TRANSCRIPT:?}" \
            ACTION20AB_NODE_B_TRANSCRIPT="${ACTION20AB_NODE_B_TRANSCRIPT:?}" \
            /bin/bash "$runner"
    ) >"$case_root/stdout" 2>"$case_root/stderr" || observed_status=$?
    [[ "$observed_status" -eq "$expected_status" ]] || return 1
    [[ ! -s "$case_root/stderr" ]] || return 1
    [[ -s "$case_root/stdin" ]] || return 1
    [[ "$(grep -Fxc -- \
        '-T -o BatchMode=yes -o IdentitiesOnly=no -o StrictHostKeyChecking=yes -o HostKeyAlias=pihole0.local.theama.co pi@10.1.0.53 cd / && sudo -n env -u CADDY_ACTION20AB_PRODUCTION_REGRESSION -u CADDY_ACTION20AB_FIXTURE_ROOT /bin/bash -s -- --node node-a' \
        "$case_root/ssh.args")" -eq 1 ]] || return 1
    [[ "$(grep -Fxc -- \
        '-T -o BatchMode=yes -o IdentitiesOnly=no -o StrictHostKeyChecking=yes -o HostKeyAlias=pihole00.local.theama.co pi@10.1.0.54 cd / && sudo -n env -u CADDY_ACTION20AB_PRODUCTION_REGRESSION -u CADDY_ACTION20AB_FIXTURE_ROOT /bin/bash -s -- --node node-b' \
        "$case_root/ssh.args")" -eq 1 ]] || return 1
    grep -Fq 'action_20a_b_runner_cleanup_complete=true' \
        "$case_root/stdout" || return 1
}
static_read_only_policy() {
    ! grep -Eq \
        'systemctl[[:space:]]+(start|stop|restart|reload|enable|disable|mask|unmask|daemon-reload|reset-failed)|ip[[:space:]]+(-[46][[:space:]]+)?(address|addr)[[:space:]]+(add|delete|del)|keepalived[[:space:]].*(reload|restart)|(^|[;&|[:space:]])(install|cp|mv|chmod|chown)[[:space:]]+(/etc|/var/backups|/usr/local)' \
        "$probe" "$runner"
}
installed_helper_and_validation_absent() {
    ! grep -Eq \
        'runuser[^\n]*check-caddy|(^|[;&|[:space:]])/usr/local/libexec/check-caddy\.sh([;&|[:space:]]|$)|caddy[[:space:]]+validate' \
        "$probe" "$runner"
}
component_contract_complete() {
    local component_root
    local component_name

    component_root=$(mktemp -d /tmp/caddy-action20ab-components.XXXXXX) ||
        return 1
    # conditional-validator-explicit-failures-begin
    /bin/bash "$probe" --snapshot-components >"$component_root/components" || {
        rm -rf -- "$component_root"
        return 1
    }
    /bin/bash "$probe" --expected-assertions >"$component_root/assertions" || {
        rm -rf -- "$component_root"
        return 1
    }
    if [[ "$(wc -l <"$component_root/components")" -ne 19 ]]; then
        rm -rf -- "$component_root"
        return 1
    fi
    if [[ "$(LC_ALL=C sort -u "$component_root/components" | wc -l)" -ne 19 ]]; then
        rm -rf -- "$component_root"
        return 1
    fi
    while IFS= read -r component_name; do
        grep -Fqx "snapshot_before_${component_name}_captured" \
            "$component_root/assertions" || {
            rm -rf -- "$component_root"
            return 1
        }
        grep -Fqx "snapshot_after_${component_name}_captured" \
            "$component_root/assertions" || {
            rm -rf -- "$component_root"
            return 1
        }
        grep -Fqx "snapshot_${component_name}_unchanged" \
            "$component_root/assertions" || {
            rm -rf -- "$component_root"
            return 1
        }
    done <"$component_root/components"
    # conditional-validator-explicit-failures-end
    rm -rf -- "$component_root"
}

require_gate probe_hash_exact test "$(file_hash "$probe")" = "$probe_sha256"
require_gate runner_hash_exact test "$(file_hash "$runner")" = "$runner_sha256"
require_gate historical_probe_immutable test "$(file_hash "$historical_probe")" = \
    "$historical_probe_sha256"
require_gate historical_runner_immutable test "$(file_hash "$historical_runner")" = \
    "$historical_runner_sha256"
require_gate historical_regression_immutable test \
    "$(file_hash "$historical_regression")" = "$historical_regression_sha256"
require_gate historical_outer_immutable test "$(file_hash "$historical_outer")" = \
    "$historical_outer_sha256"
require_gate sources_syntax bash -n "$0" "$probe" "$runner"
require_gate sources_shellcheck shellcheck "$0" "$probe" "$runner"
require_gate collision_policy /bin/bash "$collision_checker" "$0" "$probe" \
    "$runner"
require_gate conditional_policy /bin/bash "$conditional_policy" >/dev/null
require_gate transcript_policy /bin/bash "$transcript_policy" >/dev/null
require_gate output_policy /bin/bash "$output_policy" >/dev/null
require_gate probe_self_test /bin/bash "$probe" --self-test
require_gate runner_self_test /bin/bash "$runner" --self-test
require_gate runner_contract_test /bin/bash "$runner" --contract-test
require_gate component_contract_complete component_contract_complete
require_gate normalized_addresses_exclude_lifetimes test \
    "$(grep -Ec 'valid_lft|preferred_lft' "$probe")" -eq 0
require_gate exact_node_a_fragment_pin grep -Fq \
    '3a6f4c038d646bf12484d1a521a8f7fc01d05c56919ac8e6217ca50c2ab84bc5' \
    "$probe"
require_gate exact_node_b_fragment_pin grep -Fq \
    '294d5ba44d903ba4ab3ab4330ae3ae05e0160e2b134d71e91a787b65dd96dc4d' \
    "$probe"
require_gate role_specific_releases_present grep -Fq \
    '/etc/caddy/releases/action16ar-retry-node-a-default-deny' "$probe"
require_gate role_specific_node_b_release_present grep -Fq \
    '/etc/caddy/releases/action15-health-follow-redirects' "$probe"
require_gate static_read_only_policy static_read_only_policy
require_gate helper_and_validation_absent installed_helper_and_validation_absent
require_gate host_suite_probe_signature grep -Fq \
    'inspect-dual-node-caddy-postfailure-continuity-action20a-b.sh' \
    "$test_directory/run.sh"
require_gate host_suite_outer_signature grep -Fq \
    'run-dual-node-caddy-postfailure-continuity-action20a-b-outer.sh' \
    "$test_directory/run.sh"
require_gate integration_suite_probe_signature grep -Fq \
    'inspect-dual-node-caddy-postfailure-continuity-action20a-b.sh' \
    "$test_directory/integration.sh"
require_gate integration_suite_regression_signature grep -Fq \
    'action20a-b-dual-node-postfailure-continuity-regression.sh' \
    "$test_directory/integration.sh"

regression_root=$(mktemp -d /tmp/caddy-action20ab-regression.XXXXXX)
readonly regression_root
trap 'rm -rf -- "$regression_root"' EXIT
write_probe_contract "$regression_root/node-a.valid" node-a
write_probe_contract "$regression_root/node-b.valid" node-b
export ACTION20AB_NODE_A_TRANSCRIPT=$regression_root/node-a.valid
export ACTION20AB_NODE_B_TRANSCRIPT=$regression_root/node-b.valid
require_gate valid_production_contract run_intercepted_case \
    "$regression_root/valid" 0

cp -- "$regression_root/node-a.valid" "$regression_root/node-a.component-drift"
sed -i \
    's/action_20a_b_probe_value_after_caddy_main_pid=fixture-caddy_main_pid/action_20a_b_probe_value_after_caddy_main_pid=changed/' \
    "$regression_root/node-a.component-drift"
export ACTION20AB_NODE_A_TRANSCRIPT=$regression_root/node-a.component-drift
require_gate node_a_component_drift_rejected run_intercepted_case \
    "$regression_root/node-a-component-drift" 1

cp -- "$regression_root/node-b.valid" "$regression_root/node-b.semantic"
sed -i \
    's/action_20a_b_probe_assertion_current_target_exact=true/action_20a_b_probe_assertion_current_target_exact=false/' \
    "$regression_root/node-b.semantic"
export ACTION20AB_NODE_A_TRANSCRIPT=$regression_root/node-a.valid
export ACTION20AB_NODE_B_TRANSCRIPT=$regression_root/node-b.semantic
require_gate node_b_semantic_failure_rejected run_intercepted_case \
    "$regression_root/node-b-semantic" 1

cp -- "$regression_root/node-a.valid" "$regression_root/node-a.missing"
sed -i '/action_20a_b_probe_assertion_caddy_active=true/d' \
    "$regression_root/node-a.missing"
export ACTION20AB_NODE_A_TRANSCRIPT=$regression_root/node-a.missing
export ACTION20AB_NODE_B_TRANSCRIPT=$regression_root/node-b.valid
require_gate missing_label_rejected run_intercepted_case \
    "$regression_root/missing-label" 1

cp -- "$regression_root/node-a.valid" "$regression_root/node-a.duplicate"
printf '%s\n' 'action_20a_b_probe_assertion_caddy_active=true' \
    >>"$regression_root/node-a.duplicate"
export ACTION20AB_NODE_A_TRANSCRIPT=$regression_root/node-a.duplicate
require_gate duplicate_label_rejected run_intercepted_case \
    "$regression_root/duplicate-label" 1

printf '%s_false_negative_exact_contract_accepted=true\n' "$prefix"
printf '%s_false_negative_node_b_independent_continuity_preserved=true\n' "$prefix"
printf '%s_false_positive_node_a_component_drift_rejected=true\n' "$prefix"
printf '%s_false_positive_node_b_semantic_failure_rejected=true\n' "$prefix"
printf '%s_false_positive_missing_label_rejected=true\n' "$prefix"
printf '%s_false_positive_duplicate_label_rejected=true\n' "$prefix"
printf '%s_production_path_network_contact=false\n' "$prefix"
printf '%s_complete=true\n' "$prefix"
