#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly inspector_sha256=f7d50d5b3ff205e845ab577653dcc373ebd745988c81f9cbbc402664b96e6bc0
readonly runner_sha256=6878c7e14c3f2d68f667add07e1177cb1959d7b8bc0b16726cf429cf300a29ed

test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
readonly caddy_root=${test_directory%/tests}
readonly inspector="$caddy_root/scripts/inspect-caddy-vrrp-emergency-master-eligibility-action18c-vrrp-a.sh"
readonly runner="$caddy_root/scripts/run-dual-node-caddy-vrrp-emergency-master-eligibility-action18c-vrrp-a.sh"
readonly collision_checker="$test_directory/check-shell-readonly-local-collisions-v2.sh"

file_hash() {
    sha256sum "$1" | awk '{ print $1 }'
}

require_gate() {
    local gate_label=$1

    shift
    if "$@"; then
        printf 'action_18c_vrrp_a_regression_gate_%s=true\n' "$gate_label"
        return 0
    fi
    printf 'action_18c_vrrp_a_regression_gate_%s=false\n' "$gate_label" >&2
    return 1
}

extract_source_labels() {
    local source_path=$1

    awk '
        /record_command\(\)/ { next }
        /^[[:space:]]*record_command [a-z0-9_]+/ {
            line = $0
            sub(/^[[:space:]]*record_command /, "", line)
            sub(/[[:space:]].*$/, "", line)
            print line
            next
        }
        /^[[:space:]]*record_command[[:space:]]*\\$/ {
            getline
            line = $0
            sub(/^[[:space:]]*/, "", line)
            sub(/[[:space:]].*$/, "", line)
            print line
        }
    ' "$source_path"
}

write_fixture() {
    local fixture_path=$1
    local fixture_role=$2
    local fixture_state=$3
    local fixture_vip_count=$4
    local fixture_label

    while IFS= read -r fixture_label; do
        printf 'action_18c_vrrp_a_remote_assertion_%s=true\n' "$fixture_label"
    done < <(extract_source_labels "$inspector") >"$fixture_path"
    printf '%s\n' \
        "action_18c_vrrp_a_remote_value_node_role=$fixture_role" \
        "action_18c_vrrp_a_remote_value_vrrp_state=$fixture_state" \
        "action_18c_vrrp_a_remote_value_ipv4_vip_count=$fixture_vip_count" \
        "action_18c_vrrp_a_remote_value_ipv6_vip_count=$fixture_vip_count" \
        'action_18c_vrrp_a_remote_value_before_state_sha256=1111111111111111111111111111111111111111111111111111111111111111' \
        'action_18c_vrrp_a_remote_value_after_state_sha256=1111111111111111111111111111111111111111111111111111111111111111' \
        "action_18c_vrrp_a_remote_assertion_count=$(extract_source_labels "$inspector" | wc -l)" \
        'action_18c_vrrp_a_remote_failed_assertion_count=0' \
        'action_18c_vrrp_a_remote_first_failure=none' \
        'action_18c_vrrp_a_remote_publisher_invoked=false' \
        'action_18c_vrrp_a_remote_vrrp_mutations=false' \
        'action_18c_vrrp_a_remote_service_mutations=false' \
        'action_18c_vrrp_a_remote_synchronization_mutations=false' \
        'action_18c_vrrp_a_remote_persistent_mutations=false' \
        'action_18c_vrrp_a_remote_remote_complete=true' >>"$fixture_path"
}

require_gate inspector_hash_exact test "$(file_hash "$inspector")" = "$inspector_sha256"
require_gate runner_hash_exact test "$(file_hash "$runner")" = "$runner_sha256"
require_gate syntax_valid bash -n "$inspector" "$runner"
require_gate shellcheck_clean shellcheck "$inspector" "$runner"
require_gate collision_policy_clean "$collision_checker" "$inspector" "$runner" "$0"
require_gate inspector_self_test "$inspector" --self-test
require_gate runner_self_test "$runner" --self-test
require_gate runner_contract_test "$runner" --contract-test
require_gate production_labels_present test \
    "$(extract_source_labels "$inspector" | wc -l)" -gt 30
require_gate production_labels_unique test \
    "$(extract_source_labels "$inspector" | LC_ALL=C sort -u | wc -l)" -eq \
    "$(extract_source_labels "$inspector" | wc -l)"
require_gate node_a_backup_required grep -Fq 'readonly expected_state=BACKUP' "$inspector"
require_gate node_b_master_required grep -Fq 'readonly expected_state=MASTER' "$inspector"
require_gate node_a_vip_absence_required grep -Fq 'readonly expected_vip_count=0' "$inspector"
require_gate node_b_vip_ownership_required grep -Fq 'readonly expected_vip_count=1' "$inspector"
require_gate ipv4_vip_exact grep -Fq '10.1.0.56/22' "$inspector"
require_gate ipv6_vip_exact grep -Fq 'fd36:5aa8:6971:1::56/128' "$inspector"
require_gate stabilization_window_present grep -Fq 'readonly stabilization_seconds=4' "$inspector"
require_gate state_after_window_labeled grep -Fq \
    'record_command state_stable_after_window' "$inspector"
require_gate ipv4_after_window_labeled grep -Fq \
    'record_command ipv4_vip_stable_after_window' "$inspector"
require_gate ipv6_after_window_labeled grep -Fq \
    'record_command ipv6_vip_stable_after_window' "$inspector"
# These assertions intentionally match literal production shell source.
# shellcheck disable=SC2016
require_gate node_a_inspected_first grep -Fq \
    'run_remote "$node_a_target" "$node_a_alias" node-a' "$runner"
# shellcheck disable=SC2016
require_gate node_b_inspection_present grep -Fq \
    'run_remote "$node_b_target" "$node_b_alias" node-b' "$runner"
require_gate same_run_safe_stdout grep -Fq \
    'safe_content_begin=true' "$runner"
require_gate same_run_safe_stderr grep -Fq \
    'emit_stream node_b_stderr' "$runner"

if grep -Eq \
    'systemctl[[:space:]]+(start|stop|restart|reload|enable|disable|mask|unmask|daemon-reload|reset-failed)|keepalived[[:space:]]+(-f|--use-file)|publish-release-v2\.sh[[:space:]]+--|run-node-b-to-node-a-release-transfer-action18c' \
    "$inspector" "$runner"; then
    printf 'action_18c_vrrp_a_regression_gate_mutation_or_transfer_absent=false\n' >&2
    exit 1
fi
printf 'action_18c_vrrp_a_regression_gate_mutation_or_transfer_absent=true\n'

run_production_path_case() {
    local case_root=$1
    local expected_status=$2
    local case_repo="$case_root/homelab-server-configs"
    local case_bin="$case_root/bin"
    local case_runner="$case_repo/Caddy/scripts/${runner##*/}"
    local fixture_root=${case_root%/*}
    local observed_status=0

    install -d -m 0700 "$case_bin" "$case_repo/Caddy/scripts" \
        "$case_repo/Caddy/tests" "$case_root/captured"
    cp -- "$inspector" "$runner" "$case_repo/Caddy/scripts/"
    cp -- "$collision_checker" "$case_repo/Caddy/tests/"
    sed -i \
        -e "s|^PATH=/usr/bin:/bin$|PATH=$case_bin:/usr/bin:/bin|" \
        -e "s|/home/aaron/code/homelab-server-configs|$case_repo|" \
        "$case_runner"
    chmod 0755 "$case_repo/Caddy/scripts/"*.sh "$case_repo/Caddy/tests/"*.sh
    # These variables are evaluated only by the generated fake SSH process.
    # shellcheck disable=SC2016
    printf '%s\n' \
        '#!/usr/bin/env bash' \
        'set -Eeuo pipefail' \
        'call_count=0' \
        '[[ ! -f "$ACTION18C_VRRP_A_CALL_COUNT" ]] || call_count=$(<"$ACTION18C_VRRP_A_CALL_COUNT")' \
        'call_count=$((call_count + 1))' \
        'printf "%s\n" "$call_count" >"$ACTION18C_VRRP_A_CALL_COUNT"' \
        'printf "%s\n" "$*" >"$ACTION18C_VRRP_A_CAPTURE/call-$call_count.args"' \
        'cat >"$ACTION18C_VRRP_A_CAPTURE/call-$call_count.inspector"' \
        'if [[ "$call_count" -eq 1 ]]; then cat "$ACTION18C_VRRP_A_NODE_A"; else cat "$ACTION18C_VRRP_A_NODE_B"; fi' \
        >"$case_bin/ssh"
    chmod 0755 "$case_bin/ssh"
    printf '0\n' >"$case_root/call-count"
    set +e
    (
        cd "$case_repo" || exit
        ACTION18C_VRRP_A_CALL_COUNT="$case_root/call-count" \
            ACTION18C_VRRP_A_CAPTURE="$case_root/captured" \
            ACTION18C_VRRP_A_NODE_A="$fixture_root/node-a.fixture" \
            ACTION18C_VRRP_A_NODE_B="$fixture_root/node-b.fixture" \
            "$case_runner" >"$case_root/output" 2>"$case_root/error"
    )
    observed_status=$?
    set -e
    [[ "$observed_status" -eq "$expected_status" ]]
}

case_root=$(mktemp -d /tmp/caddy-action18c-vrrp-a-regression.XXXXXX)
trap 'rm -rf -- "$case_root"' EXIT
write_fixture "$case_root/node-a.fixture" node-a BACKUP 0
write_fixture "$case_root/node-b.fixture" node-b MASTER 1
run_production_path_case "$case_root/valid" 0
require_gate production_path_two_ssh_calls test \
    "$(cat "$case_root/valid/call-count")" -eq 2
require_gate production_path_node_a_inspector_exact test \
    "$(file_hash "$case_root/valid/captured/call-1.inspector")" = "$inspector_sha256"
require_gate production_path_node_b_inspector_exact test \
    "$(file_hash "$case_root/valid/captured/call-2.inspector")" = "$inspector_sha256"
require_gate production_path_root_directory grep -Fq 'cd / && sudo -n bash -s' \
    "$case_root/valid/captured/call-1.args"
require_gate production_path_eligibility_true grep -Fxq \
    'action_18c_vrrp_a_eligibility=true' "$case_root/valid/output"
require_gate production_path_action18c_not_executed grep -Fxq \
    'action_18c_vrrp_a_action_18c_executed=false' "$case_root/valid/output"

sed 's/value_vrrp_state=MASTER/value_vrrp_state=BACKUP/' \
    "$case_root/node-b.fixture" >"$case_root/node-b-invalid.fixture"
cp -- "$case_root/node-b-invalid.fixture" "$case_root/node-b.fixture"
run_production_path_case "$case_root/invalid" 1
require_gate production_semantic_failure_rejected grep -Fq \
    'action_18c_vrrp_a_assertion_node_b_state_exact=false' \
    "$case_root/invalid/output"

printf 'action_18c_vrrp_a_false_negative_valid_production_path_accepted=true\n'
printf 'action_18c_vrrp_a_false_positive_non_master_node_b_rejected=true\n'
printf 'action_18c_vrrp_a_production_path_network_contact=false\n'
printf 'action_18c_vrrp_a_regression_complete=true\n'
