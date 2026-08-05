#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_20a_a_regression
readonly probe_sha256=68d7812760c0c663b74c4bb54ed71ec79f9ae9d102dc40511e222b6aca01aac2
readonly runner_sha256=9f78d047044cb40895f45afbf48426a2c1e25024ac7711c38b15797d8196a185

test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
readonly caddy_root=${test_directory%/tests}
readonly repository_root=${caddy_root%/Caddy}
readonly probe="$caddy_root/scripts/inspect-dual-node-caddy-health-context-action20a-a.sh"
readonly runner="$caddy_root/scripts/run-dual-node-caddy-health-context-action20a-a.sh"
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
    local fixture_hash=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa

    {
        while IFS= read -r fixture_label; do
            printf 'action_20a_a_probe_assertion_%s=true\n' "$fixture_label"
        done < <(/bin/bash "$probe" --expected-assertions)
        printf '%s\n' \
            "action_20a_a_probe_value_node_role=$fixture_role" \
            'action_20a_a_probe_value_baseline_status=1' \
            'action_20a_a_probe_value_transient_validate_status=0' \
            'action_20a_a_probe_value_transient_local_pki_file_count=2' \
            "action_20a_a_probe_value_before_state_sha256=$fixture_hash" \
            "action_20a_a_probe_value_after_state_sha256=$fixture_hash"
        for fixture_stream in baseline_stdout baseline_stderr transient_stdout \
            transient_stderr; do
            printf '%s\n' \
                "action_20a_a_probe_value_${fixture_stream}_bytes=0" \
                "action_20a_a_probe_value_${fixture_stream}_lines=0" \
                "action_20a_a_probe_value_${fixture_stream}_sha256=e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855" \
                "action_20a_a_probe_value_${fixture_stream}_classification=bounded_safe" \
                "action_20a_a_probe_${fixture_stream}_content_secured=empty"
        done
        printf '%s\n' \
            'action_20a_a_probe_assertion_count=62' \
            'action_20a_a_probe_failed_assertion_count=0' \
            'action_20a_a_probe_first_failure=none' \
            'action_20a_a_probe_installed_health_helper_invoked=false' \
            'action_20a_a_probe_transient_filesystem_activity=true' \
            'action_20a_a_probe_service_mutations=false' \
            'action_20a_a_probe_vrrp_mutations=false' \
            'action_20a_a_probe_vip_mutations=false' \
            'action_20a_a_probe_persistent_mutations=false' \
            'action_20a_a_probe_remote_cleanup_complete=true' \
            'action_20a_a_probe_remote_complete=true'
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
cat >"${ACTION20AA_STDIN_CAPTURE:?}"
printf '%s\n' "$*" >>"${ACTION20AA_SSH_ARGS_CAPTURE:?}"
case "$*" in
    *pihole0.local.theama.co*) cat "${ACTION20AA_NODE_A_TRANSCRIPT:?}" ;;
    *pihole00.local.theama.co*) cat "${ACTION20AA_NODE_B_TRANSCRIPT:?}" ;;
    *) exit 64 ;;
esac
FAKE_SSH
    chmod 0700 "$fake_ssh"
    : >"$case_root/ssh.args"
    (
        cd "$repository_root" || exit 1
        CADDY_ACTION20AA_INTERCEPTED_TEST=1 \
            CADDY_ACTION20AA_SSH_BINARY="$fake_ssh" \
            ACTION20AA_STDIN_CAPTURE="$case_root/stdin" \
            ACTION20AA_SSH_ARGS_CAPTURE="$case_root/ssh.args" \
            ACTION20AA_NODE_A_TRANSCRIPT="${ACTION20AA_NODE_A_TRANSCRIPT:?}" \
            ACTION20AA_NODE_B_TRANSCRIPT="${ACTION20AA_NODE_B_TRANSCRIPT:?}" \
            /bin/bash "$runner"
    ) >"$case_root/stdout" 2>"$case_root/stderr" || observed_status=$?
    [[ "$observed_status" -eq "$expected_status" ]] || return 1
    [[ ! -s "$case_root/stderr" ]] || return 1
    [[ -s "$case_root/stdin" ]] || return 1
    [[ "$(grep -Fc \
        'env -u CADDY_ACTION20AA_PRODUCTION_REGRESSION -u CADDY_ACTION20AA_FIXTURE_ROOT /bin/bash -s --' \
        "$case_root/ssh.args")" -eq 2 ]] || return 1
    [[ "$(grep -Fxc -- \
        '-T -o BatchMode=yes -o IdentitiesOnly=no -o StrictHostKeyChecking=yes -o HostKeyAlias=pihole0.local.theama.co pi@10.1.0.53 cd / && sudo -n env -u CADDY_ACTION20AA_PRODUCTION_REGRESSION -u CADDY_ACTION20AA_FIXTURE_ROOT /bin/bash -s -- --node node-a' \
        "$case_root/ssh.args")" -eq 1 ]] || return 1
    [[ "$(grep -Fxc -- \
        '-T -o BatchMode=yes -o IdentitiesOnly=no -o StrictHostKeyChecking=yes -o HostKeyAlias=pihole00.local.theama.co pi@10.1.0.54 cd / && sudo -n env -u CADDY_ACTION20AA_PRODUCTION_REGRESSION -u CADDY_ACTION20AA_FIXTURE_ROOT /bin/bash -s -- --node node-b' \
        "$case_root/ssh.args")" -eq 1 ]] || return 1
    grep -Fq 'action_20a_a_runner_cleanup_complete=true' \
        "$case_root/stdout" || return 1
}
static_read_only_policy() {
    ! grep -Eq \
        'systemctl[[:space:]]+(start|stop|restart|reload|enable|disable|mask|unmask|daemon-reload|reset-failed)|ip[[:space:]]+(-[46][[:space:]]+)?(address|addr)[[:space:]]+(add|delete|del)|keepalived[[:space:]].*(reload|restart)|(^|[;&|[:space:]])(install|cp|mv|chmod|chown)[[:space:]]+(/etc|/var/backups|/usr/local)' \
        "$probe" "$runner"
}
installed_helper_not_invoked() {
    # Dollar-prefixed tokens are matched as literal source text.
    # shellcheck disable=SC2016
    ! grep -Eq 'runuser[^\n]*--[[:space:]]+"\$health_script"|/bin/bash[[:space:]]+"\$health_script"' \
        "$probe" "$runner"
}
production_label_alignment() {
    local alignment_root
    local alignment_label

    alignment_root=$(mktemp -d /tmp/caddy-action20aa-labels.XXXXXX) || return 1
    # conditional-validator-explicit-failures-begin
    /bin/bash "$probe" --expected-assertions | LC_ALL=C sort \
        >"$alignment_root/expected" || {
        rm -rf -- "$alignment_root"
        return 1
    }
    while IFS= read -r alignment_label; do
        grep -Fq "$alignment_label" "$probe" || {
            rm -rf -- "$alignment_root"
            return 1
        }
    done <"$alignment_root/expected"
    if [[ "$(wc -l <"$alignment_root/expected")" -ne 62 ]]; then
        rm -rf -- "$alignment_root"
        return 1
    fi
    if [[ "$(LC_ALL=C sort -u "$alignment_root/expected" | wc -l)" -ne 62 ]]; then
        rm -rf -- "$alignment_root"
        return 1
    fi
    # conditional-validator-explicit-failures-end
    rm -rf -- "$alignment_root"
}

require_gate probe_hash_exact test "$(file_hash "$probe")" = "$probe_sha256"
require_gate runner_hash_exact test "$(file_hash "$runner")" = "$runner_sha256"
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
require_gate probe_label_alignment production_label_alignment
require_gate runner_assertion_count_exact test \
    "$(/bin/bash "$runner" --expected-assertions | wc -l)" -eq 12
require_gate runner_assertions_unique test \
    "$(/bin/bash "$runner" --expected-assertions | LC_ALL=C sort -u | wc -l)" \
    -eq 12
require_gate static_read_only_policy static_read_only_policy
require_gate installed_helper_not_invoked installed_helper_not_invoked
require_gate baseline_context_unset grep -Fq \
    'env -u HOME -u XDG_CONFIG_HOME' "$probe"
# Dollar-prefixed tokens below are matched as literal source text.
# shellcheck disable=SC2016
require_gate transient_home_override grep -Fq \
    'HOME="$transient_root/home"' "$probe"
# shellcheck disable=SC2016
require_gate transient_xdg_config_override grep -Fq \
    'XDG_CONFIG_HOME="$transient_root/config"' "$probe"
# shellcheck disable=SC2016
require_gate transient_xdg_data_override grep -Fq \
    'XDG_DATA_HOME="$transient_root/data"' "$probe"
# shellcheck disable=SC2016
require_gate transient_cleanup_present grep -Fq \
    'rm -rf -- "$transient_root"' "$probe"
require_gate host_suite_probe_signature grep -Fq \
    'inspect-dual-node-caddy-health-context-action20a-a.sh' \
    "$test_directory/run.sh"
require_gate host_suite_outer_signature grep -Fq \
    'run-dual-node-caddy-health-context-action20a-a-outer.sh' \
    "$test_directory/run.sh"
require_gate integration_suite_probe_signature grep -Fq \
    'inspect-dual-node-caddy-health-context-action20a-a.sh' \
    "$test_directory/integration.sh"
require_gate integration_suite_regression_signature grep -Fq \
    'action20a-a-dual-node-caddy-health-context-regression.sh' \
    "$test_directory/integration.sh"

regression_root=$(mktemp -d /tmp/caddy-action20aa-regression.XXXXXX)
readonly regression_root
trap 'rm -rf -- "$regression_root"' EXIT
write_probe_contract "$regression_root/node-a.valid" node-a
write_probe_contract "$regression_root/node-b.valid" node-b
export ACTION20AA_NODE_A_TRANSCRIPT=$regression_root/node-a.valid
export ACTION20AA_NODE_B_TRANSCRIPT=$regression_root/node-b.valid
require_gate valid_production_contract run_intercepted_case \
    "$regression_root/valid" 0

cp -- "$regression_root/node-a.valid" "$regression_root/node-a.invalid"
sed -i \
    's/action_20a_a_probe_assertion_transient_validate_status_zero=true/action_20a_a_probe_assertion_transient_validate_status_zero=false/' \
    "$regression_root/node-a.invalid"
export ACTION20AA_NODE_A_TRANSCRIPT=$regression_root/node-a.invalid
require_gate semantic_failure_rejected run_intercepted_case \
    "$regression_root/semantic-failure" 1

cp -- "$regression_root/node-a.valid" "$regression_root/node-a.missing"
sed -i '/action_20a_a_probe_assertion_caddy_active=true/d' \
    "$regression_root/node-a.missing"
export ACTION20AA_NODE_A_TRANSCRIPT=$regression_root/node-a.missing
require_gate missing_label_rejected run_intercepted_case \
    "$regression_root/missing-label" 1

cp -- "$regression_root/node-a.valid" "$regression_root/node-a.duplicate"
printf '%s\n' 'action_20a_a_probe_assertion_caddy_active=true' \
    >>"$regression_root/node-a.duplicate"
export ACTION20AA_NODE_A_TRANSCRIPT=$regression_root/node-a.duplicate
require_gate duplicate_label_rejected run_intercepted_case \
    "$regression_root/duplicate-label" 1

printf '%s_false_negative_exact_contract_accepted=true\n' "$prefix"
printf '%s_false_negative_semantic_failure_preserved=true\n' "$prefix"
printf '%s_false_positive_missing_label_rejected=true\n' "$prefix"
printf '%s_false_positive_duplicate_label_rejected=true\n' "$prefix"
printf '%s_production_path_network_contact=false\n' "$prefix"
printf '%s_complete=true\n' "$prefix"
