#!/usr/bin/env bash

set -euo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly inspector_sha256=a6c2220ca1ee9a332c4bed3c2419283b087f400c12e9dd3bfef184543b78f6f1
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
readonly inspector="$script_dir/diagnose-node-a-sync-stage-rollback-action16aj-a.sh"

verify_sources() {
    local checksum expected_hash relative_path

    [[ -f "$inspector" && ! -L "$inspector" ]]
    [[ "$(stat -c '%U:%G:%a' "$inspector")" == aaron:aaron:755 ]]
    [[ "$(sha256sum "$inspector" | awk '{ print $1 }')" == "$inspector_sha256" ]]
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

local_test=false
if [[ "${1:-}" == --self-test ]]; then
    [[ "$inspector_sha256" =~ ^[0-9a-f]{64}$ ]]
    verify_sources
    bash -n "$inspector"
    "$inspector" --self-test >/dev/null
    printf 'action_16aj_a_rollback_diagnostic_runner_self_test_complete=true\n'
    exit 0
elif [[ "${1:-}" == --local-test && $# -eq 1 ]]; then
    local_test=true
elif (($#)); then
    printf 'Usage: %s [--self-test|--local-test]\n' "${0##*/}" >&2
    exit 2
fi

verify_sources

work_dir=$(mktemp -d /tmp/caddy-action16aj-a.XXXXXX)
readonly work_dir
readonly payload_dir="$work_dir/payload"
readonly extracted_dir="$work_dir/extracted"
readonly archive="$work_dir/payload.tar"
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

tar -C "$payload_dir" -cf "$archive" .
mapfile -t archive_files < <(
    tar -tf "$archive" |
        sed 's#^\./##' |
        sed '/^$/d' |
        sort
)
[[ "${archive_files[*]}" == "${expected_files[*]}" ]]
if printf '%s\n' "${archive_files[@]}" | grep -Fq /; then
    printf 'Unexpected nested archive path.\n' >&2
    exit 1
fi

install -d -m 0750 "$extracted_dir"
tar --extract --file "$archive" --directory "$extracted_dir" \
    --no-same-owner --no-same-permissions
chmod 0750 \
    "$extracted_dir/caddy-sync-rsync-receiver" \
    "$extracted_dir/setup-sync-ssh.sh" \
    "$extracted_dir/validate-sync-ssh.sh"
chmod 0640 \
    "$extracted_dir/node-b-host-ed25519.pub" \
    "$extracted_dir/node-b-sync-ed25519.pub"
if find "$extracted_dir" -type l -print -quit | grep -q .; then
    printf 'Unexpected symlink in extracted diagnostic payload.\n' >&2
    exit 1
fi
(
    cd "$extracted_dir"
    printf '%s\n' "${payload_checksums[@]}" |
        sha256sum --check --status
)
for file in \
    caddy-sync-rsync-receiver setup-sync-ssh.sh validate-sync-ssh.sh; do
    [[ "$(stat -c '%a' "$extracted_dir/$file")" == 750 ]]
done
for file in node-b-host-ed25519.pub node-b-sync-ed25519.pub; do
    [[ "$(stat -c '%a' "$extracted_dir/$file")" == 640 ]]
done
[[ "$(ssh-keygen -lf "$extracted_dir/node-b-host-ed25519.pub" -E sha256 |
    awk '{ print $2 }')" == 'SHA256:eDdqL/bS/EuVysKQ7yxJ6lpjJWf2PcymtfPwMlzacbo' ]]
[[ "$(ssh-keygen -lf "$extracted_dir/node-b-sync-ed25519.pub" -E sha256 |
    awk '{ print $2 }')" == 'SHA256:ykJmrl499fd2qRm9bYjgyrgeiTCA1rzTelBBKX0gy5g' ]]

if [[ "$local_test" == true ]]; then
    cleanup
    trap - EXIT
    [[ ! -e "$work_dir" && ! -L "$work_dir" ]]
    printf 'action_16aj_a_local_payload_test_complete=true\n'
    exit 0
fi

ssh -T \
    -o BatchMode=yes \
    -o ConnectTimeout=5 \
    -o HostKeyAlias=pihole0.local.theama.co \
    -o StrictHostKeyChecking=yes \
    pi@10.1.0.53 \
    'sudo -n /bin/bash -s --' \
    <"$inspector" >"$work_dir/remote.out"

grep -Fxq \
    'action_16aj_a_rollback_diagnostic_complete=true' \
    "$work_dir/remote.out"
grep -Eq '^diagnostic_mismatch_count=[0-9]+$' "$work_dir/remote.out"
grep -Eq '^rollback_state_valid=(true|false)$' "$work_dir/remote.out"
grep -Eq '^stage_absent=(true|false)$' "$work_dir/remote.out"
grep -Eq '^action_staging_count_match=(true|false)$' "$work_dir/remote.out"

diagnostic_mismatch_count=$(
    sed -n 's/^diagnostic_mismatch_count=//p' "$work_dir/remote.out"
)
rollback_state_valid=$(
    sed -n 's/^rollback_state_valid=//p' "$work_dir/remote.out"
)
if [[ "$diagnostic_mismatch_count" -eq 0 ]]; then
    [[ "$rollback_state_valid" == true ]]
else
    [[ "$rollback_state_valid" == false ]]
fi

printf 'local_payload_hashes_valid=true\n'
printf 'local_archive_file_set_valid=true\n'
printf 'local_extraction_contract_valid=true\n'
cat "$work_dir/remote.out"
cleanup
trap - EXIT
[[ ! -e "$work_dir" && ! -L "$work_dir" ]]
printf 'action_16aj_a_local_cleanup_complete=true\n'
