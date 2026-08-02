#!/usr/bin/env bash

set -euo pipefail

packages=(
    bash
    coreutils
    findutils
    iproute2
    iputils-arping
    jq
    ndisc6
    openssl
    procps
    tcpdump
    util-linux
    uuid-runtime
)

declare -A expected_versions=(
    [bash]='5.2.15-2+b13'
    [coreutils]='9.1-1'
    [findutils]='4.9.0-4'
    [iproute2]='6.1.0-3'
    [iputils - arping]='3:20221126-1+deb12u1'
    [jq]='1.6-2.1+deb12u2'
    [ndisc6]='1.0.5-1+b2'
    [openssl]='3.0.20-1~deb12u2+rpt1'
    [procps]='2:4.0.2-3'
    [tcpdump]='4.99.3-1'
    [util - linux]='2.38.1-5+deb12u3'
    [uuid - runtime]='2.38.1-5+deb12u3'
)

package_inventory() {
    dpkg-query -W \
        -f='${binary:Package}\t${db:Status-Abbrev}\t${Version}\n' |
        sort
}

mismatch_count=0
first_mismatch=none

record_mismatch() {
    local package=$1
    local field=$2

    mismatch_count=$((mismatch_count + 1))
    if [[ "$first_mismatch" == none ]]; then
        first_mismatch="${package}:${field}"
    fi
}

[[ "$(hostname)" == j1-svpihole0 ]]
ipv4_state=$(ip -o -4 address show dev eth0)
grep -Fq '10.1.0.53/22' <<<"$ipv4_state"
[[ "$(dpkg --print-architecture)" == arm64 ]]

inventory_before=$(package_inventory)
audit_before=$(dpkg --audit)

for package in "${packages[@]}"; do
    expected_version=${expected_versions[$package]}

    set +e
    status=$(
        dpkg-query -W -f='${db:Status-Abbrev}' "$package" 2>&1
    )
    status_rc=$?
    version=$(
        dpkg-query -W -f='${Version}' "$package" 2>&1
    )
    version_rc=$?
    architecture=$(
        dpkg-query -W -f='${Architecture}' "$package" 2>&1
    )
    architecture_rc=$?
    verify_output=$(dpkg --verify "$package" 2>&1)
    verify_rc=$?
    set -e

    status_match=false
    version_match=false
    architecture_match=false
    integrity_clean=false

    if [[ "$status_rc" -eq 0 && "$status" == 'ii ' ]]; then
        status_match=true
    else
        record_mismatch "$package" status
    fi
    if [[ "$version_rc" -eq 0 && "$version" == "$expected_version" ]]; then
        version_match=true
    else
        record_mismatch "$package" version
    fi
    if [[ "$architecture_rc" -eq 0 && "$architecture" == arm64 ]]; then
        architecture_match=true
    else
        record_mismatch "$package" architecture
    fi
    if [[ "$verify_rc" -eq 0 && -z "$verify_output" ]]; then
        integrity_clean=true
    else
        record_mismatch "$package" integrity
    fi

    printf '%s\n' "--- package diagnostic: $package ---"
    printf 'expected_status=%q\n' 'ii '
    printf 'observed_status=%q\n' "$status"
    printf 'status_query_rc=%s\n' "$status_rc"
    printf 'status_match=%s\n' "$status_match"
    printf 'expected_version=%s\n' "$expected_version"
    printf 'observed_version=%q\n' "$version"
    printf 'version_query_rc=%s\n' "$version_rc"
    printf 'version_match=%s\n' "$version_match"
    printf 'expected_architecture=arm64\n'
    printf 'observed_architecture=%q\n' "$architecture"
    printf 'architecture_query_rc=%s\n' "$architecture_rc"
    printf 'architecture_match=%s\n' "$architecture_match"
    printf 'dpkg_verify_rc=%s\n' "$verify_rc"
    printf 'integrity_clean=%s\n' "$integrity_clean"
    printf '%s\n' 'dpkg_verify_output_begin'
    printf '%s\n' "$verify_output"
    printf '%s\n' 'dpkg_verify_output_end'
done

inventory_after=$(package_inventory)
audit_after=$(dpkg --audit)
[[ "$inventory_after" == "$inventory_before" ]]
[[ "$audit_after" == "$audit_before" ]]

printf '%s\n' '--- diagnostic summary ---'
printf 'diagnostic_package_count=%s\n' "${#packages[@]}"
printf 'diagnostic_mismatch_count=%s\n' "$mismatch_count"
printf 'diagnostic_first_mismatch=%s\n' "$first_mismatch"
printf 'dpkg_audit_before_bytes=%s\n' "${#audit_before}"
printf 'dpkg_audit_after_bytes=%s\n' "${#audit_after}"
printf 'validation_dependency_stop_diagnostic_complete=true\n'
