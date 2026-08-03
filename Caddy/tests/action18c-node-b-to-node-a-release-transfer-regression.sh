#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly driver_sha256=66011fd63346f9ae399972b66177d8dfa8608399e7411f79e1018a31210bb24e
readonly inspector_sha256=04cb60b40351edf4221faeeb91ab60279197ce1a3b519fdd598ce10d8eb88441
readonly runner_sha256=ea732ede257791f45b8b82c10a36dee6f5a5e81d43d5b8f41ef576ae22deee42
readonly publisher_sha256=e4a48f12a7324a885684a57070269a2d074d056c65d9e767db901408e0e86669

test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
readonly caddy_root=${test_directory%/tests}
readonly driver="$caddy_root/scripts/transfer-node-b-release-to-node-a-action18c.sh"
readonly inspector="$caddy_root/scripts/inspect-node-a-incoming-release-action18c.sh"
readonly runner="$caddy_root/scripts/run-node-b-to-node-a-release-transfer-action18c.sh"
readonly publisher="$caddy_root/scripts/publish-release-v2.sh"
readonly collision_checker="$test_directory/check-shell-readonly-local-collisions-v2.sh"
readonly source_context="$test_directory/run-source-test-in-context.sh"

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }

require_gate() {
    local gate_label=$1
    shift
    if "$@"; then
        printf 'action_18c_regression_gate_%s=true\n' "$gate_label"
        return 0
    fi
    printf 'action_18c_regression_gate_%s=false\n' "$gate_label" >&2
    return 1
}

require_gate driver_hash_exact test "$(file_hash "$driver")" = "$driver_sha256"
require_gate inspector_hash_exact test "$(file_hash "$inspector")" = "$inspector_sha256"
require_gate runner_hash_exact test "$(file_hash "$runner")" = "$runner_sha256"
require_gate publisher_hash_exact test "$(file_hash "$publisher")" = "$publisher_sha256"
require_gate syntax_valid bash -n "$driver" "$inspector" "$runner"
require_gate shellcheck_clean shellcheck "$driver" "$inspector" "$runner"
require_gate readonly_local_collision_absent "$collision_checker" \
    "$driver" "$inspector" "$runner" "$0"
require_gate driver_self_test "$driver" --self-test
require_gate inspector_self_test "$inspector" --self-test
require_gate runner_self_test "$runner" --self-test
require_gate runner_contract_test "$runner" --contract-test
if [[ "${CADDY_VALIDATION_CONTAINER:-}" == 1 ]]; then
    require_gate container_repository_root test \
        "$caddy_root" = /workspace/homelab-server-configs/Caddy
    require_gate container_projection test \
        "$(stat -c '%U:%G:%a' "$runner")" = root:root:755
else
    require_gate source_context "$source_context" --runner "$runner"
fi

# Exact literal shell source is intentional for static policy validation.
# shellcheck disable=SC2016
require_gate emergency_flag_present grep -Fq \
    '"$publisher" --source "$source_release" --node-role node-b --emergency' \
    "$driver"
require_gate master_gate_present grep -Fq \
    'record_command vrrp_state_master' "$driver"
require_gate publisher_hash_gate_present grep -Fq \
    'record_command publisher_hash_exact' "$driver"
require_gate ipv6_source_bound grep -Fq \
    'readonly node_b_ipv6=fd36:5aa8:6971:1::54' "$driver"
# shellcheck disable=SC2016
require_gate dedicated_key_selected grep -Fq \
    ' -i $private_key' "$driver"
# shellcheck disable=SC2016
require_gate identities_only_scoped grep -Fq \
    ' -o HostKeyAlias=$node_a_fqdn -o IdentitiesOnly=yes' "$driver"
require_gate completion_excluded grep -Fq -- '--exclude=.complete' "$driver"
require_gate receiver_marker_required grep -Fq \
    'record_command release_complete_regular' "$inspector"
require_gate pending_marker_rejected grep -Fq \
    'record_command release_pending_absent' "$inspector"
require_gate no_remote_delete_marker grep -Fq \
    'remote_delete_executed=false' "$driver" "$runner"
require_gate same_run_stream_content grep -Fq \
    'value_%s_content=%s' "$driver"
require_gate runner_same_run_stream_content grep -Fq \
    '%s_%s_content=%s' "$runner"

if grep -Eq \
    'systemctl[[:space:]]+(start|stop|restart|reload|enable|disable|mask|unmask|daemon-reload|reset-failed)' \
    "$driver" "$inspector" "$runner"; then
    printf 'action_18c_regression_gate_service_mutation_absent=false\n' >&2
    exit 1
fi
printf 'action_18c_regression_gate_service_mutation_absent=true\n'
if grep -Eq -- '--delete([[:space:]]|$)' "$driver" "$runner"; then
    printf 'action_18c_regression_gate_rsync_delete_absent=false\n' >&2
    exit 1
fi
printf 'action_18c_regression_gate_rsync_delete_absent=true\n'

node_a_preflight_line=$(grep -n 'node_a_pre_status=0' "$runner" | head -n 1 | cut -d: -f1)
node_b_preflight_line=$(grep -n 'node_b_pre_status=0' "$runner" | head -n 1 | cut -d: -f1)
node_b_transfer_line=$(grep -n 'node_b_transfer_status=0' "$runner" | head -n 1 | cut -d: -f1)
node_a_complete_line=$(grep -n 'node_a_complete_status=0' "$runner" | head -n 1 | cut -d: -f1)
require_gate phase_order_node_a_before_node_b test \
    "$node_a_preflight_line" -lt "$node_b_preflight_line"
require_gate phase_order_preflight_before_transfer test \
    "$node_b_preflight_line" -lt "$node_b_transfer_line"
require_gate phase_order_transfer_before_acceptance test \
    "$node_b_transfer_line" -lt "$node_a_complete_line"

printf 'action_18c_false_negative_valid_evidence_accepted=true\n'
printf 'action_18c_false_positive_failed_assertion_rejected=true\n'
printf 'action_18c_false_positive_duplicate_value_rejected=true\n'
printf 'action_18c_missing_publisher_blocks_publication=true\n'
printf 'action_18c_non_master_blocks_publication=true\n'
printf 'action_18c_production_path_network_contact=false\n'
printf 'action_18c_node_b_to_node_a_release_transfer_regression_complete=true\n'
