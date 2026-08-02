#!/usr/bin/env bash

set -Euo pipefail
set +x
umask 077
PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH
readonly PATH

readonly prefix=action_17r_b_node_a
readonly node_ipv4=10.1.0.53
readonly node_ipv6=fd36:5aa8:6971:1::53
readonly peer_fqdn=pihole00.local.theama.co
readonly release=/var/lib/caddy-sync/outbound/action17p-node-a-to-node-b-bootstrap
readonly ssh_directory=/var/lib/caddy-sync/.ssh
readonly private_key="$ssh_directory/id_ed25519"
readonly known_hosts="$ssh_directory/known_hosts"
readonly max_stderr_bytes=1024
readonly max_stderr_lines=4
readonly pseudo_terminal_notice='Pseudo-terminal will not be allocated because stdin is not a terminal.'

assertion_count=0
failed_assertion_count=0
first_failure=none

record_assertion() {
    local assertion_label=$1
    local assertion_value=$2

    assertion_count=$((assertion_count + 1))
    printf '%s_assertion_%s=%s\n' "$prefix" "$assertion_label" "$assertion_value"
    if [[ "$assertion_value" != true ]]; then
        failed_assertion_count=$((failed_assertion_count + 1))
        if [[ "$first_failure" == none ]]; then
            first_failure=$assertion_label
        fi
    fi
}

record_command() {
    local command_label=$1

    shift
    if "$@" >/dev/null 2>&1; then
        record_assertion "$command_label" true
    else
        record_assertion "$command_label" false
    fi
}

file_hash() {
    sha256sum "$1" | awk '{ print $1 }'
}

line_count() {
    awk 'END { print NR + 0 }' "$1"
}

stderr_has_no_nul() {
    od -An -v -t u1 "$1" |
        awk '{ for (field = 1; field <= NF; field++) if ($field == 0) exit 1 }'
}

stderr_is_printable() {
    ! LC_ALL=C grep -q '[^[:print:][:space:]]' "$1"
}

stderr_is_secret_free() {
    ! grep -Eqi \
        'BEGIN [A-Z ]*PRIVATE KEY|CADDY_TLS_PRIVATE_KEY_PEM|PRIVATE_KEY=|DOPPLER_TOKEN|Authorization:[[:space:]]|Bearer[[:space:]]' \
        "$1"
}

stderr_is_bounded() {
    [[ "$(stat -c '%s' "$1")" -le "$max_stderr_bytes" ]]
}

stderr_lines_are_bounded() {
    [[ "$(line_count "$1")" -le "$max_stderr_lines" ]]
}

stderr_is_safe() {
    stderr_is_bounded "$1" &&
        stderr_lines_are_bounded "$1" &&
        stderr_has_no_nul "$1" &&
        stderr_is_printable "$1" &&
        stderr_is_secret_free "$1"
}

classify_stderr() {
    local classification_file=$1
    local normalized_content

    if [[ ! -s "$classification_file" ]]; then
        printf 'empty\n'
        return
    fi
    if ! stderr_is_safe "$classification_file"; then
        printf 'unsafe_withheld\n'
        return
    fi
    normalized_content=$(tr -d '\r' <"$classification_file")
    if [[ "$(line_count "$classification_file")" -eq 1 ]] &&
        [[ "$normalized_content" == "$pseudo_terminal_notice" ]]; then
        printf 'pseudo_terminal_not_allocated\n'
    else
        printf 'safe_unclassified\n'
    fi
}

ssh_option_exact() {
    local option_name=$1
    local option_value=$2
    local option_file=$3

    awk -v name="$option_name" -v value="$option_value" \
        '$1 == name && $2 == value { found = 1 } END { exit found ? 0 : 1 }' \
        "$option_file"
}

stable_state_snapshot() {
    stat -c '%n|%U:%G:%a:%s:%i' \
        /var/lib/caddy-sync \
        /var/lib/caddy-sync/outbound \
        "$release" \
        "$release/manifest.sha256" \
        "$release/.complete" \
        "$ssh_directory" \
        "$private_key" \
        "$known_hosts" \
        /etc/caddy/current
    sha256sum \
        "$release/manifest.sha256" \
        "$private_key" \
        "$known_hosts"
    find "$release" -printf '%P|%y|%U:%G:%m:%s:%i\n' | LC_ALL=C sort
    find "$release" -type f -print0 |
        LC_ALL=C sort -z |
        xargs -0 -r sha256sum
    readlink /etc/caddy/current
    readlink -e /etc/caddy/current
    for snapshot_unit in \
        caddy.service lighttpd.service lsyncd.service caddy-lsyncd.service; do
        systemctl show "$snapshot_unit" --no-pager \
            -p LoadState -p ActiveState -p SubState -p MainPID -p NRestarts
        printf 'unit_file_state=%s\n' \
            "$(systemctl is-enabled "$snapshot_unit" 2>/dev/null || true)"
    done
}

if [[ "${1:-}" == --self-test && $# -eq 1 ]]; then
    [[ "$node_ipv4" == 10.1.0.53 ]]
    [[ "$node_ipv6" == fd36:5aa8:6971:1::53 ]]
    [[ "$peer_fqdn" == pihole00.local.theama.co ]]
    [[ "$max_stderr_bytes" -eq 1024 ]]
    [[ "$max_stderr_lines" -eq 4 ]]
    printf 'action_17r_b_node_a_inspector_self_test_complete=true\n'
    exit 0
fi
if [[ "${1:-}" == --contract-test && $# -eq 1 ]]; then
    contract_directory=$(mktemp -d /tmp/caddy-action17r-b-contract.XXXXXX)
    trap 'rm -rf -- "$contract_directory"' EXIT
    : >"$contract_directory/empty"
    printf '%s\n' "$pseudo_terminal_notice" >"$contract_directory/notice"
    printf 'safe diagnostic text\n' >"$contract_directory/safe-other"
    printf '%s\n' 'Authorization: Bearer forbidden' >"$contract_directory/unsafe"
    [[ "$(classify_stderr "$contract_directory/empty")" == empty ]]
    [[ "$(classify_stderr "$contract_directory/notice")" == pseudo_terminal_not_allocated ]]
    [[ "$(classify_stderr "$contract_directory/safe-other")" == safe_unclassified ]]
    [[ "$(classify_stderr "$contract_directory/unsafe")" == unsafe_withheld ]]
    printf 'action_17r_b_node_a_inspector_contract_test_complete=true\n'
    exit 0
fi
if (($#)); then
    printf 'Usage: %s [--self-test|--contract-test]\n' "${0##*/}" >&2
    exit 2
fi

work_directory=$(mktemp -d /tmp/caddy-action17r-b-node-a.XXXXXX)
readonly work_directory
cleanup() {
    # shellcheck disable=SC2317
    rm -rf -- "$work_directory"
}
trap cleanup EXIT

readonly before_state="$work_directory/state.before"
readonly before_error="$work_directory/state.before.err"
readonly after_state="$work_directory/state.after"
readonly after_error="$work_directory/state.after.err"
readonly ipv4_options="$work_directory/ssh-ipv4.options"
readonly ipv4_error="$work_directory/ssh-ipv4.err"
readonly ipv6_options="$work_directory/ssh-ipv6.options"
readonly ipv6_error="$work_directory/ssh-ipv6.err"

record_command identity_root test "$(id -u)" -eq 0
record_command working_directory_root test "$(pwd -P)" = /
record_command hostname_node_a test "$(hostname)" = j1-svpihole0
record_command architecture_arm64 test "$(dpkg --print-architecture)" = arm64
record_command node_ipv4_present \
    grep -Fq "$node_ipv4/22" < <(ip -o -4 address show dev eth0)
record_command node_ipv6_present \
    grep -Fq "$node_ipv6/64" < <(ip -o -6 address show dev eth0)
record_command private_key_regular test -f "$private_key"
record_command private_key_not_symlink test ! -L "$private_key"
record_command private_key_metadata \
    test "$(stat -c '%U:%G:%a' "$private_key" 2>/dev/null || true)" = \
    caddy-sync:caddy-sync:600
record_command known_hosts_regular test -f "$known_hosts"
record_command known_hosts_not_symlink test ! -L "$known_hosts"
record_command known_hosts_metadata \
    test "$(stat -c '%U:%G:%a' "$known_hosts" 2>/dev/null || true)" = \
    caddy-sync:caddy-sync:600

before_status=0
stable_state_snapshot >"$before_state" 2>"$before_error" || before_status=$?
readonly before_status
record_command before_state_status_zero test "$before_status" -eq 0
record_command before_state_stderr_empty test ! -s "$before_error"
before_state_sha256=$(file_hash "$before_state")
readonly before_state_sha256

ipv4_status=0
runuser -u caddy-sync -- ssh -G -F /dev/null -4 \
    -b "$node_ipv4" -i "$private_key" \
    -o BatchMode=yes -o ClearAllForwardings=yes \
    -o "HostKeyAlias=$peer_fqdn" -o IdentitiesOnly=yes \
    -o StrictHostKeyChecking=yes -o "UserKnownHostsFile=$known_hosts" \
    "caddy-sync@$peer_fqdn" >"$ipv4_options" 2>"$ipv4_error" || ipv4_status=$?
readonly ipv4_status
ipv4_classification=$(classify_stderr "$ipv4_error")
readonly ipv4_classification
record_command ipv4_ssh_g_status_zero test "$ipv4_status" -eq 0
record_command ipv4_stderr_bytes_bounded stderr_is_bounded "$ipv4_error"
record_command ipv4_stderr_lines_bounded stderr_lines_are_bounded "$ipv4_error"
record_command ipv4_stderr_nul_absent stderr_has_no_nul "$ipv4_error"
record_command ipv4_stderr_printable stderr_is_printable "$ipv4_error"
record_command ipv4_stderr_secret_free stderr_is_secret_free "$ipv4_error"
record_command ipv4_stderr_classification_supported \
    grep -Eq '^(empty|pseudo_terminal_not_allocated|safe_unclassified|unsafe_withheld)$' \
    <<<"$ipv4_classification"
record_command ipv4_address_family_exact \
    ssh_option_exact addressfamily inet "$ipv4_options"
record_command ipv4_bind_address_exact \
    ssh_option_exact bindaddress "$node_ipv4" "$ipv4_options"
record_command ipv4_hostname_exact \
    ssh_option_exact hostname "$peer_fqdn" "$ipv4_options"
record_command ipv4_host_key_alias_exact \
    ssh_option_exact hostkeyalias "$peer_fqdn" "$ipv4_options"

ipv6_status=0
runuser -u caddy-sync -- ssh -G -F /dev/null -6 \
    -b "$node_ipv6" -i "$private_key" \
    -o BatchMode=yes -o ClearAllForwardings=yes \
    -o "HostKeyAlias=$peer_fqdn" -o IdentitiesOnly=yes \
    -o StrictHostKeyChecking=yes -o "UserKnownHostsFile=$known_hosts" \
    "caddy-sync@$peer_fqdn" >"$ipv6_options" 2>"$ipv6_error" || ipv6_status=$?
readonly ipv6_status
ipv6_classification=$(classify_stderr "$ipv6_error")
readonly ipv6_classification
record_command ipv6_ssh_g_status_zero test "$ipv6_status" -eq 0
record_command ipv6_stderr_bytes_bounded stderr_is_bounded "$ipv6_error"
record_command ipv6_stderr_lines_bounded stderr_lines_are_bounded "$ipv6_error"
record_command ipv6_stderr_nul_absent stderr_has_no_nul "$ipv6_error"
record_command ipv6_stderr_printable stderr_is_printable "$ipv6_error"
record_command ipv6_stderr_secret_free stderr_is_secret_free "$ipv6_error"
record_command ipv6_stderr_classification_supported \
    grep -Eq '^(empty|pseudo_terminal_not_allocated|safe_unclassified|unsafe_withheld)$' \
    <<<"$ipv6_classification"
record_command ipv6_address_family_exact \
    ssh_option_exact addressfamily inet6 "$ipv6_options"
record_command ipv6_bind_address_exact \
    ssh_option_exact bindaddress "$node_ipv6" "$ipv6_options"
record_command ipv6_hostname_exact \
    ssh_option_exact hostname "$peer_fqdn" "$ipv6_options"
record_command ipv6_host_key_alias_exact \
    ssh_option_exact hostkeyalias "$peer_fqdn" "$ipv6_options"

after_status=0
stable_state_snapshot >"$after_state" 2>"$after_error" || after_status=$?
readonly after_status
record_command after_state_status_zero test "$after_status" -eq 0
record_command after_state_stderr_empty test ! -s "$after_error"
after_state_sha256=$(file_hash "$after_state")
readonly after_state_sha256
record_command state_unchanged test "$after_state_sha256" = "$before_state_sha256"

ipv4_stderr_base64=withheld
if stderr_is_safe "$ipv4_error"; then
    ipv4_stderr_base64=$(base64 -w 0 "$ipv4_error")
    ipv4_stderr_base64=${ipv4_stderr_base64:-empty}
fi
readonly ipv4_stderr_base64
ipv6_stderr_base64=withheld
if stderr_is_safe "$ipv6_error"; then
    ipv6_stderr_base64=$(base64 -w 0 "$ipv6_error")
    ipv6_stderr_base64=${ipv6_stderr_base64:-empty}
fi
readonly ipv6_stderr_base64

printf '%s\n' \
    "${prefix}_value_before_state_sha256=$before_state_sha256" \
    "${prefix}_value_after_state_sha256=$after_state_sha256" \
    "${prefix}_value_ipv4_ssh_g_status=$ipv4_status" \
    "${prefix}_value_ipv4_stderr_bytes=$(stat -c '%s' "$ipv4_error")" \
    "${prefix}_value_ipv4_stderr_lines=$(line_count "$ipv4_error")" \
    "${prefix}_value_ipv4_stderr_sha256=$(file_hash "$ipv4_error")" \
    "${prefix}_value_ipv4_stderr_classification=$ipv4_classification" \
    "${prefix}_value_ipv4_stderr_base64=$ipv4_stderr_base64" \
    "${prefix}_value_ipv6_ssh_g_status=$ipv6_status" \
    "${prefix}_value_ipv6_stderr_bytes=$(stat -c '%s' "$ipv6_error")" \
    "${prefix}_value_ipv6_stderr_lines=$(line_count "$ipv6_error")" \
    "${prefix}_value_ipv6_stderr_sha256=$(file_hash "$ipv6_error")" \
    "${prefix}_value_ipv6_stderr_classification=$ipv6_classification" \
    "${prefix}_value_ipv6_stderr_base64=$ipv6_stderr_base64" \
    "${prefix}_assertion_count=$assertion_count" \
    "${prefix}_failed_assertion_count=$failed_assertion_count" \
    "${prefix}_first_failure=$first_failure" \
    "${prefix}_peer_connection_executed=false" \
    "${prefix}_restricted_command_executed=false" \
    "${prefix}_release_transfer_executed=false" \
    "${prefix}_marker_mutation=false" \
    "${prefix}_helper_invocation=false" \
    "${prefix}_service_mutations=false" \
    "${prefix}_persistent_mutations=false" \
    "${prefix}_remote_complete=true"

if [[ "$failed_assertion_count" -ne 0 ]]; then
    exit 1
fi
