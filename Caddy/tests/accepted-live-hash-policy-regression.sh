#!/usr/bin/env bash

set -Eeuo pipefail
set +x
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=accepted_live_hash_policy_regression
test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
readonly policy=$test_directory/accepted-live-hash-policy.sh
root=$(mktemp -d /tmp/caddy-accepted-live-hash-policy.XXXXXX)
readonly root
trap 'rm -rf -- "$root"' EXIT
readonly manifest=$root/Caddy/manifests/accepted-live-artifacts.tsv
readonly registry=$root/Caddy/manifests/deployable-live-hash-consumers.tsv
readonly inventory=$root/Caddy/manifests/production-artifacts.tsv
readonly lifecycle=$root/Caddy/manifests/manifest-lifecycle.tsv
readonly consumer=$root/Caddy/scripts/consumer.sh
readonly source_artifact=$root/Caddy/scripts/source.sh
readonly current_hash=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
readonly stale_hash=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb

install -d -m 0700 "$root/Caddy/manifests" "$root/Caddy/scripts"
printf 'current source\n' >"$source_artifact"
source_hash=$(sha256sum "$source_artifact" | awk '{ print $1 }')
readonly source_hash
printf 'node_a_health_helper\t%s\taccepted-action\n' "$current_hash" >"$manifest"
printf 'node_a_health_helper\tCaddy/scripts/consumer.sh\tnode_a_health_sha256\n' >"$registry"
printf 'node_a_health_helper\thomelab-server-configs\tCaddy/scripts/source.sh\t/usr/local/libexec/source.sh\tnode-a\t%s\t%s\taccepted-action\tproduction-current\n' \
    "$source_hash" "$current_hash" >"$inventory"
{
    printf 'Caddy/manifests/accepted-live-artifacts.tsv\tproduction-current\tyes\tCaddy/manifests/README.md\n'
    printf 'Caddy/manifests/deployable-live-hash-consumers.tsv\tproduction-current\tyes\tCaddy/manifests/README.md\n'
    printf 'Caddy/manifests/manifest-lifecycle.tsv\tproduction-current\tno\tCaddy/manifests/README.md\n'
    printf 'Caddy/manifests/production-artifacts.tsv\tproduction-current\tyes\tCaddy/manifests/README.md\n'
} >"$lifecycle"
printf '#!/usr/bin/env bash\nreadonly node_a_health_sha256=%s\n' "$current_hash" >"$consumer"
chmod 0755 "$consumer"

run_policy() {
    CADDY_ACCEPTED_LIVE_HASH_ROOT=$root \
        CADDY_ACCEPTED_LIVE_HASH_MANIFEST=$manifest \
        CADDY_ACCEPTED_LIVE_HASH_REGISTRY=$registry \
        CADDY_PRODUCTION_ARTIFACT_INVENTORY=$inventory \
        CADDY_MANIFEST_LIFECYCLE=$lifecycle \
        /bin/bash "$policy" --check >/dev/null 2>"$root/policy.stderr"
}
run_policy
[[ ! -s "$root/policy.stderr" ]]
printf '%s_current_consumer_accepted=true\n' "$prefix"

printf '#!/usr/bin/env bash\nreadonly node_a_health_sha256=%s\n' "$stale_hash" >"$consumer"
if run_policy; then
    printf '%s_stale_consumer_rejected=false\n' "$prefix" >&2
    exit 1
fi
printf '%s_stale_consumer_rejected=true\n' "$prefix"

printf '#!/usr/bin/env bash\nreadonly node_a_health_sha256=%s\n' "$current_hash" >"$consumer"
printf 'node_a_health_helper\t%s\taccepted-action\n' "$stale_hash" >"$manifest"
if run_policy; then
    printf '%s_manifest_change_invalidates_consumer=false\n' "$prefix" >&2
    exit 1
fi
printf '%s_manifest_change_invalidates_consumer=true\n' "$prefix"

printf 'node_a_health_helper\t%s\taccepted-action\n' "$current_hash" >"$manifest"
printf 'node_a_health_helper\t%s\tduplicate-action\n' "$current_hash" >>"$manifest"
if run_policy; then
    printf '%s_duplicate_manifest_key_rejected=false\n' "$prefix" >&2
    exit 1
fi
printf '%s_duplicate_manifest_key_rejected=true\n' "$prefix"

printf 'node_a_health_helper\t%s\taccepted-action\n' "$current_hash" >"$manifest"
: >"$inventory"
if run_policy; then
    printf '%s_missing_inventory_key_rejected=false\n' "$prefix" >&2
    exit 1
fi
printf '%s_missing_inventory_key_rejected=true\n' "$prefix"

printf 'node_a_health_helper\thomelab-server-configs\tCaddy/scripts/source.sh\t/usr/local/libexec/source.sh\tnode-a\t%s\t%s\twrong-action\tproduction-current\n' \
    "$source_hash" "$current_hash" >"$inventory"
if run_policy; then
    printf '%s_inventory_action_mismatch_rejected=false\n' "$prefix" >&2
    exit 1
fi
printf '%s_inventory_action_mismatch_rejected=true\n' "$prefix"

printf 'node_a_health_helper\thomelab-server-configs\tCaddy/scripts/source.sh\t/usr/local/libexec/source.sh\tnode-a\t%s\t%s\taccepted-action\tproduction-current\n' \
    "$source_hash" "$stale_hash" >"$inventory"
if run_policy; then
    printf '%s_inventory_deployed_identity_mismatch_rejected=false\n' "$prefix" >&2
    exit 1
fi
printf '%s_inventory_deployed_identity_mismatch_rejected=true\n' "$prefix"

printf 'node_a_health_helper\thomelab-server-configs\tCaddy/scripts/source.sh\t/usr/local/libexec/source.sh\tnode-a\t%s\t%s\taccepted-action\tproduction-current\n' \
    "$stale_hash" "$current_hash" >"$inventory"
if run_policy; then
    printf '%s_stale_source_identity_rejected=false\n' "$prefix" >&2
    exit 1
fi
printf '%s_stale_source_identity_rejected=true\n' "$prefix"

printf 'node_a_health_helper\thomelab-server-configs\tCaddy/scripts/source.sh\t/usr/local/libexec/source.sh\tnode-a\t%s\t%s\taccepted-action\tproduction-current\n' \
    "$source_hash" "$current_hash" >"$inventory"
: >"$registry"
run_policy
[[ ! -s "$root/policy.stderr" ]]
printf '%s_empty_deployable_registry_accepted=true\n' "$prefix"
printf 'node_a_health_helper\tCaddy/scripts/consumer.sh\tnode_a_health_sha256\n' >"$registry"
printf '%s\n' 'unclassified' >"$root/Caddy/manifests/unclassified.yaml"
if run_policy; then
    printf '%s_unclassified_manifest_rejected=false\n' "$prefix" >&2
    exit 1
fi
printf '%s_unclassified_manifest_rejected=true\n' "$prefix"
printf '%s_false_positive_controls=true\n' "$prefix"
printf '%s_false_negative_controls=true\n' "$prefix"
printf '%s_complete=true\n' "$prefix"
