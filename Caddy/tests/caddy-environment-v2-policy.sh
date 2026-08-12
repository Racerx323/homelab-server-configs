#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=caddy_environment_v2_policy
test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
readonly repository_root=${test_directory%/Caddy/tests}
template=$repository_root/Caddy/templates/caddy-ha.env-v2.in

if [[ $# -eq 3 && $1 == --check && $2 == --template ]]; then
    template=$3
    [[ "$template" == /tmp/* ]] || exit 64
elif [[ $# -ne 1 || $1 != --check ]]; then
    exit 64
fi
readonly template

fail() {
    printf '%s_failure=%s\n' "$prefix" "$1" >&2
    exit 1
}

[[ -f "$template" && ! -L "$template" ]] || fail template_not_regular
[[ "$(wc -l <"$template")" -eq 3 ]] || fail line_count
[[ "$(grep -Fxc 'NODE_FQDN=@NODE_FQDN@' "$template")" -eq 1 ]] ||
    fail node_fqdn_contract
[[ "$(grep -Fxc 'NODE_IPV4=@NODE_IPV4@' "$template")" -eq 1 ]] ||
    fail node_ipv4_contract
[[ "$(grep -Fxc 'NODE_IPV6=@NODE_IPV6@' "$template")" -eq 1 ]] ||
    fail node_ipv6_contract
if grep -Eq '^(NODE_ROLE|PEER_ROLE|PEER_IPV4|PEER_IPV6|CADDY_PRIORITY|NETWORK_INTERFACE|SYNC_TARGET)=' \
    "$template"; then
    fail obsolete_variable
fi
if grep -Eq '[[:cntrl:]]|[[:space:]]$|(^|=)[^=@A-Za-z0-9_.:-]' "$template"; then
    fail unsafe_value_shape
fi

printf '%s_check_exact_variables=true\n' "$prefix"
printf '%s_check_obsolete_variables_absent=true\n' "$prefix"
printf '%s_check_values_safe=true\n' "$prefix"
printf '%s_complete=true\n' "$prefix"
