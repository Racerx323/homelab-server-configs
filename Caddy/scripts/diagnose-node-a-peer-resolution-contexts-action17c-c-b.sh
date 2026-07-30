#!/usr/bin/env bash

set -euo pipefail
set +x
umask 077
PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH
readonly PATH

readonly peer_fqdn=pihole00.local.theama.co
readonly peer_ipv4=10.1.0.54
readonly peer_ipv6=fd36:5aa8:6971:1::54
readonly environment_file=/etc/default/caddy-ha
readonly resolv_conf=/etc/resolv.conf
readonly nsswitch_conf=/etc/nsswitch.conf
readonly hosts_file=/etc/hosts
readonly -a context_labels=(administrative root caddy_sync)
readonly -a context_users=(pi root caddy-sync)
readonly -a databases=(ahostsv4 ahostsv6)

file_hash() {
    sha256sum "$1" | awk '{ print $1 }'
}

encode_value() {
    printf '%s' "$1" | base64 -w 0
}

resolver_state() {
    local resolv_target

    resolv_target=$(readlink -f -- "$resolv_conf")
    stat -c '%n|%F|%U:%G:%a:%s:%i' \
        "$nsswitch_conf" "$hosts_file" "$resolv_target"
    stat -c '%n|%F|%U:%G:%a:%s:%i' "$resolv_conf"
    sha256sum "$nsswitch_conf" "$hosts_file" "$resolv_target"
    grep -E '^[[:space:]]*hosts[[:space:]]*:' "$nsswitch_conf" || true
    grep -E '^[[:space:]]*(nameserver|options)[[:space:]]+' \
        "$resolv_target" || true
}

classify_lookup() {
    local status=$1
    local database=$2
    local output_file=$3
    local error_file=$4
    local expected_address

    if [[ "$database" == ahostsv4 ]]; then
        expected_address=$peer_ipv4
    else
        expected_address=$peer_ipv6
    fi

    if [[ "$status" -eq 124 ]]; then
        printf 'timed_out\n'
    elif grep -Eqi 'permission denied|operation not permitted' "$error_file"; then
        printf 'permission_denied\n'
    elif [[ "$status" -eq 0 ]] &&
        awk -v expected="$expected_address" '$1 == expected { found = 1 } END { exit !found }' \
            "$output_file"; then
        printf 'resolved_expected\n'
    elif [[ "$status" -eq 0 ]]; then
        printf 'resolved_unexpected\n'
    elif [[ "$status" -eq 2 ]]; then
        printf 'not_found\n'
    else
        printf 'command_failed\n'
    fi
}

expected_address_present() {
    local database=$1
    local output_file=$2
    local expected_address

    if [[ "$database" == ahostsv4 ]]; then
        expected_address=$peer_ipv4
    else
        expected_address=$peer_ipv6
    fi

    if awk -v expected="$expected_address" \
        '$1 == expected { found = 1 } END { exit !found }' "$output_file"; then
        printf 'true\n'
    else
        printf 'false\n'
    fi
}

run_lookup() {
    local label=$1
    local user=$2
    local database=$3
    local output_file="$work_dir/${label}-${database}.out"
    local error_file="$work_dir/${label}-${database}.err"
    local status=0
    local address_set

    runuser -u "$user" -- \
        /usr/bin/timeout --signal=TERM 5 \
        /usr/bin/getent "$database" "$peer_fqdn" \
        >"$output_file" 2>"$error_file" || status=$?
    address_set=$(
        awk 'NR <= 32 && !seen[$1]++ {
            if (addresses != "") {
                addresses = addresses ","
            }
            addresses = addresses $1
        }
        END { print addresses }' "$output_file"
    )

    printf '%s_%s_status=%s\n' "$label" "$database" "$status"
    printf '%s_%s_class=%s\n' \
        "$label" "$database" \
        "$(classify_lookup "$status" "$database" "$output_file" "$error_file")"
    printf '%s_%s_expected_address_present=%s\n' \
        "$label" "$database" \
        "$(expected_address_present "$database" "$output_file")"
    printf '%s_%s_output_line_count=%s\n' \
        "$label" "$database" "$(wc -l <"$output_file")"
    if [[ "$(wc -l <"$output_file")" -gt 32 ]]; then
        printf '%s_%s_output_truncated=true\n' "$label" "$database"
    else
        printf '%s_%s_output_truncated=false\n' "$label" "$database"
    fi
    printf '%s_%s_address_set_b64=%s\n' \
        "$label" "$database" "$(encode_value "$address_set")"
    printf '%s_%s_stdout_sha256=%s\n' \
        "$label" "$database" "$(file_hash "$output_file")"
    printf '%s_%s_stderr_sha256=%s\n' \
        "$label" "$database" "$(file_hash "$error_file")"
}

if [[ "${1:-}" == --self-test && $# -eq 1 ]]; then
    [[ "$peer_fqdn" == pihole00.local.theama.co ]]
    [[ "$peer_ipv4" == 10.1.0.54 ]]
    [[ "$peer_ipv6" == fd36:5aa8:6971:1::54 ]]
    [[ "${context_labels[*]}" == 'administrative root caddy_sync' ]]
    [[ "${context_users[*]}" == 'pi root caddy-sync' ]]
    [[ "${databases[*]}" == 'ahostsv4 ahostsv6' ]]
    printf 'action_17c_c_b_node_a_diagnostic_self_test_complete=true\n'
    exit 0
elif (($#)); then
    printf 'Usage: %s [--self-test]\n' "${0##*/}" >&2
    exit 2
fi

[[ "$(id -u)" -eq 0 ]]
[[ "$(id -un)" == root ]]
[[ "$(pwd -P)" == / ]]
[[ "$(hostname)" == j1-svpihole0 ]]
[[ "$(dpkg --print-architecture)" == arm64 ]]
for command in awk base64 getent grep readlink runuser sha256sum sort stat timeout wc; do
    command -v "$command" >/dev/null
done
for user in "${context_users[@]}"; do
    getent passwd "$user" >/dev/null
done
grep -Fxq 'NODE_ROLE=node-a' "$environment_file"
grep -Fxq "PEER_IPV4=$peer_ipv4" "$environment_file"
grep -Fxq "PEER_IPV6=$peer_ipv6" "$environment_file"
grep -Fxq "SYNC_TARGET=$peer_fqdn" "$environment_file"
[[ -r "$resolv_conf" && -r "$nsswitch_conf" && -r "$hosts_file" ]]

work_dir=$(mktemp -d /tmp/caddy-action17c-c-b.XXXXXX)
readonly work_dir
cleanup() {
    rm -rf -- "$work_dir"
}
trap cleanup EXIT

before_state_status=0
resolver_state >"$work_dir/state-before" 2>"$work_dir/state-before.err" ||
    before_state_status=$?
printf 'prestate_root_identity=true\n'
printf 'prestate_working_directory=true\n'
printf 'prestate_hostname=true\n'
printf 'prestate_architecture=true\n'
printf 'prestate_context_users_present=true\n'
printf 'prestate_environment_values=true\n'
printf 'prestate_resolver_files_readable=true\n'
printf 'before_state_status=%s\n' "$before_state_status"
printf 'before_state_sha256=%s\n' "$(file_hash "$work_dir/state-before")"
printf 'before_state_stderr_sha256=%s\n' \
    "$(file_hash "$work_dir/state-before.err")"
printf 'action_17c_c_b_prestate_collection_complete=true\n'

resolv_target=$(readlink -f -- "$resolv_conf")
readonly resolv_target
if [[ -L "$resolv_conf" ]]; then
    printf 'resolv_conf_is_symlink=true\n'
    printf 'resolv_conf_link_target_b64=%s\n' \
        "$(encode_value "$(readlink -- "$resolv_conf")")"
else
    printf 'resolv_conf_is_symlink=false\n'
    printf 'resolv_conf_link_target_b64=%s\n' "$(encode_value none)"
fi
printf 'resolv_conf_canonical_target_b64=%s\n' \
    "$(encode_value "$resolv_target")"
printf 'resolv_conf_sha256=%s\n' "$(file_hash "$resolv_target")"
printf 'nsswitch_conf_sha256=%s\n' "$(file_hash "$nsswitch_conf")"
printf 'hosts_file_sha256=%s\n' "$(file_hash "$hosts_file")"
nsswitch_hosts_line=$(
    grep -E '^[[:space:]]*hosts[[:space:]]*:' "$nsswitch_conf" |
        head -n 1 || true
)
printf 'nsswitch_hosts_line_b64=%s\n' \
    "$(encode_value "$nsswitch_hosts_line")"
mapfile -t nameservers < <(
    awk '$1 == "nameserver" { print $2 }' "$resolv_target"
)
printf 'resolver_nameserver_count=%s\n' "${#nameservers[@]}"
for nameserver in "${nameservers[@]}"; do
    printf 'resolver_nameserver=%s\n' "$nameserver"
done
if awk -v name="$peer_fqdn" -v ipv4="$peer_ipv4" \
    '$1 == ipv4 { for (field = 2; field <= NF; field++) if ($field == name) found = 1 } END { exit !found }' \
    "$hosts_file"; then
    printf 'hosts_file_peer_ipv4_present=true\n'
else
    printf 'hosts_file_peer_ipv4_present=false\n'
fi
if awk -v name="$peer_fqdn" -v ipv6="$peer_ipv6" \
    '$1 == ipv6 { for (field = 2; field <= NF; field++) if ($field == name) found = 1 } END { exit !found }' \
    "$hosts_file"; then
    printf 'hosts_file_peer_ipv6_present=true\n'
else
    printf 'hosts_file_peer_ipv6_present=false\n'
fi
printf 'action_17c_c_b_resolver_provenance_complete=true\n'

for index in "${!context_labels[@]}"; do
    context_identity=$(
        runuser -u "${context_users[$index]}" -- /usr/bin/id -un 2>/dev/null ||
            printf unavailable
    )
    printf '%s_identity=%s\n' \
        "${context_labels[$index]}" "$context_identity"
    for database in "${databases[@]}"; do
        run_lookup \
            "${context_labels[$index]}" \
            "${context_users[$index]}" \
            "$database"
    done
done
printf 'action_17c_c_b_context_collection_complete=true\n'

after_state_status=0
resolver_state >"$work_dir/state-after" 2>"$work_dir/state-after.err" ||
    after_state_status=$?
printf 'after_state_status=%s\n' "$after_state_status"
printf 'after_state_sha256=%s\n' "$(file_hash "$work_dir/state-after")"
printf 'after_state_stderr_sha256=%s\n' \
    "$(file_hash "$work_dir/state-after.err")"
if [[ "$before_state_status" -eq 0 &&
    "$after_state_status" -eq 0 ]] &&
    cmp --silent "$work_dir/state-before" "$work_dir/state-after"; then
    printf 'node_a_resolver_state_unchanged=true\n'
else
    printf 'node_a_resolver_state_unchanged=false\n'
fi
printf 'peer_ssh_invoked=false\n'
printf 'rsync_invoked=false\n'
printf 'release_payload_transferred=false\n'
printf 'service_mutations=false\n'
printf 'persistent_mutations=false\n'

cleanup
trap - EXIT
[[ ! -e "$work_dir" && ! -L "$work_dir" ]]
printf 'action_17c_c_b_node_a_cleanup_complete=true\n'
printf 'action_17c_c_b_node_a_diagnostic_complete=true\n'
