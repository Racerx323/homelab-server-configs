#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_20c_a_regression
readonly inspector_sha256=50b5c636e68fbe9694714bda4cc92fbad40a718d038523e80ad5ffd172b5eb66
readonly runner_sha256=c477f26cfa42f41c45d4ad8563443cf3fb5b2df2e4db8a75ddea9c000769a8d0
readonly continuity_inspector_sha256=bc1f5fc7dc9de385ba00e8f9868df6857306cc4268de6a899a73ccc7098c1ceb
readonly transaction_outer_sha256=e1b21e1aac1a3b66d6f1d16866ae4fd5b13f3ab87bc2322a50c8c885a8a0f43d

test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
readonly caddy_root=${test_directory%/tests}
readonly repository_root=${caddy_root%/Caddy}
readonly inspector="$caddy_root/scripts/inspect-node-a-caddy-health-postinstall-action20c-a.sh"
readonly runner="$caddy_root/scripts/run-node-a-caddy-health-postinstall-action20c-a.sh"
readonly continuity_inspector="$caddy_root/scripts/inspect-dual-node-caddy-postfailure-continuity-action20a-b.sh"
readonly transaction_outer="$caddy_root/scripts/run-node-a-caddy-health-context-correction-action20c-outer.sh"
readonly collision_checker="$test_directory/check-shell-readonly-local-collisions-v2.sh"
readonly host_suite="$test_directory/run.sh"
readonly integration_suite="$test_directory/integration.sh"

case "${1:-}" in
    --self-test) [[ $# -eq 1 ]] || exit 64 ;;
    "") [[ $# -eq 0 ]] || exit 64 ;;
    *)
        printf 'Usage: %s [--self-test]\n' "${0##*/}" >&2
        exit 64
        ;;
esac

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

production_label_alignment() {
    local alignment_root
    local expected_count
    local static_label

    alignment_root=$(mktemp -d /tmp/caddy-action20c-a-labels.XXXXXX)
    "$inspector" --expected-assertions | LC_ALL=C sort >"$alignment_root/expected"
    awk '/^run_assertion [a-z0-9_]+/ { print $2 }' "$inspector" |
        LC_ALL=C sort -u >"$alignment_root/static"
    while IFS= read -r static_label; do
        grep -Fqx "$static_label" "$alignment_root/expected" || {
            rm -rf -- "$alignment_root"
            return 1
        }
    done <"$alignment_root/static"
    expected_count=$(wc -l <"$alignment_root/expected")
    [[ "$expected_count" -eq "$(LC_ALL=C sort -u "$alignment_root/expected" | wc -l)" ]] ||
        {
            rm -rf -- "$alignment_root"
            return 1
        }
    [[ "$(wc -l <"$alignment_root/static")" -eq 105 ]] || {
        rm -rf -- "$alignment_root"
        return 1
    }
    [[ "$expected_count" -eq 138 ]] || {
        rm -rf -- "$alignment_root"
        return 1
    }
    # Literal source contracts intentionally preserve parameter expansion.
    # shellcheck disable=SC2016
    grep -Fq 'service_${unit_label}_${common_property_labels[$property_index]}_observed' \
        "$inspector" || {
        rm -rf -- "$alignment_root"
        return 1
    }
    # shellcheck disable=SC2016
    grep -Fq 'service_${unit_label}_${service_property_labels[$property_index]}_observed' \
        "$inspector" || {
        rm -rf -- "$alignment_root"
        return 1
    }
    rm -rf -- "$alignment_root"
}

static_read_only_policy() {
    if grep -Eq \
        'systemctl[[:space:]]+(start|stop|restart|reload|enable|disable|mask|unmask|daemon-reload|reset-failed)|(^|[;&|[:space:]])ip[[:space:]]+(address|addr)[[:space:]]+(add|replace|delete|del)|(^|[;&|[:space:]])(install|mv|rsync|scp|sftp)[[:space:]]' \
        "$inspector" "$runner"; then
        return 1
    fi
    grep -Fq 'run_assertion health_helper_execution_success runuser -u keepalived_script --' \
        "$inspector" || return 1
    grep -Fq "printf '%s_helper_execution=true" "$inspector" || return 1
    grep -Fq "printf '%s_filesystem_mutations=false" "$inspector" || return 1
    grep -Fq "printf '%s_persistent_mutations=false" "$inspector" || return 1
    grep -Fq 'health_backup_tree_sha256=' "$inspector" || return 1
    grep -Fq 'cd / && sudo -n /bin/bash -s --' "$runner" || return 1
}

node_a_contract() {
    grep -Fq 'readonly expected_backup_path=/var/backups/caddy-ha/action19e-node-a-keepalived-fragment.JgYBbS' \
        "$inspector" "$runner" &&
        grep -Fq 'readonly expected_health_backup_path=/var/backups/caddy-ha/action20c-node-a-health-context.DzQFvI' \
            "$inspector" "$runner" &&
        grep -Fq 'readonly expected_active_release=/etc/caddy/releases/action16ar-retry-node-a-default-deny' \
            "$inspector" &&
        grep -Fq 'priority 140' "$inspector" &&
        grep -Fq 'unicast_src_ip 10.1.0.53' "$inspector" &&
        grep -Fq '10.1.0.54 min_ttl 255 max_ttl 255' "$inspector" &&
        grep -Fq 'unicast_src_ip fd36:5aa8:6971:1::53' "$inspector" &&
        grep -Fq 'fd36:5aa8:6971:1::54 min_ttl 255 max_ttl 255' "$inspector" &&
        ! grep -Eq \
            'node-b|pihole00|j1-svpihole00|10\.1\.0\.54/22|fd36:5aa8:6971:1::54/64|priority 100' \
            "$inspector" "$runner"
}

write_contract_from_producer() {
    local output_path=$1
    local assertion_label
    local assertion_count
    local state_hash=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa

    assertion_count=$("$inspector" --expected-assertions | wc -l)
    {
        while IFS= read -r assertion_label; do
            printf 'action_20c_a_assertion_%s=true\n' "$assertion_label"
        done < <("$inspector" --expected-assertions)
        printf '%s\n' \
            "action_20c_a_value_expected_assertion_count=$assertion_count" \
            'action_20c_a_value_backup_path=/var/backups/caddy-ha/action19e-node-a-keepalived-fragment.JgYBbS' \
            'action_20c_a_value_backup_count=1' \
            'action_20c_a_value_health_backup_path=/var/backups/caddy-ha/action20c-node-a-health-context.DzQFvI' \
            'action_20c_a_value_health_backup_count=1' \
            'action_20c_a_value_health_sha256=9bf531ab7cbb047f8f09ce5956b597d5c8b6ede397c166f0b040e2e92fe8bbab' \
            "action_20c_a_value_main_sha256=$state_hash" \
            'action_20c_a_value_fragment_sha256=3a6f4c038d646bf12484d1a521a8f7fc01d05c56919ac8e6217ca50c2ab84bc5' \
            "action_20c_a_value_before_state_sha256=$state_hash" \
            "action_20c_a_value_after_state_sha256=$state_hash" \
            "action_20c_a_assertion_count=$assertion_count" \
            'action_20c_a_failed_assertion_count=0' \
            'action_20c_a_first_failure=none' \
            'action_20c_a_helper_execution=true' \
            'action_20c_a_filesystem_mutations=false' \
            'action_20c_a_service_mutations=false' \
            'action_20c_a_vrrp_mutations=false' \
            'action_20c_a_vip_mutations=false' \
            'action_20c_a_persistent_mutations=false' \
            'action_20c_a_remote_complete=true'
    } >"$output_path"
}

run_intercepted() {
    local case_root=$1
    local expected_runner_status=$2
    local transcript_path=$3
    local expected_ssh_status=$4
    local fake_ssh=$case_root/fake-ssh
    local observed_status=0
    local protected_evidence

    cat >"$fake_ssh" <<'FAKE_SSH'
#!/usr/bin/env bash
set -Eeuo pipefail
cat >"${ACTION20CA_STDIN_CAPTURE:?}"
printf '%s\n' "$*" >"${ACTION20CA_ARGS_CAPTURE:?}"
cat "${ACTION20CA_TRANSCRIPT:?}"
exit "${ACTION20CA_SSH_STATUS:?}"
FAKE_SSH
    chmod 0700 "$fake_ssh"
    (
        cd "$repository_root"
        CADDY_ACTION20CA_INTERCEPTED_TEST=1 \
            CADDY_ACTION20CA_SSH_BINARY="$fake_ssh" \
            ACTION20CA_STDIN_CAPTURE="$case_root/stdin" \
            ACTION20CA_ARGS_CAPTURE="$case_root/args" \
            ACTION20CA_TRANSCRIPT="$transcript_path" \
            ACTION20CA_SSH_STATUS="$expected_ssh_status" \
            "$runner"
    ) >"$case_root/stdout" 2>"$case_root/stderr" || observed_status=$?
    [[ "$observed_status" -eq "$expected_runner_status" ]] || return 1
    [[ -s "$case_root/stdin" ]]
    grep -Fq -- '-T -o BatchMode=yes -o IdentitiesOnly=no' "$case_root/args"
    grep -Fq -- '-o HostKeyAlias=pihole0.local.theama.co' "$case_root/args"
    grep -Fq 'pi@10.1.0.53 cd / && sudo -n /bin/bash -s --' "$case_root/args"
    grep -Fq 'action_20c_a_remote_stream_classification=bounded_safe' "$case_root/stdout"
    if [[ "$expected_runner_status" -eq 97 ]]; then
        protected_evidence=$(sed -n \
            's/^action_20c_a_protected_evidence=//p' "$case_root/stderr")
        [[ "$protected_evidence" == /tmp/caddy-action20c-a-runner.* ]] || return 1
        [[ -d "$protected_evidence" && ! -L "$protected_evidence" ]] || return 1
        rm -rf -- "$protected_evidence"
    else
        grep -Fq 'action_20c_a_runner_cleanup_complete=true' "$case_root/stdout"
    fi
}

require_gate inspector_hash_exact test "$(file_hash "$inspector")" = "$inspector_sha256"
require_gate runner_hash_exact test "$(file_hash "$runner")" = "$runner_sha256"
require_gate continuity_inspector_immutable test \
    "$(file_hash "$continuity_inspector")" = "$continuity_inspector_sha256"
require_gate transaction_outer_immutable test \
    "$(file_hash "$transaction_outer")" = "$transaction_outer_sha256"
require_gate sources_syntax bash -n "$inspector" "$runner"
require_gate sources_shellcheck shellcheck "$inspector" "$runner"
require_gate collision_policy "$collision_checker" "$inspector" "$runner"
require_gate inspector_self_test "$inspector" --self-test
require_gate runner_self_test "$runner" --self-test
require_gate runner_contract_test "$runner" --contract-test
require_gate production_label_alignment production_label_alignment
require_gate static_read_only_policy static_read_only_policy
require_gate node_a_contract node_a_contract
require_gate host_suite_outer_signature grep -Fq \
    'run-node-a-caddy-health-postinstall-action20c-a-outer.sh' "$host_suite"
require_gate host_suite_regression_signature grep -Fq \
    'action20c-a-node-a-caddy-health-postinstall-regression.sh' "$host_suite"
require_gate integration_suite_outer_signature grep -Fq \
    'run-node-a-caddy-health-postinstall-action20c-a-outer.sh' "$integration_suite"
require_gate integration_suite_regression_signature grep -Fq \
    'action20c-a-node-a-caddy-health-postinstall-regression.sh' "$integration_suite"
# The child Bash expands its positional parameter.
# shellcheck disable=SC2016
require_gate arbitrary_minimum_absent bash -c \
    '! grep -Eq "\$[A-Za-z_]*(check|assertion)[A-Za-z_]*.*-(ge|gt)[[:space:]]+[0-9]+" "$1"' \
    _ "$runner"
# shellcheck disable=SC2016
require_gate numbered_synthetic_fixture_absent bash -c \
    '! grep -Eq "seq 1 [0-9]+|check_fixture_[%0-9]" "$1"' _ "${BASH_SOURCE[0]}"

regression_root=$(mktemp -d /tmp/caddy-action20c-a-regression.XXXXXX)
readonly regression_root
cleanup() { rm -rf -- "$regression_root"; }
trap cleanup EXIT
install -d -m 0700 "$regression_root/valid" "$regression_root/mismatch" \
    "$regression_root/missing" "$regression_root/duplicate"
write_contract_from_producer "$regression_root/valid/transcript"
cp -- "$regression_root/valid/transcript" "$regression_root/mismatch/transcript"
sed -i \
    -e 's/action_20c_a_assertion_fragment_hash_exact=true/action_20c_a_assertion_fragment_hash_exact=false/' \
    -e 's/action_20c_a_failed_assertion_count=0/action_20c_a_failed_assertion_count=1/' \
    -e 's/action_20c_a_first_failure=none/action_20c_a_first_failure=fragment_hash_exact/' \
    "$regression_root/mismatch/transcript"
if [[ "${CADDY_VALIDATION_CONTAINER:-}" = 1 ]]; then
    require_gate container_projection_root test "$caddy_root" = \
        /workspace/homelab-server-configs/Caddy
    printf '%s_intercepted_production_path=host_authoritative\n' "$prefix"
else
    run_intercepted "$regression_root/valid" 0 \
        "$regression_root/valid/transcript" 0
    printf '%s_false_negative_exact_producer_contract_accepted=true\n' "$prefix"
    run_intercepted "$regression_root/mismatch" 1 \
        "$regression_root/mismatch/transcript" 1
    printf '%s_false_negative_semantic_mismatch_preserved=true\n' "$prefix"

    cp -- "$regression_root/valid/transcript" "$regression_root/missing/transcript"
    sed -i '/^action_20c_a_assertion_health_script_hash_exact=/d' \
        "$regression_root/missing/transcript"
    run_intercepted "$regression_root/missing" 97 \
        "$regression_root/missing/transcript" 0
    printf '%s_false_positive_missing_label_rejected=true\n' "$prefix"

    cp -- "$regression_root/valid/transcript" "$regression_root/duplicate/transcript"
    printf '%s\n' 'action_20c_a_assertion_health_script_hash_exact=true' \
        >>"$regression_root/duplicate/transcript"
    run_intercepted "$regression_root/duplicate" 97 \
        "$regression_root/duplicate/transcript" 0
    printf '%s_false_positive_duplicate_label_rejected=true\n' "$prefix"
fi

if [[ "${CADDY_VALIDATION_CONTAINER:-}" = 1 ]]; then
    printf '%s_false_positive_missing_label_rejected=host_authoritative\n' "$prefix"
    printf '%s_false_positive_duplicate_label_rejected=host_authoritative\n' "$prefix"
fi
printf '%s_production_path_network_contact=false\n' "$prefix"
printf '%s_complete=true\n' "$prefix"
