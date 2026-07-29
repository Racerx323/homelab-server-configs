#!/usr/bin/env bash

set -euo pipefail

command_paths=(
    /usr/bin/bash
    /usr/bin/sha256sum
    /usr/bin/find
    /usr/sbin/ip
    /usr/bin/arping
    /usr/bin/jq
    /usr/bin/ndisc6
    /usr/bin/openssl
    /usr/bin/ps
    /usr/bin/tcpdump
    /usr/bin/uuidgen
    /usr/bin/uuidparse
    /usr/sbin/uuidd
)

package_inventory() {
    dpkg-query -W \
        -f='${binary:Package}\t${db:Status-Abbrev}\t${Version}\n' |
        sort
}

version_matches() {
    local mode=$1
    local expected=$2
    local output=$3

    case "$mode" in
        exact)
            [[ "$output" == "$expected" ]]
            ;;
        prefix)
            [[ "$output" == "$expected"* ]]
            ;;
        contains)
            [[ "$output" == *"$expected"* ]]
            ;;
        *)
            return 2
            ;;
    esac
}

record_failure() {
    local label=$1
    local field=$2

    if [[ "$first_failure" == none ]]; then
        first_failure="${label}:${field}"
    fi
}

run_version_probe() {
    local label=$1
    local mode=$2
    local expected=$3
    shift 3
    local output
    local query_rc
    local match=false
    local command_text

    set +e
    output=$("$@" 2>&1)
    query_rc=$?
    set -e

    if [[ "$query_rc" -eq 0 ]] &&
        version_matches "$mode" "$expected" "$output"; then
        match=true
    else
        version_mismatch_count=$((version_mismatch_count + 1))
        if [[ "$query_rc" -ne 0 ]]; then
            query_failure_count=$((query_failure_count + 1))
            record_failure "$label" query
        else
            record_failure "$label" match
        fi
    fi

    printf -v command_text '%q ' "$@"
    command_text=${command_text% }
    printf '%s\n' "--- command version diagnostic: $label ---"
    printf 'command=%s\n' "$command_text"
    printf 'match_mode=%s\n' "$mode"
    printf 'expected=%q\n' "$expected"
    printf 'query_rc=%s\n' "$query_rc"
    printf 'version_match=%s\n' "$match"
    printf '%s\n' 'output_begin'
    printf '%s\n' "$output"
    printf '%s\n' 'output_end'
    version_probe_count=$((version_probe_count + 1))
}

inspect_command_path() {
    local path=$1
    local exists=false
    local executable=false
    local symlink=false
    local match=false
    local state
    local state_rc

    if [[ -e "$path" || -L "$path" ]]; then
        exists=true
    fi
    if [[ -x "$path" ]]; then
        executable=true
    fi
    if [[ -L "$path" ]]; then
        symlink=true
    fi
    if [[ "$executable" == true && "$symlink" == false ]]; then
        match=true
    else
        path_mismatch_count=$((path_mismatch_count + 1))
        record_failure "$path" path
    fi

    set +e
    state=$(stat -c '%F %U:%G %a %s' -- "$path" 2>&1)
    state_rc=$?
    set -e

    printf '%s\n' "--- command path diagnostic: $path ---"
    printf 'exists=%s\n' "$exists"
    printf 'executable=%s\n' "$executable"
    printf 'symlink=%s\n' "$symlink"
    printf 'path_match=%s\n' "$match"
    printf 'stat_rc=%s\n' "$state_rc"
    printf 'stat_output=%q\n' "$state"
    path_probe_count=$((path_probe_count + 1))
}

self_test() {
    version_matches exact 'jq-1.6' 'jq-1.6'
    version_matches prefix 'OpenSSL 3.0.20 ' \
        'OpenSSL 3.0.20 12 Feb 2026'
    version_matches contains 'iproute2-6.1.0' \
        'ip utility, iproute2-6.1.0, libbpf 1.1.2'

    if version_matches exact 'jq-1.6' 'jq-1.7'; then
        printf 'Exact version matcher accepted a mismatch.\n' >&2
        return 1
    fi
    if version_matches prefix 'OpenSSL 3.0.20 ' 'OpenSSL 3.0.21 '; then
        printf 'Prefix version matcher accepted a mismatch.\n' >&2
        return 1
    fi
    if version_matches contains 'tcpdump version 4.99.3' \
        'tcpdump version 4.99.4'; then
        printf 'Contains version matcher accepted a mismatch.\n' >&2
        return 1
    fi
    if version_matches unknown expected output; then
        printf 'Unknown version match mode was accepted.\n' >&2
        return 1
    fi

    [[ "${#command_paths[@]}" -eq 13 ]]
    printf 'action_16x_c_self_test_complete=true\n'
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
[[ "${#command_paths[@]}" -eq 13 ]]

inventory_before=$(package_inventory)
audit_before=$(dpkg --audit)

version_probe_count=0
version_mismatch_count=0
query_failure_count=0
path_probe_count=0
path_mismatch_count=0
first_failure=none

run_version_probe \
    bash contains 'GNU bash, version 5.2.15' \
    /usr/bin/bash --version
run_version_probe \
    sha256sum contains 'sha256sum (GNU coreutils) 9.1' \
    /usr/bin/sha256sum --version
run_version_probe \
    find contains 'find (GNU findutils) 4.9.0' \
    /usr/bin/find --version
run_version_probe \
    ip contains 'iproute2-6.1.0' \
    /usr/sbin/ip -Version
run_version_probe \
    arping contains 'arping from iputils 20221126' \
    /usr/bin/arping -V
run_version_probe \
    jq exact 'jq-1.6' \
    /usr/bin/jq --version
run_version_probe \
    openssl prefix 'OpenSSL 3.0.20 ' \
    /usr/bin/openssl version
run_version_probe \
    ps contains 'ps from procps-ng 4.0.2' \
    /usr/bin/ps --version
run_version_probe \
    tcpdump contains 'tcpdump version 4.99.3' \
    /usr/bin/tcpdump --version
run_version_probe \
    uuidgen exact 'uuidgen from util-linux 2.38.1' \
    /usr/bin/uuidgen --version

for command_path in "${command_paths[@]}"; do
    inspect_command_path "$command_path"
done

inventory_after=$(package_inventory)
audit_after=$(dpkg --audit)
[[ "$inventory_after" == "$inventory_before" ]]
[[ "$audit_after" == "$audit_before" ]]

printf '%s\n' '--- command/version diagnostic summary ---'
printf 'version_probe_count=%s\n' "$version_probe_count"
printf 'version_mismatch_count=%s\n' "$version_mismatch_count"
printf 'query_failure_count=%s\n' "$query_failure_count"
printf 'path_probe_count=%s\n' "$path_probe_count"
printf 'path_mismatch_count=%s\n' "$path_mismatch_count"
printf 'first_failure=%s\n' "$first_failure"
printf 'dpkg_audit_before_bytes=%s\n' "${#audit_before}"
printf 'dpkg_audit_after_bytes=%s\n' "${#audit_after}"
printf 'command_version_diagnostic_16x_c_complete=true\n'
