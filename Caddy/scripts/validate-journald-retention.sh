#!/usr/bin/env bash
set -euo pipefail

effective_value() {
    local key=$1
    systemd-analyze cat-config systemd/journald.conf |
        awk -F= -v key="$key" '
            $1 == key && $2 != "" {
                value = $2
            }
            END {
                if (value != "") {
                    print value
                } else {
                    print "<default>"
                }
            }
        '
}

printf 'Storage=%s\n' "$(effective_value Storage)"
printf 'SystemMaxUse=%s\n' "$(effective_value SystemMaxUse)"
printf 'SystemKeepFree=%s\n' "$(effective_value SystemKeepFree)"
printf 'MaxRetentionSec=%s\n' "$(effective_value MaxRetentionSec)"

if [[ "$(effective_value Storage)" == "none" ]]; then
    printf 'journald Storage=none is incompatible with operational evidence.\n' >&2
    exit 1
fi
