#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=template_lifecycle_policy
test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
default_repository_root=${test_directory%/Caddy/tests}
repository_root=$default_repository_root

if [[ $# -eq 3 && $1 == --check && $2 == --repository-root ]]; then
    repository_root=$3
    [[ "$repository_root" == /tmp/* && -d "$repository_root" &&
        ! -L "$repository_root" ]] || exit 64
elif [[ $# -ne 1 || $1 != --check ]]; then
    exit 64
fi

readonly default_repository_root repository_root
readonly lifecycle_manifest=$repository_root/Caddy/manifests/template-lifecycle.tsv
readonly template_directory=$repository_root/Caddy/templates

fail() {
    printf '%s_failure=%s\n' "$prefix" "$1" >&2
    exit 1
}

[[ -f "$lifecycle_manifest" && ! -L "$lifecycle_manifest" ]] ||
    fail manifest_not_regular
[[ -f "$template_directory/README.md" && ! -L "$template_directory/README.md" ]] ||
    fail readme_not_regular

observed_paths=$(mktemp /tmp/caddy-template-paths.XXXXXX)
manifest_paths=$(mktemp /tmp/caddy-template-manifest-paths.XXXXXX)
readonly observed_paths manifest_paths
trap 'rm -f -- "$observed_paths" "$manifest_paths"' EXIT

find "$template_directory" -maxdepth 1 -type f ! -name README.md \
    -printf 'Caddy/templates/%f\n' | LC_ALL=C sort >"$observed_paths"
awk -F '\t' '!/^#/ && NF { print $1 }' "$lifecycle_manifest" |
    LC_ALL=C sort >"$manifest_paths"
cmp --silent "$observed_paths" "$manifest_paths" || fail inventory_mismatch

awk -F '\t' '
    BEGIN { valid = 1 }
    /^#/ || !NF { next }
    NF != 4 { valid = 0; next }
    seen[$1]++
    $2 !~ /^(production-current|historical-obsolete|historical-superseded|historical-rejected|deferred-example)$/ { valid = 0 }
    $3 !~ /^(yes|no)$/ { valid = 0 }
    $2 == "production-current" && $3 != "yes" { valid = 0 }
    $2 != "production-current" && $3 != "no" { valid = 0 }
    END {
        for (path in seen) if (seen[path] != 1) valid = 0
        exit(valid ? 0 : 1)
    }
' "$lifecycle_manifest" || fail invalid_manifest_contract

require_entry() {
    local lifecycle_path=$1
    local lifecycle_state=$2
    local lifecycle_deployable=$3
    local lifecycle_authority=$4

    awk -F '\t' \
        -v path="$lifecycle_path" \
        -v state="$lifecycle_state" \
        -v deployable="$lifecycle_deployable" \
        -v authority="$lifecycle_authority" \
        '$1 == path && $2 == state && $3 == deployable && $4 == authority { found = 1 }
         END { exit(found ? 0 : 1) }' "$lifecycle_manifest" ||
        fail "required_entry_${lifecycle_path##*/}"
}

require_entry \
    Caddy/templates/authorized-key-receiver-finalized-v2.in \
    production-current yes Caddy/manifests/synchronization-protocol-v2.yaml
require_entry Caddy/templates/caddy-ha.env-v2.in production-current yes \
    Caddy/templates/caddy-ha.env-v2.in
require_entry Caddy/templates/caddy-ha.env.in historical-superseded no \
    Caddy/templates/caddy-ha.env-v2.in
require_entry Caddy/templates/keepalived-caddy-ha.conf.in \
    historical-obsolete no homelab-dns/Keepalived/configs
require_entry Caddy/templates/keepalived-caddy-ha-v2.conf.in \
    historical-obsolete no homelab-dns/Keepalived/configs
require_entry Caddy/templates/lsyncd-caddy-receiver-finalized-v2.lua.in \
    historical-superseded no Caddy/configs/lsyncd

[[ -f "$repository_root/Caddy/configs/lsyncd/caddy-node-a.lua" ]] ||
    fail node_a_lsyncd_missing
[[ -f "$repository_root/Caddy/configs/lsyncd/caddy-node-b.lua" ]] ||
    fail node_b_lsyncd_missing

installer=$repository_root/Caddy/scripts/install-caddy-ha.sh
renderer=$repository_root/Caddy/scripts/render-node-config.sh
readonly installer renderer
grep -Fq 'configs/lsyncd/caddy-node-a.lua' "$installer" ||
    fail installer_node_a_canonical_source_missing
grep -Fq 'configs/lsyncd/caddy-node-b.lua' "$installer" ||
    fail installer_node_b_canonical_source_missing
grep -Fq 'Keepalived is externally owned by homelab-dns/Keepalived/configs' \
    "$installer" || fail installer_keepalived_rejection_missing
if grep -Eq 'render_dir/(keepalived-caddy-ha\.conf|lsyncd-caddy\.lua)' \
    "$installer"; then
    fail installer_historical_render_consumer
fi
grep -Fq -- '--include-historical-components' "$renderer" ||
    fail renderer_historical_opt_in_missing

production_inventory=$repository_root/inventory/prod
readonly production_inventory
while IFS=$'\t' read -r lifecycle_path lifecycle_state \
    lifecycle_deployable lifecycle_authority; do
    [[ -n "$lifecycle_path" && "$lifecycle_path" != \#* ]] || continue
    [[ "$lifecycle_deployable" == no ]] || continue
    if grep -R -Fq -- "$lifecycle_path" "$production_inventory" \
        "$repository_root/Caddy/manifests/deployment.yaml" \
        "$repository_root/Caddy/manifests/synchronization-protocol-v2.yaml"; then
        fail "nondeployable_inventory_consumer_${lifecycle_path##*/}"
    fi
done <"$lifecycle_manifest"

printf '%s_check_inventory_complete=true\n' "$prefix"
printf '%s_check_lifecycle_contract=true\n' "$prefix"
printf '%s_check_canonical_sources=true\n' "$prefix"
printf '%s_check_production_inventory=true\n' "$prefix"
printf '%s_complete=true\n' "$prefix"
