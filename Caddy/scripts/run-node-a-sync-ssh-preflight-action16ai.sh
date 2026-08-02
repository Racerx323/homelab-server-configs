#!/usr/bin/env bash

set -euo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly node_a_inspector_sha256=7228e30eae408c88b30ed0ff5679f34bd8eaaddf891c1d7fbea16d3ff15554a4
readonly node_b_inspector_sha256=4721428e0ff94b1b4b9be456e954ef09891705b8828b3dbb39d506bffc09bf11
readonly expected_node_a_host_fingerprint='SHA256:tuPVPiBenlqqCDmfqEFfQMpM0q90zj94QMGlNZNC1QI'
readonly expected_node_b_sync_fingerprint='SHA256:ykJmrl499fd2qRm9bYjgyrgeiTCA1rzTelBBKX0gy5g'

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_dir
readonly node_a_inspector="$script_dir/inspect-node-a-sync-ssh-prestate-action16ai.sh"
readonly node_b_inspector="$script_dir/inspect-node-b-sync-peer-material-action16ai.sh"

verify_file() {
    local path=$1
    local expected_sha256=$2

    [[ -f "$path" && ! -L "$path" ]]
    [[ "$(stat -c '%U:%G:%a' "$path")" == aaron:aaron:755 ]]
    [[ "$(sha256sum "$path" | awk '{ print $1 }')" == "$expected_sha256" ]]
}

verify_artifacts() {
    verify_file "$node_a_inspector" "$node_a_inspector_sha256"
    verify_file "$node_b_inspector" "$node_b_inspector_sha256"
}

if [[ "${1:-}" == --self-test ]]; then
    verify_artifacts
    bash -n "$node_a_inspector"
    bash -n "$node_b_inspector"
    "$node_a_inspector" --self-test >/dev/null
    "$node_b_inspector" --self-test >/dev/null
    printf 'action_16ai_sync_ssh_preflight_runner_self_test_complete=true\n'
    exit 0
elif (($#)); then
    printf 'Usage: %s [--self-test]\n' "${0##*/}" >&2
    exit 2
fi

verify_artifacts

work_dir=$(mktemp -d /tmp/caddy-action16ai.XXXXXX)
readonly work_dir
cleanup() {
    rm -rf -- "$work_dir"
}
trap cleanup EXIT

ssh -T \
    -o BatchMode=yes \
    -o ConnectTimeout=5 \
    -o HostKeyAlias=pihole0.local.theama.co \
    -o StrictHostKeyChecking=yes \
    pi@10.1.0.53 \
    'sudo -n /bin/bash -s --' \
    <"$node_a_inspector" >"$work_dir/node-a.out"

ssh -T \
    -o BatchMode=yes \
    -o ConnectTimeout=5 \
    -o HostKeyAlias=pihole00.local.theama.co \
    -o StrictHostKeyChecking=yes \
    pi@10.1.0.54 \
    'sudo -n /bin/bash -s --' \
    <"$node_b_inspector" >"$work_dir/node-b.out"

[[ "$(wc -l <"$work_dir/node-a.out")" -eq 6 ]]
[[ "$(wc -l <"$work_dir/node-b.out")" -eq 6 ]]
grep -Fxq \
    "node_a_host_ed25519_fingerprint=$expected_node_a_host_fingerprint" \
    "$work_dir/node-a.out"
grep -Eq \
    '^node_a_host_ed25519_public_key=ssh-ed25519 [A-Za-z0-9+/=]+ .+$' \
    "$work_dir/node-a.out"
grep -Fxq 'node_a_sync_private_key_present=false' "$work_dir/node-a.out"
grep -Fxq 'node_a_sync_authorized_keys_present=false' "$work_dir/node-a.out"
grep -Fxq 'node_a_sync_live_scripts_present=false' "$work_dir/node-a.out"
grep -Fxq 'node_a_sync_ssh_prestate_complete=true' "$work_dir/node-a.out"

grep -Eq \
    '^node_b_host_ed25519_fingerprint=SHA256:[A-Za-z0-9+/]{43}$' \
    "$work_dir/node-b.out"
grep -Eq \
    '^node_b_host_ed25519_public_key=ssh-ed25519 [A-Za-z0-9+/=]+ .+$' \
    "$work_dir/node-b.out"
grep -Fxq \
    "node_b_sync_ed25519_fingerprint=$expected_node_b_sync_fingerprint" \
    "$work_dir/node-b.out"
grep -Eq \
    '^node_b_sync_ed25519_public_key=ssh-ed25519 [A-Za-z0-9+/=]+ .+$' \
    "$work_dir/node-b.out"
grep -Fxq 'node_b_authorized_keys_present=false' "$work_dir/node-b.out"
grep -Fxq 'node_b_sync_peer_material_complete=true' "$work_dir/node-b.out"

if grep -Eq 'PRIVATE KEY|CADDY_TLS_PRIVATE_KEY_PEM' \
    "$work_dir/node-a.out" "$work_dir/node-b.out"; then
    printf 'Unexpected private-key material marker in public evidence.\n' >&2
    exit 1
fi

cat "$work_dir/node-a.out"
cat "$work_dir/node-b.out"
printf 'action_16ai_sync_ssh_preflight_complete=true\n'
