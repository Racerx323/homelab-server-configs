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

expected_versions=(
    '5.2.15-2+b13'
    '9.1-1'
    '4.9.0-4'
    '6.1.0-3'
    '3:20221126-1+deb12u1'
    '1.6-2.1+deb12u2'
    '1.0.5-1+b2'
    '3.0.20-1~deb12u2+rpt1'
    '2:4.0.2-3'
    '4.99.3-1'
    '2.38.1-5+deb12u3'
    '2.38.1-5+deb12u3'
)

package_inventory() {
    dpkg-query -W \
        -f='${binary:Package}\t${db:Status-Abbrev}\t${Version}\n' |
        sort
}

classify_verification_output() {
    local verify_output=$1
    local line

    verification_conffile_lines=()
    verification_payload_lines=()
    while IFS= read -r line; do
        [[ -n "$line" ]] || continue
        if [[ "$line" =~ ^.{9}[[:space:]]c[[:space:]] ]]; then
            verification_conffile_lines+=("$line")
        else
            verification_payload_lines+=("$line")
        fi
    done <<<"$verify_output"
}

print_conffile_evidence() {
    local package=$1
    local record
    local path
    local state
    local state_rc
    local digest
    local digest_rc

    for record in "${verification_conffile_lines[@]}"; do
        path=${record#* c }
        set +e
        state=$(stat -c '%F %U:%G %a %s' -- "$path" 2>&1)
        state_rc=$?
        digest=$(sha256sum -- "$path" 2>&1)
        digest_rc=$?
        set -e

        printf '%s\n' "--- conffile evidence: $package ---"
        printf 'verification_record=%q\n' "$record"
        printf 'conffile_path=%q\n' "$path"
        printf 'conffile_stat_rc=%s\n' "$state_rc"
        printf 'conffile_stat=%q\n' "$state"
        printf 'conffile_sha256_rc=%s\n' "$digest_rc"
        printf 'conffile_sha256_output=%q\n' "$digest"
        conffile_evidence_count=$((conffile_evidence_count + 1))
    done
}

self_test() {
    local candidate
    local found
    local package

    [[ "${#packages[@]}" -eq 12 ]]
    [[ "${#expected_versions[@]}" -eq "${#packages[@]}" ]]
    for package in iputils-arping util-linux uuid-runtime; do
        found=false
        for candidate in "${packages[@]}"; do
            if [[ "$candidate" == "$package" ]]; then
                found=true
            fi
        done
        [[ "$found" == true ]]
    done

    classify_verification_output $'??5?????? c /etc/example.conf\n??5??????   /usr/bin/example'
    [[ "${#verification_conffile_lines[@]}" -eq 1 ]]
    [[ "${verification_conffile_lines[0]}" == '??5?????? c /etc/example.conf' ]]
    [[ "${#verification_payload_lines[@]}" -eq 1 ]]
    [[ "${verification_payload_lines[0]}" == '??5??????   /usr/bin/example' ]]

    classify_verification_output ''
    [[ "${#verification_conffile_lines[@]}" -eq 0 ]]
    [[ "${#verification_payload_lines[@]}" -eq 0 ]]

    printf 'action_16x_b_self_test_complete=true\n'
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
[[ "${#packages[@]}" -eq 12 ]]
[[ "${#expected_versions[@]}" -eq "${#packages[@]}" ]]

inventory_before=$(package_inventory)
audit_before=$(dpkg --audit)

metadata_mismatch_count=0
query_failure_count=0
package_difference_count=0
conffile_record_count=0
payload_record_count=0
conffile_evidence_count=0
first_difference=none

for index in "${!packages[@]}"; do
    package=${packages[$index]}
    expected_version=${expected_versions[$index]}

    set +e
    status=$(dpkg-query -W -f='${db:Status-Abbrev}' "$package" 2>&1)
    status_rc=$?
    version=$(dpkg-query -W -f='${Version}' "$package" 2>&1)
    version_rc=$?
    architecture=$(dpkg-query -W -f='${Architecture}' "$package" 2>&1)
    architecture_rc=$?
    verify_output=$(dpkg --verify "$package" 2>&1)
    verify_rc=$?
    set -e

    status_match=false
    version_match=false
    architecture_match=false
    if [[ "$status_rc" -eq 0 && "$status" == 'ii ' ]]; then
        status_match=true
    else
        metadata_mismatch_count=$((metadata_mismatch_count + 1))
    fi
    if [[ "$version_rc" -eq 0 && "$version" == "$expected_version" ]]; then
        version_match=true
    else
        metadata_mismatch_count=$((metadata_mismatch_count + 1))
    fi
    if [[ "$architecture_rc" -eq 0 && "$architecture" == arm64 ]]; then
        architecture_match=true
    else
        metadata_mismatch_count=$((metadata_mismatch_count + 1))
    fi
    if [[ "$status_rc" -ne 0 || "$version_rc" -ne 0 ||
        "$architecture_rc" -ne 0 || "$verify_rc" -ne 0 ]]; then
        query_failure_count=$((query_failure_count + 1))
    fi

    classify_verification_output "$verify_output"
    package_conffile_count=${#verification_conffile_lines[@]}
    package_payload_count=${#verification_payload_lines[@]}
    conffile_record_count=$((conffile_record_count + package_conffile_count))
    payload_record_count=$((payload_record_count + package_payload_count))
    if ((package_conffile_count || package_payload_count)); then
        package_difference_count=$((package_difference_count + 1))
        if [[ "$first_difference" == none ]]; then
            first_difference=$package
        fi
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
    printf 'conffile_record_count=%s\n' "$package_conffile_count"
    printf 'payload_record_count=%s\n' "$package_payload_count"
    printf '%s\n' 'conffile_verification_output_begin'
    printf '%s\n' "${verification_conffile_lines[@]}"
    printf '%s\n' 'conffile_verification_output_end'
    printf '%s\n' 'payload_verification_output_begin'
    printf '%s\n' "${verification_payload_lines[@]}"
    printf '%s\n' 'payload_verification_output_end'
    print_conffile_evidence "$package"
done

inventory_after=$(package_inventory)
audit_after=$(dpkg --audit)
[[ "$inventory_after" == "$inventory_before" ]]
[[ "$audit_after" == "$audit_before" ]]

printf '%s\n' '--- diagnostic summary ---'
printf 'diagnostic_package_count=%s\n' "${#packages[@]}"
printf 'metadata_mismatch_count=%s\n' "$metadata_mismatch_count"
printf 'query_failure_count=%s\n' "$query_failure_count"
printf 'package_difference_count=%s\n' "$package_difference_count"
printf 'conffile_record_count=%s\n' "$conffile_record_count"
printf 'payload_record_count=%s\n' "$payload_record_count"
printf 'conffile_evidence_count=%s\n' "$conffile_evidence_count"
printf 'first_difference=%s\n' "$first_difference"
printf 'dpkg_audit_before_bytes=%s\n' "${#audit_before}"
printf 'dpkg_audit_after_bytes=%s\n' "${#audit_after}"
printf 'validation_dependency_diagnostic_16x_b_complete=true\n'
