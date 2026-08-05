#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_20a_retry_a
readonly inspector_sha256=09b5d6fd7d86fe3bd79e84850a88210a4fed55c2ae1f80946f9e96a7da6ba764
readonly failed_retry_outer_sha256=ea0817dccfee0cabf096a53d2d2077035f3cec8a78baded465519df854583845
readonly accepted_node_a_outer_sha256=42874857457884bf143fe4d5faa8492cd2b409994182243bf9734bafb98c29f3
readonly accepted_node_b_outer_sha256=6f017e78870c6433c2b9f7180003fe6ab81f2a0f1e44fc63dbaf5ee6ea67487f
readonly normalized_baseline_sha256=bc1f5fc7dc9de385ba00e8f9868df6857306cc4268de6a899a73ccc7098c1ceb
readonly maximum_stream_bytes=1048576
readonly maximum_stream_lines=8192

script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
readonly inspector="$script_directory/inspect-node-b-caddy-state-difference-action20a-retry-a.sh"
readonly failed_retry_outer="$script_directory/run-dual-node-caddy-vrrp-preactivation-action20a-retry-outer.sh"
readonly accepted_node_a_outer="$script_directory/run-node-a-caddy-health-postinstall-action20c-a-outer.sh"
readonly accepted_node_b_outer="$script_directory/run-node-b-caddy-health-postinstall-action20b-a-outer.sh"
readonly normalized_baseline="$script_directory/inspect-dual-node-caddy-postfailure-continuity-action20a-b.sh"

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }
line_count() { awk 'END { print NR }' "$1"; }
require_one() {
    local exact_line=$1
    local transcript_path=$2

    [[ "$(grep -Fxc "$exact_line" "$transcript_path")" -eq 1 ]]
}
extract_one() {
    local key_name=$1
    local transcript_path=$2
    local extracted_value

    [[ "$(grep -c "^${key_name}=" "$transcript_path")" -eq 1 ]] || return 1
    extracted_value=$(sed -n "s/^${key_name}=//p" "$transcript_path") || return 1
    printf '%s\n' "$extracted_value"
}
safe_stream() {
    local stream_path=$1

    [[ "$(wc -c <"$stream_path")" -le "$maximum_stream_bytes" ]] || return 1
    [[ "$(line_count "$stream_path")" -le "$maximum_stream_lines" ]] ||
        return 1
    ! LC_ALL=C grep -n '[^[:print:][:space:]]' "$stream_path" >/dev/null ||
        return 1
    ! grep -Eqi \
        'BEGIN [A-Z ]*PRIVATE KEY|CADDY_TLS_PRIVATE_KEY_PEM|PRIVATE_KEY=|DOPPLER_TOKEN|Authorization:[[:space:]]*Bearer' \
        "$stream_path"
}
emit_stream() {
    local stream_label=$1
    local stream_path=$2

    printf '%s_%s_bytes=%s\n' "$prefix" "$stream_label" \
        "$(wc -c <"$stream_path")"
    printf '%s_%s_lines=%s\n' "$prefix" "$stream_label" \
        "$(line_count "$stream_path")"
    printf '%s_%s_sha256=%s\n' "$prefix" "$stream_label" \
        "$(file_hash "$stream_path")"
    if safe_stream "$stream_path"; then
        printf '%s_%s_classification=bounded_safe\n' "$prefix" "$stream_label"
        if [[ -s "$stream_path" ]]; then
            printf '%s_%s_begin\n' "$prefix" "$stream_label"
            cat "$stream_path"
            printf '%s_%s_end\n' "$prefix" "$stream_label"
        else
            printf '%s_%s_content_secured=empty\n' "$prefix" "$stream_label"
        fi
        return 0
    fi
    printf '%s_%s_classification=unsafe_retained\n' "$prefix" "$stream_label" >&2
    return 97
}
expected_assertions() {
    printf '%s\n' \
        remote_status_zero remote_stderr_empty producer_contract_exact \
        node_role_exact component_inventory_complete \
        component_comparisons_consistent changed_inventory_exact \
        classification_consistent mutation_markers_false
}
hash_relationship_valid() {
    local changed_count_value=$1
    local before_hash_value=$2
    local after_hash_value=$3

    if [[ "$changed_count_value" -eq 0 ]]; then
        [[ "$before_hash_value" = "$after_hash_value" ]]
    else
        [[ "$before_hash_value" != "$after_hash_value" ]]
    fi
}
# Called indirectly through run_assertion.
# shellcheck disable=SC2317
component_inventory_valid() {
    local inventory_transcript_path=$1
    local inventory_component
    local inventory_count=0

    while IFS= read -r inventory_component; do
        [[ "$(grep -Ec \
            "^action_20a_retry_a_probe_value_before_${inventory_component}=.*$" \
            "$inventory_transcript_path")" -eq 1 ]] || return 1
        [[ "$(grep -Ec \
            "^action_20a_retry_a_probe_value_after_${inventory_component}=.*$" \
            "$inventory_transcript_path")" -eq 1 ]] || return 1
        inventory_count=$((inventory_count + 1))
    done < <(/bin/bash "$inspector" --snapshot-components)
    [[ "$inventory_count" -eq 21 ]]
}
verify_sources() {
    [[ -f "$inspector" && ! -L "$inspector" ]] || return 1
    [[ -f "$failed_retry_outer" && ! -L "$failed_retry_outer" ]] || return 1
    [[ -f "$accepted_node_a_outer" && ! -L "$accepted_node_a_outer" ]] ||
        return 1
    [[ -f "$accepted_node_b_outer" && ! -L "$accepted_node_b_outer" ]] ||
        return 1
    [[ -f "$normalized_baseline" && ! -L "$normalized_baseline" ]] || return 1
    [[ "$(file_hash "$inspector")" = "$inspector_sha256" ]] || return 1
    [[ "$(file_hash "$failed_retry_outer")" = "$failed_retry_outer_sha256" ]] ||
        return 1
    [[ "$(file_hash "$accepted_node_a_outer")" = "$accepted_node_a_outer_sha256" ]] ||
        return 1
    [[ "$(file_hash "$accepted_node_b_outer")" = "$accepted_node_b_outer_sha256" ]] ||
        return 1
    [[ "$(file_hash "$normalized_baseline")" = "$normalized_baseline_sha256" ]] ||
        return 1
    /bin/bash -n "$inspector" || return 1
    /bin/bash "$inspector" --self-test >/dev/null || return 1
}
validate_transcript() {
    local transcript_path=$1
    local transcript_status=$2
    local validation_root
    local expected_label
    local inspected_component
    local before_value
    local after_value
    local observed_classification
    local expected_classification
    local observed_changed_components
    local observed_changed_count
    local recomputed_changed_components=none
    local recomputed_changed_count=0
    local recomputed_overall_classification
    local observed_before_hash
    local observed_after_hash
    local expected_count

    [[ "$transcript_status" -eq 0 ]] || return 1
    validation_root=$(mktemp -d /tmp/caddy-action20a-retry-a-contract.XXXXXX) ||
        return 1
    # conditional-validator-explicit-failures-begin
    /bin/bash "$inspector" --expected-assertions | LC_ALL=C sort \
        >"$validation_root/expected" || {
        rm -rf -- "$validation_root"
        return 1
    }
    sed -n 's/^action_20a_retry_a_probe_assertion_\([a-z0-9_]*\)=true$/\1/p' \
        "$transcript_path" | LC_ALL=C sort >"$validation_root/observed" || {
        rm -rf -- "$validation_root"
        return 1
    }
    if ! cmp -s "$validation_root/expected" "$validation_root/observed"; then
        rm -rf -- "$validation_root"
        return 1
    fi
    expected_count=$(wc -l <"$validation_root/expected") || {
        rm -rf -- "$validation_root"
        return 1
    }
    while IFS= read -r expected_label; do
        if ! require_one \
            "action_20a_retry_a_probe_assertion_${expected_label}=true" \
            "$transcript_path"; then
            rm -rf -- "$validation_root"
            return 1
        fi
    done <"$validation_root/expected"
    if grep -Eq '^action_20a_retry_a_probe_assertion_[a-z0-9_]+=false$' \
        "$transcript_path"; then
        rm -rf -- "$validation_root"
        return 1
    fi
    for required_record in \
        "action_20a_retry_a_probe_assertion_count=$expected_count" \
        action_20a_retry_a_probe_failed_assertion_count=0 \
        action_20a_retry_a_probe_first_failure=none \
        action_20a_retry_a_probe_value_node_role=node-b \
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
        action_20a_retry_a_probe_remote_complete=true; do
        if ! require_one "$required_record" "$transcript_path"; then
            rm -rf -- "$validation_root"
            return 1
        fi
    done
    /bin/bash "$inspector" --snapshot-components >"$validation_root/components" || {
        rm -rf -- "$validation_root"
        return 1
    }
    while IFS= read -r inspected_component; do
        before_value=$(extract_one \
            "action_20a_retry_a_probe_value_before_${inspected_component}" \
            "$transcript_path") || {
            rm -rf -- "$validation_root"
            return 1
        }
        after_value=$(extract_one \
            "action_20a_retry_a_probe_value_after_${inspected_component}" \
            "$transcript_path") || {
            rm -rf -- "$validation_root"
            return 1
        }
        observed_classification=$(extract_one \
            "action_20a_retry_a_probe_value_component_${inspected_component}_classification" \
            "$transcript_path") || {
            rm -rf -- "$validation_root"
            return 1
        }
        if [[ "$before_value" = "$after_value" ]]; then
            expected_classification=unchanged
        else
            expected_classification=changed
            recomputed_changed_count=$((recomputed_changed_count + 1))
            if [[ "$recomputed_changed_components" = none ]]; then
                recomputed_changed_components=$inspected_component
            else
                recomputed_changed_components+=,$inspected_component
            fi
        fi
        if [[ "$observed_classification" != "$expected_classification" ]]; then
            rm -rf -- "$validation_root"
            return 1
        fi
    done <"$validation_root/components"
    observed_changed_count=$(extract_one \
        action_20a_retry_a_probe_value_changed_component_count \
        "$transcript_path") || {
        rm -rf -- "$validation_root"
        return 1
    }
    observed_changed_components=$(extract_one \
        action_20a_retry_a_probe_value_changed_components \
        "$transcript_path") || {
        rm -rf -- "$validation_root"
        return 1
    }
    if [[ "$observed_changed_count" != "$recomputed_changed_count" ||
        "$observed_changed_components" != "$recomputed_changed_components" ]]; then
        rm -rf -- "$validation_root"
        return 1
    fi
    observed_before_hash=$(extract_one \
        action_20a_retry_a_probe_value_before_state_sha256 \
        "$transcript_path") || {
        rm -rf -- "$validation_root"
        return 1
    }
    observed_after_hash=$(extract_one \
        action_20a_retry_a_probe_value_after_state_sha256 \
        "$transcript_path") || {
        rm -rf -- "$validation_root"
        return 1
    }
    if [[ ! "$observed_before_hash" =~ ^[0-9a-f]{64}$ ||
        ! "$observed_after_hash" =~ ^[0-9a-f]{64}$ ]]; then
        rm -rf -- "$validation_root"
        return 1
    fi
    hash_relationship_valid "$recomputed_changed_count" "$observed_before_hash" \
        "$observed_after_hash" || {
        rm -rf -- "$validation_root"
        return 1
    }
    case "$recomputed_changed_components" in
        none) recomputed_overall_classification=no_difference_observed ;;
        legacy_addresses_sha256 | legacy_addresses_raw | \
            legacy_addresses_sha256,legacy_addresses_raw)
            recomputed_overall_classification=legacy_address_lifetime_drift_only
            ;;
        *)
            recomputed_overall_classification=persistent_component_difference_observed
            ;;
    esac
    if ! require_one \
        "action_20a_retry_a_probe_value_state_difference_classification=${recomputed_overall_classification}" \
        "$transcript_path"; then
        rm -rf -- "$validation_root"
        return 1
    fi
    # conditional-validator-explicit-failures-end
    rm -rf -- "$validation_root"
}
write_contract_fixture() {
    local fixture_path=$1
    local fixture_classification=$2
    local fixture_label
    local fixture_component
    local fixture_before
    local fixture_after
    local fixture_component_classification
    local fixture_changed_components=none
    local fixture_changed_count=0
    local fixture_before_hash=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
    local fixture_after_hash=$fixture_before_hash

    {
        while IFS= read -r fixture_label; do
            printf 'action_20a_retry_a_probe_assertion_%s=true\n' "$fixture_label"
        done < <(/bin/bash "$inspector" --expected-assertions)
        while IFS= read -r fixture_component; do
            fixture_before=fixture-$fixture_component
            fixture_after=$fixture_before
            case "$fixture_classification:$fixture_component" in
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
        case "$fixture_classification" in
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
run_contract_test() {
    local contract_root
    local contract_classification

    contract_root=$(mktemp -d /tmp/caddy-action20a-retry-a-runner-contract.XXXXXX) ||
        return 1
    for contract_classification in none legacy persistent; do
        write_contract_fixture "$contract_root/$contract_classification" \
            "$contract_classification" || {
            rm -rf -- "$contract_root"
            return 1
        }
        validate_transcript "$contract_root/$contract_classification" 0 || {
            rm -rf -- "$contract_root"
            return 1
        }
        printf '%s_contract_%s_classification_accepted=true\n' "$prefix" \
            "$contract_classification"
    done
    rm -rf -- "$contract_root"
}

case "${1:-}" in
    --expected-assertions)
        [[ $# -eq 1 ]] || exit 64
        expected_assertions
        exit 0
        ;;
    --self-test)
        [[ $# -eq 1 ]] || exit 64
        verify_sources
        printf '%s_runner_self_test_complete=true\n' "$prefix"
        exit 0
        ;;
    --contract-test)
        [[ $# -eq 1 ]] || exit 64
        verify_sources
        run_contract_test
        printf '%s_runner_contract_test_complete=true\n' "$prefix"
        exit 0
        ;;
    "") [[ $# -eq 0 ]] || exit 64 ;;
    *)
        printf 'Usage: %s [--self-test|--contract-test|--expected-assertions]\n' \
            "${0##*/}" >&2
        exit 64
        ;;
esac

verify_sources
if [[ "${CADDY_ACTION20ARETRYA_INTERCEPTED_TEST:-}" = 1 ]]; then
    case "$PWD" in
        /home/aaron/code/homelab-server-configs | \
            /workspace/homelab-server-configs) ;;
        *) exit 1 ;;
    esac
    ssh_binary=${CADDY_ACTION20ARETRYA_SSH_BINARY:?}
else
    [[ "$PWD" = /home/aaron/code/homelab-server-configs ]]
    ssh_binary=/usr/bin/ssh
fi
readonly ssh_binary

work_directory=$(mktemp -d /tmp/caddy-action20a-retry-a-runner.XXXXXX)
readonly work_directory
cleanup() {
    # shellcheck disable=SC2317
    rm -rf -- "$work_directory"
}
trap cleanup EXIT
readonly stdout_path=$work_directory/remote.stdout
readonly stderr_path=$work_directory/remote.stderr
: >"$stdout_path"
: >"$stderr_path"
chmod 0600 "$stdout_path" "$stderr_path"

remote_status=0
"$ssh_binary" -T -o BatchMode=yes -o IdentitiesOnly=no \
    -o StrictHostKeyChecking=yes -o HostKeyAlias=pihole00.local.theama.co \
    pi@10.1.0.54 'cd / && sudo -n /bin/bash -s' <"$inspector" \
    >"$stdout_path" 2>"$stderr_path" || remote_status=$?
readonly remote_status
emit_stream remote_stdout "$stdout_path" || {
    trap - EXIT
    printf '%s_protected_evidence=%s\n' "$prefix" "$work_directory" >&2
    exit 97
}
emit_stream remote_stderr "$stderr_path" || {
    trap - EXIT
    printf '%s_protected_evidence=%s\n' "$prefix" "$work_directory" >&2
    exit 97
}

failed_count=0
first_failure=none
run_assertion() {
    local assertion_label=$1

    shift
    if "$@"; then
        printf '%s_assertion_%s=true\n' "$prefix" "$assertion_label"
        return 0
    fi
    printf '%s_assertion_%s=false\n' "$prefix" "$assertion_label"
    failed_count=$((failed_count + 1))
    if [[ "$first_failure" = none ]]; then first_failure=$assertion_label; fi
    return 0
}

transcript_validation=0
validate_transcript "$stdout_path" "$remote_status" || transcript_validation=$?
readonly transcript_validation
classification=$(extract_one \
    action_20a_retry_a_probe_value_state_difference_classification \
    "$stdout_path" || true)
changed_components=$(extract_one \
    action_20a_retry_a_probe_value_changed_components "$stdout_path" || true)
changed_count=$(extract_one \
    action_20a_retry_a_probe_value_changed_component_count "$stdout_path" || true)
readonly classification changed_components changed_count

run_assertion remote_status_zero test "$remote_status" -eq 0
run_assertion remote_stderr_empty test ! -s "$stderr_path"
run_assertion producer_contract_exact test "$transcript_validation" -eq 0
run_assertion node_role_exact require_one \
    action_20a_retry_a_probe_value_node_role=node-b "$stdout_path"
run_assertion component_inventory_complete component_inventory_valid "$stdout_path"
run_assertion component_comparisons_consistent test "$transcript_validation" -eq 0
run_assertion changed_inventory_exact test "$transcript_validation" -eq 0
run_assertion classification_consistent grep -Eq \
    '^(no_difference_observed|legacy_address_lifetime_drift_only|persistent_component_difference_observed)$' \
    <<<"$classification"
run_assertion mutation_markers_false test "$transcript_validation" -eq 0

expected_assertion_count=$(expected_assertions | wc -l)
readonly expected_assertion_count
printf '%s_value_state_difference_classification=%s\n' "$prefix" "$classification"
printf '%s_value_changed_component_count=%s\n' "$prefix" "$changed_count"
printf '%s_value_changed_components=%s\n' "$prefix" "$changed_components"
printf '%s_assertion_count=%s\n' "$prefix" "$expected_assertion_count"
printf '%s_failed_assertion_count=%s\n' "$prefix" "$failed_count"
printf '%s_first_failure=%s\n' "$prefix" "$first_failure"
printf '%s_health_helper_invoked=false\n' "$prefix"
printf '%s_notification_helper_invoked=false\n' "$prefix"
printf '%s_service_mutations=false\n' "$prefix"
printf '%s_keepalived_mutations=false\n' "$prefix"
printf '%s_vrrp_mutations=false\n' "$prefix"
printf '%s_vip_mutations=false\n' "$prefix"
printf '%s_persistent_mutations=false\n' "$prefix"
rm -rf -- "$work_directory"
trap - EXIT
printf '%s_runner_cleanup_complete=true\n' "$prefix"
if [[ "$failed_count" -eq 0 ]]; then exit 0; fi
exit 1
