#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_20a_retry_a_regression
readonly inspector_sha256=09b5d6fd7d86fe3bd79e84850a88210a4fed55c2ae1f80946f9e96a7da6ba764
readonly runner_sha256=bbbc69d964d63c33ae413dc65f2687c914c2b2b0b4019aa9b89201d0f9f7be56
readonly failed_retry_probe_sha256=19d3fffb5519d143c4e7c27c384ba9d30020ffc0174fb320be5088ca90c51076
readonly failed_retry_runner_sha256=cfac0ff96026ec1586ad3265e44d5962310cc9bfb18b0bdfcf883fb38ef0e536
readonly failed_retry_outer_sha256=ea0817dccfee0cabf096a53d2d2077035f3cec8a78baded465519df854583845
readonly normalized_baseline_sha256=bc1f5fc7dc9de385ba00e8f9868df6857306cc4268de6a899a73ccc7098c1ceb

test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
readonly caddy_root=${test_directory%/tests}
readonly repository_root=${caddy_root%/Caddy}
readonly inspector="$caddy_root/scripts/inspect-node-b-caddy-state-difference-action20a-retry-a.sh"
readonly runner="$caddy_root/scripts/run-node-b-caddy-state-difference-action20a-retry-a.sh"
readonly failed_retry_probe="$caddy_root/scripts/inspect-dual-node-caddy-vrrp-preactivation-action20a-retry.sh"
readonly failed_retry_runner="$caddy_root/scripts/run-dual-node-caddy-vrrp-preactivation-action20a-retry.sh"
readonly failed_retry_outer="$caddy_root/scripts/run-dual-node-caddy-vrrp-preactivation-action20a-retry-outer.sh"
readonly normalized_baseline="$caddy_root/scripts/inspect-dual-node-caddy-postfailure-continuity-action20a-b.sh"
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
write_fixture() {
    local fixture_path=$1
    local fixture_kind=$2
    local fixture_label
    local fixture_component
    local fixture_before
    local fixture_after
    local fixture_component_classification
    local fixture_changed_components=none
    local fixture_changed_count=0
    local fixture_before_hash=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
    local fixture_after_hash=$fixture_before_hash
    local fixture_overall

    {
        while IFS= read -r fixture_label; do
            printf 'action_20a_retry_a_probe_assertion_%s=true\n' "$fixture_label"
        done < <(/bin/bash "$inspector" --expected-assertions)
        while IFS= read -r fixture_component; do
            fixture_before=fixture-$fixture_component
            fixture_after=$fixture_before
            case "$fixture_kind:$fixture_component" in
                legacy:legacy_addresses_sha256 | legacy:legacy_addresses_raw | \
                    persistent:caddy_main_pid)
                    fixture_after=changed-$fixture_component
                    fixture_component_classification=changed
                    fixture_changed_count=$((fixture_changed_count + 1))
                    fixture_after_hash=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
                    if [[ "$fixture_changed_components" = none ]]; then
                        fixture_changed_components=$fixture_component
                    else
                        fixture_changed_components+=,$fixture_component
                    fi
                    ;;
                *) fixture_component_classification=unchanged ;;
            esac
            printf 'action_20a_retry_a_probe_value_before_%s=%s\n' \
                "$fixture_component" "$fixture_before"
            printf 'action_20a_retry_a_probe_value_after_%s=%s\n' \
                "$fixture_component" "$fixture_after"
            printf 'action_20a_retry_a_probe_value_component_%s_classification=%s\n' \
                "$fixture_component" "$fixture_component_classification"
        done < <(/bin/bash "$inspector" --snapshot-components)
        case "$fixture_kind" in
            none) fixture_overall=no_difference_observed ;;
            legacy) fixture_overall=legacy_address_lifetime_drift_only ;;
            persistent) fixture_overall=persistent_component_difference_observed ;;
            *) return 1 ;;
        esac
        printf '%s\n' \
            action_20a_retry_a_probe_value_node_role=node-b \
            action_20a_retry_a_probe_value_dns_ipv4_vip_count=0 \
            action_20a_retry_a_probe_value_dns_ipv6_vip_count=0 \
            "action_20a_retry_a_probe_value_before_state_sha256=$fixture_before_hash" \
            "action_20a_retry_a_probe_value_after_state_sha256=$fixture_after_hash" \
            "action_20a_retry_a_probe_value_changed_component_count=$fixture_changed_count" \
            "action_20a_retry_a_probe_value_changed_components=$fixture_changed_components" \
            "action_20a_retry_a_probe_value_state_difference_classification=$fixture_overall" \
            "action_20a_retry_a_probe_assertion_count=$(/bin/bash "$inspector" --expected-assertions | wc -l)" \
            action_20a_retry_a_probe_failed_assertion_count=0 \
            action_20a_retry_a_probe_first_failure=none \
            action_20a_retry_a_probe_health_helper_invoked=false \
            action_20a_retry_a_probe_notification_helper_invoked=false \
            action_20a_retry_a_probe_caddy_validation_invoked=false \
            action_20a_retry_a_probe_transient_filesystem_activity=true \
            action_20a_retry_a_probe_service_mutations=false \
            action_20a_retry_a_probe_keepalived_mutations=false \
            action_20a_retry_a_probe_vrrp_mutations=false \
            action_20a_retry_a_probe_vip_mutations=false \
            action_20a_retry_a_probe_persistent_mutations=false \
            action_20a_retry_a_probe_remote_cleanup_complete=true \
            action_20a_retry_a_probe_remote_complete=true
    } >"$fixture_path"
}
run_intercepted_case() {
    local case_root=$1
    local fixture_kind=$2
    local corruption_kind=$3
    local expected_status=$4
    local fake_ssh=$case_root/fake-ssh
    local duplicate_line
    local observed_status=0

    install -d -m 0700 "$case_root"
    write_fixture "$case_root/transcript" "$fixture_kind"
    case "$corruption_kind" in
        none) ;;
        missing)
            awk '!removed && /^action_20a_retry_a_probe_assertion_/ { removed=1; next } { print }' \
                "$case_root/transcript" >"$case_root/transcript.new"
            mv "$case_root/transcript.new" "$case_root/transcript"
            ;;
        duplicate)
            duplicate_line=$(grep -m1 '^action_20a_retry_a_probe_assertion_' \
                "$case_root/transcript")
            printf '%s\n' "$duplicate_line" >>"$case_root/transcript"
            ;;
        inconsistent)
            sed -i \
                's/value_state_difference_classification=legacy_address_lifetime_drift_only/value_state_difference_classification=no_difference_observed/' \
                "$case_root/transcript"
            ;;
        *) return 1 ;;
    esac
    cat >"$fake_ssh" <<'FAKE_SSH'
#!/usr/bin/env bash
set -Eeuo pipefail
cat >"${ACTION20ARETRYA_STDIN_CAPTURE:?}"
printf '%s\n' "$*" >"${ACTION20ARETRYA_SSH_ARGS_CAPTURE:?}"
cat "${ACTION20ARETRYA_TRANSCRIPT:?}"
FAKE_SSH
    chmod 0700 "$fake_ssh"
    (
        cd "$repository_root" || exit 1
        CADDY_ACTION20ARETRYA_INTERCEPTED_TEST=1 \
            CADDY_ACTION20ARETRYA_SSH_BINARY="$fake_ssh" \
            ACTION20ARETRYA_STDIN_CAPTURE="$case_root/stdin" \
            ACTION20ARETRYA_SSH_ARGS_CAPTURE="$case_root/ssh.args" \
            ACTION20ARETRYA_TRANSCRIPT="$case_root/transcript" \
            /bin/bash "$runner"
    ) >"$case_root/stdout" 2>"$case_root/stderr" || observed_status=$?
    printf '%s_case_%s_status=%s\n' "$prefix" "${case_root##*/}" \
        "$observed_status"
    if [[ "$observed_status" -ne "$expected_status" ]]; then
        printf '%s_case_%s_expected_status=%s\n' "$prefix" \
            "${case_root##*/}" "$expected_status" >&2
        sed -n '/action_20a_retry_a_assertion_.*=false/p;/action_20a_retry_a_first_failure=/p' \
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
    [[ -s "$case_root/stdin" ]] || return 1
    grep -Fqx -- \
        '-T -o BatchMode=yes -o IdentitiesOnly=no -o StrictHostKeyChecking=yes -o HostKeyAlias=pihole00.local.theama.co pi@10.1.0.54 cd / && sudo -n /bin/bash -s' \
        "$case_root/ssh.args" || return 1
}
static_read_only_policy() {
    ! grep -Eq \
        'systemctl[[:space:]]+(start|stop|restart|reload|enable|disable|mask|unmask|daemon-reload|reset-failed)|ip[[:space:]]+(-[46][[:space:]]+)?(address|addr)[[:space:]]+(add|delete|del)|keepalived[[:space:]].*(reload|restart)|(^|[;&|[:space:]])(install|cp|mv|chmod|chown)[[:space:]]+(/etc|/var/backups|/usr/local)' \
        "$inspector" "$runner"
}
helper_invocation_absent() {
    ! grep -Eq \
        'runuser.*check-caddy|(^|[;&|[:space:]])/usr/local/libexec/check-caddy\.sh([;&|[:space:]]|$)|caddy[[:space:]]+validate|lsyncd-ha-failover-notify\.sh[;&|[:space:]]' \
        "$inspector" "$runner"
}

require_gate inspector_hash_exact test "$(file_hash "$inspector")" = \
    "$inspector_sha256"
require_gate runner_hash_exact test "$(file_hash "$runner")" = "$runner_sha256"
require_gate failed_retry_probe_immutable test "$(file_hash "$failed_retry_probe")" = \
    "$failed_retry_probe_sha256"
require_gate failed_retry_runner_immutable test "$(file_hash "$failed_retry_runner")" = \
    "$failed_retry_runner_sha256"
require_gate failed_retry_outer_immutable test "$(file_hash "$failed_retry_outer")" = \
    "$failed_retry_outer_sha256"
require_gate normalized_baseline_immutable test "$(file_hash "$normalized_baseline")" = \
    "$normalized_baseline_sha256"
require_gate sources_syntax /bin/bash -n "$0" "$inspector" "$runner"
require_gate sources_shellcheck shellcheck "$0" "$inspector" "$runner"
require_gate collision_policy /bin/bash "$collision_checker" "$0" \
    "$inspector" "$runner"
require_gate conditional_policy /bin/bash "$conditional_policy" >/dev/null
require_gate transcript_policy /bin/bash "$transcript_policy" >/dev/null
require_gate output_policy /bin/bash "$output_policy" >/dev/null
require_gate inspector_self_test /bin/bash "$inspector" --self-test
require_gate runner_self_test /bin/bash "$runner" --self-test
require_gate runner_contract_test /bin/bash "$runner" --contract-test
require_gate component_count_exact test \
    "$(/bin/bash "$inspector" --snapshot-components | wc -l)" -eq 21
require_gate component_inventory_unique test \
    "$(/bin/bash "$inspector" --snapshot-components | LC_ALL=C sort -u | wc -l)" \
    -eq 21
require_gate assertion_count_exact test \
    "$(/bin/bash "$inspector" --expected-assertions | wc -l)" -eq 85
require_gate static_read_only_policy static_read_only_policy
require_gate helper_invocation_absent helper_invocation_absent
require_gate normalized_addresses_exclude_lifetimes test \
    "$(sed -n '/^normalized_addresses()/,/^}/p' "$inspector" |
        grep -Ec 'valid_lft|preferred_lft')" -eq 0
require_gate legacy_address_boundary_present grep -Fq \
    'legacy_addresses_sha256' "$inspector"

regression_root=$(mktemp -d /tmp/caddy-action20a-retry-a-regression.XXXXXX)
readonly regression_root
trap 'rm -rf -- "$regression_root"' EXIT
require_gate no_difference_accepted run_intercepted_case \
    "$regression_root/none" none none 0
require_gate legacy_lifetime_drift_accepted run_intercepted_case \
    "$regression_root/legacy" legacy none 0
require_gate persistent_difference_accepted run_intercepted_case \
    "$regression_root/persistent" persistent none 0
require_gate missing_label_rejected run_intercepted_case \
    "$regression_root/missing" none missing 1
require_gate duplicate_label_rejected run_intercepted_case \
    "$regression_root/duplicate" none duplicate 1
require_gate inconsistent_classification_rejected run_intercepted_case \
    "$regression_root/inconsistent" legacy inconsistent 1

printf '%s_false_negative_no_difference_accepted=true\n' "$prefix"
printf '%s_false_negative_legacy_drift_accepted=true\n' "$prefix"
printf '%s_false_negative_persistent_difference_accepted=true\n' "$prefix"
printf '%s_false_positive_missing_label_rejected=true\n' "$prefix"
printf '%s_false_positive_duplicate_label_rejected=true\n' "$prefix"
printf '%s_false_positive_inconsistent_classification_rejected=true\n' "$prefix"
printf '%s_production_path_network_contact=false\n' "$prefix"
printf '%s_complete=true\n' "$prefix"
