#!/usr/bin/env bash

set -euo pipefail

usage() {
    printf 'Usage: %s --controller URL --site-id UUID\n' "${0##*/}" >&2
}

controller=
site_id=

while (($# > 0)); do
    case "$1" in
        --controller)
            (($# >= 2)) || {
                usage
                exit 2
            }
            controller=$2
            shift 2
            ;;
        --site-id)
            (($# >= 2)) || {
                usage
                exit 2
            }
            site_id=$2
            shift 2
            ;;
        *)
            usage
            exit 2
            ;;
    esac
done

[[ "$controller" =~ ^https://[^/]+$ ]] || {
    printf 'Controller must be an HTTPS origin without a trailing slash.\n' >&2
    exit 2
}

[[ "$site_id" =~ ^[[:xdigit:]]{8}-[[:xdigit:]]{4}-[[:xdigit:]]{4}-[[:xdigit:]]{4}-[[:xdigit:]]{12}$ ]] || {
    printf 'Site ID must be a UUID.\n' >&2
    exit 2
}

[[ -n "${AUDIT:-}" ]] || {
    printf 'AUDIT is missing or empty.\n' >&2
    exit 2
}

for command_name in curl jq; do
    command -v "$command_name" >/dev/null 2>&1 || {
        printf 'Required command is unavailable: %s\n' "$command_name" >&2
        exit 2
    }
done

api_get_complete_page() {
    local resource=$1
    local response

    response=$(
        printf 'X-API-Key: %s\n' "$AUDIT" |
            curl \
                --header @- \
                --fail-with-body \
                --silent \
                --show-error \
                --globoff \
                --connect-timeout 5 \
                --max-time 30 \
                --request GET \
                "$controller/proxy/network/integration/v1/sites/$site_id/$resource?offset=0&limit=200"
    )

    if ! jq -e \
        'type == "object"
        and (.data | type == "array")
        and (.count | type == "number")
        and (.totalCount | type == "number")
        and (.count == .totalCount)' \
        >/dev/null <<<"$response"; then
        printf 'Invalid or incomplete UniFi response for %s.\n' "$resource" >&2
        exit 3
    fi

    printf '%s\n' "$response"
}

networks=$(api_get_complete_page networks)
zones=$(api_get_complete_page firewall/zones)
policies=$(api_get_complete_page firewall/policies)

printf '%s\n%s\n%s\n' "$networks" "$zones" "$policies" |
    jq -s '
        {
            networks: [
                .[0].data[] |
                {
                    id,
                    name,
                    enabled,
                    default,
                    vlanId,
                    management,
                    metadata
                }
            ],
            firewallZones: [
                .[1].data[] |
                {
                    id,
                    name,
                    networkIds,
                    metadata
                }
            ],
            firewallPolicies: [
                .[2].data[] |
                {
                    id,
                    name,
                    enabled,
                    index,
                    action,
                    source,
                    destination,
                    ipProtocolScope,
                    connectionStateFilter,
                    ipsecFilter,
                    loggingEnabled,
                    schedule,
                    metadata
                }
            ]
        }
    '
