#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
readonly repository_root=${test_directory%/Caddy/tests}
readonly renderer=$repository_root/Caddy/scripts/render-node-config.sh
readonly installer=$repository_root/Caddy/scripts/install-caddy-ha.sh
readonly manifest=$repository_root/Caddy/tests/fixtures/deployment.yaml
work_directory=$(mktemp -d /tmp/caddy-template-lifecycle.XXXXXX)
readonly work_directory
trap 'rm -rf -- "$work_directory"' EXIT

/bin/bash "$test_directory/template-lifecycle-policy.sh" --check >/dev/null

fixture_repository=$work_directory/policy-fixture
readonly fixture_repository
install -d -m 0700 \
    "$fixture_repository/Caddy/configs/lsyncd" \
    "$fixture_repository/Caddy/manifests" \
    "$fixture_repository/Caddy/scripts" \
    "$fixture_repository/Caddy/templates" \
    "$fixture_repository/inventory/prod"
cp -a -- "$repository_root/Caddy/templates/." \
    "$fixture_repository/Caddy/templates/"
cp -- "$repository_root/Caddy/manifests/template-lifecycle.tsv" \
    "$repository_root/Caddy/manifests/deployment.yaml" \
    "$repository_root/Caddy/manifests/synchronization-protocol-v2.yaml" \
    "$fixture_repository/Caddy/manifests/"
cp -- "$repository_root/Caddy/configs/lsyncd/caddy-node-a.lua" \
    "$repository_root/Caddy/configs/lsyncd/caddy-node-b.lua" \
    "$fixture_repository/Caddy/configs/lsyncd/"
cp -- "$renderer" "$installer" "$fixture_repository/Caddy/scripts/"
printf '%s\n' \
    'forbidden_template: Caddy/templates/keepalived-caddy-ha.conf.in' \
    >>"$fixture_repository/Caddy/manifests/deployment.yaml"
negative_policy_status=0
/bin/bash "$test_directory/template-lifecycle-policy.sh" --check \
    --repository-root "$fixture_repository" \
    >"$work_directory/negative-policy.stdout" \
    2>"$work_directory/negative-policy.stderr" || negative_policy_status=$?
[[ "$negative_policy_status" -eq 1 ]]
grep -Fxq \
    'template_lifecycle_policy_failure=nondeployable_inventory_consumer_keepalived-caddy-ha.conf.in' \
    "$work_directory/negative-policy.stderr"

default_output=$work_directory/default
historical_output=$work_directory/historical
readonly default_output historical_output
/bin/bash "$renderer" --node node-a --manifest "$manifest" \
    --output "$default_output" >/dev/null
[[ -f "$default_output/caddy-ha.env" ]]
[[ ! -e "$default_output/keepalived-caddy-ha.conf" ]]
[[ ! -e "$default_output/lsyncd-caddy.lua" ]]

/bin/bash "$renderer" --node node-a --manifest "$manifest" \
    --output "$historical_output" --include-historical-components \
    >"$work_directory/historical.stdout" \
    2>"$work_directory/historical.stderr"
[[ -f "$historical_output/caddy-ha.env" ]]
[[ -f "$historical_output/keepalived-caddy-ha.conf" ]]
[[ -f "$historical_output/lsyncd-caddy.lua" ]]
grep -Fxq \
    'Rendering historical non-production components for offline reconstruction only.' \
    "$work_directory/historical.stderr"

keepalived_status=0
/bin/bash "$installer" --node node-a --component keepalived --dry-run \
    >"$work_directory/keepalived.stdout" \
    2>"$work_directory/keepalived.stderr" || keepalived_status=$?
[[ "$keepalived_status" -eq 2 ]]
[[ ! -s "$work_directory/keepalived.stdout" ]]
grep -Fxq \
    'Keepalived is externally owned by homelab-dns/Keepalived/configs; installation from Caddy is prohibited.' \
    "$work_directory/keepalived.stderr"

for node_role in node-a node-b; do
    case "$node_role" in
        node-a) expected_source=caddy-node-a.lua ;;
        node-b) expected_source=caddy-node-b.lua ;;
    esac
    /bin/bash "$installer" --node "$node_role" --component lsyncd \
        --manifest "$manifest" --root "$work_directory/root-$node_role" \
        --dry-run >"$work_directory/$node_role.json" \
        2>"$work_directory/$node_role.stderr"
    jq -e \
        --arg node "$node_role" \
        '.node == $node and .component == "lsyncd" and .dry_run == true and .changes == 1' \
        "$work_directory/$node_role.json" >/dev/null
    grep -Fq "/configs/lsyncd/$expected_source -> " \
        "$work_directory/$node_role.stderr"
    if grep -Eq 'templates/lsyncd-|keepalived-caddy-ha' \
        "$work_directory/$node_role.stderr"; then
        exit 1
    fi
done

printf 'template_lifecycle_regression_complete=true\n'
