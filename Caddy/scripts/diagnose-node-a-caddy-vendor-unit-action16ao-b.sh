#!/usr/bin/env bash

set -uo pipefail
set +x
PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH
readonly PATH

readonly mask_path=/etc/systemd/system/caddy.service

sanitize_line() {
    tr '\t\r\n' '   ' |
        sed -E 's/[[:space:]]+/ /g; s/^ //; s/ $//'
}

if [[ "${1:-}" == --self-test && $# -eq 1 ]]; then
    [[ "$(printf '  a\t b  \n' | sanitize_line)" == 'a b' ]]
    [[ "$mask_path" == /etc/systemd/system/caddy.service ]]
    printf 'action_16ao_b_diagnostic_self_test_complete=true\n'
    exit 0
elif (($#)); then
    printf 'Usage: %s [--self-test]\n' "${0##*/}" >&2
    exit 2
fi

printf 'action_16ao_b_remote_reached=true\n'

hostname_status=0
node_hostname=$(hostname 2>/dev/null) || hostname_status=$?
architecture_status=0
node_architecture=$(dpkg --print-architecture 2>/dev/null) ||
    architecture_status=$?

mask_lstat_status=0
mask_lstat=$(stat -c '%F|%U:%G|%a|%s' "$mask_path" 2>/dev/null) ||
    mask_lstat_status=$?
mask_readlink_status=0
mask_link_target=$(readlink -- "$mask_path" 2>/dev/null) ||
    mask_readlink_status=$?
mask_canonical_status=0
mask_canonical_target=$(readlink -f -- "$mask_path" 2>/dev/null) ||
    mask_canonical_status=$?
mask_canonical_stat_status=0
mask_canonical_stat=$(
    stat -Lc '%F|%U:%G|%a|%s' "$mask_path" 2>/dev/null
) || mask_canonical_stat_status=$?

package_query_status=0
package_record=$(
    dpkg-query -W \
        -f='${db:Status-Abbrev}|${binary:Package}|${Version}|${Architecture}\n' \
        caddy 2>/dev/null
) || package_query_status=$?

package_file_list_status=0
package_file_list=$(dpkg-query -L caddy 2>/dev/null) ||
    package_file_list_status=$?
vendor_unit_paths=()
declare -A seen_vendor_paths=()
while IFS= read -r candidate; do
    [[ "$candidate" == /*/caddy.service ]] || continue
    if [[ -z "${seen_vendor_paths[$candidate]+present}" ]]; then
        vendor_unit_paths+=("$candidate")
        seen_vendor_paths["$candidate"]=1
    fi
done <<<"$package_file_list"

vendor_inspection_status=0
vendor_unit_records=()
vendor_type_records=()
for vendor_path in "${vendor_unit_paths[@]}"; do
    vendor_lstat_status=0
    vendor_lstat=$(stat -c '%F|%U:%G|%a|%s' "$vendor_path" 2>/dev/null) ||
        vendor_lstat_status=$?
    vendor_canonical_status=0
    vendor_canonical=$(readlink -f -- "$vendor_path" 2>/dev/null) ||
        vendor_canonical_status=$?
    vendor_sha_status=0
    vendor_sha=$(sha256sum -- "$vendor_path" 2>/dev/null | awk '{ print $1 }') ||
        vendor_sha_status=$?
    vendor_owner_status=0
    vendor_owner=$(dpkg-query -S "$vendor_path" 2>/dev/null) ||
        vendor_owner_status=$?
    if ((vendor_lstat_status != 0 || \
        vendor_canonical_status != 0 || \
        vendor_sha_status != 0 || \
        vendor_owner_status != 0)); then
        vendor_inspection_status=1
    fi
    vendor_unit_records+=(
        "path=$vendor_path|lstat_status=$vendor_lstat_status|lstat=$vendor_lstat|canonical_status=$vendor_canonical_status|canonical=$vendor_canonical|sha256_status=$vendor_sha_status|sha256=$vendor_sha|owner_status=$vendor_owner_status|owner=$vendor_owner"
    )
    while IFS= read -r directive; do
        vendor_type_records+=("$vendor_path:$directive")
    done < <(
        grep -nE '^[[:space:]]*Type[[:space:]]*=' "$vendor_path" \
            2>/dev/null || true
    )
done

printf 'hostname_status=%s\n' "$hostname_status"
printf 'node_hostname=%s\n' "$(printf '%s' "$node_hostname" | sanitize_line)"
printf 'architecture_status=%s\n' "$architecture_status"
printf 'node_architecture=%s\n' \
    "$(printf '%s' "$node_architecture" | sanitize_line)"
printf 'mask_lstat_status=%s\n' "$mask_lstat_status"
printf 'mask_path=%s\n' "$mask_path"
printf 'mask_lstat=%s\n' "$(printf '%s' "$mask_lstat" | sanitize_line)"
printf 'mask_readlink_status=%s\n' "$mask_readlink_status"
printf 'mask_link_target=%s\n' \
    "$(printf '%s' "$mask_link_target" | sanitize_line)"
printf 'mask_canonical_status=%s\n' "$mask_canonical_status"
printf 'mask_canonical_target=%s\n' \
    "$(printf '%s' "$mask_canonical_target" | sanitize_line)"
printf 'mask_canonical_stat_status=%s\n' "$mask_canonical_stat_status"
printf 'mask_canonical_stat=%s\n' \
    "$(printf '%s' "$mask_canonical_stat" | sanitize_line)"
printf 'package_query_status=%s\n' "$package_query_status"
printf 'package_record=%s\n' \
    "$(printf '%s' "$package_record" | sanitize_line)"
printf 'package_file_list_status=%s\n' "$package_file_list_status"
printf 'vendor_inspection_status=%s\n' "$vendor_inspection_status"
printf 'vendor_unit_record_count=%s\n' "${#vendor_unit_records[@]}"
for record in "${vendor_unit_records[@]}"; do
    printf 'vendor_unit_record=%s\n' \
        "$(printf '%s' "$record" | sanitize_line)"
done
printf 'vendor_type_record_count=%s\n' "${#vendor_type_records[@]}"
for record in "${vendor_type_records[@]}"; do
    printf 'vendor_type_record=%s\n' \
        "$(printf '%s' "$record" | sanitize_line)"
done

printf 'peer_connections=false\n'
printf 'installed_helper_execution=false\n'
printf 'systemd_daemon_reload_performed=false\n'
printf 'service_mutations=false\n'
printf 'action_16ao_b_diagnostic_complete=true\n'
exit 0
