#!/usr/bin/env bash

set -Euo pipefail
set +x
umask 077
PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH
readonly PATH

readonly revision=action17p-node-a-to-node-b-bootstrap
readonly retained_release="/var/lib/caddy-sync/incoming/node-a/$revision"
readonly receiver_v1=/usr/local/libexec/caddy-sync-rsync-receiver
readonly receiver_v2=/usr/local/libexec/caddy-sync-release-receiver-v2
readonly finalizer_v2=/usr/local/libexec/finalize-incoming-release-v2.sh
readonly authorized_keys=/var/lib/caddy-sync/.ssh/authorized_keys
readonly lsyncd_config=/etc/lsyncd/caddy.lua
readonly rollback_root=/var/backups/caddy-ha
readonly expected_active_release=/etc/caddy/releases/action15-health-follow-redirects
readonly expected_receiver_v1_sha256=65d872f63a7a7e9dc108111057164c1785a77bf00429672452cfd3f9f3fe7134
readonly expected_authorization_sha256=2d07f2dd0bdd1be96f5e6eb227cd23ddc407876925f01849ffa3333c50b553e1
readonly expected_payload_sha256=3635265ef2ad9d6a0a88b9b972fa329d97655d3b4c9df56a1b491952bf1f8f6e
readonly expected_manifest_sha256=f4dc87dab7075c4b20ed2acafb4969b757534bad49f5b47c85de4474d17175c8
readonly reconcile_path_unit=caddy-sync-reconcile.path

assertion_count=0
failed_assertion_count=0
first_failure=none

record_assertion() {
    local assertion_label=$1
    local assertion_value=$2

    assertion_count=$((assertion_count + 1))
    printf 'action_17q_a_assertion_%s=%s\n' \
        "$assertion_label" "$assertion_value"
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

is_boolean() {
    [[ "$1" =~ ^(true|false)$ ]]
}

is_nonnegative_integer() {
    [[ "$1" =~ ^[0-9]+$ ]]
}

is_sha256() {
    [[ "$1" =~ ^[0-9a-f]{64}$ ]]
}

is_supported_conclusion() {
    [[ "$1" =~ ^path_(omits_mainpid_and_nrestarts|omits_mainpid|omits_nrestarts|exposes_both_service_properties)$ ]]
}

property_value() {
    local lookup_name=$1
    local property_file=$2

    awk -F= -v name="$lookup_name" '
        $1 == name {
            sub(/^[^=]*=/, "")
            print
            found = 1
            exit
        }
        END {
            if (!found) {
                print "unavailable"
            }
        }
    ' "$property_file"
}

property_present() {
    local lookup_name=$1
    local property_file=$2

    grep -Eq "^${lookup_name}=" "$property_file"
}

payload_digest() {
    (
        cd "$retained_release" || exit
        find . -type f ! -name .complete -print0 |
            LC_ALL=C sort -z |
            xargs -0 -r sha256sum |
            sha256sum |
            awk '{ print $1 }'
    )
}

stable_state_snapshot() {
    stat -c '%n|%U:%G:%a:%s:%i' \
        "$receiver_v1" \
        "$authorized_keys" \
        "$retained_release" \
        "$retained_release/manifest.sha256" \
        /etc/caddy/current \
        "$rollback_root"
    printf 'receiver_v1_sha256=%s\n' "$(file_hash "$receiver_v1")"
    printf 'authorization_sha256=%s\n' "$(file_hash "$authorized_keys")"
    printf 'payload_sha256=%s\n' "$(payload_digest)"
    printf 'manifest_sha256=%s\n' \
        "$(file_hash "$retained_release/manifest.sha256")"
    printf 'current_link=%s\n' "$(readlink /etc/caddy/current)"
    printf 'current_target=%s\n' "$(readlink -e /etc/caddy/current)"
    find "$retained_release" -printf '%P|%y|%U:%G:%m:%s:%i\n' |
        LC_ALL=C sort
    find "$retained_release" -type f -print0 |
        LC_ALL=C sort -z |
        xargs -0 -r sha256sum
    for snapshot_service in \
        caddy.service \
        lighttpd.service \
        lsyncd.service \
        caddy-lsyncd.service \
        caddy-sync-reconcile.service; do
        printf 'unit=%s\n' "$snapshot_service"
        systemctl show "$snapshot_service" --no-pager \
            -p LoadState \
            -p ActiveState \
            -p SubState \
            -p MainPID \
            -p NRestarts \
            -p FragmentPath
        printf 'unit_file_state=%s\n' \
            "$(systemctl is-enabled "$snapshot_service" 2>/dev/null || true)"
    done
    printf 'unit=%s\n' "$reconcile_path_unit"
    systemctl show "$reconcile_path_unit" --no-pager \
        -p LoadState \
        -p ActiveState \
        -p SubState \
        -p UnitFileState \
        -p UnitFilePreset \
        -p FragmentPath \
        -p Triggers \
        -p TriggeredBy
}

if [[ "${1:-}" == --self-test && $# -eq 1 ]]; then
    [[ "$revision" == action17p-node-a-to-node-b-bootstrap ]]
    [[ "$expected_active_release" == /etc/caddy/releases/action15-health-follow-redirects ]]
    for self_test_hash in \
        "$expected_receiver_v1_sha256" \
        "$expected_authorization_sha256" \
        "$expected_payload_sha256" \
        "$expected_manifest_sha256"; do
        is_sha256 "$self_test_hash"
    done
    printf 'action_17q_a_inspector_self_test_complete=true\n'
    exit 0
elif (($#)); then
    printf 'Usage: %s [--self-test]\n' "${0##*/}" >&2
    exit 2
fi

work_directory=$(mktemp -d /tmp/caddy-action17q-a.XXXXXX)
readonly work_directory
cleanup() {
    # shellcheck disable=SC2317
    rm -rf -- "$work_directory"
}
trap cleanup EXIT

readonly property_output="$work_directory/reconcile-path.properties"
readonly property_error="$work_directory/reconcile-path.properties.err"
readonly property_names="$work_directory/reconcile-path.property-names"
readonly before_state="$work_directory/state.before"
readonly before_error="$work_directory/state.before.err"
readonly after_state="$work_directory/state.after"
readonly after_error="$work_directory/state.after.err"

record_command identity_root test "$(id -u)" -eq 0
record_command working_directory_root test "$(pwd -P)" = /
record_command hostname_node_b test "$(hostname)" = j1-svpihole00
record_command architecture_arm64 \
    test "$(dpkg --print-architecture 2>/dev/null || true)" = arm64

property_status=0
systemctl show "$reconcile_path_unit" --all --no-pager \
    >"$property_output" 2>"$property_error" || property_status=$?
readonly property_status
record_command reconcile_path_property_query_status_zero \
    test "$property_status" -eq 0
record_command reconcile_path_property_query_stderr_empty \
    test ! -s "$property_error"
awk -F= '/^[A-Za-z][A-Za-z0-9]*=/{ print $1 }' "$property_output" |
    LC_ALL=C sort -u >"$property_names"
property_count=$(wc -l <"$property_names")
readonly property_count
property_names_sha256=$(file_hash "$property_names")
readonly property_names_sha256
record_command reconcile_path_property_count_positive \
    test "$property_count" -gt 0
record_command reconcile_path_property_names_hash_format \
    is_sha256 "$property_names_sha256"

path_load_state=$(property_value LoadState "$property_output")
readonly path_load_state
path_active_state=$(property_value ActiveState "$property_output")
readonly path_active_state
path_sub_state=$(property_value SubState "$property_output")
readonly path_sub_state
path_unit_file_state=$(property_value UnitFileState "$property_output")
readonly path_unit_file_state
path_fragment_path=$(property_value FragmentPath "$property_output")
readonly path_fragment_path
record_command reconcile_path_load_state_loaded \
    test "$path_load_state" = loaded
record_command reconcile_path_active_state_inactive \
    test "$path_active_state" = inactive
record_command reconcile_path_sub_state_dead \
    test "$path_sub_state" = dead
record_command reconcile_path_unit_file_state_disabled \
    test "$path_unit_file_state" = disabled
record_command reconcile_path_fragment_path_exact \
    test "$path_fragment_path" = \
    /etc/systemd/system/caddy-sync-reconcile.path

path_mainpid_present=false
if property_present MainPID "$property_output"; then
    path_mainpid_present=true
fi
readonly path_mainpid_present
path_nrestarts_present=false
if property_present NRestarts "$property_output"; then
    path_nrestarts_present=true
fi
readonly path_nrestarts_present
record_command reconcile_path_mainpid_presence_boolean \
    is_boolean "$path_mainpid_present"
record_command reconcile_path_nrestarts_presence_boolean \
    is_boolean "$path_nrestarts_present"

record_command receiver_v1_regular test -f "$receiver_v1"
record_command receiver_v1_not_symlink test ! -L "$receiver_v1"
record_command receiver_v1_hash_exact \
    test "$(file_hash "$receiver_v1" 2>/dev/null || true)" = \
    "$expected_receiver_v1_sha256"
record_command receiver_v2_absent test ! -e "$receiver_v2"
record_command receiver_v2_not_symlink test ! -L "$receiver_v2"
record_command finalizer_v2_absent test ! -e "$finalizer_v2"
record_command finalizer_v2_not_symlink test ! -L "$finalizer_v2"
record_command authorized_keys_regular test -f "$authorized_keys"
record_command authorized_keys_not_symlink test ! -L "$authorized_keys"
record_command authorized_keys_metadata \
    test "$(stat -c '%U:%G:%a' "$authorized_keys" 2>/dev/null || true)" = \
    caddy-sync:caddy-sync:600
record_command authorized_keys_hash_exact \
    test "$(file_hash "$authorized_keys" 2>/dev/null || true)" = \
    "$expected_authorization_sha256"

record_command retained_release_directory test -d "$retained_release"
record_command retained_release_not_symlink test ! -L "$retained_release"
record_command retained_release_metadata \
    test "$(stat -c '%U:%G:%a' "$retained_release" 2>/dev/null || true)" = \
    caddy-sync:caddy-sync:550
record_command retained_complete_absent \
    test ! -e "$retained_release/.complete"
record_command retained_complete_not_symlink \
    test ! -L "$retained_release/.complete"
record_command retained_pending_absent \
    test ! -e "$retained_release/.complete.pending"
record_command retained_pending_not_symlink \
    test ! -L "$retained_release/.complete.pending"
record_command retained_finalize_request_absent \
    test ! -e "$retained_release/.finalize-request"
record_command retained_finalize_request_not_symlink \
    test ! -L "$retained_release/.finalize-request"
record_command retained_payload_hash_exact \
    test "$(payload_digest 2>/dev/null || true)" = "$expected_payload_sha256"
record_command retained_manifest_hash_exact \
    test "$(file_hash "$retained_release/manifest.sha256" \
        2>/dev/null || true)" = "$expected_manifest_sha256"
record_command retained_not_writable_by_sync \
    runuser -u caddy-sync -- test ! -w "$retained_release"

record_command current_link_exact \
    test "$(readlink /etc/caddy/current 2>/dev/null || true)" = \
    "$expected_active_release"
record_command current_target_exact \
    test "$(readlink -e /etc/caddy/current 2>/dev/null || true)" = \
    "$expected_active_release"
record_command caddy_active \
    test "$(systemctl is-active caddy.service 2>/dev/null || true)" = active
record_command lighttpd_active \
    test "$(systemctl is-active lighttpd.service 2>/dev/null || true)" = active
record_command lsyncd_inactive \
    test "$(systemctl is-active lsyncd.service 2>/dev/null || true)" = inactive
record_command lsyncd_masked \
    test "$(systemctl is-enabled lsyncd.service 2>/dev/null || true)" = masked
record_command caddy_lsyncd_inactive \
    test "$(systemctl is-active caddy-lsyncd.service \
        2>/dev/null || true)" = inactive
record_command caddy_lsyncd_disabled \
    test "$(systemctl is-enabled caddy-lsyncd.service \
        2>/dev/null || true)" = disabled
record_command reconcile_path_inactive \
    test "$(systemctl is-active "$reconcile_path_unit" \
        2>/dev/null || true)" = inactive
record_command reconcile_service_inactive \
    test "$(systemctl is-active caddy-sync-reconcile.service \
        2>/dev/null || true)" = inactive
record_command lsyncd_configuration_absent test ! -e "$lsyncd_config"
record_command lsyncd_configuration_not_symlink test ! -L "$lsyncd_config"

action17q_backup_count=$(
    find "$rollback_root" -mindepth 1 -maxdepth 1 \
        -name 'action17q-node-b-protocol-v2.*' -printf '.' 2>/dev/null |
        wc -c
)
readonly action17q_backup_count
action17q_stage_count=$(
    find /run -mindepth 1 -maxdepth 1 \
        -name 'caddy-action17q-stage.*' -printf '.' 2>/dev/null |
        wc -c
)
readonly action17q_stage_count
record_command action17q_backup_count_zero \
    test "$action17q_backup_count" -eq 0
record_command action17q_stage_count_zero \
    test "$action17q_stage_count" -eq 0

before_status=0
stable_state_snapshot >"$before_state" 2>"$before_error" || before_status=$?
readonly before_status
record_command before_state_status_zero test "$before_status" -eq 0
record_command before_state_stderr_empty test ! -s "$before_error"
before_state_sha256=unavailable
if [[ "$before_status" -eq 0 ]]; then
    before_state_sha256=$(file_hash "$before_state")
fi
readonly before_state_sha256
record_command before_state_hash_format is_sha256 "$before_state_sha256"

after_status=0
stable_state_snapshot >"$after_state" 2>"$after_error" || after_status=$?
readonly after_status
record_command after_state_status_zero test "$after_status" -eq 0
record_command after_state_stderr_empty test ! -s "$after_error"
after_state_sha256=unavailable
if [[ "$after_status" -eq 0 ]]; then
    after_state_sha256=$(file_hash "$after_state")
fi
readonly after_state_sha256
record_command after_state_hash_format is_sha256 "$after_state_sha256"
record_command state_unchanged \
    test "$after_state_sha256" = "$before_state_sha256"

if [[ "$path_mainpid_present" == false &&
    "$path_nrestarts_present" == false ]]; then
    conclusion=path_omits_mainpid_and_nrestarts
elif [[ "$path_mainpid_present" == false &&
    "$path_nrestarts_present" == true ]]; then
    conclusion=path_omits_mainpid
elif [[ "$path_mainpid_present" == true &&
    "$path_nrestarts_present" == false ]]; then
    conclusion=path_omits_nrestarts
else
    conclusion=path_exposes_both_service_properties
fi
readonly conclusion
record_command conclusion_supported is_supported_conclusion "$conclusion"

record_command assertion_count_nonnegative \
    is_nonnegative_integer "$assertion_count"

printf 'action_17q_a_value_reconcile_path_property_count=%s\n' \
    "$property_count"
printf 'action_17q_a_value_reconcile_path_property_names_sha256=%s\n' \
    "$property_names_sha256"
printf 'action_17q_a_value_reconcile_path_load_state=%s\n' \
    "$path_load_state"
printf 'action_17q_a_value_reconcile_path_active_state=%s\n' \
    "$path_active_state"
printf 'action_17q_a_value_reconcile_path_sub_state=%s\n' "$path_sub_state"
printf 'action_17q_a_value_reconcile_path_unit_file_state=%s\n' \
    "$path_unit_file_state"
printf 'action_17q_a_value_reconcile_path_fragment_path=%s\n' \
    "$path_fragment_path"
printf 'action_17q_a_value_reconcile_path_mainpid_present=%s\n' \
    "$path_mainpid_present"
printf 'action_17q_a_value_reconcile_path_nrestarts_present=%s\n' \
    "$path_nrestarts_present"
printf 'action_17q_a_value_action17q_backup_count=%s\n' \
    "$action17q_backup_count"
printf 'action_17q_a_value_action17q_stage_count=%s\n' \
    "$action17q_stage_count"
printf 'action_17q_a_value_before_state_sha256=%s\n' \
    "$before_state_sha256"
printf 'action_17q_a_value_after_state_sha256=%s\n' \
    "$after_state_sha256"
printf 'action_17q_a_value_conclusion=%s\n' "$conclusion"
printf 'action_17q_a_assertion_count=%s\n' "$assertion_count"
printf 'action_17q_a_failed_assertion_count=%s\n' \
    "$failed_assertion_count"
printf 'action_17q_a_first_failure=%s\n' "$first_failure"
printf 'action_17q_a_helper_execution=false\n'
printf 'action_17q_a_release_mutation=false\n'
printf 'action_17q_a_authorization_mutation=false\n'
printf 'action_17q_a_lsyncd_reconciliation_activation=false\n'
printf 'action_17q_a_service_mutations=false\n'
printf 'action_17q_a_persistent_mutations=false\n'
printf 'action_17q_a_remote_complete=true\n'

if [[ "$failed_assertion_count" -ne 0 ]]; then
    exit 1
fi
