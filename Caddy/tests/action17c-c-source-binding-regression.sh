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
readonly validator="$caddy_root/scripts/validate-sync-ssh-source-bound.sh"
readonly runner="$caddy_root/scripts/run-node-a-source-bound-transport-action17c-c.sh"
readonly template="$caddy_root/templates/lsyncd-caddy-source-bound.lua.in"
readonly renderer="$caddy_root/scripts/render-source-bound-sync-config-action17c-c.sh"
readonly historical_renderer="$caddy_root/scripts/render-node-config.sh"
readonly historical_template="$caddy_root/templates/lsyncd-caddy.lua.in"
readonly historical_validator="$caddy_root/scripts/validate-sync-ssh.sh"
readonly historical_renderer_sha256=d7fa1c57a4d74edd966b78cf66d79e534f49c09a7265c2ad326f00018fa4c1c2
readonly historical_template_sha256=5091566ae9f8165d502305ce08dad75cf1c78b417eca3dbd1dca8efa7eff105a
readonly historical_validator_sha256=85df8a934c8dd9561a6f567f42549ebc01ee2605ca630150265004b9ec108072

if [[ "${1:-}" != --self-test || $# -ne 1 ]]; then
    printf 'Usage: %s --self-test\n' "${0##*/}" >&2
    exit 2
fi

[[ "$(sha256sum "$historical_template" | awk '{ print $1 }')" == "$historical_template_sha256" ]]
[[ "$(sha256sum "$historical_validator" | awk '{ print $1 }')" == "$historical_validator_sha256" ]]
[[ "$(sha256sum "$historical_renderer" | awk '{ print $1 }')" == "$historical_renderer_sha256" ]]
bash -n "$validator" "$runner" "$renderer"
"$validator" --self-test >/dev/null
"$runner" --self-test >/dev/null
"$runner" --contract-test >/dev/null
"$renderer" --self-test >/dev/null

grep -Fq 'templates/lsyncd-caddy-source-bound.lua.in' \
    "$renderer"
grep -Fq 'AddressFamily = "inet6"' "$template"
grep -Fq 'BindAddress = "@NODE_IPV6@"' "$template"
grep -Fq 'HostKeyAlias = "@PEER_FQDN@"' "$template"
# shellcheck disable=SC2016
grep -Fq -- '-b "$NODE_IPV6"' "$validator"
# shellcheck disable=SC2016
grep -Fq 'remote_shell="ssh -6 -F /dev/null -b $NODE_IPV6' "$validator"
grep -Fq 'source_bound_direct_ssh_reached_forced_receiver=true' "$validator"
grep -Fq 'source_bound_rsync_dry_run=true' "$validator"
grep -Fq 'release_payload_transferred=false' "$validator"
grep -Fq \
    "'sudo -n /usr/sbin/runuser -u caddy-sync -- /bin/bash -s -- --connect'" \
    "$runner"

[[ "$(grep -Fc 'BindAddress = "@NODE_IPV6@"' "$template")" -eq 1 ]]
# shellcheck disable=SC2016
[[ "$(grep -Fc -- '-b "$NODE_IPV6"' "$validator")" -eq 2 ]]

if grep -Eq \
    'systemctl[[:space:]]+(start|stop|restart|reload|enable|disable|mask|unmask|daemon-reload|reset-failed)' \
    "$validator" "$runner"; then
    printf 'Action 17c-c contains a service mutation.\n' >&2
    exit 1
fi
if grep -Eq \
    'ip[[:space:]]+(-4[[:space:]]+|-6[[:space:]]+)?(address|addr|route|link|neigh)[[:space:]]+(add|append|change|delete|del|flush|replace|set)' \
    "$validator" "$runner"; then
    printf 'Action 17c-c contains a network mutation.\n' >&2
    exit 1
fi
if grep -Eq '(^|[[:space:]])--delete([[:space:]]|$)' \
    "$validator" "$runner" "$template"; then
    printf 'Action 17c-c contains a deletion request.\n' >&2
    exit 1
fi
if ! grep -Fq -- '--dry-run' "$validator"; then
    printf 'Action 17c-c rsync is not dry-run only.\n' >&2
    exit 1
fi

render_dir=$(mktemp -d /tmp/caddy-action17c-c-regression.XXXXXX)
trap 'rm -rf -- "$render_dir"' EXIT
for node_role in node-a node-b; do
    "$renderer" \
        --node "$node_role" \
        --manifest "$caddy_root/tests/fixtures/deployment.yaml" \
        --output "$render_dir/$node_role" >/dev/null
done
grep -Fxq '            BindAddress = "fd36:5aa8:6971:1::53",' \
    "$render_dir/node-a/caddy.lua"
grep -Fxq '            HostKeyAlias = "pihole00.local.theama.co",' \
    "$render_dir/node-a/caddy.lua"
grep -Fxq '            BindAddress = "fd36:5aa8:6971:1::54",' \
    "$render_dir/node-b/caddy.lua"
grep -Fxq '            HostKeyAlias = "pihole0.local.theama.co",' \
    "$render_dir/node-b/caddy.lua"

printf 'action_17c_c_source_binding_regression_complete=true\n'
