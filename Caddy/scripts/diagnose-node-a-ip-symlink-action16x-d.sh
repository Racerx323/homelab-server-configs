#!/usr/bin/env bash

set -euo pipefail

link_path=/usr/sbin/ip
expected_package=iproute2

package_inventory() {
    dpkg-query -W \
        -f='${binary:Package}\t${db:Status-Abbrev}\t${Version}\n' |
        sort
}

path_owner_query() {
    local path=$1
    local output
    local query_rc

    set +e
    output=$(dpkg-query --search "$path" 2>&1)
    query_rc=$?
    set -e

    printf 'path=%q\n' "$path"
    printf 'query_rc=%s\n' "$query_rc"
    printf 'output=%q\n' "$output"
    if [[ "$query_rc" -eq 0 ]] &&
        grep -Eq "^${expected_package}(:[^:]+)?: " <<<"$output"; then
        printf 'expected_package_match=true\n'
    else
        printf 'expected_package_match=false\n'
    fi
}

literal_target_path() {
    local path=$1
    local link_text=$2

    if [[ "$link_text" == /* ]]; then
        readlink -m -- "$link_text"
    else
        readlink -m -- "$(dirname -- "$path")/$link_text"
    fi
}

self_test() {
    [[ "$(
        literal_target_path /usr/sbin/ip /bin/ip
    )" == /usr/bin/ip ||
    "$(
        literal_target_path /usr/sbin/ip /bin/ip
    )" == /bin/ip ]]
    [[ "$(
        literal_target_path /usr/sbin/example ../bin/example
    )" == /usr/bin/example ]]
    [[ "$(
        literal_target_path /usr/sbin/example example.real
    )" == /usr/sbin/example.real ]]
    printf 'action_16x_d_self_test_complete=true\n'
}

if [[ "${1:-}" == --self-test ]]; then
    [[ "$#" -eq 1 ]]
    self_test
    exit 0
elif (($#)); then
    printf 'Usage: %s [--self-test]\n' "${0##*/}" >&2
    exit 2
fi

[[ "$(hostname)" == j1-svpihole0 ]]
ipv4_state=$(ip -o -4 address show dev eth0)
grep -Fq '10.1.0.53/22' <<<"$ipv4_state"
[[ "$(dpkg --print-architecture)" == arm64 ]]

inventory_before=$(package_inventory)
audit_before=$(dpkg --audit)

[[ -L "$link_path" ]]
[[ -x "$link_path" ]]

link_text=$(readlink -- "$link_path")
literal_path=$(literal_target_path "$link_path" "$link_text")
canonical_path=$(readlink -e -- "$link_path")

[[ -n "$link_text" ]]
[[ -n "$literal_path" ]]
[[ -n "$canonical_path" ]]
[[ -e "$canonical_path" ]]
[[ -x "$canonical_path" ]]

link_lstat=$(stat -c '%F %U:%G %a %s %N' -- "$link_path")
resolved_stat=$(stat -L -c '%F %U:%G %a %s %n' -- "$link_path")
canonical_lstat=$(stat -c '%F %U:%G %a %s %n' -- "$canonical_path")
canonical_sha=$(sha256sum -- "$canonical_path" | awk '{ print $1 }')

package_status=$(dpkg-query -W -f='${db:Status-Abbrev}' "$expected_package")
package_version=$(dpkg-query -W -f='${Version}' "$expected_package")
package_architecture=$(dpkg-query -W -f='${Architecture}' "$expected_package")
package_files=$(dpkg-query -L "$expected_package")
package_verify=$(dpkg --verify "$expected_package")

printf '%s\n' '--- /usr/sbin/ip symlink diagnostic ---'
printf 'link_path=%q\n' "$link_path"
printf 'link_text=%q\n' "$link_text"
printf 'literal_target_path=%q\n' "$literal_path"
printf 'canonical_target_path=%q\n' "$canonical_path"
printf 'link_lstat=%q\n' "$link_lstat"
printf 'resolved_target_stat=%q\n' "$resolved_stat"
printf 'canonical_target_lstat=%q\n' "$canonical_lstat"
printf 'canonical_target_sha256=%s\n' "$canonical_sha"

printf '%s\n' '--- package ownership: link path ---'
path_owner_query "$link_path"
printf '%s\n' '--- package ownership: literal target path ---'
path_owner_query "$literal_path"
printf '%s\n' '--- package ownership: canonical target path ---'
path_owner_query "$canonical_path"

printf '%s\n' '--- iproute2 package state ---'
printf 'expected_package=%s\n' "$expected_package"
printf 'status=%q\n' "$package_status"
printf 'version=%q\n' "$package_version"
printf 'architecture=%q\n' "$package_architecture"
printf 'verification_output=%q\n' "$package_verify"
printf 'file_list_contains_link=%s\n' "$(
    if grep -Fxq "$link_path" <<<"$package_files"; then
        printf true
    else
        printf false
    fi
)"
printf 'file_list_contains_literal_target=%s\n' "$(
    if grep -Fxq "$literal_path" <<<"$package_files"; then
        printf true
    else
        printf false
    fi
)"
printf 'file_list_contains_canonical_target=%s\n' "$(
    if grep -Fxq "$canonical_path" <<<"$package_files"; then
        printf true
    else
        printf false
    fi
)"

inventory_after=$(package_inventory)
audit_after=$(dpkg --audit)
[[ "$inventory_after" == "$inventory_before" ]]
[[ "$audit_after" == "$audit_before" ]]

printf '%s\n' '--- symlink diagnostic summary ---'
printf 'dpkg_audit_before_bytes=%s\n' "${#audit_before}"
printf 'dpkg_audit_after_bytes=%s\n' "${#audit_after}"
printf 'ip_symlink_diagnostic_16x_d_complete=true\n'
