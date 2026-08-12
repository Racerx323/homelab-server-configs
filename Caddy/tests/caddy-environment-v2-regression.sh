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
readonly policy=$test_directory/caddy-environment-v2-policy.sh
readonly renderer=$repository_root/Caddy/scripts/render-node-config.sh
work_directory=$(mktemp -d /tmp/caddy-environment-v2.XXXXXX)
readonly work_directory
trap 'rm -rf -- "$work_directory"' EXIT

/bin/bash "$policy" --check >/dev/null

for defect in missing extra duplicate unsafe obsolete; do
    fixture=$work_directory/$defect.in
    case "$defect" in
        missing)
            printf '%s\n' 'NODE_FQDN=@NODE_FQDN@' 'NODE_IPV4=@NODE_IPV4@' >"$fixture"
            ;;
        extra)
            cp -- "$repository_root/Caddy/templates/caddy-ha.env-v2.in" "$fixture"
            printf '%s\n' 'EXTRA=value' >>"$fixture"
            ;;
        duplicate)
            cp -- "$repository_root/Caddy/templates/caddy-ha.env-v2.in" "$fixture"
            printf '%s\n' 'NODE_IPV6=@NODE_IPV6@' >>"$fixture"
            ;;
        unsafe)
            # shellcheck disable=SC2016
            printf '%s\n' 'NODE_FQDN=$(id)' 'NODE_IPV4=@NODE_IPV4@' \
                'NODE_IPV6=@NODE_IPV6@' >"$fixture"
            ;;
        obsolete)
            printf '%s\n' 'NODE_FQDN=@NODE_FQDN@' 'NODE_IPV4=@NODE_IPV4@' \
                'SYNC_TARGET=peer' >"$fixture"
            ;;
    esac
    defect_status=0
    /bin/bash "$policy" --check --template "$fixture" >/dev/null 2>&1 ||
        defect_status=$?
    [[ "$defect_status" -eq 1 ]]
done

for node_role in node-a node-b; do
    output_directory=$work_directory/$node_role
    /bin/bash "$renderer" --node "$node_role" --output "$output_directory" \
        >/dev/null
    [[ "$(wc -l <"$output_directory/caddy-ha.env")" -eq 3 ]]
    case "$node_role" in
        node-a)
            expected_fqdn=pihole0.local.theama.co
            expected_ipv4=10.1.0.53
            expected_ipv6=fd36:5aa8:6971:1::53
            ;;
        node-b)
            expected_fqdn=pihole00.local.theama.co
            expected_ipv4=10.1.0.54
            expected_ipv6=fd36:5aa8:6971:1::54
            ;;
    esac
    grep -Fxq "NODE_FQDN=$expected_fqdn" "$output_directory/caddy-ha.env"
    grep -Fxq "NODE_IPV4=$expected_ipv4" "$output_directory/caddy-ha.env"
    grep -Fxq "NODE_IPV6=$expected_ipv6" "$output_directory/caddy-ha.env"
    if grep -Eq 'NODE_ROLE|PEER_|CADDY_PRIORITY|NETWORK_INTERFACE|SYNC_TARGET' \
        "$output_directory/caddy-ha.env"; then
        exit 1
    fi
done

printf 'caddy_environment_v2_regression_complete=true\n'
