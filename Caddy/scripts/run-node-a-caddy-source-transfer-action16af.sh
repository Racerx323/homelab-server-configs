#!/usr/bin/env bash

set -euo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly driver_sha256=632de019c924fe504c74d1d55d795422145686c4486260b6729e550a9d3a383b
readonly expected_files=(
    Caddy/configs/caddy/Caddyfile
    Caddy/configs/caddy/conf.d/00-health.caddy
    Caddy/configs/caddy/conf.d/10-pihole-admin.caddy
    Caddy/configs/caddy/conf.d/90-default-deny.caddy
    Caddy/manifests/dependencies.yaml
    Caddy/manifests/deployment.yaml
    Caddy/manifests/dns-records.yaml
    Caddy/scripts/install-caddy-ha.sh
    Caddy/scripts/render-node-config.sh
    Caddy/templates/caddy-ha.env.in
    Caddy/templates/keepalived-caddy-ha.conf.in
    Caddy/templates/lsyncd-caddy.lua.in
)
readonly expected_checksums=(
    'a41c7816e927c16278fab018675a3f2db5b2aae89dd5b181f1ecb06ec9beb86e  Caddy/configs/caddy/Caddyfile'
    '05fa1d2875ee0639601447ccd31284d3df55fc8d5e8cedef4a291c61d44f4b27  Caddy/configs/caddy/conf.d/00-health.caddy'
    '5621134920da9dde97122fe9968a2debdd0c980ac0e432323fb46e0c1139798c  Caddy/configs/caddy/conf.d/10-pihole-admin.caddy'
    '9ce8430d11882f4e2008ff27f4f4a2fcad568f81081629289f64ad2450316b27  Caddy/configs/caddy/conf.d/90-default-deny.caddy'
    '0a9c6632171c7490b030f9e4ebc2a122342c0eb8c08f95db0becf09a3f965696  Caddy/manifests/dependencies.yaml'
    'ee58ae3d2af19c6b5fd45b8c87d9c4866450d1a2d737c277c26442db36ebcfd0  Caddy/manifests/deployment.yaml'
    '809c3734dccafc743ced9db81c03db94d1bf9f6918de68b6cc38383a204ebf22  Caddy/manifests/dns-records.yaml'
    '851e93e7b32b907374dfedab8c91867b74fda50243b10f9859128c24f6149ab7  Caddy/scripts/install-caddy-ha.sh'
    'd7fa1c57a4d74edd966b78cf66d79e534f49c09a7265c2ad326f00018fa4c1c2  Caddy/scripts/render-node-config.sh'
    'bbd5ff898e49b70e4d3dbac247c5ea11b762035404f5b58e2928d3dd5dc03679  Caddy/templates/caddy-ha.env.in'
    'ebc60650edd4cb384000604b402ce1e99153b50d505c7e13289b6b33d7abdd09  Caddy/templates/keepalived-caddy-ha.conf.in'
    '5091566ae9f8165d502305ce08dad75cf1c78b417eca3dbd1dca8efa7eff105a  Caddy/templates/lsyncd-caddy.lua.in'
)

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
caddy_root=$(cd -- "$script_dir/.." && pwd)
readonly script_dir caddy_root
readonly driver="$script_dir/stage-node-a-caddy-source-action16af.sh"

verify_sources() {
    local checksum expected_hash relative_path

    [[ -f "$driver" && ! -L "$driver" ]]
    [[ "$(stat -c '%U:%G:%a' "$driver")" == aaron:aaron:755 ]]
    [[ "$(sha256sum "$driver" | awk '{ print $1 }')" == "$driver_sha256" ]]
    [[ "${#expected_files[@]}" -eq 12 ]]
    [[ "${#expected_checksums[@]}" -eq 12 ]]

    for checksum in "${expected_checksums[@]}"; do
        expected_hash=${checksum%% *}
        relative_path=${checksum#*  }
        [[ -f "$caddy_root/../$relative_path" &&
            ! -L "$caddy_root/../$relative_path" ]]
        [[ "$(sha256sum "$caddy_root/../$relative_path" |
            awk '{ print $1 }')" == "$expected_hash" ]]
    done
}

if [[ "${1:-}" == --self-test ]]; then
    [[ "$driver_sha256" =~ ^[0-9a-f]{64}$ ]]
    verify_sources
    bash -n "$driver"
    printf 'action_16af_caddy_source_transfer_runner_self_test_complete=true\n'
    exit 0
elif (($#)); then
    printf 'Usage: %s [--self-test]\n' "${0##*/}" >&2
    exit 2
fi

verify_sources
remote_script=$(<"$driver")
printf -v remote_command 'sudo -n /bin/bash -c %q' "$remote_script"

tar -C "$caddy_root/.." -cf - "${expected_files[@]}" |
    ssh -T \
        -o BatchMode=yes \
        -o ConnectTimeout=5 \
        -o HostKeyAlias=pihole0.local.theama.co \
        -o StrictHostKeyChecking=yes \
        pi@10.1.0.53 \
        "$remote_command"
