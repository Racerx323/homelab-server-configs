#!/usr/bin/env bash

set -euo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly driver_sha256=377e58fe29f8a8ed1ef8fe32c28f33e46d025f4ea906e68c3e92800d07fa0145
readonly node_b_host_public_key='ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDsoJtJAFw7LCD85Jwfen/kzYhH13I5NuvkmgIy1jmyJ root@(none)'
readonly node_b_sync_public_key='ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBwBAlvUOqcazWjzfUOnwk1AHath8Xn8eoUDXBFQIG7e caddy-ha-sync'
readonly -a payload_checksums=(
    '65d872f63a7a7e9dc108111057164c1785a77bf00429672452cfd3f9f3fe7134  caddy-sync-rsync-receiver'
    '909ee3ca843757d8d956ac6d442d6079134b0235fa7d37c97d80590eb5870fbd  node-b-host-ed25519.pub'
    'c9a2ecfcc6a44c0cd30d06bbb2841ec50ffd11866ce1da77ff69f2b5ff8320b0  node-b-sync-ed25519.pub'
    'd1d1e4fd0fd3787e43d7801babfbcdec20015b6517282cdba67904aa1b554140  setup-sync-ssh.sh'
    '85df8a934c8dd9561a6f567f42549ebc01ee2605ca630150265004b9ec108072  validate-sync-ssh.sh'
)
readonly -a expected_files=(
    caddy-sync-rsync-receiver
    node-b-host-ed25519.pub
    node-b-sync-ed25519.pub
    setup-sync-ssh.sh
    validate-sync-ssh.sh
)

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_dir
readonly driver="$script_dir/stage-node-a-sync-ssh-artifacts-action16aj-e.sh"

verify_sources() {
    local checksum expected_hash relative_path

    [[ -f "$driver" && ! -L "$driver" ]]
    [[ "$(stat -c '%U:%G:%a' "$driver")" == aaron:aaron:755 ]]
    [[ "$(sha256sum "$driver" | awk '{ print $1 }')" == "$driver_sha256" ]]
    [[ "${#payload_checksums[@]}" -eq 5 ]]
    [[ "${#expected_files[@]}" -eq 5 ]]
    for checksum in "${payload_checksums[@]}"; do
        expected_hash=${checksum%% *}
        relative_path=${checksum#*  }
        case "$relative_path" in
            node-b-host-ed25519.pub | node-b-sync-ed25519.pub)
                continue
                ;;
        esac
        [[ -f "$script_dir/$relative_path" &&
            ! -L "$script_dir/$relative_path" ]]
        [[ "$(sha256sum "$script_dir/$relative_path" |
            awk '{ print $1 }')" == "$expected_hash" ]]
    done
}

mode=run
if [[ "${1:-}" == --self-test && $# -eq 1 ]]; then
    [[ "$driver_sha256" =~ ^[0-9a-f]{64}$ ]]
    verify_sources
    bash -n "$driver"
    "$driver" --self-test >/dev/null
    printf 'action_16aj_e_retained_stage_runner_self_test_complete=true\n'
    exit 0
elif [[ "${1:-}" == --local-test && $# -eq 1 ]]; then
    mode=local-test
elif (($#)); then
    printf 'Usage: %s [--self-test|--local-test]\n' "${0##*/}" >&2
    exit 2
fi

verify_sources

work_dir=$(mktemp -d /tmp/caddy-action16aj-e.XXXXXX)
readonly work_dir
readonly payload_dir="$work_dir/payload"
readonly extracted_dir="$work_dir/extracted"
readonly archive="$work_dir/payload.tar"
readonly remote_output="$work_dir/remote.out"
readonly remote_error="$work_dir/remote.err"
cleanup() {
    rm -rf -- "$work_dir"
}
trap cleanup EXIT

finish_local() {
    local status=$1

    cleanup
    trap - EXIT
    if [[ -e "$work_dir" || -L "$work_dir" ]]; then
        printf 'action_16aj_e_local_cleanup_complete=false\n' >&2
        exit 97
    fi
    printf 'action_16aj_e_local_cleanup_complete=true\n'
    exit "$status"
}

install -d -m 0700 "$payload_dir"
install -m 0750 \
    "$script_dir/caddy-sync-rsync-receiver" \
    "$script_dir/setup-sync-ssh.sh" \
    "$script_dir/validate-sync-ssh.sh" \
    "$payload_dir/"
printf '%s\n' "$node_b_host_public_key" \
    >"$payload_dir/node-b-host-ed25519.pub"
printf '%s\n' "$node_b_sync_public_key" \
    >"$payload_dir/node-b-sync-ed25519.pub"
chmod 0640 \
    "$payload_dir/node-b-host-ed25519.pub" \
    "$payload_dir/node-b-sync-ed25519.pub"
(
    cd "$payload_dir"
    printf '%s\n' "${payload_checksums[@]}" |
        sha256sum --check --status
)
printf 'local_payload_hashes_valid=true\n'

if [[ "$mode" == local-test ]]; then
    tar -C "$payload_dir" -cf "$archive" .
    mapfile -t archive_files < <(
        tar -tf "$archive" |
            sed 's#^\./##' |
            sed '/^$/d' |
            sort
    )
    [[ "${archive_files[*]}" == "${expected_files[*]}" ]]
    install -d -m 0750 "$extracted_dir"
    tar --extract --file "$archive" --directory "$extracted_dir" \
        --no-same-owner --no-same-permissions
    [[ "$(stat -c '%a' "$extracted_dir")" == 700 ]]
    chmod 0750 "$extracted_dir"
    [[ "$(stat -c '%a' "$extracted_dir")" == 750 ]]
    (
        cd "$extracted_dir"
        printf '%s\n' "${payload_checksums[@]}" |
            sha256sum --check --status
    )
    printf 'local_post_extract_root_mode_valid=true\n'
    printf 'local_archive_and_extraction_valid=true\n'
    finish_local 0
fi

remote_script=$(<"$driver")
printf -v remote_command 'sudo -n /bin/bash -c %q' "$remote_script"
set +e
tar -C "$payload_dir" -cf - . |
    ssh -T \
        -o BatchMode=yes \
        -o ConnectTimeout=5 \
        -o HostKeyAlias=pihole0.local.theama.co \
        -o StrictHostKeyChecking=yes \
        pi@10.1.0.53 \
        "$remote_command" >"$remote_output" 2>"$remote_error"
pipeline_result="$? ${PIPESTATUS[*]}"
set -e
read -r pipeline_status tar_status ssh_status <<<"$pipeline_result"

cat "$remote_output"
cat "$remote_error" >&2
printf 'tar_exit_status=%s\n' "${tar_status:-missing}"
printf 'ssh_exit_status=%s\n' "${ssh_status:-missing}"
printf 'pipeline_exit_status=%s\n' "$pipeline_status"
if [[ "$pipeline_status" -ne 0 ||
    "${tar_status:-1}" -ne 0 ||
    "${ssh_status:-1}" -ne 0 ]]; then
    finish_local 1
fi

required_markers=(
    action_16aj_e_remote_reached=true
    preflight_live_state=true
    preflight_original_stage_absent=true
    preflight_failed_diagnostic_stage_absent=true
    preflight_transient_diagnostic_stage_absent=true
    preflight_retained_stage_absent=true
    preflight_action_staging_count_zero=true
    preflight_protected_state_capture=true
    action_16aj_e_preflight_valid=true
    stage_root_post_extract_owner=true
    stage_root_post_extract_mode=true
    stage_root_post_extract_meta=true
    live_state_with_retained_stage=true
    protected_state_unchanged=true
    first_failure=none
    stage_path=/var/tmp/caddy-sync-ssh-node-a-action16aj-e
    stage_owner_mode=root:root:750
    stage_file_count=5
    stage_retained=true
    action_16aj_e_retained_stage_complete=true
)
for marker in "${required_markers[@]}"; do
    if ! grep -Fxq "$marker" "$remote_output"; then
        printf 'Missing required marker: %s\n' "$marker" >&2
        finish_local 1
    fi
done
if grep -Eq '=false$|manual_intervention_required=true' \
    "$remote_output" "$remote_error"; then
    finish_local 97
fi

finish_local 0
