#!/usr/bin/env bash
set -euo pipefail

skip_container=false
if [[ "${1:-}" == --skip-container ]]; then
    skip_container=true
elif (($#)); then
    printf 'Usage: %s [--skip-container]\n' "${0##*/}" >&2
    exit 2
fi

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
caddy_root=$(cd -- "$script_dir/.." && pwd)
server_repo=$(cd -- "$caddy_root/.." && pwd)
workspace=$(cd -- "$server_repo/.." && pwd)
monitoring_root="$workspace/homelab-monitoring-observability/Munin"

mapfile -d '' shell_files < <(
    find "$caddy_root/scripts" "$monitoring_root/scripts" -type f -print0
    find "$caddy_root/tests" -type f -name '*.sh' -print0
)

shellcheck "${shell_files[@]}"
shfmt -d -i 4 -ci "${shell_files[@]}"
yamllint --strict "$caddy_root/manifests"

while IFS= read -r -d '' json_file; do
    jq empty "$json_file"
done < <(find "$caddy_root" -type f -name '*.json' -print0)

work_dir=$(mktemp -d "${TMPDIR:-/tmp}/caddy-host-tests.XXXXXX")
trap 'rm -rf -- "$work_dir"' EXIT

for node_role in node-a node-b; do
    "$caddy_root/scripts/render-node-config.sh" \
        --node "$node_role" \
        --manifest "$caddy_root/tests/fixtures/deployment.yaml" \
        --output "$work_dir/$node_role" >/dev/null
    "$caddy_root/scripts/install-caddy-ha.sh" \
        --node "$node_role" \
        --manifest "$caddy_root/tests/fixtures/deployment.yaml" \
        --root "$work_dir/root-$node_role" \
        --dry-run >"$work_dir/dry-run-$node_role.json"
    jq -e \
        --arg node "$node_role" \
        '.node == $node and .dry_run == true and .service_mutations == false' \
        "$work_dir/dry-run-$node_role.json" >/dev/null
done

grep -R -Fq 'protocols h1 h2 h3' "$caddy_root/configs/caddy"
grep -Fq 'skip_install_trust' "$caddy_root/configs/caddy/Caddyfile"
grep -Fq 'health_follow_redirects' \
    "$caddy_root/configs/caddy/conf.d/10-pihole-admin.caddy"
grep -Fq 'TimeoutStopSec=30s' \
    "$caddy_root/systemd/caddy.service.d/override.conf"
grep -R -Fq 'ports: [443]' "$caddy_root/manifests/deployment.yaml"
grep -R -Fq 'virtual_router_id 110' "$caddy_root/templates"
grep -R -Fq 'virtual_router_id 111' "$caddy_root/templates"
grep -Fq 'targetdir = "/@NODE_ROLE@/"' \
    "$caddy_root/templates/lsyncd-caddy.lua.in"
grep -Fq "caddy-sync@\$SYNC_TARGET:/\$NODE_ROLE/" \
    "$caddy_root/scripts/validate-sync-ssh.sh"
grep -Fq \
    'exec /usr/bin/rrsync -wo -no-del /var/lib/caddy-sync/incoming' \
    "$caddy_root/scripts/caddy-sync-rsync-receiver"
grep -Fq -- '--shell /bin/sh' \
    "$caddy_root/scripts/install-caddy-ha.sh"
grep -Fq 'passwd --lock caddy-sync' \
    "$caddy_root/scripts/install-caddy-ha.sh"
grep -Fq 'scope: operator_workstation_only' \
    "$caddy_root/manifests/dependencies.yaml"
grep -Fq 'operator_workstation_required:' \
    "$caddy_root/manifests/dependencies.yaml"
[[ "$(grep -Ec '^[[:space:]]+- doppler$' \
    "$caddy_root/manifests/dependencies.yaml")" -eq 2 ]]

for plugin in caddy_health caddy_requests caddy_tls lsyncd_caddy; do
    "$monitoring_root/scripts/$plugin" config >/dev/null
    "$monitoring_root/scripts/$plugin" >/dev/null 2>&1
done

if [[ "$skip_container" == true ]]; then
    printf 'Host validation passed; Podman integration skipped.\n'
    exit 0
fi

podman build \
    --tag localhost/caddy-ha-validation:latest \
    --file "$script_dir/Containerfile" \
    "$script_dir"
podman run \
    --rm \
    --cap-add NET_ADMIN \
    --volume "$workspace:/workspace:ro" \
    localhost/caddy-ha-validation:latest \
    /workspace/homelab-server-configs/Caddy/tests/integration.sh

printf 'All Caddy HA repository validation passed.\n'
