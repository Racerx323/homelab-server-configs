#!/usr/bin/env bash

set -euo pipefail

raw_path=/bin/ip
canonical_path=/usr/bin/ip
front_path=/usr/sbin/ip
expected_package=iproute2

package_inventory() {
    dpkg-query -W \
        -f='${binary:Package}\t${db:Status-Abbrev}\t${Version}\n' |
        sort
}

owner_matches_expected_package() {
    local output=$1

    grep -Eq "^${expected_package}(:[^:]+)?: ${raw_path}$" <<<"$output"
}

ip_file_list_entries() {
    local package_files=$1

    awk '$0 ~ /(^|\/)ip$/ { print }' <<<"$package_files"
}

self_test() {
    owner_matches_expected_package 'iproute2: /bin/ip'
    owner_matches_expected_package 'iproute2:arm64: /bin/ip'
    if owner_matches_expected_package 'other: /bin/ip'; then
        printf 'Unexpected package owner was accepted.\n' >&2
        return 1
    fi
    if owner_matches_expected_package 'iproute2: /usr/bin/ip'; then
        printf 'Canonical alias was accepted as raw-path ownership.\n' >&2
        return 1
    fi

    sample_files=$'/bin/ip\n/usr/share/doc/iproute2\n/usr/bin/bridge'
    [[ "$(ip_file_list_entries "$sample_files")" == /bin/ip ]]
    printf 'action_16x_e_self_test_complete=true\n'
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

[[ -L "$front_path" ]]
[[ "$(readlink -- "$front_path")" == "$raw_path" ]]
[[ -e "$raw_path" && -x "$raw_path" ]]
[[ "$(readlink -e -- "$raw_path")" == "$canonical_path" ]]
[[ -f "$canonical_path" && ! -L "$canonical_path" && -x "$canonical_path" ]]

set +e
raw_owner_output=$(dpkg-query --search "$raw_path" 2>&1)
raw_owner_rc=$?
canonical_owner_output=$(dpkg-query --search "$canonical_path" 2>&1)
canonical_owner_rc=$?
front_owner_output=$(dpkg-query --search "$front_path" 2>&1)
front_owner_rc=$?
set -e

raw_owner_match=false
if [[ "$raw_owner_rc" -eq 0 ]] &&
    owner_matches_expected_package "$raw_owner_output"; then
    raw_owner_match=true
fi

package_status=$(dpkg-query -W -f='${db:Status-Abbrev}' "$expected_package")
package_version=$(dpkg-query -W -f='${Version}' "$expected_package")
package_architecture=$(dpkg-query -W -f='${Architecture}' "$expected_package")
package_files=$(dpkg-query -L "$expected_package")
package_list_path=$(dpkg-query --control-path "$expected_package" .list)
package_list_state=$(stat -c '%F %U:%G %a %s %n' -- "$package_list_path")
package_list_sha=$(sha256sum -- "$package_list_path" | awk '{ print $1 }')
package_verify=$(dpkg --verify "$expected_package")
relevant_file_entries=$(ip_file_list_entries "$package_files")

raw_file_list_match=false
if grep -Fxq "$raw_path" <<<"$package_files"; then
    raw_file_list_match=true
fi
canonical_file_list_match=false
if grep -Fxq "$canonical_path" <<<"$package_files"; then
    canonical_file_list_match=true
fi
front_file_list_match=false
if grep -Fxq "$front_path" <<<"$package_files"; then
    front_file_list_match=true
fi

raw_state=$(stat -L -c '%F %U:%G %a %s %d:%i %n' -- "$raw_path")
canonical_state=$(stat -c '%F %U:%G %a %s %d:%i %n' -- "$canonical_path")
raw_sha=$(sha256sum -- "$raw_path" | awk '{ print $1 }')
canonical_sha=$(sha256sum -- "$canonical_path" | awk '{ print $1 }')
raw_device_inode=$(stat -L -c '%d:%i' -- "$raw_path")
canonical_device_inode=$(stat -c '%d:%i' -- "$canonical_path")

same_device_inode=false
if [[ "$raw_device_inode" == "$canonical_device_inode" ]]; then
    same_device_inode=true
fi
same_sha256=false
if [[ "$raw_sha" == "$canonical_sha" ]]; then
    same_sha256=true
fi

printf '%s\n' '--- raw /bin/ip ownership ---'
printf 'raw_path=%q\n' "$raw_path"
printf 'raw_owner_query_rc=%s\n' "$raw_owner_rc"
printf 'raw_owner_output=%q\n' "$raw_owner_output"
printf 'raw_owner_matches_iproute2=%s\n' "$raw_owner_match"

printf '%s\n' '--- alias ownership comparison ---'
printf 'canonical_path=%q\n' "$canonical_path"
printf 'canonical_owner_query_rc=%s\n' "$canonical_owner_rc"
printf 'canonical_owner_output=%q\n' "$canonical_owner_output"
printf 'front_path=%q\n' "$front_path"
printf 'front_owner_query_rc=%s\n' "$front_owner_rc"
printf 'front_owner_output=%q\n' "$front_owner_output"

printf '%s\n' '--- iproute2 package file list ---'
printf 'package_status=%q\n' "$package_status"
printf 'package_version=%q\n' "$package_version"
printf 'package_architecture=%q\n' "$package_architecture"
printf 'package_list_path=%q\n' "$package_list_path"
printf 'package_list_state=%q\n' "$package_list_state"
printf 'package_list_sha256=%s\n' "$package_list_sha"
printf 'relevant_file_entries_begin\n%s\nrelevant_file_entries_end\n' \
    "$relevant_file_entries"
printf 'raw_file_list_match=%s\n' "$raw_file_list_match"
printf 'canonical_file_list_match=%s\n' "$canonical_file_list_match"
printf 'front_file_list_match=%s\n' "$front_file_list_match"
printf 'package_verification_output=%q\n' "$package_verify"

printf '%s\n' '--- raw and canonical target reconciliation ---'
printf 'raw_state=%q\n' "$raw_state"
printf 'canonical_state=%q\n' "$canonical_state"
printf 'raw_sha256=%s\n' "$raw_sha"
printf 'canonical_sha256=%s\n' "$canonical_sha"
printf 'same_device_inode=%s\n' "$same_device_inode"
printf 'same_sha256=%s\n' "$same_sha256"

inventory_after=$(package_inventory)
audit_after=$(dpkg --audit)
[[ "$inventory_after" == "$inventory_before" ]]
[[ "$audit_after" == "$audit_before" ]]

printf '%s\n' '--- iproute2 ownership diagnostic summary ---'
printf 'dpkg_audit_before_bytes=%s\n' "${#audit_before}"
printf 'dpkg_audit_after_bytes=%s\n' "${#audit_after}"
printf 'iproute2_ownership_diagnostic_16x_e_complete=true\n'
