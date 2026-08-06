#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
readonly caddy_root=${test_directory%/tests}
readonly outer=$caddy_root/scripts/run-dual-node-caddy-notifier-context-action20d-c-retry-outer.sh
readonly probe=$caddy_root/scripts/inspect-caddy-notifier-context-action20d-c.sh
readonly runner=$caddy_root/scripts/run-dual-node-caddy-notifier-context-action20d-c.sh
readonly probe_prefix=action_20d_c_probe
readonly prior_prefix=action_20d_c
readonly expected_state_metadata=pi:caddy-sync:750
readonly expected_dedupe_metadata=pi:pi:700

regression_root=$(mktemp -d /tmp/caddy-action20d-c-retry-regression.XXXXXX)
readonly regression_root
trap 'rm -rf -- "$regression_root"' EXIT
readonly valid_transcript=$regression_root/valid.transcript

emit_probe() {
    local node_role=$1
    local expected_dns_count=$2
    local expected_label
    local snapshot_hash=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa

    while IFS= read -r expected_label; do
        printf '%s_assertion_%s=true\n' "$probe_prefix" "$expected_label"
    done < <(/bin/bash "$probe" --expected-assertions)
    printf '%s_value_node_role=%s\n' "$probe_prefix" "$node_role"
    printf '%s_value_inherited_execution_user=pi\n' "$probe_prefix"
    printf '%s_value_state_directory_metadata=%s\n' "$probe_prefix" "$expected_state_metadata"
    printf '%s_value_dedupe_directory_metadata=%s\n' "$probe_prefix" "$expected_dedupe_metadata"
    printf '%s_value_caddy_ipv4_vip_count=0\n' "$probe_prefix"
    printf '%s_value_caddy_ipv6_vip_count=0\n' "$probe_prefix"
    printf '%s_value_dns_ipv4_vip_count=%s\n' "$probe_prefix" "$expected_dns_count"
    printf '%s_value_dns_ipv6_vip_count=%s\n' "$probe_prefix" "$expected_dns_count"
    printf '%s_value_before_snapshot_sha256=%s\n' "$probe_prefix" "$snapshot_hash"
    printf '%s_value_after_snapshot_sha256=%s\n' "$probe_prefix" "$snapshot_hash"
    printf '%s_assertion_count=44\n' "$probe_prefix"
    printf '%s_failed_assertion_count=0\n' "$probe_prefix"
    printf '%s_first_failure=none\n' "$probe_prefix"
    printf '%s_notification_helper_invoked=false\n' "$probe_prefix"
    printf '%s_filesystem_mutations=false\n' "$probe_prefix"
    printf '%s_service_mutations=false\n' "$probe_prefix"
    printf '%s_keepalived_mutations=false\n' "$probe_prefix"
    printf '%s_vrrp_mutations=false\n' "$probe_prefix"
    printf '%s_vip_mutations=false\n' "$probe_prefix"
    printf '%s_network_mutations=false\n' "$probe_prefix"
    printf '%s_persistent_mutations=false\n' "$probe_prefix"
    printf '%s_remote_complete=true\n' "$probe_prefix"
}

{
    emit_probe node-a 1
    emit_probe node-b 0
    while IFS= read -r expected_label; do
        printf '%s_assertion_%s=true\n' "$prior_prefix" "$expected_label"
    done < <(/bin/bash "$runner" --expected-assertions)
    printf '%s_value_node_a_state_directory_metadata=%s\n' "$prior_prefix" "$expected_state_metadata"
    printf '%s_value_node_b_state_directory_metadata=%s\n' "$prior_prefix" "$expected_state_metadata"
    printf '%s_value_node_a_dedupe_directory_metadata=%s\n' "$prior_prefix" "$expected_dedupe_metadata"
    printf '%s_value_node_b_dedupe_directory_metadata=%s\n' "$prior_prefix" "$expected_dedupe_metadata"
    printf '%s_assertion_count=27\n' "$prior_prefix"
    printf '%s_failed_assertion_count=0\n' "$prior_prefix"
    printf '%s_first_failure=none\n' "$prior_prefix"
    printf '%s_notification_helper_invoked=false\n' "$prior_prefix"
    printf '%s_filesystem_mutations=false\n' "$prior_prefix"
    printf '%s_service_mutations=false\n' "$prior_prefix"
    printf '%s_keepalived_mutations=false\n' "$prior_prefix"
    printf '%s_vrrp_mutations=false\n' "$prior_prefix"
    printf '%s_vip_mutations=false\n' "$prior_prefix"
    printf '%s_network_mutations=false\n' "$prior_prefix"
    printf '%s_persistent_mutations=false\n' "$prior_prefix"
    printf '%s_runner_cleanup_complete=true\n' "$prior_prefix"
    printf '%s_inner_status=0\n' "$prior_prefix"
    printf '%s_outer_cleanup_complete=true\n' "$prior_prefix"
} >"$valid_transcript"

/bin/bash "$outer" --validate-transcript "$valid_transcript" 0 >/dev/null

missing_transcript=$regression_root/missing.transcript
readonly missing_transcript
grep -Fvx "${probe_prefix}_assertion_state_directory_writable_as_pi=true" "$valid_transcript" >"$missing_transcript"
if /bin/bash "$outer" --validate-transcript "$missing_transcript" 0 >/dev/null 2>&1; then
    printf 'missing production label was accepted\n' >&2
    exit 1
fi

duplicate_transcript=$regression_root/duplicate.transcript
readonly duplicate_transcript
cp "$valid_transcript" "$duplicate_transcript"
printf '%s_assertion_state_directory_writable_as_pi=true\n' "$probe_prefix" >>"$duplicate_transcript"
if /bin/bash "$outer" --validate-transcript "$duplicate_transcript" 0 >/dev/null 2>&1; then
    printf 'duplicate production label was accepted\n' >&2
    exit 1
fi

false_transcript=$regression_root/false.transcript
readonly false_transcript
cp "$valid_transcript" "$false_transcript"
printf '%s_assertion_state_directory_writable_as_pi=false\n' "$probe_prefix" >>"$false_transcript"
if /bin/bash "$outer" --validate-transcript "$false_transcript" 0 >/dev/null 2>&1; then
    printf 'false production label was accepted\n' >&2
    exit 1
fi

metadata_transcript=$regression_root/metadata.transcript
readonly metadata_transcript
sed "0,/${expected_state_metadata}/s//pi:caddy-sync:755/" "$valid_transcript" >"$metadata_transcript"
if /bin/bash "$outer" --validate-transcript "$metadata_transcript" 0 >/dev/null 2>&1; then
    printf 'wrong production metadata was accepted\n' >&2
    exit 1
fi

if /bin/bash "$outer" --validate-transcript "$valid_transcript" 1 >/dev/null 2>&1; then
    printf 'nonzero production status was accepted\n' >&2
    exit 1
fi

printf 'action_20d_c_retry_regression_complete=true\n'
