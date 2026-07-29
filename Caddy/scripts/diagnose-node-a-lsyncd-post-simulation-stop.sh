#!/usr/bin/env bash

set -euo pipefail

packages=(
    keepalived
    lsyncd
    rsync
    openssh-client
    openssh-server
)

package_inventory() {
    dpkg-query -W \
        -f='${binary:Package}\t${db:Status-Abbrev}\t${Version}\n' |
        sort
}

protected_service_state() {
    for service in \
        lighttpd.service keepalived.service ssh.service unbound.service \
        pihole-FTL.service munin-node.service; do
        systemctl show "$service" --no-pager \
            -p ActiveState -p SubState -p MainPID -p NRestarts
    done
}

text_sha256() {
    printf '%s' "$1" | sha256sum | awk '{ print $1 }'
}

regex_result() {
    local name=$1
    local pattern=$2

    if grep -Eq "$pattern" <<<"$simulation"; then
        printf '%s=true\n' "$name"
    else
        printf '%s=false\n' "$name"
    fi
}

fixed_result() {
    local name=$1
    local value=$2

    if grep -Fxq "$value" <<<"$simulation"; then
        printf '%s=true\n' "$name"
    else
        printf '%s=false\n' "$name"
    fi
}

[[ "$(hostname)" == j1-svpihole0 ]]

inventory_before=$(package_inventory)
services_before=$(protected_service_state)
listeners_before=$(ss -H -lntup | sort)

simulation=$(
    LC_ALL=C apt-get -s install --no-install-recommends \
        "${packages[@]}" 2>&1
)
printf '%s\n' "$simulation"

printf '%s\n' '--- simulation assertion diagnostics ---'
printf 'inst_count=%s\n' "$(
    awk '$1 == "Inst" { count++ } END { print count + 0 }' <<<"$simulation"
)"
printf 'conf_count=%s\n' "$(
    awk '$1 == "Conf" { count++ } END { print count + 0 }' <<<"$simulation"
)"
printf 'remv_count=%s\n' "$(
    awk '$1 == "Remv" { count++ } END { print count + 0 }' <<<"$simulation"
)"
regex_result \
    liblua_install_line_match \
    '^Inst liblua5[.]3-0 \(5[.]3[.]6-2 .*\[arm64\]\)$'
regex_result \
    lua_install_line_match \
    '^Inst lua5[.]3 \(5[.]3[.]6-2 .*\[arm64\]\)$'
regex_result \
    lsyncd_install_line_match \
    '^Inst lsyncd \(2[.]2[.]3-1 .*\[arm64\]\)$'
fixed_result \
    transaction_summary_match \
    '0 upgraded, 3 newly installed, 0 to remove and 0 not upgraded.'

inventory_after=$(package_inventory)
services_after=$(protected_service_state)
listeners_after=$(ss -H -lntup | sort)
audit=$(dpkg --audit)

printf '%s\n' '--- unchanged-state diagnostics ---'
printf 'inventory_before_sha256=%s\n' "$(text_sha256 "$inventory_before")"
printf 'inventory_after_sha256=%s\n' "$(text_sha256 "$inventory_after")"
printf 'inventory_unchanged=%s\n' \
    "$([[ "$inventory_after" == "$inventory_before" ]] && printf true || printf false)"
printf 'services_before_sha256=%s\n' "$(text_sha256 "$services_before")"
printf 'services_after_sha256=%s\n' "$(text_sha256 "$services_after")"
printf 'services_unchanged=%s\n' \
    "$([[ "$services_after" == "$services_before" ]] && printf true || printf false)"
printf 'listeners_before_sha256=%s\n' "$(text_sha256 "$listeners_before")"
printf 'listeners_after_sha256=%s\n' "$(text_sha256 "$listeners_after")"
printf 'listeners_unchanged=%s\n' \
    "$([[ "$listeners_after" == "$listeners_before" ]] && printf true || printf false)"
printf 'dpkg_audit_empty=%s\n' \
    "$([[ -z "$audit" ]] && printf true || printf false)"

printf 'lsyncd_post_simulation_diagnostic_complete=true\n'
