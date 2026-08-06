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
readonly outer=$caddy_root/scripts/run-dual-node-caddy-runtime-postinstall-action20e-retry2-a-outer.sh
readonly inspector=$caddy_root/scripts/inspect-caddy-runtime-directories-action20e-retry-a.sh
readonly prior_prefix=action_20e_retry_a
readonly expected_node_a_backup=/var/backups/caddy-ha/action20e-node-a-runtime-directories.IYZkKA
readonly expected_node_b_backup=/var/backups/caddy-ha/action20e-node-b-runtime-directories.TFeSbH

regression_root=$(mktemp -d /tmp/caddy-action20e-retry2-a-regression.XXXXXX)
readonly regression_root
trap 'rm -rf -- "$regression_root"' EXIT
readonly valid_transcript=$regression_root/valid.transcript

emit_probe() {
    local node_role=$1
    local backup_path=$2
    local expected_probe_label

    while IFS= read -r expected_probe_label; do
        printf '%s_probe_assertion_%s=true\n' "$prior_prefix" "$expected_probe_label"
    done < <(/bin/bash "$inspector" --expected-assertions)
    printf '%s_probe_assertion_count=63\n' "$prior_prefix"
    printf '%s_probe_failed_assertion_count=0\n' "$prior_prefix"
    printf '%s_probe_first_failure=none\n' "$prior_prefix"
    printf '%s_probe_node_role=%s\n' "$prior_prefix" "$node_role"
    printf '%s_probe_backup_path=%s\n' "$prior_prefix" "$backup_path"
    printf '%s_probe_persistent_mutations=false\n' "$prior_prefix"
    printf '%s_probe_inspection_complete=true\n' "$prior_prefix"
}

{
    emit_probe node-b "$expected_node_b_backup"
    printf '%s_node_b_status=0\n' "$prior_prefix"
    printf '%s_node_b_accepted=true\n' "$prior_prefix"
    emit_probe node-a "$expected_node_a_backup"
    printf '%s_node_a_status=0\n' "$prior_prefix"
    printf '%s_node_a_accepted=true\n' "$prior_prefix"
    printf '%s_keepalived_mutated=false\n' "$prior_prefix"
    printf '%s_service_mutations=false\n' "$prior_prefix"
    printf '%s_vrrp_mutated=false\n' "$prior_prefix"
    printf '%s_vip_mutated=false\n' "$prior_prefix"
    printf '%s_notifier_invoked=false\n' "$prior_prefix"
    printf '%s_persistent_mutations=false\n' "$prior_prefix"
    printf '%s_acceptance_complete=true\n' "$prior_prefix"
    printf '%s_outer_runner_status=0\n' "$prior_prefix"
    printf '%s_outer_cleanup_complete=true\n' "$prior_prefix"
} >"$valid_transcript"

/bin/bash "$outer" --validate-transcript "$valid_transcript" 0 >/dev/null

missing_transcript=$regression_root/missing.transcript
readonly missing_transcript
grep -Fvx "${prior_prefix}_probe_assertion_config_hash_exact=true" "$valid_transcript" >"$missing_transcript"
if /bin/bash "$outer" --validate-transcript "$missing_transcript" 0 >/dev/null 2>&1; then
    printf 'missing production label was accepted\n' >&2
    exit 1
fi

duplicate_transcript=$regression_root/duplicate.transcript
readonly duplicate_transcript
cp "$valid_transcript" "$duplicate_transcript"
printf '%s_probe_assertion_config_hash_exact=true\n' "$prior_prefix" >>"$duplicate_transcript"
if /bin/bash "$outer" --validate-transcript "$duplicate_transcript" 0 >/dev/null 2>&1; then
    printf 'duplicate production label was accepted\n' >&2
    exit 1
fi

false_transcript=$regression_root/false.transcript
readonly false_transcript
cp "$valid_transcript" "$false_transcript"
printf '%s_probe_assertion_config_hash_exact=false\n' "$prior_prefix" >>"$false_transcript"
if /bin/bash "$outer" --validate-transcript "$false_transcript" 0 >/dev/null 2>&1; then
    printf 'false production label was accepted\n' >&2
    exit 1
fi

if /bin/bash "$outer" --validate-transcript "$valid_transcript" 1 >/dev/null 2>&1; then
    printf 'nonzero production status was accepted\n' >&2
    exit 1
fi

printf 'action_20e_retry2_a_regression_complete=true\n'
