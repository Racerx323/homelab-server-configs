#!/usr/bin/env bash

set -Euo pipefail
set +x
umask 077
PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH
readonly PATH

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_dir
caddy_root=$(cd -- "$script_dir/.." && pwd)
readonly caddy_root
readonly runner="$caddy_root/scripts/run-node-a-to-node-b-release-transfer-action17p.sh"
readonly node_a_driver="$caddy_root/scripts/transfer-node-a-release-to-node-b-action17p.sh"
readonly node_b_inspector="$caddy_root/scripts/inspect-node-b-incoming-release-action17p.sh"
readonly collision_checker="$script_dir/check-shell-readonly-local-collisions.sh"

for artifact in "$runner" "$node_a_driver" "$node_b_inspector"; do
    [[ -f "$artifact" ]]
    [[ ! -L "$artifact" ]]
    bash -n "$artifact"
    shellcheck "$artifact"
done

"$runner" --self-test >/dev/null
"$runner" --contract-test >/dev/null
"$collision_checker" \
    "$runner" "$node_a_driver" "$node_b_inspector" "$0" >/dev/null

grep -Fq 'readonly revision=action17p-node-a-to-node-b-bootstrap' \
    "$node_a_driver"
grep -Fq 'readonly parent_revision=action15-health-follow-redirects' \
    "$node_a_driver"
grep -Fq \
    'readonly source_release=/etc/caddy/releases/action16ar-retry-node-a-default-deny' \
    "$node_a_driver"
grep -Fq -- '--exclude=.complete' "$node_a_driver"
grep -Fq "\$sync_user@\$node_b_fqdn:/" "$node_a_driver"
grep -Fq "\$release_dir/.complete" "$node_a_driver"
grep -Fq 'completion_marker_absent' "$node_b_inspector"
grep -Fq 'completion_marker_regular' "$node_b_inspector"
grep -Fq 'release_directories_metadata' "$node_b_inspector"
grep -Fq 'release_files_metadata' "$node_b_inspector"
grep -Fq 'release_symlinks_absent' "$node_b_inspector"
grep -Fq 'source_directory_metadata' "$node_b_inspector"
grep -Fq 'reconcile_path_inactive' "$node_b_inspector"
grep -Fq 'reconcile_service_inactive' "$node_b_inspector"
grep -Fq 'incomplete_release_preserved_no_remote_delete' "$runner"
grep -Fq 'false_positive_raw_output_rejected=true' "$runner"
grep -Fq 'source_manifest_hashes_valid' "$node_a_driver"
grep -Fq 'current_revision_exact' "$node_b_inspector"
if grep -Fq -- '--no-perms' "$node_a_driver"; then
    printf 'Action 17p disables immutable release mode preservation.\n' >&2
    exit 1
fi
if grep -Fq 'runuser -u caddy --' "$node_a_driver" "$node_b_inspector"; then
    printf 'Action 17p uses the wrong identity for incoming validation.\n' >&2
    exit 1
fi

payload_line=$(
    grep -n 'node_a_payload_status=0' "$runner" |
        head -n 1 |
        cut -d: -f1
)
payload_validation_line=$(
    grep -n 'node_b_payload_status=0' "$runner" |
        head -n 1 |
        cut -d: -f1
)
completion_line=$(
    grep -n 'node_a_complete_status=0' "$runner" |
        head -n 1 |
        cut -d: -f1
)
final_validation_line=$(
    grep -n 'node_b_complete_status=0' "$runner" |
        head -n 1 |
        cut -d: -f1
)
[[ "$payload_line" -lt "$payload_validation_line" ]]
[[ "$payload_validation_line" -lt "$completion_line" ]]
[[ "$completion_line" -lt "$final_validation_line" ]]

if grep -Eq \
    'systemctl[[:space:]]+(start|stop|restart|reload|enable|disable|mask|unmask|daemon-reload|reset-failed)' \
    "$runner" "$node_a_driver" "$node_b_inspector"; then
    printf 'Action 17p contains an unauthorized service mutation.\n' >&2
    exit 1
fi

if grep -Eq \
    '(^|[[:space:]])(rm|rmdir)[[:space:]].*(incoming|node-a)' \
    "$runner" "$node_a_driver" "$node_b_inspector"; then
    printf 'Action 17p contains prohibited remote incoming deletion.\n' >&2
    exit 1
fi

printf 'action_17p_release_parent_pinned=true\n'
printf 'action_17p_payload_precedes_completion=true\n'
printf 'action_17p_incomplete_tree_validated_before_completion=true\n'
printf 'action_17p_incoming_metadata_validated=true\n'
printf 'action_17p_reconciler_identity_validation_aligned=true\n'
printf 'action_17p_remote_delete_absent=true\n'
printf 'action_17p_service_mutation_absent=true\n'
printf 'action_17p_false_positive_and_false_negative_regression=true\n'
printf 'action_17p_release_transfer_regression_complete=true\n'
