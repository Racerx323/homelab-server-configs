#!/usr/bin/env bash

set -uo pipefail
set +x
PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH
readonly PATH

readonly environment_file=/etc/default/caddy-ha
readonly current_link=/etc/caddy/current
readonly caddyfile=/etc/caddy/current/Caddyfile

sanitize_line() {
    tr '\t\r\n' '   ' |
        sed -E 's/[[:space:]]+/ /g; s/^ //; s/ $//'
}

config_tree_hash() {
    local root=$1

    (
        cd "$root" || exit 1
        {
            [[ -f Caddyfile ]] && printf '%s\0' Caddyfile
            find conf.d -type f -print0 2>/dev/null
        } |
            sort -z |
            xargs -0 -r sha256sum
    ) | sha256sum | awk '{ print $1 }'
}

unit_property() {
    local property=$1

    systemctl show caddy.service --property="$property" --value 2>/dev/null |
        sanitize_line
}

emit_validation() {
    local mode=$1
    local status=$2
    local output=$3
    local -a records=()
    local record

    mapfile -t records < <(
        printf '%s\n' "$output" |
            sed -n '1,40p' |
            sed -E 's/[[:space:]]+/ /g; s/^ //; s/ $//'
    )
    if [[ "${#records[@]}" -eq 1 && -z "${records[0]}" ]]; then
        records=()
    fi
    printf 'validation_status_%s=%s\n' "$mode" "$status"
    printf 'validation_record_count_%s=%s\n' "$mode" "${#records[@]}"
    for record in "${records[@]}"; do
        printf 'validation_output_record=%s|%s\n' "$mode" "$record"
    done
}

if [[ "${1:-}" == --self-test && $# -eq 1 ]]; then
    [[ "$environment_file" == /etc/default/caddy-ha ]]
    [[ "$current_link" == /etc/caddy/current ]]
    [[ "$(printf '  a\t b  \n' | sanitize_line)" == 'a b' ]]
    printf 'action_16ap_b_validation_provenance_self_test_complete=true\n'
    exit 0
elif [[ $# -ne 1 || ! "$1" =~ ^node-(a|b)$ ]]; then
    printf 'Usage: %s node-a|node-b\n' "${0##*/}" >&2
    exit 2
fi

readonly expected_node=$1
case "$expected_node" in
    node-a)
        readonly expected_hostname=j1-svpihole0
        ;;
    node-b)
        readonly expected_hostname=j1-svpihole00
        ;;
esac

observed_hostname=$(hostname 2>/dev/null)
readonly observed_hostname
[[ "$observed_hostname" == "$expected_hostname" ]]
[[ $EUID -eq 0 ]]

printf 'action_16ap_b_remote_reached=true\n'
printf 'diagnostic_node=%s\n' "$expected_node"
printf 'node_hostname=%s\n' "$observed_hostname"
printf 'node_architecture=%s\n' \
    "$(dpkg --print-architecture 2>/dev/null | sanitize_line)"

caddy_path=$(command -v caddy 2>/dev/null || true)
printf 'caddy_binary_path=%s\n' \
    "$(printf '%s' "$caddy_path" | sanitize_line)"
printf 'caddy_binary_sha256=%s\n' \
    "$(sha256sum "$caddy_path" 2>/dev/null | awk '{ print $1 }' ||
        printf 'unavailable')"
caddy_version_output=$(caddy version 2>&1)
caddy_version_status=$?
printf 'caddy_version_status=%s\n' "$caddy_version_status"
printf 'caddy_version=%s\n' \
    "$(printf '%s' "$caddy_version_output" | sanitize_line)"
printf 'caddy_package=%s\n' \
    "$(dpkg-query -W \
        -f='${Status}|${binary:Package}|${Version}|${Architecture}' \
        caddy 2>/dev/null | sanitize_line)"

printf 'environment_metadata=%s\n' \
    "$(stat -c '%U:%G:%a:%s:%d:%i' "$environment_file" 2>/dev/null ||
        printf 'unavailable')"
printf 'environment_sha256=%s\n' \
    "$(sha256sum "$environment_file" 2>/dev/null |
        awk '{ print $1 }' || printf 'unavailable')"

printf 'current_link_target=%s\n' \
    "$(readlink "$current_link" 2>/dev/null | sanitize_line)"
printf 'current_release=%s\n' \
    "$(readlink -e "$current_link" 2>/dev/null | sanitize_line)"
printf 'current_revision=%s\n' \
    "$(jq -r '.revision // "unavailable"' \
        "$current_link/release-manifest.json" 2>/dev/null | sanitize_line)"
printf 'caddyfile_sha256=%s\n' \
    "$(sha256sum "$caddyfile" 2>/dev/null |
        awk '{ print $1 }' || printf 'unavailable')"
printf 'config_tree_sha256=%s\n' \
    "$(config_tree_hash "$current_link" 2>/dev/null ||
        printf 'unavailable')"

readonly -a unit_properties=(
    LoadState
    ActiveState
    SubState
    UnitFileState
    User
    Group
    EnvironmentFiles
    ExecStart
    FragmentPath
    DropInPaths
)
printf 'unit_property_record_count=%s\n' "${#unit_properties[@]}"
for property in "${unit_properties[@]}"; do
    printf 'unit_property_record=%s|%s\n' \
        "$property" "$(unit_property "$property")"
done

bare_output=$(
    env \
        -u NODE_ROLE \
        -u NODE_FQDN \
        -u NODE_IPV4 \
        -u NODE_IPV6 \
        -u CADDY_CONFIG_ROOT \
        runuser -u caddy -- \
        caddy validate --config "$caddyfile" --adapter caddyfile 2>&1
)
bare_status=$?
emit_validation bare "$bare_status" "$bare_output"

environment_source_status=0
set -a
# shellcheck disable=SC1090
source "$environment_file" 2>/dev/null || environment_source_status=$?
set +a
printf 'environment_source_status=%s\n' "$environment_source_status"
for variable_name in \
    NODE_ROLE NODE_FQDN NODE_IPV4 NODE_IPV6 CADDY_CONFIG_ROOT; do
    printf 'environment_value=%s|%s\n' \
        "$variable_name" \
        "$(printf '%s' "${!variable_name-}" | sanitize_line)"
done
printf 'environment_value_count=5\n'

if [[ "$environment_source_status" -eq 0 ]]; then
    environment_output=$(
        runuser -u caddy -- \
            caddy validate --config "$caddyfile" --adapter caddyfile 2>&1
    )
    environment_status=$?
    emit_validation environment "$environment_status" "$environment_output"
else
    emit_validation environment not_applicable ''
fi

printf 'peer_connections=false\n'
printf 'installed_helper_execution=false\n'
printf 'systemd_daemon_reload_performed=false\n'
printf 'service_mutations=false\n'
printf 'filesystem_mutations=false\n'
printf 'action_16ap_b_validation_provenance_complete=true\n'
exit 0
