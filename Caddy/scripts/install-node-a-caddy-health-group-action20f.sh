#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export PATH
readonly PATH

readonly prefix=action_20f
readonly fragment=/etc/keepalived/conf.d/caddy-ha.conf
readonly main_configuration=/etc/keepalived/keepalived.conf
readonly environment_file=/etc/default/caddy-ha
readonly health_helper=/usr/local/libexec/check-caddy.sh
readonly active_release=/etc/caddy/releases/action16ar-retry-node-a-default-deny
readonly backup_root=/var/backups/caddy-ha
readonly old_fragment_sha256=3a6f4c038d646bf12484d1a521a8f7fc01d05c56919ac8e6217ca50c2ab84bc5
readonly candidate_fragment_sha256=6f5a58ca8fd39a1218de6fc964f54aef69f374351c0727bbb0fabf899a80ef39
readonly environment_sha256=2e439dd4c868736fd7a9dceff7ba3627a1d9fe8780ba7dcef2ce5d0e5e62a2b8
readonly health_helper_sha256=9bf531ab7cbb047f8f09ce5956b597d5c8b6ede397c166f0b040e2e92fe8bbab
readonly main_sha256=cf4858888ae80772f1a50dda7c0ea120ff083eafae33a0ad4ca291d44755c1e2
readonly caddy_ipv4=10.1.0.56/22
readonly caddy_ipv6=fd36:5aa8:6971:1::56/128
readonly dns_ipv4=10.1.0.55/22
readonly dns_ipv6=fd36:5aa8:6971:1::55/128
readonly maximum_stream_bytes=1048576
readonly maximum_stream_lines=4096

stage_directory=
backup_directory=
install_stage=
mutation_started=false
transaction_complete=false
caddy_pid_before=
keepalived_pid_before=
lighttpd_pid_before=
context_runtime_root=

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }
line_count() { awk 'END { print NR }' "$1"; }
address_count() {
    local action20f_address_family=$1
    local action20f_address_cidr=$2

    ip -o "$action20f_address_family" address show dev eth0 |
        awk -v address="$action20f_address_cidr" \
            '$4 == address { count++ } END { print count + 0 }'
}
record_check() {
    local action20f_check_label=$1

    shift
    if "$@"; then
        printf '%s_check_%s=true\n' "$prefix" "$action20f_check_label"
        return 0
    fi
    printf '%s_check_%s=false\n' "$prefix" "$action20f_check_label" >&2
    return 1
}
safe_stream() {
    local action20f_stream_path=$1

    [[ "$(wc -c <"$action20f_stream_path")" -le "$maximum_stream_bytes" ]] || return 1
    [[ "$(line_count "$action20f_stream_path")" -le "$maximum_stream_lines" ]] || return 1
    ! LC_ALL=C grep -n '[^[:print:][:space:]]' "$action20f_stream_path" >/dev/null || return 1
    ! grep -Eqi \
        'BEGIN [A-Z ]*PRIVATE KEY|CADDY_TLS_PRIVATE_KEY_PEM|PRIVATE_KEY=|DOPPLER_TOKEN|Authorization:[[:space:]]*Bearer' \
        "$action20f_stream_path" || return 1
}
emit_stream() {
    local action20f_stream_label=$1
    local action20f_stream_path=$2

    printf '%s_capture_%s_bytes=%s\n' "$prefix" "$action20f_stream_label" \
        "$(wc -c <"$action20f_stream_path")"
    printf '%s_capture_%s_lines=%s\n' "$prefix" "$action20f_stream_label" \
        "$(line_count "$action20f_stream_path")"
    printf '%s_capture_%s_sha256=%s\n' "$prefix" "$action20f_stream_label" \
        "$(file_hash "$action20f_stream_path")"
    printf '%s_capture_%s_classification=bounded_safe\n' "$prefix" \
        "$action20f_stream_label"
    if [[ ! -s "$action20f_stream_path" ]]; then
        printf '%s_capture_%s_content_secured=empty\n' "$prefix" \
            "$action20f_stream_label"
        return 0
    fi
    printf '%s_capture_%s_begin\n' "$prefix" "$action20f_stream_label"
    sed "s/^/${prefix}_capture_${action20f_stream_label}_content=/" \
        "$action20f_stream_path"
    printf '%s_capture_%s_end\n' "$prefix" "$action20f_stream_label"
}
run_probe() {
    local action20f_probe_label=$1
    local action20f_probe_root=$2
    local action20f_probe_stdout=$action20f_probe_root/$action20f_probe_label.stdout
    local action20f_probe_stderr=$action20f_probe_root/$action20f_probe_label.stderr
    local action20f_probe_status=0

    shift 2
    : >"$action20f_probe_stdout"
    : >"$action20f_probe_stderr"
    chmod 0600 "$action20f_probe_stdout" "$action20f_probe_stderr"
    "$@" >"$action20f_probe_stdout" 2>"$action20f_probe_stderr" ||
        action20f_probe_status=$?
    if ! safe_stream "$action20f_probe_stdout" ||
        ! safe_stream "$action20f_probe_stderr"; then
        printf '%s_probe_%s_stream_classification=unsafe_retained\n' \
            "$prefix" "$action20f_probe_label" >&2
        printf '%s_protected_evidence=%s\n' "$prefix" "$action20f_probe_root" >&2
        return 97
    fi
    emit_stream "${action20f_probe_label}_stdout" "$action20f_probe_stdout"
    emit_stream "${action20f_probe_label}_stderr" "$action20f_probe_stderr"
    printf '%s_value_%s_status=%s\n' "$prefix" "$action20f_probe_label" \
        "$action20f_probe_status"
    [[ "$action20f_probe_status" -eq 0 ]]
}
expected_checks() {
    printf '%s\n' \
        identity_root working_directory_root hostname_node_a architecture_arm64 \
        stage_directory_regular stage_directory_not_symlink stage_directory_metadata \
        stage_template_regular stage_template_not_symlink stage_template_metadata \
        candidate_fragment_hash_exact candidate_placeholders_absent \
        candidate_health_user_group_exact candidate_old_health_user_absent \
        main_regular main_not_symlink main_metadata main_hash_exact main_include_absent \
        fragment_regular fragment_not_symlink fragment_metadata fragment_old_hash_exact \
        fragment_old_health_user_exact fragment_new_health_user_absent \
        environment_regular environment_not_symlink environment_metadata \
        environment_hash_exact helper_regular helper_not_symlink helper_metadata \
        helper_hash_exact script_user_identity script_user_uid_exact \
        script_user_primary_gid_exact caddy_tls_group_identity caddy_tls_gid_exact \
        script_user_caddy_tls_membership_exact active_release_exact \
        candidate_context_runtime_metadata \
        candidate_context_environment_access candidate_context_fullchain_access \
        candidate_context_private_key_access candidate_context_caddy_validate \
        candidate_context_curl candidate_context_full_helper \
        candidate_context_runtime_cleanup \
        keepalived_active caddy_active lighttpd_active caddy_ipv4_absent \
        caddy_ipv6_absent dns_ipv4_present dns_ipv6_present backup_root_regular \
        backup_root_not_symlink backup_root_metadata prior_backup_absent \
        prior_install_stage_absent live_fragment_hash_exact \
        live_fragment_health_user_group_exact live_fragment_old_health_user_absent \
        installed_context_runtime_metadata \
        installed_context_environment_access installed_context_fullchain_access \
        installed_context_private_key_access installed_context_caddy_validate \
        installed_context_curl installed_context_full_helper \
        installed_context_runtime_cleanup \
        backup_directory_regular backup_directory_not_symlink backup_directory_metadata \
        backup_fragment_regular backup_fragment_not_symlink backup_fragment_metadata \
        backup_fragment_hash_exact backup_manifest_regular backup_manifest_not_symlink \
        backup_manifest_metadata backup_manifest_exact main_hash_unchanged \
        caddy_pid_unchanged keepalived_pid_unchanged lighttpd_pid_unchanged \
        keepalived_still_active caddy_still_active lighttpd_still_active \
        caddy_ipv4_still_absent caddy_ipv6_still_absent dns_ipv4_still_present \
        dns_ipv6_still_present install_stage_absent
}
render_candidate() {
    local action20f_template_path=$1
    local action20f_candidate_path=$2

    sed \
        -e 's|@NODE_IPV4@|10.1.0.53|g' \
        -e 's|@NODE_IPV6@|fd36:5aa8:6971:1::53|g' \
        -e 's|@PEER_IPV4@|10.1.0.54|g' \
        -e 's|@PEER_IPV6@|fd36:5aa8:6971:1::54|g' \
        -e 's|@CADDY_PRIORITY@|140|g' \
        -e 's|@NETWORK_INTERFACE@|eth0|g' \
        "$action20f_template_path" >"$action20f_candidate_path"
    chmod 0600 "$action20f_candidate_path"
}
run_exact_context_checks() {
    local action20f_phase=$1
    local action20f_probe_root=$2
    local action20f_script_uid=$3
    local action20f_tls_gid=$4
    local action20f_runtime_metadata
    local -a action20f_setpriv=(
        setpriv --reuid "$action20f_script_uid" --regid "$action20f_tls_gid" --clear-groups --
    )

    context_runtime_root=$(mktemp -d /tmp/caddy-action20f-context.XXXXXX) || return 1
    chown "$action20f_script_uid:$action20f_tls_gid" "$context_runtime_root" || return 1
    chmod 0700 "$context_runtime_root" || return 1
    install -d -o "$action20f_script_uid" -g "$action20f_tls_gid" -m 0700 \
        "$context_runtime_root/home" "$context_runtime_root/config" \
        "$context_runtime_root/data" || return 1
    action20f_runtime_metadata=$(stat -c '%u:%g:%a' "$context_runtime_root")
    record_check "${action20f_phase}_context_runtime_metadata" test \
        "$action20f_runtime_metadata" = \
        "$action20f_script_uid:$action20f_tls_gid:700" || return 1

    record_check "${action20f_phase}_context_environment_access" \
        "${action20f_setpriv[@]}" test -r "$environment_file" || return 1
    record_check "${action20f_phase}_context_fullchain_access" \
        "${action20f_setpriv[@]}" test -r "$active_release/tls/fullchain.pem" || return 1
    record_check "${action20f_phase}_context_private_key_access" \
        "${action20f_setpriv[@]}" test -r "$active_release/tls/privkey.pem" || return 1
    record_check "${action20f_phase}_context_caddy_validate" run_probe \
        "${action20f_phase}_context_caddy_validate" "$action20f_probe_root" \
        "${action20f_setpriv[@]}" /usr/bin/env \
        HOME="$context_runtime_root/home" \
        XDG_CONFIG_HOME="$context_runtime_root/config" \
        XDG_DATA_HOME="$context_runtime_root/data" /bin/bash -c \
        'set -a; source /etc/default/caddy-ha; set +a; exec /usr/bin/caddy validate --config /etc/caddy/current/Caddyfile --adapter caddyfile' || return 1
    record_check "${action20f_phase}_context_curl" run_probe \
        "${action20f_phase}_context_curl" "$action20f_probe_root" \
        "${action20f_setpriv[@]}" /usr/bin/curl --insecure --head --fail \
        --silent --show-error --max-time 3 https://localhost || return 1
    record_check "${action20f_phase}_context_full_helper" run_probe \
        "${action20f_phase}_context_full_helper" "$action20f_probe_root" \
        "${action20f_setpriv[@]}" /bin/bash "$health_helper" || return 1
    rm -rf -- "$context_runtime_root" || return 1
    record_check "${action20f_phase}_context_runtime_cleanup" test \
        ! -e "$context_runtime_root" || return 1
    context_runtime_root=
}
validate_prestate() {
    local action20f_candidate=$stage_directory/caddy-ha.conf
    local action20f_probe_root=$stage_directory/probes-pre
    local action20f_script_uid
    local action20f_tls_gid

    install -d -o root -g root -m 0700 "$action20f_probe_root"
    record_check identity_root test "$(id -u)" -eq 0 || return 1
    record_check working_directory_root test "$(pwd -P)" = / || return 1
    record_check hostname_node_a test "$(hostname)" = j1-svpihole0 || return 1
    record_check architecture_arm64 test "$(dpkg --print-architecture)" = arm64 || return 1
    record_check stage_directory_regular test -d "$stage_directory" || return 1
    record_check stage_directory_not_symlink test ! -L "$stage_directory" || return 1
    record_check stage_directory_metadata test \
        "$(stat -c '%U:%G:%a' "$stage_directory")" = root:root:700 || return 1
    record_check stage_template_regular test -f "$stage_directory/keepalived-caddy-ha-v2.conf.in" || return 1
    record_check stage_template_not_symlink test ! -L "$stage_directory/keepalived-caddy-ha-v2.conf.in" || return 1
    record_check stage_template_metadata test \
        "$(stat -c '%U:%G:%a' "$stage_directory/keepalived-caddy-ha-v2.conf.in")" = root:root:600 || return 1
    render_candidate "$stage_directory/keepalived-caddy-ha-v2.conf.in" "$action20f_candidate"
    record_check candidate_fragment_hash_exact test \
        "$(file_hash "$action20f_candidate")" = "$candidate_fragment_sha256" || return 1
    record_check candidate_placeholders_absent test \
        "$(grep -Ec '@[A-Z0-9_]+@' "$action20f_candidate" || true)" -eq 0 || return 1
    record_check candidate_health_user_group_exact test \
        "$(grep -Fxc '    user keepalived_script caddy-tls' "$action20f_candidate")" -eq 1 || return 1
    record_check candidate_old_health_user_absent test \
        "$(grep -Fxc '    user keepalived_script' "$action20f_candidate" || true)" -eq 0 || return 1
    record_check main_regular test -f "$main_configuration" || return 1
    record_check main_not_symlink test ! -L "$main_configuration" || return 1
    record_check main_metadata test \
        "$(stat -c '%U:%G:%a' "$main_configuration")" = root:root:644 || return 1
    record_check main_hash_exact test "$(file_hash "$main_configuration")" = "$main_sha256" || return 1
    record_check main_include_absent test \
        "$(grep -Fxc 'include /etc/keepalived/conf.d/caddy-ha.conf' "$main_configuration" || true)" -eq 0 || return 1
    record_check fragment_regular test -f "$fragment" || return 1
    record_check fragment_not_symlink test ! -L "$fragment" || return 1
    record_check fragment_metadata test "$(stat -c '%U:%G:%a' "$fragment")" = root:root:644 || return 1
    record_check fragment_old_hash_exact test "$(file_hash "$fragment")" = "$old_fragment_sha256" || return 1
    record_check fragment_old_health_user_exact test \
        "$(grep -Fxc '    user keepalived_script' "$fragment")" -eq 1 || return 1
    record_check fragment_new_health_user_absent test \
        "$(grep -Fxc '    user keepalived_script caddy-tls' "$fragment" || true)" -eq 0 || return 1
    record_check environment_regular test -f "$environment_file" || return 1
    record_check environment_not_symlink test ! -L "$environment_file" || return 1
    record_check environment_metadata test \
        "$(stat -c '%U:%G:%a' "$environment_file")" = root:caddy-tls:640 || return 1
    record_check environment_hash_exact test "$(file_hash "$environment_file")" = "$environment_sha256" || return 1
    record_check helper_regular test -f "$health_helper" || return 1
    record_check helper_not_symlink test ! -L "$health_helper" || return 1
    record_check helper_metadata test "$(stat -c '%U:%G:%a' "$health_helper")" = root:root:755 || return 1
    record_check helper_hash_exact test "$(file_hash "$health_helper")" = "$health_helper_sha256" || return 1
    record_check script_user_identity getent passwd keepalived_script || return 1
    action20f_script_uid=$(id -u keepalived_script)
    record_check script_user_uid_exact test "$action20f_script_uid" -eq 993 || return 1
    record_check script_user_primary_gid_exact test "$(id -g keepalived_script)" -eq 989 || return 1
    record_check caddy_tls_group_identity getent group caddy-tls || return 1
    action20f_tls_gid=$(getent group caddy-tls | cut -d: -f3)
    record_check caddy_tls_gid_exact test "$action20f_tls_gid" -eq 991 || return 1
    record_check script_user_caddy_tls_membership_exact test \
        "$(id -Gn keepalived_script | tr ' ' '\n' | grep -Fxc caddy-tls)" -eq 1 || return 1
    record_check active_release_exact test "$(readlink -e /etc/caddy/current)" = "$active_release" || return 1
    run_exact_context_checks candidate "$action20f_probe_root" \
        "$action20f_script_uid" "$action20f_tls_gid" || return 1
    record_check keepalived_active systemctl is-active --quiet keepalived || return 1
    record_check caddy_active systemctl is-active --quiet caddy || return 1
    record_check lighttpd_active systemctl is-active --quiet lighttpd || return 1
    record_check caddy_ipv4_absent test "$(address_count -4 "$caddy_ipv4")" -eq 0 || return 1
    record_check caddy_ipv6_absent test "$(address_count -6 "$caddy_ipv6")" -eq 0 || return 1
    record_check dns_ipv4_present test "$(address_count -4 "$dns_ipv4")" -eq 1 || return 1
    record_check dns_ipv6_present test "$(address_count -6 "$dns_ipv6")" -eq 1 || return 1
    record_check backup_root_regular test -d "$backup_root" || return 1
    record_check backup_root_not_symlink test ! -L "$backup_root" || return 1
    record_check backup_root_metadata test "$(stat -c '%U:%G:%a' "$backup_root")" = root:root:700 || return 1
    record_check prior_backup_absent test -z \
        "$(find "$backup_root" -mindepth 1 -maxdepth 1 -name 'action20f-node-a-health-group.*' -print -quit)" || return 1
    record_check prior_install_stage_absent test -z \
        "$(find /etc/keepalived/conf.d -mindepth 1 -maxdepth 1 -name '.caddy-ha.action20f.*' -print -quit)" || return 1
    caddy_pid_before=$(systemctl show caddy.service --property=MainPID --value)
    keepalived_pid_before=$(systemctl show keepalived.service --property=MainPID --value)
    lighttpd_pid_before=$(systemctl show lighttpd.service --property=MainPID --value)
}
validate_backup() {
    record_check backup_directory_regular test -d "$backup_directory" || return 1
    record_check backup_directory_not_symlink test ! -L "$backup_directory" || return 1
    record_check backup_directory_metadata test \
        "$(stat -c '%U:%G:%a' "$backup_directory")" = root:root:700 || return 1
    record_check backup_fragment_regular test -f "$backup_directory/caddy-ha.conf" || return 1
    record_check backup_fragment_not_symlink test ! -L "$backup_directory/caddy-ha.conf" || return 1
    record_check backup_fragment_metadata test \
        "$(stat -c '%U:%G:%a' "$backup_directory/caddy-ha.conf")" = root:root:600 || return 1
    record_check backup_fragment_hash_exact test \
        "$(file_hash "$backup_directory/caddy-ha.conf")" = "$old_fragment_sha256" || return 1
    record_check backup_manifest_regular test -f "$backup_directory/manifest" || return 1
    record_check backup_manifest_not_symlink test ! -L "$backup_directory/manifest" || return 1
    record_check backup_manifest_metadata test \
        "$(stat -c '%U:%G:%a' "$backup_directory/manifest")" = root:root:600 || return 1
    # The positional parameters are intentionally expanded by the child shell.
    # shellcheck disable=SC2016
    record_check backup_manifest_exact /bin/bash -c \
        '[[ $(awk '\''END { print NR }'\'' "$1") -eq 5 ]] && grep -Fxq action=action20f "$1" && grep -Fxq node=node-a "$1" && grep -Fxq "old_fragment_sha256=$2" "$1" && grep -Fxq "candidate_fragment_sha256=$3" "$1" && grep -Fxq "main_sha256=$4" "$1"' \
        _ "$backup_directory/manifest" "$old_fragment_sha256" \
        "$candidate_fragment_sha256" "$main_sha256" || return 1
}
validate_poststate() {
    local action20f_probe_root=$stage_directory/probes-post
    local action20f_script_uid
    local action20f_tls_gid

    install -d -o root -g root -m 0700 "$action20f_probe_root"
    action20f_script_uid=$(id -u keepalived_script)
    action20f_tls_gid=$(getent group caddy-tls | cut -d: -f3)
    record_check live_fragment_hash_exact test "$(file_hash "$fragment")" = "$candidate_fragment_sha256" || return 1
    record_check live_fragment_health_user_group_exact test \
        "$(grep -Fxc '    user keepalived_script caddy-tls' "$fragment")" -eq 1 || return 1
    record_check live_fragment_old_health_user_absent test \
        "$(grep -Fxc '    user keepalived_script' "$fragment" || true)" -eq 0 || return 1
    run_exact_context_checks installed "$action20f_probe_root" \
        "$action20f_script_uid" "$action20f_tls_gid" || return 1
    validate_backup || return 1
    record_check main_hash_unchanged test "$(file_hash "$main_configuration")" = "$main_sha256" || return 1
    record_check caddy_pid_unchanged test \
        "$(systemctl show caddy.service --property=MainPID --value)" = "$caddy_pid_before" || return 1
    record_check keepalived_pid_unchanged test \
        "$(systemctl show keepalived.service --property=MainPID --value)" = "$keepalived_pid_before" || return 1
    record_check lighttpd_pid_unchanged test \
        "$(systemctl show lighttpd.service --property=MainPID --value)" = "$lighttpd_pid_before" || return 1
    record_check keepalived_still_active systemctl is-active --quiet keepalived || return 1
    record_check caddy_still_active systemctl is-active --quiet caddy || return 1
    record_check lighttpd_still_active systemctl is-active --quiet lighttpd || return 1
    record_check caddy_ipv4_still_absent test "$(address_count -4 "$caddy_ipv4")" -eq 0 || return 1
    record_check caddy_ipv6_still_absent test "$(address_count -6 "$caddy_ipv6")" -eq 0 || return 1
    record_check dns_ipv4_still_present test "$(address_count -4 "$dns_ipv4")" -eq 1 || return 1
    record_check dns_ipv6_still_present test "$(address_count -6 "$dns_ipv6")" -eq 1 || return 1
    record_check install_stage_absent test -z \
        "$(find /etc/keepalived/conf.d -mindepth 1 -maxdepth 1 -name '.caddy-ha.action20f.*' -print -quit)" || return 1
}
rollback() {
    local action20f_original_status=$?
    local action20f_rollback_failed=false

    trap - ERR INT TERM EXIT
    [[ -z "$install_stage" ]] || rm -f -- "$install_stage" || action20f_rollback_failed=true
    [[ -z "$context_runtime_root" ]] || rm -rf -- "$context_runtime_root" ||
        action20f_rollback_failed=true
    if [[ "$transaction_complete" == true ]]; then
        return 0
    fi
    if [[ "$mutation_started" != true ]]; then
        exit "$action20f_original_status"
    fi
    printf '%s_rollback_started=true\n' "$prefix" >&2
    if [[ -n "$backup_directory" && -f "$backup_directory/caddy-ha.conf" ]]; then
        install -o root -g root -m 0644 "$backup_directory/caddy-ha.conf" "$fragment" ||
            action20f_rollback_failed=true
    else
        action20f_rollback_failed=true
    fi
    [[ "$(file_hash "$fragment")" = "$old_fragment_sha256" ]] || action20f_rollback_failed=true
    [[ "$(file_hash "$main_configuration")" = "$main_sha256" ]] || action20f_rollback_failed=true
    [[ "$(systemctl show keepalived.service --property=MainPID --value)" = "$keepalived_pid_before" ]] ||
        action20f_rollback_failed=true
    if [[ "$action20f_rollback_failed" == true ]]; then
        printf '%s_rollback_complete=false\n' "$prefix" >&2
        printf '%s_manual_intervention_required=true\n' "$prefix" >&2
        exit 125
    fi
    printf '%s_rollback_complete=true\n' "$prefix" >&2
    exit "$action20f_original_status"
}
write_success_fixture() {
    local action20f_fixture_label
    local action20f_fixture_capture

    while IFS= read -r action20f_fixture_label; do
        printf '%s_check_%s=true\n' "$prefix" "$action20f_fixture_label"
    done < <(expected_checks)
    for action20f_fixture_capture in \
        candidate_context_caddy_validate_stdout candidate_context_caddy_validate_stderr \
        candidate_context_curl_stdout candidate_context_curl_stderr \
        candidate_context_full_helper_stdout candidate_context_full_helper_stderr \
        installed_context_caddy_validate_stdout installed_context_caddy_validate_stderr \
        installed_context_curl_stdout installed_context_curl_stderr \
        installed_context_full_helper_stdout installed_context_full_helper_stderr; do
        printf '%s\n' \
            "${prefix}_capture_${action20f_fixture_capture}_bytes=0" \
            "${prefix}_capture_${action20f_fixture_capture}_lines=0" \
            "${prefix}_capture_${action20f_fixture_capture}_sha256=e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855" \
            "${prefix}_capture_${action20f_fixture_capture}_classification=bounded_safe" \
            "${prefix}_capture_${action20f_fixture_capture}_content_secured=empty"
    done
    printf '%s\n' \
        "${prefix}_preflight_complete=true" \
        "${prefix}_backup_path=/var/backups/caddy-ha/action20f-node-a-health-group.FIXTURE" \
        "${prefix}_mutation_started=true" \
        "${prefix}_fragment_installed=true" \
        "${prefix}_main_configuration_mutated=false" \
        "${prefix}_keepalived_reloaded=false" \
        "${prefix}_keepalived_restarted=false" \
        "${prefix}_health_context_validated=true" \
        "${prefix}_service_mutations=false" \
        "${prefix}_vrrp_transition_requested=false" \
        "${prefix}_vip_mutations=false" \
        "${prefix}_node_b_contacted=false" \
        "${prefix}_persistent_mutation_scope=fragment,rollback_backup" \
        "${prefix}_install_complete=true"
}

case "${1:-}" in
    --expected-checks)
        [[ $# -eq 1 ]] || exit 64
        expected_checks
        exit 0
        ;;
    --self-test)
        [[ $# -eq 1 ]] || exit 64
        [[ "$old_fragment_sha256" =~ ^[0-9a-f]{64}$ ]]
        [[ "$candidate_fragment_sha256" =~ ^[0-9a-f]{64}$ ]]
        [[ "$(expected_checks | wc -l)" -eq "$(expected_checks | LC_ALL=C sort -u | wc -l)" ]]
        printf '%s_self_test_complete=true\n' "$prefix"
        exit 0
        ;;
    --success-fixture)
        [[ $# -eq 1 ]] || exit 64
        write_success_fixture
        exit 0
        ;;
    --stage)
        [[ $# -eq 2 ]] || exit 64
        stage_directory=$2
        ;;
    *)
        printf 'Usage: %s --expected-checks|--self-test|--success-fixture|--stage DIRECTORY\n' "${0##*/}" >&2
        exit 64
        ;;
esac

trap rollback ERR INT TERM EXIT
validate_prestate
printf '%s_preflight_complete=true\n' "$prefix"

backup_directory=$(mktemp -d "$backup_root/action20f-node-a-health-group.XXXXXX")
chmod 0700 "$backup_directory"
install -o root -g root -m 0600 "$fragment" "$backup_directory/caddy-ha.conf"
printf '%s\n' \
    'action=action20f' \
    'node=node-a' \
    "old_fragment_sha256=$old_fragment_sha256" \
    "candidate_fragment_sha256=$candidate_fragment_sha256" \
    "main_sha256=$main_sha256" >"$backup_directory/manifest"
chmod 0600 "$backup_directory/manifest"
validate_backup
printf '%s_backup_path=%s\n' "$prefix" "$backup_directory"

mutation_started=true
printf '%s_mutation_started=true\n' "$prefix"
install_stage=$(mktemp /etc/keepalived/conf.d/.caddy-ha.action20f.XXXXXX)
install -o root -g root -m 0644 "$stage_directory/caddy-ha.conf" "$install_stage"
mv -- "$install_stage" "$fragment"
install_stage=

validate_poststate
transaction_complete=true
trap - ERR INT TERM EXIT
printf '%s_fragment_installed=true\n' "$prefix"
printf '%s_main_configuration_mutated=false\n' "$prefix"
printf '%s_keepalived_reloaded=false\n' "$prefix"
printf '%s_keepalived_restarted=false\n' "$prefix"
printf '%s_health_context_validated=true\n' "$prefix"
printf '%s_service_mutations=false\n' "$prefix"
printf '%s_vrrp_transition_requested=false\n' "$prefix"
printf '%s_vip_mutations=false\n' "$prefix"
printf '%s_node_b_contacted=false\n' "$prefix"
printf '%s_persistent_mutation_scope=fragment,rollback_backup\n' "$prefix"
printf '%s_install_complete=true\n' "$prefix"
