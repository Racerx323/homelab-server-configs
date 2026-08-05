#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH
readonly PATH

readonly prefix=action_20a_a_probe
readonly health_script=/usr/local/libexec/check-caddy.sh
readonly fragment=/etc/keepalived/conf.d/caddy-ha.conf
readonly caddyfile=/etc/caddy/current/Caddyfile
readonly fullchain=/etc/caddy/tls/fullchain.pem
readonly private_key=/etc/caddy/tls/privkey.pem
readonly environment_file=/etc/default/caddy-ha
readonly keepalived_home=/home/keepalived_script
readonly caddy_home=/var/lib/caddy
readonly expected_health_sha256=c3bc1c080cd148efc0a64440a2a411ec115d0ca83f8e6a66220d7bd201971414
readonly maximum_stream_bytes=131072
readonly maximum_stream_lines=1024

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }
line_count() { awk 'END { print NR }' "$1"; }
sanitize_value() {
    tr '\t\r\n' '   ' | sed -E 's/[[:space:]]+/ /g; s/^ //; s/ $//'
}
safe_stream() {
    local inspected_stream_path=$1

    [[ "$(wc -c <"$inspected_stream_path")" -le "$maximum_stream_bytes" ]] ||
        return 1
    [[ "$(line_count "$inspected_stream_path")" -le "$maximum_stream_lines" ]] ||
        return 1
    ! LC_ALL=C grep -n '[^[:print:][:space:]]' "$inspected_stream_path" \
        >/dev/null || return 1
    ! grep -Eqi \
        'BEGIN [A-Z ]*PRIVATE KEY|CADDY_TLS_PRIVATE_KEY_PEM|PRIVATE_KEY=|DOPPLER_TOKEN|Authorization:[[:space:]]*Bearer' \
        "$inspected_stream_path"
}
snapshot_state() {
    local snapshot_unit_name

    printf 'health_sha256=%s\n' "$(file_hash "$health_script")"
    printf 'fragment_sha256=%s\n' "$(file_hash "$fragment")"
    printf 'caddyfile_sha256=%s\n' "$(file_hash "$caddyfile")"
    printf 'current=%s\n' "$(readlink -f /etc/caddy/current)"
    printf 'keepalived_home=%s\n' \
        "$(stat -c '%F|%U:%G:%a|%d:%i' "$keepalived_home" 2>/dev/null || printf absent)"
    printf 'caddy_home=%s\n' \
        "$(stat -c '%F|%U:%G:%a|%d:%i' "$caddy_home" 2>/dev/null || printf absent)"
    printf 'addresses_sha256=%s\n' \
        "$(ip -o address show dev eth0 | sha256sum | awk '{ print $1 }')"
    for snapshot_unit_name in caddy.service keepalived.service lighttpd.service; do
        printf 'unit=%s|%s\n' "$snapshot_unit_name" \
            "$(systemctl show "$snapshot_unit_name" \
                --property=ActiveState,SubState,MainPID,NRestarts --value |
                tr '\n' '|')"
    done
}
expected_assertions() {
    printf '%s\n' \
        identity_root working_directory_root node_role_exact hostname_exact \
        health_script_regular health_script_not_symlink \
        health_script_metadata_exact health_script_hash_exact \
        fragment_health_user_exact keepalived_account_query_status_zero \
        keepalived_home_exact keepalived_shell_nologin \
        keepalived_primary_group_exact caddy_account_query_status_zero \
        caddy_home_exact caddy_shell_nologin caddy_primary_group_exact \
        keepalived_groups_query_status_zero keepalived_member_of_caddy_group \
        keepalived_home_absent keepalived_home_parent_not_writable \
        caddy_home_regular caddy_home_not_symlink \
        caddy_home_caddy_accessible caddy_home_keepalived_not_writable \
        caddy_unit_user_query_status_zero caddy_unit_user_exact \
        caddy_unit_group_query_status_zero caddy_unit_group_exact \
        caddy_unit_environment_query_status_zero \
        caddy_unit_environment_home_absent \
        caddy_unit_environment_xdg_config_absent \
        caddy_unit_environment_xdg_data_absent \
        caddy_unit_environment_files_query_status_zero \
        caddy_unit_environment_file_present \
        caddy_unit_working_directory_query_status_zero \
        caddy_unit_state_directory_query_status_zero \
        caddy_unit_protect_home_query_status_zero \
        keepalived_unit_user_query_status_zero \
        keepalived_unit_group_query_status_zero \
        keepalived_unit_environment_query_status_zero caddy_active \
        keepalived_active current_caddyfile_keepalived_readable \
        fullchain_keepalived_readable private_key_keepalived_readable \
        before_state_status_zero baseline_status_nonzero \
        baseline_stdout_safe baseline_stderr_safe \
        baseline_permission_denied_observed baseline_home_reference_observed \
        baseline_did_not_create_keepalived_home transient_setup_status_zero \
        transient_validate_status_zero transient_stdout_safe \
        transient_stderr_safe transient_local_pki_created \
        transient_storage_cleanup_complete after_state_status_zero \
        state_unchanged persistent_keepalived_home_absent
}
record_command() {
    local assertion_label=$1

    shift
    if "$@"; then
        printf '%s_assertion_%s=true\n' "$prefix" "$assertion_label"
        return 0
    fi
    printf '%s_assertion_%s=false\n' "$prefix" "$assertion_label"
    return 1
}
emit_stream() {
    local emitted_name=$1
    local emitted_path=$2
    local emitted_safe=$3

    printf '%s_value_%s_bytes=%s\n' "$prefix" "$emitted_name" \
        "$(wc -c <"$emitted_path")"
    printf '%s_value_%s_lines=%s\n' "$prefix" "$emitted_name" \
        "$(line_count "$emitted_path")"
    printf '%s_value_%s_sha256=%s\n' "$prefix" "$emitted_name" \
        "$(file_hash "$emitted_path")"
    printf '%s_value_%s_classification=%s\n' "$prefix" "$emitted_name" \
        "$emitted_safe"
    if [[ "$emitted_safe" != bounded_safe ]]; then
        return 0
    fi
    if [[ ! -s "$emitted_path" ]]; then
        printf '%s_%s_content_secured=empty\n' "$prefix" "$emitted_name"
        return 0
    fi
    printf '%s_%s_begin\n' "$prefix" "$emitted_name"
    cat "$emitted_path"
    printf '%s_%s_end\n' "$prefix" "$emitted_name"
}
unit_property() {
    local inspected_property=$1

    systemctl show caddy.service --property="$inspected_property" --value \
        2>/dev/null | sanitize_value
}

case "${1:-}" in
    --expected-assertions)
        [[ $# -eq 1 ]] || exit 64
        expected_assertions
        exit 0
        ;;
    --self-test)
        [[ $# -eq 1 ]] || exit 64
        self_test_root=$(mktemp -d /tmp/caddy-action20aa-probe-self.XXXXXX)
        readonly self_test_root
        trap 'rm -rf -- "$self_test_root"' EXIT
        expected_assertions >"$self_test_root/labels"
        [[ "$(wc -l <"$self_test_root/labels")" -eq 62 ]]
        [[ "$(LC_ALL=C sort -u "$self_test_root/labels" | wc -l)" -eq 62 ]]
        ! grep -Ev '^[a-z0-9_]+$' "$self_test_root/labels" | grep -q .
        printf '%s_self_test_complete=true\n' "$prefix"
        exit 0
        ;;
    --node)
        [[ $# -eq 2 ]] || exit 64
        node_role=$2
        ;;
    *)
        printf 'Usage: %s --self-test|--expected-assertions|--node node-a|node-b\n' \
            "${0##*/}" >&2
        exit 64
        ;;
esac

case "$node_role" in
    node-a) expected_hostname=j1-svpihole0 ;;
    node-b) expected_hostname=j1-svpihole00 ;;
    *)
        printf 'Unknown node role: %s\n' "$node_role" >&2
        exit 64
        ;;
esac
readonly node_role expected_hostname

work_directory=$(mktemp -d /tmp/caddy-action20aa-probe.XXXXXX)
readonly work_directory
readonly transient_root=$work_directory/transient-context
cleanup() {
    # shellcheck disable=SC2317
    rm -rf -- "$work_directory"
}
trap cleanup EXIT
readonly before_state=$work_directory/before.state
readonly after_state=$work_directory/after.state
readonly baseline_stdout=$work_directory/baseline.stdout
readonly baseline_stderr=$work_directory/baseline.stderr
readonly transient_stdout=$work_directory/transient.stdout
readonly transient_stderr=$work_directory/transient.stderr
for capture_path in "$before_state" "$after_state" "$baseline_stdout" \
    "$baseline_stderr" "$transient_stdout" "$transient_stderr"; do
    : >"$capture_path"
    chmod 0600 "$capture_path"
done

failed_count=0
first_failure=none
run_assertion() {
    local executed_assertion_label=$1

    shift
    if ! record_command "$executed_assertion_label" "$@"; then
        failed_count=$((failed_count + 1))
        if [[ "$first_failure" == none ]]; then
            first_failure=$executed_assertion_label
        fi
    fi
}

before_status=0
snapshot_state >"$before_state" 2>/dev/null || before_status=$?
readonly before_status
before_state_sha256=$(file_hash "$before_state")
readonly before_state_sha256

keepalived_passwd_status=0
keepalived_passwd=$(getent passwd keepalived_script) || keepalived_passwd_status=$?
readonly keepalived_passwd_status keepalived_passwd
caddy_passwd_status=0
caddy_passwd=$(getent passwd caddy) || caddy_passwd_status=$?
readonly caddy_passwd_status caddy_passwd
keepalived_groups_status=0
keepalived_groups=$(id -Gn keepalived_script) || keepalived_groups_status=$?
readonly keepalived_groups_status keepalived_groups

caddy_unit_user_status=0
caddy_unit_user=$(unit_property User) || caddy_unit_user_status=$?
readonly caddy_unit_user_status caddy_unit_user
caddy_unit_group_status=0
caddy_unit_group=$(unit_property Group) || caddy_unit_group_status=$?
readonly caddy_unit_group_status caddy_unit_group
caddy_unit_environment_status=0
caddy_unit_environment=$(unit_property Environment) || caddy_unit_environment_status=$?
readonly caddy_unit_environment_status caddy_unit_environment
caddy_unit_environment_files_status=0
caddy_unit_environment_files=$(unit_property EnvironmentFiles) ||
    caddy_unit_environment_files_status=$?
readonly caddy_unit_environment_files_status caddy_unit_environment_files
caddy_unit_working_directory_status=0
caddy_unit_working_directory=$(unit_property WorkingDirectory) ||
    caddy_unit_working_directory_status=$?
readonly caddy_unit_working_directory_status caddy_unit_working_directory
caddy_unit_state_directory_status=0
caddy_unit_state_directory=$(unit_property StateDirectory) ||
    caddy_unit_state_directory_status=$?
readonly caddy_unit_state_directory_status caddy_unit_state_directory
caddy_unit_protect_home_status=0
caddy_unit_protect_home=$(unit_property ProtectHome) ||
    caddy_unit_protect_home_status=$?
readonly caddy_unit_protect_home_status caddy_unit_protect_home
keepalived_unit_user_status=0
keepalived_unit_user=$(systemctl show keepalived.service --property=User --value |
    sanitize_value) || keepalived_unit_user_status=$?
readonly keepalived_unit_user_status keepalived_unit_user
keepalived_unit_group_status=0
keepalived_unit_group=$(systemctl show keepalived.service --property=Group --value |
    sanitize_value) || keepalived_unit_group_status=$?
readonly keepalived_unit_group_status keepalived_unit_group
keepalived_unit_environment_status=0
keepalived_unit_environment=$(systemctl show keepalived.service \
    --property=Environment --value | sanitize_value) ||
    keepalived_unit_environment_status=$?
readonly keepalived_unit_environment_status keepalived_unit_environment

run_assertion identity_root test "$(id -u)" -eq 0
run_assertion working_directory_root test "$(pwd -P)" = /
run_assertion node_role_exact test "$node_role" = "$2"
run_assertion hostname_exact test "$(hostname)" = "$expected_hostname"
run_assertion health_script_regular test -f "$health_script"
run_assertion health_script_not_symlink test ! -L "$health_script"
run_assertion health_script_metadata_exact test \
    "$(stat -c '%U:%G:%a' "$health_script")" = root:root:755
run_assertion health_script_hash_exact test "$(file_hash "$health_script")" = \
    "$expected_health_sha256"
run_assertion fragment_health_user_exact grep -Fq 'user keepalived_script' "$fragment"
run_assertion keepalived_account_query_status_zero test \
    "$keepalived_passwd_status" -eq 0
run_assertion keepalived_home_exact test \
    "$(printf '%s' "$keepalived_passwd" | cut -d: -f6)" = "$keepalived_home"
run_assertion keepalived_shell_nologin test \
    "$(printf '%s' "$keepalived_passwd" | cut -d: -f7)" = /usr/sbin/nologin
run_assertion keepalived_primary_group_exact test \
    "$(id -gn keepalived_script)" = keepalived_script
run_assertion caddy_account_query_status_zero test "$caddy_passwd_status" -eq 0
run_assertion caddy_home_exact test \
    "$(printf '%s' "$caddy_passwd" | cut -d: -f6)" = "$caddy_home"
run_assertion caddy_shell_nologin test \
    "$(printf '%s' "$caddy_passwd" | cut -d: -f7)" = /usr/sbin/nologin
run_assertion caddy_primary_group_exact test "$(id -gn caddy)" = caddy
run_assertion keepalived_groups_query_status_zero test \
    "$keepalived_groups_status" -eq 0
run_assertion keepalived_member_of_caddy_group grep -Eq '(^| )caddy( |$)' \
    <<<"$keepalived_groups"
run_assertion keepalived_home_absent test ! -e "$keepalived_home"
run_assertion keepalived_home_parent_not_writable runuser -u keepalived_script -- \
    test ! -w /home
run_assertion caddy_home_regular test -d "$caddy_home"
run_assertion caddy_home_not_symlink test ! -L "$caddy_home"
run_assertion caddy_home_caddy_accessible runuser -u caddy -- test -r "$caddy_home"
run_assertion caddy_home_keepalived_not_writable runuser -u keepalived_script -- \
    test ! -w "$caddy_home"
run_assertion caddy_unit_user_query_status_zero test "$caddy_unit_user_status" -eq 0
run_assertion caddy_unit_user_exact test "$caddy_unit_user" = caddy
run_assertion caddy_unit_group_query_status_zero test "$caddy_unit_group_status" -eq 0
run_assertion caddy_unit_group_exact test "$caddy_unit_group" = caddy
run_assertion caddy_unit_environment_query_status_zero test \
    "$caddy_unit_environment_status" -eq 0
if grep -Eq '(^| )HOME=' <<<"$caddy_unit_environment"; then
    failed_count=$((failed_count + 1))
    [[ "$first_failure" != none ]] || first_failure=caddy_unit_environment_home_absent
    printf '%s_assertion_caddy_unit_environment_home_absent=false\n' "$prefix"
else
    printf '%s_assertion_caddy_unit_environment_home_absent=true\n' "$prefix"
fi
for xdg_pair in \
    xdg_config:XDG_CONFIG_HOME \
    xdg_data:XDG_DATA_HOME; do
    xdg_label=${xdg_pair%%:*}
    xdg_name=${xdg_pair#*:}
    if grep -Eq "(^| )${xdg_name}=" <<<"$caddy_unit_environment"; then
        failed_count=$((failed_count + 1))
        [[ "$first_failure" != none ]] ||
            first_failure="caddy_unit_environment_${xdg_label}_absent"
        printf '%s_assertion_caddy_unit_environment_%s_absent=false\n' \
            "$prefix" "$xdg_label"
    else
        printf '%s_assertion_caddy_unit_environment_%s_absent=true\n' \
            "$prefix" "$xdg_label"
    fi
done
run_assertion caddy_unit_environment_files_query_status_zero test \
    "$caddy_unit_environment_files_status" -eq 0
run_assertion caddy_unit_environment_file_present grep -Fq "$environment_file" \
    <<<"$caddy_unit_environment_files"
run_assertion caddy_unit_working_directory_query_status_zero test \
    "$caddy_unit_working_directory_status" -eq 0
run_assertion caddy_unit_state_directory_query_status_zero test \
    "$caddy_unit_state_directory_status" -eq 0
run_assertion caddy_unit_protect_home_query_status_zero test \
    "$caddy_unit_protect_home_status" -eq 0
run_assertion keepalived_unit_user_query_status_zero test \
    "$keepalived_unit_user_status" -eq 0
run_assertion keepalived_unit_group_query_status_zero test \
    "$keepalived_unit_group_status" -eq 0
run_assertion keepalived_unit_environment_query_status_zero test \
    "$keepalived_unit_environment_status" -eq 0
run_assertion caddy_active test "$(systemctl is-active caddy.service)" = active
run_assertion keepalived_active test "$(systemctl is-active keepalived.service)" = active
run_assertion current_caddyfile_keepalived_readable runuser -u keepalived_script -- \
    test -r "$caddyfile"
run_assertion fullchain_keepalived_readable runuser -u keepalived_script -- \
    test -r "$fullchain"
run_assertion private_key_keepalived_readable runuser -u keepalived_script -- \
    test -r "$private_key"
run_assertion before_state_status_zero test "$before_status" -eq 0

baseline_status=0
runuser -u keepalived_script -- env -u HOME -u XDG_CONFIG_HOME \
    -u XDG_DATA_HOME /usr/bin/timeout 15s /usr/bin/caddy validate \
    --config "$caddyfile" --adapter caddyfile >"$baseline_stdout" \
    2>"$baseline_stderr" || baseline_status=$?
readonly baseline_status
baseline_stdout_safe=unsafe
safe_stream "$baseline_stdout" && baseline_stdout_safe=bounded_safe
readonly baseline_stdout_safe
baseline_stderr_safe=unsafe
safe_stream "$baseline_stderr" && baseline_stderr_safe=bounded_safe
readonly baseline_stderr_safe
run_assertion baseline_status_nonzero test "$baseline_status" -ne 0
run_assertion baseline_stdout_safe test "$baseline_stdout_safe" = bounded_safe
run_assertion baseline_stderr_safe test "$baseline_stderr_safe" = bounded_safe
run_assertion baseline_permission_denied_observed grep -Fqi 'permission denied' \
    "$baseline_stderr"
run_assertion baseline_home_reference_observed grep -Fq "$keepalived_home" \
    "$baseline_stderr"
run_assertion baseline_did_not_create_keepalived_home test ! -e "$keepalived_home"

transient_setup_status=0
install -d -o keepalived_script -g keepalived_script -m 0700 \
    "$transient_root" "$transient_root/home" "$transient_root/config" \
    "$transient_root/data" || transient_setup_status=$?
readonly transient_setup_status
run_assertion transient_setup_status_zero test "$transient_setup_status" -eq 0
transient_validate_status=125
if [[ "$transient_setup_status" -eq 0 ]]; then
    set -a
    # shellcheck disable=SC1090
    source "$environment_file"
    set +a
    transient_validate_status=0
    runuser -u keepalived_script -- env \
        HOME="$transient_root/home" \
        XDG_CONFIG_HOME="$transient_root/config" \
        XDG_DATA_HOME="$transient_root/data" \
        /usr/bin/timeout 15s /usr/bin/caddy validate \
        --config "$caddyfile" --adapter caddyfile >"$transient_stdout" \
        2>"$transient_stderr" || transient_validate_status=$?
fi
readonly transient_validate_status
transient_stdout_safe=unsafe
safe_stream "$transient_stdout" && transient_stdout_safe=bounded_safe
readonly transient_stdout_safe
transient_stderr_safe=unsafe
safe_stream "$transient_stderr" && transient_stderr_safe=bounded_safe
readonly transient_stderr_safe
transient_local_pki_count=$(find "$transient_root/data" -type f 2>/dev/null |
    wc -l)
readonly transient_local_pki_count
run_assertion transient_validate_status_zero test "$transient_validate_status" -eq 0
run_assertion transient_stdout_safe test "$transient_stdout_safe" = bounded_safe
run_assertion transient_stderr_safe test "$transient_stderr_safe" = bounded_safe
run_assertion transient_local_pki_created test "$transient_local_pki_count" -gt 0
rm -rf -- "$transient_root"
run_assertion transient_storage_cleanup_complete test ! -e "$transient_root"

after_status=0
snapshot_state >"$after_state" 2>/dev/null || after_status=$?
readonly after_status
after_state_sha256=$(file_hash "$after_state")
readonly after_state_sha256
run_assertion after_state_status_zero test "$after_status" -eq 0
run_assertion state_unchanged test "$before_state_sha256" = "$after_state_sha256"
run_assertion persistent_keepalived_home_absent test ! -e "$keepalived_home"

printf '%s_value_node_role=%s\n' "$prefix" "$node_role"
printf '%s_value_keepalived_passwd=%s\n' "$prefix" \
    "$(printf '%s' "$keepalived_passwd" | sanitize_value)"
printf '%s_value_caddy_passwd=%s\n' "$prefix" \
    "$(printf '%s' "$caddy_passwd" | sanitize_value)"
printf '%s_value_keepalived_groups=%s\n' "$prefix" \
    "$(printf '%s' "$keepalived_groups" | sanitize_value)"
for property_record in \
    "User|$caddy_unit_user" \
    "Group|$caddy_unit_group" \
    "Environment|$caddy_unit_environment" \
    "EnvironmentFiles|$caddy_unit_environment_files" \
    "WorkingDirectory|$caddy_unit_working_directory" \
    "StateDirectory|$caddy_unit_state_directory" \
    "ProtectHome|$caddy_unit_protect_home"; do
    printf '%s_value_caddy_unit_property=%s\n' "$prefix" "$property_record"
done
printf '%s_value_keepalived_unit_user=%s\n' "$prefix" "$keepalived_unit_user"
printf '%s_value_keepalived_unit_group=%s\n' "$prefix" "$keepalived_unit_group"
printf '%s_value_keepalived_unit_environment=%s\n' "$prefix" \
    "$keepalived_unit_environment"
printf '%s_value_baseline_status=%s\n' "$prefix" "$baseline_status"
printf '%s_value_transient_validate_status=%s\n' "$prefix" \
    "$transient_validate_status"
printf '%s_value_transient_local_pki_file_count=%s\n' "$prefix" \
    "$transient_local_pki_count"
printf '%s_value_before_state_sha256=%s\n' "$prefix" "$before_state_sha256"
printf '%s_value_after_state_sha256=%s\n' "$prefix" "$after_state_sha256"
emit_stream baseline_stdout "$baseline_stdout" "$baseline_stdout_safe"
emit_stream baseline_stderr "$baseline_stderr" "$baseline_stderr_safe"
emit_stream transient_stdout "$transient_stdout" "$transient_stdout_safe"
emit_stream transient_stderr "$transient_stderr" "$transient_stderr_safe"
expected_assertion_count=$(expected_assertions | wc -l)
readonly expected_assertion_count
printf '%s_assertion_count=%s\n' "$prefix" "$expected_assertion_count"
printf '%s_failed_assertion_count=%s\n' "$prefix" "$failed_count"
printf '%s_first_failure=%s\n' "$prefix" "$first_failure"
printf '%s_installed_health_helper_invoked=false\n' "$prefix"
printf '%s_transient_filesystem_activity=true\n' "$prefix"
printf '%s_service_mutations=false\n' "$prefix"
printf '%s_vrrp_mutations=false\n' "$prefix"
printf '%s_vip_mutations=false\n' "$prefix"
printf '%s_persistent_mutations=false\n' "$prefix"
printf '%s_remote_cleanup_complete=true\n' "$prefix"
printf '%s_remote_complete=true\n' "$prefix"

if [[ "$failed_count" -eq 0 ]]; then exit 0; fi
exit 1
