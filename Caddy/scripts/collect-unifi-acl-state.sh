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
            "$controller/proxy/network/integration/v1/sites/$site_id/acl-rules?offset=0&limit=200"
)

if ! jq -e \
    'type == "object"
    and (.data | type == "array")
    and (.count | type == "number")
    and (.totalCount | type == "number")
    and (.count == .totalCount)' \
    >/dev/null <<<"$response"; then
    printf 'Invalid or incomplete UniFi ACL response.\n' >&2
    exit 3
fi

jq -c '
    {
        count,
        totalCount,
        rules: [
            .data[] |
            {
                id,
                name,
                description,
                enabled,
                index,
                action,
                type,
                networkId,
                protocolFilter,
                sourceFilter,
                destinationFilter,
                enforcingDeviceFilter,
                metadata
            }
        ]
    }
' <<<"$response"
