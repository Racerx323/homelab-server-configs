#!/usr/bin/env bash

set -euo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly source_stage=/tmp/caddy-cert-node-b-action12
readonly validator_sha256=fbca4722dc3da0f28ab44bea9fb8b846cac9bb25439658ad3d3b33815250aacb
readonly driver_sha256=4151960cbd6f955ee6d17353c491e890467ee535e6b467109b33d74b5d316378

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_dir
readonly validator="$script_dir/validate-workstation-certificate-stage-action16ac.sh"
readonly driver="$script_dir/stage-node-a-certificate-action16ae.sh"

verify_sources() {
    [[ -f "$validator" && ! -L "$validator" ]]
    [[ -f "$driver" && ! -L "$driver" ]]
    [[ "$(stat -c '%U:%G:%a' "$validator")" == aaron:aaron:755 ]]
    [[ "$(stat -c '%U:%G:%a' "$driver")" == aaron:aaron:755 ]]
    [[ "$(sha256sum "$validator" | awk '{ print $1 }')" == "$validator_sha256" ]]
    [[ "$(sha256sum "$driver" | awk '{ print $1 }')" == "$driver_sha256" ]]
}

if [[ "${1:-}" == --self-test ]]; then
    [[ "$source_stage" == /tmp/caddy-cert-node-b-action12 ]]
    [[ "$validator_sha256" == fbca4722dc3da0f28ab44bea9fb8b846cac9bb25439658ad3d3b33815250aacb ]]
    [[ "$driver_sha256" =~ ^[0-9a-f]{64}$ ]]
    verify_sources
    bash -n "$driver"
    printf 'action_16ae_certificate_transfer_runner_self_test_complete=true\n'
    exit 0
elif (($#)); then
    printf 'Usage: %s [--self-test]\n' "${0##*/}" >&2
    exit 2
fi

verify_sources
"$validator"

readonly files=(
    certificate-manifest.json
    fullchain.pem
    intermediates.pem
    leaf.pem
    privkey.pem
)

remote_script=$(<"$driver")
printf -v remote_command 'sudo -n /bin/bash -c %q' "$remote_script"

tar -C "$source_stage" -cf - "${files[@]}" |
    ssh -T \
        -o BatchMode=yes \
        -o ConnectTimeout=5 \
        -o HostKeyAlias=pihole0.local.theama.co \
        -o StrictHostKeyChecking=yes \
        pi@10.1.0.53 \
        "$remote_command"
