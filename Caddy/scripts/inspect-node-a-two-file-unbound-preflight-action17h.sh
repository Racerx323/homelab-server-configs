#!/usr/bin/env bash

set -u -o pipefail
set +x
umask 077
PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH
readonly PATH

readonly expected_hostname=j1-svpihole0
readonly live_root=/etc/unbound/unbound.conf
readonly live_conf_dir=/etc/unbound/unbound.conf.d
readonly live_primary="$live_conf_dir/pihole.conf"
readonly live_local_zone="$live_conf_dir/pihole-local-zone.conf"
readonly legacy_local_zone="$live_conf_dir/pihole0-local-zone.conf"
readonly accepted_live_primary_sha256=dd5af7ccbbac11324921e1d447d753dbab33b633bc4cb1db248ee0574825d3ae
readonly candidate_primary_sha256=cef0349528f87e97362c5917f1d0f77baca92eebf04790ed96997dfe3a0dd2e8
readonly candidate_local_zone_sha256=8a7d1c6d2235e6f37a98dfd3e10165b49968fcc5f3e898ce0b359f70bc0456d1
readonly expected_root_include='include-toplevel: "/etc/unbound/unbound.conf.d/*.conf"'

assertion_count=0
failed_assertion_count=0
first_failure=none

file_hash() {
    sha256sum "$1" | awk '{ print $1 }'
}

active_directives() {
    awk '
        /^[[:space:]]*(#|$)/ { next }
        {
            sub(/^[[:space:]]+/, "")
            sub(/[[:space:]]+$/, "")
            gsub(/[[:space:]]+/, " ")
            print
        }
    ' "$@"
}

normalized_directives() {
    active_directives "$@" |
        awk '$0 != "server:" { print }' |
        LC_ALL=C sort
}

record_assertion() {
    local assertion_label=$1
    local assertion_status=$2
    local observed_value=${3:-unavailable}

    ((assertion_count += 1))
    printf 'action_17h_assertion_%s=%s\n' \
        "$assertion_label" "$assertion_status"
    if [[ "$assertion_status" != true ]]; then
        ((failed_assertion_count += 1))
        if [[ "$first_failure" == none ]]; then
            first_failure=$assertion_label
        fi
        printf 'action_17h_observed_%s=%s\n' \
            "$assertion_label" "$observed_value"
    fi
}

assert_equal() {
    local equality_label=$1
    local observed_value=$2
    local expected_value=$3

    if [[ "$observed_value" == "$expected_value" ]]; then
        record_assertion "$equality_label" true
    else
        record_assertion "$equality_label" false "$observed_value"
    fi
}

assert_regular_file() {
    local regular_label=$1
    local regular_path=$2

    if [[ -f "$regular_path" && ! -L "$regular_path" ]]; then
        record_assertion "$regular_label" true
    else
        record_assertion "$regular_label" false \
            "$(stat -c %F "$regular_path" 2>/dev/null || printf absent)"
    fi
}

assert_absent() {
    local absent_label=$1
    local absent_path=$2

    if [[ ! -e "$absent_path" && ! -L "$absent_path" ]]; then
        record_assertion "$absent_label" true
    else
        record_assertion "$absent_label" false \
            "$(stat -c %F "$absent_path" 2>/dev/null || printf present)"
    fi
}

state_snapshot() {
    local snapshot_path

    for snapshot_path in "$live_root" "$live_primary" "$live_local_zone" \
        "$legacy_local_zone"; do
        if [[ -f "$snapshot_path" && ! -L "$snapshot_path" ]]; then
            printf 'file|%s|%s|%s\n' \
                "$snapshot_path" \
                "$(stat -c '%U:%G:%a:%s' "$snapshot_path")" \
                "$(file_hash "$snapshot_path")"
        elif [[ -L "$snapshot_path" ]]; then
            printf 'link|%s|%s\n' "$snapshot_path" \
                "$(readlink -- "$snapshot_path")"
        else
            printf 'absent|%s\n' "$snapshot_path"
        fi
    done
    systemctl show --property=ActiveState,SubState,UnitFileState \
        pihole-FTL.service unbound.service 2>/dev/null || true
}

if [[ "${1:-}" == --self-test && $# -eq 1 ]]; then
    [[ "$live_local_zone" == /etc/unbound/unbound.conf.d/pihole-local-zone.conf ]]
    [[ "$legacy_local_zone" == /etc/unbound/unbound.conf.d/pihole0-local-zone.conf ]]
    printf 'action_17h_inspector_self_test_complete=true\n'
    exit 0
elif [[ "${1:-}" != --stage || $# -ne 2 ]]; then
    printf 'Usage: %s --stage /run/caddy-action17h.*\n' "${0##*/}" >&2
    exit 2
fi

stage_path=$2
readonly stage_path
candidate_primary="$stage_path/pihole.conf"
readonly candidate_primary
candidate_local_zone="$stage_path/pihole-local-zone.conf"
readonly candidate_local_zone

printf 'action_17h_remote_reached=true\n'
for required_command in \
    awk cmp comm cp find grep hostname id install readlink rm sed sha256sum \
    sort stat systemctl unbound-checkconf wc; do
    command_label=${required_command//-/_}
    if command -v "$required_command" >/dev/null; then
        record_assertion "command_${command_label}_available" true
    else
        record_assertion "command_${command_label}_available" false missing
    fi
done

assert_equal uid_is_root "$(id -u)" 0
assert_equal working_directory_is_root "$PWD" /
assert_equal hostname_matches "$(hostname)" "$expected_hostname"
if [[ "$stage_path" =~ ^/run/caddy-action17h\.[A-Za-z0-9]+$ &&
    -d "$stage_path" && ! -L "$stage_path" ]]; then
    record_assertion stage_directory true
else
    record_assertion stage_directory false "$stage_path"
fi
assert_equal stage_directory_metadata \
    "$(stat -c '%U:%G:%a' "$stage_path" 2>/dev/null)" root:root:700
assert_regular_file candidate_primary_regular "$candidate_primary"
assert_equal candidate_primary_metadata \
    "$(stat -c '%U:%G:%a' "$candidate_primary" 2>/dev/null)" root:root:600
assert_equal candidate_primary_hash \
    "$(file_hash "$candidate_primary" 2>/dev/null)" \
    "$candidate_primary_sha256"
assert_regular_file candidate_local_zone_regular "$candidate_local_zone"
assert_equal candidate_local_zone_metadata \
    "$(stat -c '%U:%G:%a' "$candidate_local_zone" 2>/dev/null)" root:root:600
assert_equal candidate_local_zone_hash \
    "$(file_hash "$candidate_local_zone" 2>/dev/null)" \
    "$candidate_local_zone_sha256"

assert_regular_file live_root_regular "$live_root"
root_active_directive_count=$(active_directives "$live_root" | wc -l)
readonly root_active_directive_count
root_include_count=$(
    active_directives "$live_root" |
        grep -Fxc "$expected_root_include" || true
)
readonly root_include_count
assert_equal root_active_directive_count "$root_active_directive_count" 1
assert_equal root_include_count "$root_include_count" 1
assert_equal nonregular_conf_count \
    "$(find "$live_conf_dir" -mindepth 1 -maxdepth 1 \
        -name '*.conf' ! -type f -printf '.' | wc -c)" 0

assert_regular_file live_primary_regular "$live_primary"
assert_equal live_primary_hash \
    "$(file_hash "$live_primary" 2>/dev/null)" \
    "$accepted_live_primary_sha256"
assert_equal live_primary_metadata \
    "$(stat -c '%U:%G:%a:%s' "$live_primary" 2>/dev/null)" \
    root:root:644:33211
assert_absent live_local_zone_absent "$live_local_zone"
assert_absent legacy_local_zone_absent "$legacy_local_zone"
assert_equal unbound_active \
    "$(systemctl is-active unbound.service 2>/dev/null)" active
assert_equal pihole_ftl_active \
    "$(systemctl is-active pihole-FTL.service 2>/dev/null)" active

before_state=$(state_snapshot)
readonly before_state
before_state_sha256=$(
    printf '%s' "$before_state" | sha256sum | awk '{ print $1 }'
)
readonly before_state_sha256

live_parser_status=0
unbound-checkconf "$live_root" >/dev/null 2>&1 || live_parser_status=$?
assert_equal live_parser_status "$live_parser_status" 0
assert_equal candidate_primary_server_count \
    "$(active_directives "$candidate_primary" | grep -Fxc server: || true)" 1
assert_equal candidate_local_zone_server_count \
    "$(active_directives "$candidate_local_zone" | grep -Fxc server: || true)" 1
assert_equal candidate_primary_local_policy_count \
    "$(active_directives "$candidate_primary" |
        grep -Ec '^(private-domain|domain-insecure|local-zone|local-data|local-data-ptr):' ||
        true)" 0
assert_equal candidate_local_zone_forbidden_count \
    "$(active_directives "$candidate_local_zone" |
        awk -F: '$1 != "server" && $1 != "private-domain" &&
            $1 != "domain-insecure" && $1 != "local-zone" &&
            $1 != "local-data" && $1 != "local-data-ptr" { count++ }
            END { print count + 0 }')" 0

live_normalized="$stage_path/live.normalized"
candidate_normalized="$stage_path/candidate.normalized"
normalized_directives "$live_primary" >"$live_normalized"
normalized_directives \
    "$candidate_primary" "$candidate_local_zone" >"$candidate_normalized"
assert_equal normalized_directive_count \
    "$(wc -l <"$live_normalized")" "$(wc -l <"$candidate_normalized")"
assert_equal normalized_sha256 \
    "$(file_hash "$live_normalized")" "$(file_hash "$candidate_normalized")"
assert_equal live_only_directive_count \
    "$(comm -23 "$live_normalized" "$candidate_normalized" | wc -l)" 0
assert_equal candidate_only_directive_count \
    "$(comm -13 "$live_normalized" "$candidate_normalized" | wc -l)" 0

shadow_root="$stage_path/shadow"
install -d -o root -g root -m 0700 "$shadow_root/conf.d"
cp -a -- "$live_conf_dir/." "$shadow_root/conf.d/"
rm -f -- "$shadow_root/conf.d/pihole.conf" \
    "$shadow_root/conf.d/pihole-local-zone.conf" \
    "$shadow_root/conf.d/pihole0-local-zone.conf"
install -o root -g root -m 0600 "$candidate_primary" \
    "$shadow_root/conf.d/pihole.conf"
install -o root -g root -m 0600 "$candidate_local_zone" \
    "$shadow_root/conf.d/pihole-local-zone.conf"
printf 'include-toplevel: "%s/*.conf"\n' \
    "$shadow_root/conf.d" >"$shadow_root/unbound.conf"
candidate_parser_status=0
unbound-checkconf "$shadow_root/unbound.conf" >/dev/null 2>&1 ||
    candidate_parser_status=$?
assert_equal candidate_parser_status "$candidate_parser_status" 0

after_state=$(state_snapshot)
readonly after_state
after_state_sha256=$(
    printf '%s' "$after_state" | sha256sum | awk '{ print $1 }'
)
readonly after_state_sha256
assert_equal node_state_unchanged "$after_state" "$before_state"

printf 'action_17h_assertion_count=%s\n' "$assertion_count"
printf 'action_17h_failed_assertion_count=%s\n' "$failed_assertion_count"
printf 'action_17h_first_failure=%s\n' "$first_failure"
printf 'action_17h_before_state_sha256=%s\n' "$before_state_sha256"
printf 'action_17h_after_state_sha256=%s\n' "$after_state_sha256"
printf 'remote_stage_created=true\n'
printf 'dns_queries_performed=false\n'
printf 'dns_configuration_mutations=false\n'
printf 'service_mutations=false\n'
printf 'persistent_mutations=false\n'
if [[ "$failed_assertion_count" -eq 0 ]]; then
    printf 'action_17h_conclusion=ready_for_node_a_staged_adoption\n'
    printf 'action_17h_remote_complete=true\n'
    exit 0
fi
printf 'action_17h_conclusion=node_a_preflight_mismatch\n'
printf 'action_17h_remote_complete=true\n'
exit 1
