#!/usr/bin/env bash

set -euo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly inspector_sha256=3a38e6a76c7fb94dbb0bfbf7caf3c1f01627603c5983639d49a541ef9e6bf5a5

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_dir
readonly inspector="$script_dir/inspect-node-a-retained-stage-metadata-action16ak-b.sh"

verify_inspector() {
    [[ -f "$inspector" && ! -L "$inspector" ]]
    [[ "$(stat -c '%U:%G:%a' "$inspector")" == aaron:aaron:755 ]]
    [[ "$(sha256sum "$inspector" | awk '{ print $1 }')" == "$inspector_sha256" ]]
}

if [[ "${1:-}" == --self-test ]]; then
    [[ "$inspector_sha256" =~ ^[0-9a-f]{64}$ ]]
    verify_inspector
    bash -n "$inspector"
    "$inspector" --self-test >/dev/null
    printf 'action_16ak_b_retained_stage_metadata_runner_self_test_complete=true\n'
    exit 0
elif (($#)); then
    printf 'Usage: %s [--self-test]\n' "${0##*/}" >&2
    exit 2
fi

verify_inspector
work_dir=$(mktemp -d /tmp/caddy-action16ak-b.XXXXXX)
readonly work_dir
readonly remote_output="$work_dir/remote.out"
readonly remote_error="$work_dir/remote.err"
cleanup() {
    rm -rf -- "$work_dir"
}
trap cleanup EXIT

finish() {
    local status=$1

    cleanup
    trap - EXIT
    if [[ -e "$work_dir" || -L "$work_dir" ]]; then
        printf 'action_16ak_b_local_cleanup_complete=false\n' >&2
        exit 97
    fi
    printf 'action_16ak_b_local_cleanup_complete=true\n'
    exit "$status"
}

ssh_status=0
ssh -T \
    -o BatchMode=yes \
    -o ConnectTimeout=5 \
    -o HostKeyAlias=pihole0.local.theama.co \
    -o StrictHostKeyChecking=yes \
    pi@10.1.0.53 \
    'sudo -n /bin/bash -s --' \
    <"$inspector" >"$remote_output" 2>"$remote_error" || ssh_status=$?

if grep -Eq \
    'BEGIN [A-Z ]*PRIVATE KEY|CADDY_TLS_PRIVATE_KEY_PEM|node_a_sync_ed25519_public_key=' \
    "$remote_output" "$remote_error"; then
    printf 'Action 16ak-b suppressed unexpected key material.\n' >&2
    finish 97
fi

cat "$remote_output"
cat "$remote_error" >&2
printf 'ssh_exit_status=%s\n' "$ssh_status"
if [[ "$ssh_status" -ne 0 ]]; then
    finish "$ssh_status"
fi

readonly -a required_markers=(
    action_16ak_b_remote_reached=true
    root_effective_uid=true
    node_hostname=true
    retained_stage_directory=true
    retained_stage_not_symlink=true
    parent_directory=true
    parent_not_symlink=true
    findmnt_available=true
    retained_stage_file_set=true
    retained_stage_symlink_count=true
    retained_stage_hashes=true
    action_16ak_a_continuity_anchor=true
    first_failure=none
    service_mutations=false
    action_16ak_b_read_only_inspection_complete=true
)
for marker in "${required_markers[@]}"; do
    grep -Fxq "$marker" "$remote_output"
done
[[ "$(grep -Fxc 'live_synchronization_targets_absent=true' \
    "$remote_output")" -eq 8 ]]
grep -Fxq 'libexec_absent=true' "$remote_output"

for label in retained_stage parent; do
    grep -Eq "^${label}_owner_names=[^:[:space:]]+:[^:[:space:]]+$" \
        "$remote_output"
    grep -Eq "^${label}_owner_numeric=[0-9]+:[0-9]+$" \
        "$remote_output"
    grep -Eq "^${label}_mode_numeric=[0-7]{3,4}$" "$remote_output"
    grep -Eq "^${label}_mode_symbolic=d[-rwxstST]{9}$" "$remote_output"
    grep -Eq "^${label}_ls_mode=d[-rwxstST]{9}[+.@]?$" "$remote_output"
    grep -Eq "^${label}_inode=[0-9]+$" "$remote_output"
    grep -Eq "^${label}_device=[0-9]+$" "$remote_output"
    grep -Eq "^${label}_hard_links=[0-9]+$" "$remote_output"
    grep -Eq "^${label}_size_bytes=[0-9]+$" "$remote_output"
    grep -Eq "^${label}_birth_time=(-|[0-9]{4}-[0-9]{2}-[0-9]{2} .+)$" \
        "$remote_output"
    grep -Eq "^${label}_access_time=[0-9]{4}-[0-9]{2}-[0-9]{2} .+$" \
        "$remote_output"
    grep -Eq "^${label}_modify_time=[0-9]{4}-[0-9]{2}-[0-9]{2} .+$" \
        "$remote_output"
    grep -Eq "^${label}_change_time=[0-9]{4}-[0-9]{2}-[0-9]{2} .+$" \
        "$remote_output"
done
grep -Eq '^filesystem_mount_target=/.*$' "$remote_output"
grep -Eq '^filesystem_type=[^[:space:]]+$' "$remote_output"
grep -Eq '^filesystem_options=[^[:space:]]+$' "$remote_output"
grep -Eq '^acl_tool_available=(true|false)$' "$remote_output"

acl_tool_available=$(
    sed -n 's/^acl_tool_available=//p' "$remote_output"
)
if [[ "$acl_tool_available" == true ]]; then
    grep -Eq '^acl_tool_path=/.*getfacl$' "$remote_output"
    for label in retained_stage parent; do
        grep -Eq "^${label}_acl_line_count=[0-9]+$" "$remote_output"
        grep -Eq "^${label}_acl_sha256=[0-9a-f]{64}$" "$remote_output"
        grep -Eq "^${label}_acl_extended=(true|false)$" "$remote_output"
        acl_line_count=$(
            sed -n "s/^${label}_acl_line_count=//p" "$remote_output"
        )
        observed_acl_lines=$(
            grep -c "^${label}_acl_entry=" "$remote_output"
        )
        [[ "$observed_acl_lines" -eq "$acl_line_count" ]]
    done
else
    grep -Fxq 'acl_tool_path=unavailable' "$remote_output"
    grep -Fxq 'retained_stage_acl_line_count=unavailable' "$remote_output"
    grep -Fxq 'retained_stage_acl_sha256=unavailable' "$remote_output"
    grep -Fxq 'retained_stage_acl_extended=unknown' "$remote_output"
    grep -Fxq 'parent_acl_line_count=unavailable' "$remote_output"
    grep -Fxq 'parent_acl_sha256=unavailable' "$remote_output"
    grep -Fxq 'parent_acl_extended=unknown' "$remote_output"
    if grep -Eq '^(retained_stage|parent)_acl_entry=' "$remote_output"; then
        printf 'Unexpected ACL entries without getfacl.\n' >&2
        finish 97
    fi
fi

finish 0
