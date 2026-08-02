#!/usr/bin/env bash

set -euo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly driver_sha256=e614883201526b82f7e5fe02b818210033d23ad3b3668dbe8a31fb6187c01897
readonly node_b_host_public_key='ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDsoJtJAFw7LCD85Jwfen/kzYhH13I5NuvkmgIy1jmyJ root@(none)'
readonly node_b_sync_public_key='ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBwBAlvUOqcazWjzfUOnwk1AHath8Xn8eoUDXBFQIG7e caddy-ha-sync'
readonly -a payload_checksums=(
    '65d872f63a7a7e9dc108111057164c1785a77bf00429672452cfd3f9f3fe7134  caddy-sync-rsync-receiver'
    '909ee3ca843757d8d956ac6d442d6079134b0235fa7d37c97d80590eb5870fbd  node-b-host-ed25519.pub'
    'c9a2ecfcc6a44c0cd30d06bbb2841ec50ffd11866ce1da77ff69f2b5ff8320b0  node-b-sync-ed25519.pub'
    'd1d1e4fd0fd3787e43d7801babfbcdec20015b6517282cdba67904aa1b554140  setup-sync-ssh.sh'
    '85df8a934c8dd9561a6f567f42549ebc01ee2605ca630150265004b9ec108072  validate-sync-ssh.sh'
)

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_dir
readonly driver="$script_dir/diagnose-node-a-sync-stage-transient-action16aj-b.sh"

verify_sources() {
    local checksum expected_hash relative_path

    [[ -f "$driver" && ! -L "$driver" ]]
    [[ "$(stat -c '%U:%G:%a' "$driver")" == aaron:aaron:755 ]]
    [[ "$(sha256sum "$driver" | awk '{ print $1 }')" == "$driver_sha256" ]]
    [[ "${#payload_checksums[@]}" -eq 5 ]]

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

if [[ "${1:-}" == --self-test ]]; then
    [[ "$driver_sha256" =~ ^[0-9a-f]{64}$ ]]
    verify_sources
    bash -n "$driver"
    "$driver" --self-test >/dev/null
    printf 'action_16aj_b_transient_diagnostic_runner_self_test_complete=true\n'
    exit 0
elif (($#)); then
    printf 'Usage: %s [--self-test]\n' "${0##*/}" >&2
    exit 2
fi

verify_sources

work_dir=$(mktemp -d /tmp/caddy-action16aj-b.XXXXXX)
readonly work_dir
readonly payload_dir="$work_dir/payload"
cleanup() {
    rm -rf -- "$work_dir"
}
trap cleanup EXIT

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

remote_script=$(<"$driver")
printf -v remote_command 'sudo -n /bin/bash -c %q' "$remote_script"
tar -C "$payload_dir" -cf - . |
    ssh -T \
        -o BatchMode=yes \
        -o ConnectTimeout=5 \
        -o HostKeyAlias=pihole0.local.theama.co \
        -o StrictHostKeyChecking=yes \
        pi@10.1.0.53 \
        "$remote_command" >"$work_dir/remote.out"

grep -Fxq \
    'action_16aj_b_transient_diagnostic_complete=true' \
    "$work_dir/remote.out"
grep -Eq '^diagnostic_failure_count=[0-9]+$' "$work_dir/remote.out"
grep -Eq '^first_failure=[A-Za-z0-9_]+$' "$work_dir/remote.out"
grep -Fxq 'stage_cleanup=true' "$work_dir/remote.out"
grep -Fxq 'live_state_after_cleanup=true' "$work_dir/remote.out"
grep -Fxq 'protected_state_after_cleanup_match=true' \
    "$work_dir/remote.out"
grep -Fxq 'diagnostic_stage_cleanup_valid=true' \
    "$work_dir/remote.out"

failure_count=$(
    sed -n 's/^diagnostic_failure_count=//p' "$work_dir/remote.out"
)
first_failure=$(
    sed -n 's/^first_failure=//p' "$work_dir/remote.out"
)
if [[ "$failure_count" -eq 0 ]]; then
    [[ "$first_failure" == none ]]
else
    [[ "$first_failure" != none ]]
fi

printf 'local_payload_hashes_valid=true\n'
cat "$work_dir/remote.out"
cleanup
trap - EXIT
[[ ! -e "$work_dir" && ! -L "$work_dir" ]]
printf 'action_16aj_b_local_cleanup_complete=true\n'
