#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_20a_retry2_regression
readonly probe_sha256=d8a55729ca33ebc30b8110dbe3e9cb9b31fbeaef27ecb24cb5e955f572137b47
readonly runner_sha256=04d79efa70a2ad390d4a8025822f077cf8a3189b6866b0476da19bba4bbddbad
readonly node_a_baseline_sha256=42874857457884bf143fe4d5faa8492cd2b409994182243bf9734bafb98c29f3
readonly node_b_baseline_sha256=6f017e78870c6433c2b9f7180003fe6ab81f2a0f1e44fc63dbaf5ee6ea67487f
readonly node_a_producer_sha256=50b5c636e68fbe9694714bda4cc92fbad40a718d038523e80ad5ffd172b5eb66
readonly node_b_producer_sha256=dc0a52d807490ca71946f7a310a973712fe09a30f5355a879c5c977012206744
readonly historical_retry_outer_sha256=ea0817dccfee0cabf096a53d2d2077035f3cec8a78baded465519df854583845
readonly normalized_diagnostic_outer_sha256=86e520f467ae2a59a050c1bc870fd4816691f5dd3ee4b397494a44a57961ba00

test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
readonly caddy_root=${test_directory%/tests}
readonly repository_root=${caddy_root%/Caddy}
readonly probe="$caddy_root/scripts/inspect-dual-node-caddy-vrrp-preactivation-action20a-retry2.sh"
readonly runner="$caddy_root/scripts/run-dual-node-caddy-vrrp-preactivation-action20a-retry2.sh"
readonly node_a_baseline="$caddy_root/scripts/run-node-a-caddy-health-postinstall-action20c-a-outer.sh"
readonly node_b_baseline="$caddy_root/scripts/run-node-b-caddy-health-postinstall-action20b-a-outer.sh"
readonly node_a_producer="$caddy_root/scripts/inspect-node-a-caddy-health-postinstall-action20c-a.sh"
readonly node_b_producer="$caddy_root/scripts/inspect-node-b-caddy-health-postinstall-action20b-a.sh"
readonly historical_retry_outer="$caddy_root/scripts/run-dual-node-caddy-vrrp-preactivation-action20a-retry-outer.sh"
readonly normalized_diagnostic_outer="$caddy_root/scripts/run-node-b-caddy-state-difference-action20a-retry-a-outer.sh"
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
write_baseline_fixture() {
    local fixture_role=$1
    local fixture_path=$2
    local fixture_prefix
    local fixture_producer
    local fixture_label

    if [[ "$fixture_role" = node-a ]]; then
        fixture_prefix=action_20c_a
        fixture_producer=$node_a_producer
    else
        fixture_prefix=action_20b_a
        fixture_producer=$node_b_producer
    fi
    {
        while IFS= read -r fixture_label; do
            printf '%s_assertion_%s=true\n' "$fixture_prefix" "$fixture_label"
        done < <("$fixture_producer" --expected-assertions)
        printf '%s\n' \
            "${fixture_prefix}_assertion_count=138" \
            "${fixture_prefix}_failed_assertion_count=0" \
            "${fixture_prefix}_first_failure=none" \
            "${fixture_prefix}_helper_execution=true" \
            "${fixture_prefix}_filesystem_mutations=false" \
            "${fixture_prefix}_service_mutations=false" \
            "${fixture_prefix}_vrrp_mutations=false" \
            "${fixture_prefix}_vip_mutations=false" \
            "${fixture_prefix}_persistent_mutations=false" \
            "${fixture_prefix}_validation_status=0" \
            "${fixture_prefix}_runner_status=0" \
            "${fixture_prefix}_outer_cleanup_complete=true"
    } >"$fixture_path"
}
write_probe_fixture() {
    local fixture_role=$1
    local dns_count=$2
    local fixture_path=$3
    local fixture_label
    local fixture_priority fixture_ipv4_source fixture_ipv4_peer
    local fixture_ipv6_source fixture_ipv6_peer fixture_fragment
    local fixture_state=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa

    if [[ "$fixture_role" = node-a ]]; then
        fixture_priority=140
        fixture_ipv4_source=10.1.0.53
        fixture_ipv4_peer=10.1.0.54
        fixture_ipv6_source=fd36:5aa8:6971:1::53
        fixture_ipv6_peer=fd36:5aa8:6971:1::54
        fixture_fragment=3a6f4c038d646bf12484d1a521a8f7fc01d05c56919ac8e6217ca50c2ab84bc5
    else
        fixture_priority=100
        fixture_ipv4_source=10.1.0.54
        fixture_ipv4_peer=10.1.0.53
        fixture_ipv6_source=fd36:5aa8:6971:1::54
        fixture_ipv6_peer=fd36:5aa8:6971:1::53
        fixture_fragment=294d5ba44d903ba4ab3ab4330ae3ae05e0160e2b134d71e91a787b65dd96dc4d
    fi
    {
        while IFS= read -r fixture_label; do
            printf 'action_20a_retry2_probe_assertion_%s=true\n' "$fixture_label"
        done < <("$probe" --expected-assertions)
        printf '%s\n' \
            "action_20a_retry2_probe_value_node_role=$fixture_role" \
            "action_20a_retry2_probe_value_priority=$fixture_priority" \
            'action_20a_retry2_probe_value_ipv4_vrid=110' \
            'action_20a_retry2_probe_value_ipv6_vrid=111' \
            "action_20a_retry2_probe_value_ipv4_source=$fixture_ipv4_source" \
            "action_20a_retry2_probe_value_ipv4_peer=$fixture_ipv4_peer" \
            "action_20a_retry2_probe_value_ipv6_source=$fixture_ipv6_source" \
            "action_20a_retry2_probe_value_ipv6_peer=$fixture_ipv6_peer" \
            "action_20a_retry2_probe_value_dns_ipv4_vip_count=$dns_count" \
            "action_20a_retry2_probe_value_dns_ipv6_vip_count=$dns_count" \
            'action_20a_retry2_probe_value_caddy_ipv4_vip_count=0' \
            'action_20a_retry2_probe_value_caddy_ipv6_vip_count=0' \
            "action_20a_retry2_probe_value_main_sha256=$fixture_state" \
            "action_20a_retry2_probe_value_fragment_sha256=$fixture_fragment" \
            "action_20a_retry2_probe_value_before_state_sha256=$fixture_state" \
            "action_20a_retry2_probe_value_after_state_sha256=$fixture_state" \
            'action_20a_retry2_probe_value_state_address_normalization=interface_cidr_scope' \
            'action_20a_retry2_probe_value_health_status=0' \
            'action_20a_retry2_probe_value_health_stream_classification=true' \
            "action_20a_retry2_probe_assertion_count=$("$probe" --expected-assertions | wc -l)" \
            'action_20a_retry2_probe_failed_assertion_count=0' \
            'action_20a_retry2_probe_first_failure=none' \
            'action_20a_retry2_probe_notification_helper_invoked=false' \
            'action_20a_retry2_probe_filesystem_mutations=false' \
            'action_20a_retry2_probe_service_mutations=false' \
            'action_20a_retry2_probe_vrrp_mutations=false' \
            'action_20a_retry2_probe_vip_mutations=false' \
            'action_20a_retry2_probe_persistent_mutations=false' \
            'action_20a_retry2_probe_remote_complete=true'
    } >"$fixture_path"
}
run_intercepted_case() {
    local case_root=$1
    local node_a_dns_count=$2
    local node_b_dns_count=$3
    local expected_status=$4
    local expected_readiness=$5
    local baseline_corruption=${6:-none}
    local probe_corruption=${7:-none}
    local duplicate_line
    local fake_node_a=$case_root/fake-node-a-baseline
    local fake_node_b=$case_root/fake-node-b-baseline
    local fake_ssh=$case_root/fake-ssh
    local observed_status=0

    install -d -m 0700 "$case_root"
    write_baseline_fixture node-a "$case_root/node-a.baseline"
    write_baseline_fixture node-b "$case_root/node-b.baseline"
    case "$baseline_corruption" in
        none) ;;
        node-a-missing)
            awk '!removed && /^action_20c_a_assertion_/ { removed=1; next } { print }' \
                "$case_root/node-a.baseline" >"$case_root/node-a.baseline.new"
            mv "$case_root/node-a.baseline.new" "$case_root/node-a.baseline"
            ;;
        node-b-duplicate)
            duplicate_line=$(grep -m1 '^action_20b_a_assertion_' \
                "$case_root/node-b.baseline")
            printf '%s\n' "$duplicate_line" >>"$case_root/node-b.baseline"
            ;;
        *) return 1 ;;
    esac
    write_probe_fixture node-a "$node_a_dns_count" "$case_root/node-a.probe"
    write_probe_fixture node-b "$node_b_dns_count" "$case_root/node-b.probe"
    case "$probe_corruption" in
        none) ;;
        node-a-missing)
            awk '!removed && /^action_20a_retry2_probe_assertion_/ { removed=1; next } { print }' \
                "$case_root/node-a.probe" >"$case_root/node-a.probe.new"
            mv "$case_root/node-a.probe.new" "$case_root/node-a.probe"
            ;;
        node-b-duplicate)
            duplicate_line=$(grep -m1 '^action_20a_retry2_probe_assertion_' \
                "$case_root/node-b.probe")
            printf '%s\n' "$duplicate_line" >>"$case_root/node-b.probe"
            ;;
        *) return 1 ;;
    esac
    # These fake commands expand their environment at intercepted runtime.
    # shellcheck disable=SC2016
    printf '%s\n' '#!/usr/bin/env bash' 'set -Eeuo pipefail' \
        'cat "${ACTION20ARETRY_NODE_A_BASELINE_TRANSCRIPT:?}"' >"$fake_node_a"
    # shellcheck disable=SC2016
    printf '%s\n' '#!/usr/bin/env bash' 'set -Eeuo pipefail' \
        'cat "${ACTION20ARETRY_NODE_B_BASELINE_TRANSCRIPT:?}"' >"$fake_node_b"
    cat >"$fake_ssh" <<'FAKE_SSH'
#!/usr/bin/env bash
set -Eeuo pipefail
cat >"${ACTION20ARETRY_LAST_STDIN_CAPTURE:?}"
printf '%s\n' "$*" >>"${ACTION20ARETRY_SSH_ARGS_CAPTURE:?}"
case "$*" in
    *pihole0.local.theama.co*) cat "${ACTION20ARETRY_NODE_A_PROBE_TRANSCRIPT:?}" ;;
    *pihole00.local.theama.co*) cat "${ACTION20ARETRY_NODE_B_PROBE_TRANSCRIPT:?}" ;;
    *) exit 64 ;;
esac
FAKE_SSH
    chmod 0700 "$fake_node_a" "$fake_node_b" "$fake_ssh"
    : >"$case_root/ssh.args"
    (
        cd "$repository_root" || exit 1
        CADDY_ACTION20ARETRY2_INTERCEPTED_TEST=1 \
            CADDY_ACTION20ARETRY_NODE_A_BASELINE="$fake_node_a" \
            CADDY_ACTION20ARETRY_NODE_B_BASELINE="$fake_node_b" \
            CADDY_ACTION20ARETRY_SSH_BINARY="$fake_ssh" \
            ACTION20ARETRY_NODE_A_BASELINE_TRANSCRIPT="$case_root/node-a.baseline" \
            ACTION20ARETRY_NODE_B_BASELINE_TRANSCRIPT="$case_root/node-b.baseline" \
            ACTION20ARETRY_NODE_A_PROBE_TRANSCRIPT="$case_root/node-a.probe" \
            ACTION20ARETRY_NODE_B_PROBE_TRANSCRIPT="$case_root/node-b.probe" \
            ACTION20ARETRY_LAST_STDIN_CAPTURE="$case_root/stdin" \
            ACTION20ARETRY_SSH_ARGS_CAPTURE="$case_root/ssh.args" \
            "$runner"
    ) >"$case_root/stdout" 2>"$case_root/stderr" || observed_status=$?
    printf '%s_case_%s_status=%s\n' "$prefix" "${case_root##*/}" \
        "$observed_status"
    if [[ "$observed_status" -ne "$expected_status" ]]; then
        printf '%s_case_%s_expected_status=%s\n' "$prefix" \
            "${case_root##*/}" "$expected_status" >&2
        sed -n '/action_20a_retry2_assertion_.*=false/p;/action_20a_retry2_first_failure=/p' \
            "$case_root/stdout" >&2
        printf '%s_case_%s_stdout_tail_begin=true\n' "$prefix" \
            "${case_root##*/}" >&2
        tail -n 40 "$case_root/stdout" >&2
        printf '%s_case_%s_stdout_tail_end=true\n' "$prefix" \
            "${case_root##*/}" >&2
        if [[ -s "$case_root/stderr" ]]; then
            printf '%s_case_%s_stderr_begin=true\n' "$prefix" \
                "${case_root##*/}" >&2
            cat "$case_root/stderr" >&2
            printf '%s_case_%s_stderr_end=true\n' "$prefix" \
                "${case_root##*/}" >&2
        fi
        return 1
    fi
    if [[ -s "$case_root/stderr" ]]; then
        printf '%s_case_%s_stderr_nonempty=true\n' "$prefix" \
            "${case_root##*/}" >&2
        return 1
    fi
    if ! grep -Fqx "action_20a_retry2_readiness=$expected_readiness" \
        "$case_root/stdout"; then
        printf '%s_case_%s_readiness_mismatch=true\n' "$prefix" \
            "${case_root##*/}" >&2
        return 1
    fi
    [[ "$(grep -Fxc -- '-T -o BatchMode=yes -o IdentitiesOnly=no -o StrictHostKeyChecking=yes -o HostKeyAlias=pihole0.local.theama.co pi@10.1.0.53 cd / && sudo -n /bin/bash -s -- --node node-a' "$case_root/ssh.args")" -eq 1 ]] ||
        return 1
    [[ "$(grep -Fxc -- '-T -o BatchMode=yes -o IdentitiesOnly=no -o StrictHostKeyChecking=yes -o HostKeyAlias=pihole00.local.theama.co pi@10.1.0.54 cd / && sudo -n /bin/bash -s -- --node node-b' "$case_root/ssh.args")" -eq 1 ]] ||
        return 1
    [[ -s "$case_root/stdin" ]] || return 1
}
run_wrong_directory_case() {
    local case_root=$1
    local observed_status=0

    (
        cd /tmp || exit 1
        CADDY_ACTION20ARETRY2_INTERCEPTED_TEST=1 \
            CADDY_ACTION20ARETRY_NODE_A_BASELINE="$case_root/fake-node-a-baseline" \
            CADDY_ACTION20ARETRY_NODE_B_BASELINE="$case_root/fake-node-b-baseline" \
            CADDY_ACTION20ARETRY_SSH_BINARY="$case_root/fake-ssh" \
            ACTION20ARETRY_NODE_A_BASELINE_TRANSCRIPT="$case_root/node-a.baseline" \
            ACTION20ARETRY_NODE_B_BASELINE_TRANSCRIPT="$case_root/node-b.baseline" \
            ACTION20ARETRY_NODE_A_PROBE_TRANSCRIPT="$case_root/node-a.probe" \
            ACTION20ARETRY_NODE_B_PROBE_TRANSCRIPT="$case_root/node-b.probe" \
            ACTION20ARETRY_LAST_STDIN_CAPTURE="$case_root/wrong-directory.stdin" \
            ACTION20ARETRY_SSH_ARGS_CAPTURE="$case_root/wrong-directory.ssh.args" \
            "$runner"
    ) >"$case_root/wrong-directory.stdout" \
        2>"$case_root/wrong-directory.stderr" || observed_status=$?
    [[ "$observed_status" -eq 1 ]] || return 1
    [[ ! -s "$case_root/wrong-directory.stdout" ]] || return 1
    [[ ! -s "$case_root/wrong-directory.stderr" ]] || return 1
}
static_read_only_policy() {
    ! grep -Eq \
        'systemctl[[:space:]]+(start|stop|restart|reload|enable|disable|mask|unmask|daemon-reload|reset-failed)|ip[[:space:]]+(-[46][[:space:]]+)?(address|addr)[[:space:]]+(add|delete|del)|keepalived[[:space:]].*(reload|restart)|(^|[;&|[:space:]])(install|cp|mv|rm|chmod|chown)[[:space:]]+(/etc|/var/backups|/usr/local)' \
        "$probe" "$runner"
}
notification_not_executed() {
    # Dollar-prefixed tokens are matched as literal source text.
    # shellcheck disable=SC2016
    [[ "$(grep -Fc '$notification_script' "$probe")" -eq 1 ]] || return 1
    # shellcheck disable=SC2016
    grep -Fqx '    _ "$notification_script" "$notification_sha256"' "$probe" ||
        return 1
}

require_gate probe_hash_exact test "$(file_hash "$probe")" = "$probe_sha256"
require_gate runner_hash_exact test "$(file_hash "$runner")" = "$runner_sha256"
require_gate node_a_baseline_immutable test "$(file_hash "$node_a_baseline")" = \
    "$node_a_baseline_sha256"
require_gate node_b_baseline_immutable test "$(file_hash "$node_b_baseline")" = \
    "$node_b_baseline_sha256"
require_gate node_a_producer_immutable test "$(file_hash "$node_a_producer")" = \
    "$node_a_producer_sha256"
require_gate node_b_producer_immutable test "$(file_hash "$node_b_producer")" = \
    "$node_b_producer_sha256"
require_gate historical_retry_outer_immutable test \
    "$(file_hash "$historical_retry_outer")" = "$historical_retry_outer_sha256"
require_gate normalized_diagnostic_outer_immutable test \
    "$(file_hash "$normalized_diagnostic_outer")" = \
    "$normalized_diagnostic_outer_sha256"
require_gate node_a_producer_assertion_count_exact test \
    "$("$node_a_producer" --expected-assertions | wc -l)" -eq 138
require_gate node_b_producer_assertion_count_exact test \
    "$("$node_b_producer" --expected-assertions | wc -l)" -eq 138
require_gate sources_syntax bash -n "$0" "$probe" "$runner" \
    "$node_a_producer" "$node_b_producer"
require_gate sources_shellcheck shellcheck "$0" "$probe" "$runner"
require_gate collision_policy "$collision_checker" "$0" "$probe" "$runner"
require_gate conditional_policy /bin/bash "$conditional_policy" >/dev/null
require_gate transcript_policy /bin/bash "$transcript_policy" >/dev/null
require_gate output_policy /bin/bash "$output_policy" >/dev/null
probe_self_test_status=0
probe_self_test_transcript=$("$probe" --self-test) || probe_self_test_status=$?
readonly probe_self_test_status probe_self_test_transcript
require_gate probe_self_test_status_zero test "$probe_self_test_status" -eq 0
require_gate lifetime_only_drift_regression grep -Fqx \
    'action_20a_retry2_probe_self_test_assertion_lifetime_only_drift_ignored=true' \
    <<<"$probe_self_test_transcript"
require_gate actual_address_change_regression grep -Fqx \
    'action_20a_retry2_probe_self_test_assertion_actual_address_change_detected=true' \
    <<<"$probe_self_test_transcript"
require_gate runner_self_test "$runner" --self-test
require_gate runner_contract_test "$runner" --contract-test
require_gate probe_assertion_count_exact test \
    "$("$probe" --expected-assertions | wc -l)" -eq 46
require_gate probe_assertions_unique test \
    "$("$probe" --expected-assertions | LC_ALL=C sort -u | wc -l)" -eq 46
require_gate runner_assertion_count_exact test \
    "$("$runner" --expected-assertions | wc -l)" -eq 19
require_gate runner_assertions_unique test \
    "$("$runner" --expected-assertions | LC_ALL=C sort -u | wc -l)" -eq 19
require_gate static_read_only_policy static_read_only_policy
require_gate normalized_snapshot_member grep -Fq \
    "printf 'addresses_normalized_sha256=%s\\n'" "$probe"
require_gate volatile_raw_snapshot_member_absent test \
    "$(grep -Fc "printf 'addresses_sha256=%s\\n'" "$probe")" -eq 0
# The dollar-prefixed token is matched as literal source text.
# shellcheck disable=SC2016
require_gate health_helper_invocation_scoped grep -Fq \
    'runuser -u keepalived_script -- "$health_script"' "$probe"
require_gate notification_helper_invocation_absent notification_not_executed
require_gate exact_ipv4_vrid grep -Fq 'value_ipv4_vrid=110' "$probe"
require_gate exact_ipv6_vrid grep -Fq 'value_ipv6_vrid=111' "$probe"
require_gate node_a_priority grep -Fq 'expected_priority=140' "$probe"
require_gate node_b_priority grep -Fq 'expected_priority=100' "$probe"
require_gate node_a_source grep -Fq 'expected_ipv4_source=10.1.0.53' "$probe"
require_gate node_b_source grep -Fq 'expected_ipv4_source=10.1.0.54' "$probe"
require_gate node_a_alias grep -Fq 'host_alias=pihole0.local.theama.co' "$runner"
require_gate node_b_alias grep -Fq 'host_alias=pihole00.local.theama.co' "$runner"
# The dollar-prefixed token is matched as literal source text.
# shellcheck disable=SC2016
require_gate host_alias_applied grep -Fq '"HostKeyAlias=$host_alias"' "$runner"
# The dollar-prefixed token is matched as literal source text.
# shellcheck disable=SC2016
require_gate pseudo_terminal_suppressed grep -Fq \
    '"$ssh_binary" -T -o BatchMode=yes -o IdentitiesOnly=no' "$runner"
require_gate main_inclusion_gate grep -Fq 'main_inclusion_prerequisites' "$runner"
require_gate single_dns_owner_gate grep -Fq 'dns_ipv4_single_owner' "$runner"
require_gate absent_caddy_vips_gate grep -Fq 'caddy_ipv4_absent_both' "$runner"
require_gate intercepted_working_directory_policy grep -Fq \
    '/workspace/homelab-server-configs)' "$runner"

regression_root=$(mktemp -d /tmp/caddy-action20a-retry2-regression.XXXXXX)
readonly regression_root
trap 'rm -rf -- "$regression_root"' EXIT
run_intercepted_case "$regression_root/valid" 1 0 0 \
    ready_for_separately_authorized_action20_activation_design
printf '%s_false_negative_exact_ready_state_accepted=true\n' "$prefix"
require_gate arbitrary_working_directory_rejected run_wrong_directory_case \
    "$regression_root/valid"
run_intercepted_case "$regression_root/no-owner" 0 0 1 \
    prerequisites_required_before_action20_activation
printf '%s_false_positive_zero_dns_owner_rejected=true\n' "$prefix"
run_intercepted_case "$regression_root/node-a-baseline-missing" 1 0 1 \
    prerequisites_required_before_action20_activation node-a-missing
printf '%s_false_positive_missing_node_a_baseline_label_rejected=true\n' "$prefix"
run_intercepted_case "$regression_root/node-b-baseline-duplicate" 1 0 1 \
    prerequisites_required_before_action20_activation node-b-duplicate
printf '%s_false_positive_duplicate_node_b_baseline_label_rejected=true\n' "$prefix"
run_intercepted_case "$regression_root/node-a-probe-missing" 1 0 1 \
    prerequisites_required_before_action20_activation none node-a-missing
printf '%s_false_positive_missing_probe_label_rejected=true\n' "$prefix"
run_intercepted_case "$regression_root/node-b-probe-duplicate" 1 0 1 \
    prerequisites_required_before_action20_activation none node-b-duplicate
printf '%s_false_positive_duplicate_probe_label_rejected=true\n' "$prefix"
printf '%s_false_negative_health_output_capture_preserved=true\n' "$prefix"
printf '%s_production_path_network_contact=false\n' "$prefix"
printf '%s_complete=true\n' "$prefix"
