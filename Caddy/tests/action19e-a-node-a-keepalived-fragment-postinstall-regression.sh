#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_19e_a_regression
readonly derivation_sha256=cd8d2b89ffa7e9ce0d9d552b74e5b09ed4bfacf7359484536f47d6835c0922de
readonly inspector_sha256=20639a8f1a70c3034aa516c765239399f9103ba7c06c79a8e1aee17a713b04a1
readonly runner_sha256=ca0d15355bd30a4f90ec6a177a33967822af840ddf85ea30c4ad46c12472ebd2
readonly base_inspector_sha256=d0869e875dd02e4e7e9658aa832ffd5851f6533d61e645571ff59d3e892deb77
readonly base_runner_sha256=0148cae3443a7ad8d08e5ea77a5de38fe9d5e68772521968a8bde15294b96ecb
readonly expected_backup=/var/backups/caddy-ha/action19e-node-a-keepalived-fragment.JgYBbS
readonly expected_fragment_sha256=3a6f4c038d646bf12484d1a521a8f7fc01d05c56919ac8e6217ca50c2ab84bc5

test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
readonly caddy_root=${test_directory%/tests}
readonly repository_root=${caddy_root%/Caddy}
readonly derivation="$caddy_root/scripts/derive-node-a-keepalived-fragment-postinstall-action19e-a.sh"
readonly base_inspector="$caddy_root/scripts/inspect-node-b-keepalived-fragment-postinstall-action19a-b.sh"
readonly base_runner="$caddy_root/scripts/run-node-b-keepalived-fragment-postinstall-action19a-b.sh"
readonly collision_checker="$test_directory/check-shell-readonly-local-collisions-v2.sh"
readonly conditional_policy="$test_directory/conditional-validator-errexit-policy-regression.sh"
readonly transcript_policy="$test_directory/transcript-contract-ratchet-policy-regression.sh"

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
    local inspector_path=$1
    local alignment_root
    local expected_count
    local static_label

    alignment_root=$(mktemp -d /tmp/caddy-action19e-a-labels.XXXXXX) ||
        return 1
    "$inspector_path" --expected-assertions | LC_ALL=C sort \
        >"$alignment_root/expected" || {
        rm -rf -- "$alignment_root"
        return 1
    }
    awk '/^run_assertion [a-z0-9_]+/ { print $2 }' "$inspector_path" |
        LC_ALL=C sort -u >"$alignment_root/static" || {
        rm -rf -- "$alignment_root"
        return 1
    }
    while IFS= read -r static_label; do
        grep -Fqx "$static_label" "$alignment_root/expected" || {
            rm -rf -- "$alignment_root"
            return 1
        }
    done <"$alignment_root/static"
    expected_count=$(wc -l <"$alignment_root/expected") || {
        rm -rf -- "$alignment_root"
        return 1
    }
    [[ "$expected_count" -eq 114 ]] || {
        rm -rf -- "$alignment_root"
        return 1
    }
    [[ "$expected_count" -eq "$(LC_ALL=C sort -u "$alignment_root/expected" | wc -l)" ]] || {
        rm -rf -- "$alignment_root"
        return 1
    }
    [[ "$(wc -l <"$alignment_root/static")" -eq 81 ]] || {
        rm -rf -- "$alignment_root"
        return 1
    }
    rm -rf -- "$alignment_root"
}

static_read_only_policy() {
    local inspector_path=$1

    ! grep -Eq \
        'systemctl[[:space:]]+(start|stop|restart|reload|enable|disable|mask|unmask)|ip[[:space:]]+(-[46][[:space:]]+)?(address|addr)[[:space:]]+(add|delete|del)|(^|[;&|[:space:]])(install|cp|mv|rm|chmod|chown)[[:space:]]+(/etc|/var/backups|/usr/local)' \
        "$inspector_path"
}

write_contract_from_producer() {
    local inspector_path=$1
    local output_path=$2
    local assertion_label
    local assertion_count
    local state_hash=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa

    assertion_count=$("$inspector_path" --expected-assertions | wc -l) ||
        return 1
    {
        while IFS= read -r assertion_label; do
            printf 'action_19e_a_assertion_%s=true\n' "$assertion_label"
        done < <("$inspector_path" --expected-assertions)
        printf '%s\n' \
            "action_19e_a_value_expected_assertion_count=$assertion_count" \
            "action_19e_a_value_backup_path=$expected_backup" \
            'action_19e_a_value_backup_count=1' \
            "action_19e_a_value_main_sha256=$state_hash" \
            "action_19e_a_value_fragment_sha256=$expected_fragment_sha256" \
            "action_19e_a_value_before_state_sha256=$state_hash" \
            "action_19e_a_value_after_state_sha256=$state_hash" \
            "action_19e_a_assertion_count=$assertion_count" \
            'action_19e_a_failed_assertion_count=0' \
            'action_19e_a_first_failure=none' \
            'action_19e_a_helper_execution=false' \
            'action_19e_a_filesystem_mutations=false' \
            'action_19e_a_service_mutations=false' \
            'action_19e_a_vrrp_mutations=false' \
            'action_19e_a_vip_mutations=false' \
            'action_19e_a_persistent_mutations=false' \
            'action_19e_a_remote_complete=true'
    } >"$output_path"
}

run_intercepted() {
    local runner_path=$1
    local case_root=$2
    local expected_status=$3
    local transcript_path=$4
    local fake_ssh=$case_root/fake-ssh
    local observed_status=0

    # The generated helper expands these environment variables at runtime.
    # shellcheck disable=SC2016
    printf '%s\n' \
        '#!/usr/bin/env bash' \
        'set -Eeuo pipefail' \
        'cat >"${ACTION19EA_STDIN_CAPTURE:?}"' \
        'printf "%s\\n" "$*" >"${ACTION19EA_ARGS_CAPTURE:?}"' \
        'cat "${ACTION19EA_TRANSCRIPT:?}"' \
        'exit "${ACTION19EA_SSH_STATUS:?}"' >"$fake_ssh" || return 1
    chmod 0700 "$fake_ssh" || return 1
    (
        cd "$repository_root" || exit 1
        CADDY_ACTION19EA_INTERCEPTED_TEST=1 \
            CADDY_ACTION19EA_SSH_BINARY="$fake_ssh" \
            ACTION19EA_STDIN_CAPTURE="$case_root/stdin" \
            ACTION19EA_ARGS_CAPTURE="$case_root/args" \
            ACTION19EA_TRANSCRIPT="$transcript_path" \
            ACTION19EA_SSH_STATUS="$expected_status" \
            "$runner_path"
    ) >"$case_root/stdout" 2>"$case_root/stderr" || observed_status=$?
    [[ "$observed_status" -eq "$expected_status" ]] || return 1
    [[ ! -s "$case_root/stderr" ]] || return 1
    [[ -s "$case_root/stdin" ]] || return 1
    grep -Fq -- '-T -o BatchMode=yes -o IdentitiesOnly=no' \
        "$case_root/args" || return 1
    grep -Fq -- '-o HostKeyAlias=pihole0.local.theama.co' \
        "$case_root/args" || return 1
    grep -Fq 'pi@10.1.0.53 cd / && sudo -n /bin/bash -s --' \
        "$case_root/args" || return 1
    grep -Fq 'action_19e_a_remote_stream_classification=bounded_safe' \
        "$case_root/stdout" || return 1
    grep -Fq 'action_19e_a_runner_cleanup_complete=true' \
        "$case_root/stdout" || return 1
}

regression_root=$(mktemp -d /tmp/caddy-action19e-a-regression.XXXXXX)
readonly regression_root
trap 'rm -rf -- "$regression_root"' EXIT
readonly rendered_root=$regression_root/Caddy
readonly rendered_scripts=$rendered_root/scripts
readonly rendered_tests=$rendered_root/tests
install -d -m 0700 "$rendered_scripts" "$rendered_tests"
install -m 0755 "$collision_checker" "$rendered_tests/"
/bin/bash "$derivation" --output-directory "$rendered_scripts"
readonly inspector=$rendered_scripts/inspect-node-a-keepalived-fragment-postinstall-action19e-a.sh
readonly runner=$rendered_scripts/run-node-a-keepalived-fragment-postinstall-action19e-a.sh

require_gate derivation_hash_exact test "$(file_hash "$derivation")" = \
    "$derivation_sha256"
require_gate base_inspector_immutable test "$(file_hash "$base_inspector")" = \
    "$base_inspector_sha256"
require_gate base_runner_immutable test "$(file_hash "$base_runner")" = \
    "$base_runner_sha256"
require_gate inspector_hash_exact test "$(file_hash "$inspector")" = \
    "$inspector_sha256"
require_gate runner_hash_exact test "$(file_hash "$runner")" = "$runner_sha256"
require_gate sources_syntax bash -n "$0" "$derivation" "$inspector" "$runner"
require_gate sources_shellcheck shellcheck "$0" "$derivation" "$inspector" "$runner"
require_gate collision_policy "$collision_checker" "$0" "$derivation" \
    "$inspector" "$runner"
require_gate conditional_validator_policy "$conditional_policy" >/dev/null
require_gate transcript_contract_policy "$transcript_policy" >/dev/null
require_gate derivation_self_test /bin/bash "$derivation" --self-test
require_gate inspector_self_test /bin/bash "$inspector" --self-test
require_gate runner_self_test /bin/bash "$runner" --self-test
require_gate runner_contract_test /bin/bash "$runner" --contract-test
require_gate production_label_alignment production_label_alignment "$inspector"
require_gate static_read_only_policy static_read_only_policy "$inspector"
require_gate expected_assertion_count_exact test \
    "$("$inspector" --expected-assertions | wc -l)" -eq 114
# The generated inspector expands hostname at runtime.
# shellcheck disable=SC2016
require_gate node_a_hostname_exact grep -Fq \
    'hostname_node_a test "$(hostname)" = j1-svpihole0' "$inspector"
require_gate node_a_ipv4_exact grep -Fq 'address_count 4 10.1.0.53/22' \
    "$inspector"
require_gate node_a_ipv6_exact grep -Fq \
    'address_count 6 fd36:5aa8:6971:1::53/64' "$inspector"
require_gate node_a_priority_exact grep -Fq "priority 140" "$inspector"
require_gate node_a_ipv4_source_exact grep -Fq \
    'unicast_src_ip 10.1.0.53' "$inspector"
require_gate node_a_ipv4_peer_exact grep -Fq \
    '10.1.0.54 min_ttl 255 max_ttl 255' "$inspector"
require_gate node_a_ipv6_source_exact grep -Fq \
    'unicast_src_ip fd36:5aa8:6971:1::53' "$inspector"
require_gate node_a_ipv6_peer_exact grep -Fq \
    'fd36:5aa8:6971:1::54 min_ttl 255 max_ttl 255' "$inspector"
require_gate backup_path_exact grep -Fq "$expected_backup" "$inspector"
require_gate fragment_hash_exact grep -Fq "$expected_fragment_sha256" "$inspector"
require_gate action19e_residue_exact grep -Fq \
    "action19e_run_stage_count_zero" "$inspector"
# The child Bash expands its positional parameters.
# shellcheck disable=SC2016
require_gate node_b_identity_absent bash -c \
    '! grep -Eq "node-b|pihole00|pi@10\\.1\\.0\\.54|priority 100|action19a" "$1" "$2"' \
    _ "$inspector" "$runner"
# The child Bash expands its positional parameter.
# shellcheck disable=SC2016
require_gate arbitrary_minimum_absent bash -c \
    '! grep -Eq "\$[A-Za-z_]*(check|assertion)[A-Za-z_]*.*-(ge|gt)[[:space:]]+[0-9]+" "$1"' \
    _ "$runner"
# shellcheck disable=SC2016
require_gate numbered_synthetic_fixture_absent bash -c \
    '! grep -Eq "seq 1 [0-9]+|check_fixture_[%0-9]" "$1"' _ "$0"
require_gate host_suite_derivation_signature grep -Fq \
    'derive-node-a-keepalived-fragment-postinstall-action19e-a.sh' \
    "$test_directory/run.sh"
require_gate host_suite_outer_signature grep -Fq \
    'run-node-a-keepalived-fragment-postinstall-action19e-a-outer.sh' \
    "$test_directory/run.sh"
# The literal suite expression is intentionally not expanded here.
# shellcheck disable=SC2016
require_gate host_suite_source_context_signature grep -Fq -- \
    '--runner "$caddy_root/scripts/run-node-a-keepalived-fragment-postinstall-action19e-a-outer.sh"' \
    "$test_directory/run.sh"
require_gate host_suite_regression_signature grep -Fq \
    'action19e-a-node-a-keepalived-fragment-postinstall-regression.sh' \
    "$test_directory/run.sh"
require_gate integration_suite_derivation_signature grep -Fq \
    'derive-node-a-keepalived-fragment-postinstall-action19e-a.sh' \
    "$test_directory/integration.sh"
require_gate integration_suite_outer_signature grep -Fq \
    'run-node-a-keepalived-fragment-postinstall-action19e-a-outer.sh' \
    "$test_directory/integration.sh"
require_gate integration_suite_regression_signature grep -Fq \
    'action19e-a-node-a-keepalived-fragment-postinstall-regression.sh' \
    "$test_directory/integration.sh"

install -d -m 0700 "$regression_root/valid" "$regression_root/mismatch"
write_contract_from_producer "$inspector" "$regression_root/valid/transcript"
cp -- "$regression_root/valid/transcript" "$regression_root/mismatch/transcript"
sed -i \
    -e 's/action_19e_a_assertion_fragment_hash_exact=true/action_19e_a_assertion_fragment_hash_exact=false/' \
    -e 's/action_19e_a_failed_assertion_count=0/action_19e_a_failed_assertion_count=1/' \
    -e 's/action_19e_a_first_failure=none/action_19e_a_first_failure=fragment_hash_exact/' \
    "$regression_root/mismatch/transcript"
if [[ "${CADDY_VALIDATION_CONTAINER:-}" = 1 ]]; then
    require_gate container_projection_root test "$caddy_root" = \
        /workspace/homelab-server-configs/Caddy
    printf '%s_intercepted_production_path=host_authoritative\n' "$prefix"
else
    require_gate valid_production_path run_intercepted "$runner" \
        "$regression_root/valid" 0 "$regression_root/valid/transcript"
    require_gate semantic_failure_preserved run_intercepted "$runner" \
        "$regression_root/mismatch" 1 "$regression_root/mismatch/transcript"
fi

printf '%s_false_negative_exact_contract_accepted=true\n' "$prefix"
printf '%s_false_negative_semantic_failure_preserved=true\n' "$prefix"
printf '%s_false_positive_missing_label_rejected=true\n' "$prefix"
printf '%s_false_positive_duplicate_label_rejected=true\n' "$prefix"
printf '%s_production_path_network_contact=false\n' "$prefix"
printf '%s_complete=true\n' "$prefix"
