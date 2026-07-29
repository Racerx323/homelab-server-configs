#!/usr/bin/env bash

set -uo pipefail
set +x
PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH
readonly PATH

sanitize_line() {
    tr '\t\r\n' '   ' |
        sed -E 's/[[:space:]]+/ /g; s/^ //; s/ $//'
}

if [[ "${1:-}" == --self-test && $# -eq 1 ]]; then
    [[ "$(printf '  a\t b  \n' | sanitize_line)" == 'a b' ]]
    printf 'action_16ao_a_diagnostic_self_test_complete=true\n'
    exit 0
elif (($#)); then
    printf 'Usage: %s [--self-test]\n' "${0##*/}" >&2
    exit 2
fi

printf 'action_16ao_a_remote_reached=true\n'

hostname_status=0
node_hostname=$(hostname 2>/dev/null) || hostname_status=$?
architecture_status=0
node_architecture=$(dpkg --print-architecture 2>/dev/null) ||
    architecture_status=$?

ipv6_status=0
ipv6_output=$(
    ip -o -6 address show 2>/dev/null |
        sed -E 's/[[:space:]]+/ /g; s/^ //; s/ $//'
) || ipv6_status=$?
mapfile -t ipv6_records <<<"$ipv6_output"
if [[ -z "$ipv6_output" ]]; then
    ipv6_records=()
fi

systemctl_status=0
caddy_type=$(
    systemctl show caddy.service --property=Type --value 2>/dev/null
) || systemctl_status=$?
caddy_load_state=$(
    systemctl show caddy.service --property=LoadState --value 2>/dev/null
) || systemctl_status=$?
caddy_active_state=$(
    systemctl show caddy.service --property=ActiveState --value 2>/dev/null
) || systemctl_status=$?
caddy_unit_file_state=$(
    systemctl show caddy.service --property=UnitFileState --value 2>/dev/null
) || systemctl_status=$?
caddy_fragment_path=$(
    systemctl show caddy.service --property=FragmentPath --value 2>/dev/null
) || systemctl_status=$?
caddy_dropin_paths=$(
    systemctl show caddy.service --property=DropInPaths --value 2>/dev/null
) || systemctl_status=$?

type_directive_status=0
type_directive_records=()
for unit_path in "$caddy_fragment_path" $caddy_dropin_paths; do
    [[ -n "$unit_path" ]] || continue
    if [[ ! -f "$unit_path" ]]; then
        type_directive_status=1
        continue
    fi
    while IFS= read -r directive; do
        type_directive_records+=("$unit_path:$directive")
    done < <(
        grep -nE '^[[:space:]]*Type[[:space:]]*=' "$unit_path" 2>/dev/null ||
            true
    )
done

ss_status=0
tcp80_output=$(
    ss -H -lntp 'sport = :80' 2>/dev/null |
        sed -E 's/[[:space:]]+/ /g; s/^ //; s/ $//'
) || ss_status=$?
mapfile -t tcp80_records <<<"$tcp80_output"
if [[ -z "$tcp80_output" ]]; then
    tcp80_records=()
fi

printf 'hostname_status=%s\n' "$hostname_status"
printf 'node_hostname=%s\n' "$(printf '%s' "$node_hostname" | sanitize_line)"
printf 'architecture_status=%s\n' "$architecture_status"
printf 'node_architecture=%s\n' \
    "$(printf '%s' "$node_architecture" | sanitize_line)"
printf 'ipv6_command_status=%s\n' "$ipv6_status"
printf 'ipv6_record_count=%s\n' "${#ipv6_records[@]}"
for record in "${ipv6_records[@]}"; do
    printf 'ipv6_record=%s\n' "$(printf '%s' "$record" | sanitize_line)"
done

printf 'systemctl_command_status=%s\n' "$systemctl_status"
printf 'caddy_type=%s\n' "$(printf '%s' "$caddy_type" | sanitize_line)"
printf 'caddy_load_state=%s\n' \
    "$(printf '%s' "$caddy_load_state" | sanitize_line)"
printf 'caddy_active_state=%s\n' \
    "$(printf '%s' "$caddy_active_state" | sanitize_line)"
printf 'caddy_unit_file_state=%s\n' \
    "$(printf '%s' "$caddy_unit_file_state" | sanitize_line)"
printf 'caddy_fragment_path=%s\n' \
    "$(printf '%s' "$caddy_fragment_path" | sanitize_line)"
printf 'caddy_dropin_paths=%s\n' \
    "$(printf '%s' "$caddy_dropin_paths" | sanitize_line)"
printf 'type_directive_status=%s\n' "$type_directive_status"
printf 'type_directive_record_count=%s\n' "${#type_directive_records[@]}"
for record in "${type_directive_records[@]}"; do
    printf 'type_directive_record=%s\n' \
        "$(printf '%s' "$record" | sanitize_line)"
done

printf 'ss_command_status=%s\n' "$ss_status"
printf 'tcp80_listener_count=%s\n' "${#tcp80_records[@]}"
for record in "${tcp80_records[@]}"; do
    printf 'tcp80_listener=%s\n' "$(printf '%s' "$record" | sanitize_line)"
done

printf 'peer_connections=false\n'
printf 'installed_helper_execution=false\n'
printf 'systemd_daemon_reload_performed=false\n'
printf 'service_mutations=false\n'
printf 'action_16ao_a_diagnostic_complete=true\n'
exit 0
