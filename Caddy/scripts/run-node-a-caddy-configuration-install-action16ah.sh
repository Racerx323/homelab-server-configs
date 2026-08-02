#!/usr/bin/env bash

set -euo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly driver_sha256=7324f3ded9d0d7ea550e072e14da46350d8abf35cc32b60926c811af2c10669e

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_dir
readonly driver="$script_dir/install-node-a-caddy-configuration-action16ah.sh"

verify_driver() {
    [[ -f "$driver" && ! -L "$driver" ]]
    [[ "$(stat -c '%U:%G:%a' "$driver")" == aaron:aaron:755 ]]
    [[ "$(sha256sum "$driver" | awk '{ print $1 }')" == "$driver_sha256" ]]
}

if [[ "${1:-}" == --self-test ]]; then
    [[ "$driver_sha256" =~ ^[0-9a-f]{64}$ ]]
    verify_driver
    bash -n "$driver"
    "$driver" --self-test >/dev/null
    printf 'action_16ah_caddy_install_runner_self_test_complete=true\n'
    exit 0
elif (($#)); then
    printf 'Usage: %s [--self-test]\n' "${0##*/}" >&2
    exit 2
fi

verify_driver
ssh -T \
    -o BatchMode=yes \
    -o ConnectTimeout=5 \
    -o HostKeyAlias=pihole0.local.theama.co \
    -o StrictHostKeyChecking=yes \
    pi@10.1.0.53 \
    'sudo -n /bin/bash -s --' <"$driver"
