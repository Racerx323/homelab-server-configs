#!/usr/bin/env bash

set -euo pipefail
set +x
PATH=/usr/bin:/bin
export PATH
readonly PATH

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_dir
caddy_root=$(cd -- "$script_dir/.." && pwd)
readonly caddy_root
readonly inspector="$caddy_root/scripts/inspect-node-b-restricted-transport-state-action17c.sh"
readonly driver="$caddy_root/scripts/validate-node-a-to-node-b-restricted-transport-action17c.sh"
readonly runner="$caddy_root/scripts/run-node-a-to-node-b-restricted-transport-action17c.sh"
readonly receiver="$caddy_root/scripts/caddy-sync-rsync-receiver"
readonly inspector_sha256=37e5390fb132c77002b468d9dfabfc579d5bb03f1da44f60802c448df3a35111
readonly driver_sha256=f3e775716ec0d3506b67088286545fb5998e2c587b56f18e5f20b27c314a15c0
readonly runner_sha256=d2b8672f7b3c336e4dfe9e1bf7f12b61290e8a993a8c92eef252b3a5b03f510b
readonly receiver_sha256=65d872f63a7a7e9dc108111057164c1785a77bf00429672452cfd3f9f3fe7134

assert_hash() {
    local path=$1
    local expected=$2

    [[ "$(sha256sum "$path" | awk '{ print $1 }')" == "$expected" ]]
}

if [[ "${1:-}" != --self-test || $# -ne 1 ]]; then
    printf 'Usage: %s --self-test\n' "${0##*/}" >&2
    exit 2
fi

assert_hash "$inspector" "$inspector_sha256"
assert_hash "$driver" "$driver_sha256"
assert_hash "$runner" "$runner_sha256"
assert_hash "$receiver" "$receiver_sha256"
bash -n "$inspector" "$driver" "$runner" "$receiver"
"$inspector" --self-test >/dev/null
"$driver" --self-test >/dev/null
"$runner" --contract-test >/dev/null

grep -Fq 'readonly node_b_ipv4=10.1.0.54' "$driver"
grep -Fq 'readonly node_b_ipv6=fd36:5aa8:6971:1::54' "$driver"
grep -Fq 'readonly node_b_host_alias=pihole00.local.theama.co' "$driver"
# These are intentional literal shell-source assertions.
# shellcheck disable=SC2016
grep -Fq 'run_denied_probe -4 "$node_b_ipv4"' "$driver"
# shellcheck disable=SC2016
grep -Fq 'run_denied_probe -6 "$node_b_ipv6"' "$driver"
grep -Fq -- '--dry-run' "$driver"
grep -Fq '/var/lib/caddy-sync/outbound/' "$driver"
# shellcheck disable=SC2016
grep -Fq '"caddy-sync@$node_b_ipv4:/node-a/"' "$driver"
grep -Fq 'release_payload_transferred=false' "$driver"
grep -Fq 'node_a_protected_state_unchanged=true' "$driver"
grep -Fq 'node_b_protected_state_unchanged=true' "$runner"
grep -Fq 'UpdateHostKeys=no' "$driver"
grep -Fq 'GlobalKnownHostsFile=/dev/null' "$driver"
grep -Fq 'ClearAllForwardings=yes' "$driver"
grep -Fq 'action_17c_restricted_transport_accepted=true' "$runner"

if grep -Eq \
    'systemctl[[:space:]]+(start|stop|restart|reload|enable|disable|mask|unmask|daemon-reload|reset-failed)' \
    "$inspector" "$driver"; then
    printf 'Action 17c contains a service mutation.\n' >&2
    exit 1
fi
if grep -Fq -- '--delete' "$driver"; then
    printf 'Action 17c driver contains a deletion request.\n' >&2
    exit 1
fi
if grep -Eq \
    '^[[:space:]]*(install|cp|mv|touch|chmod|chown|tee|truncate|ln|mkdir)([[:space:]]|$)' \
    "$inspector"; then
    printf 'Action 17c Node B inspector contains a write command.\n' >&2
    exit 1
fi

negative_dir=$(mktemp -d /tmp/caddy-action17c-receiver.XXXXXX)
trap 'rm -rf -- "$negative_dir"' EXIT
negative_status=0
SSH_ORIGINAL_COMMAND=caddy-action17c-denied-probe \
    "$receiver" >"$negative_dir/out" 2>"$negative_dir/err" ||
    negative_status=$?
[[ "$negative_status" -eq 126 ]]
[[ ! -s "$negative_dir/out" ]]
[[ "$(<"$negative_dir/err")" == 'Only the rsync server protocol is permitted.' ]]

printf 'action_17c_restricted_transport_regression_complete=true\n'
