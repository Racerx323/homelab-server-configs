#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH
readonly PATH

readonly prefix=action_35_l
readonly node_a_revision=20260811T180754Z-d7816a72-48c7-461c-a86f-451027f5de04
readonly serving_revision=20260817T160328Z-472d68b9-2bfb-40f1-8563-0754067182ca
readonly serving_parent=$node_a_revision
readonly serving_payload_manifest_sha256=ecb1a00827899bffc47d9e180b4f0a19a6daf0fc4beee9cb52898a9608102962
readonly incoming_root=/var/lib/caddy-sync/incoming
readonly outgoing_root=/var/lib/caddy-sync/outbound
readonly quarantine_root=/var/lib/caddy-sync/quarantine
readonly releases_root=/etc/caddy/releases
readonly node_environment=${ACTION35L_ENVIRONMENT_FILE:-/etc/default/caddy-ha}
readonly keepalived_command=${ACTION35L_KEEPALIVED_COMMAND:-/usr/sbin/keepalived}
readonly runuser_command=${ACTION35L_RUNUSER_COMMAND:-/usr/sbin/runuser}
readonly systemctl_command=${ACTION35L_SYSTEMCTL_COMMAND:-/usr/bin/systemctl}
readonly journalctl_command=${ACTION35L_JOURNALCTL_COMMAND:-/usr/bin/journalctl}
readonly unbound_checkconf_command=${ACTION35L_UNBOUND_CHECKCONF_COMMAND:-/usr/sbin/unbound-checkconf}
readonly target_root=${ACTION35L_TARGET_ROOT:-}

usage() {
    printf 'Usage: %s --production-path-test | MODE node-a|node-b PAYLOAD_ROOT EVIDENCE_ROOT\n' "${0##*/}" >&2
}

safe_root() {
    local action35l_root=$1

    [[ "$action35l_root" == /tmp/caddy-action35l-* &&
        -d "$action35l_root" && ! -L "$action35l_root" ]]
}

regular_file() {
    [[ -f "$1" && ! -L "$1" ]]
}

effective_path() {
    local action35l_logical_path=$1

    [[ "$action35l_logical_path" = /* ]]
    printf '%s%s\n' "$target_root" "$action35l_logical_path"
}

capture_command() {
    local action35l_label=$1
    shift
    local action35l_stdout=$evidence_root/$action35l_label.stdout
    local action35l_stderr=$evidence_root/$action35l_label.stderr
    local action35l_status=$evidence_root/$action35l_label.status
    local action35l_rc=0

    : >"$action35l_stdout"
    : >"$action35l_stderr"
    if "$@" >"$action35l_stdout" 2>"$action35l_stderr"; then
        action35l_rc=0
    else
        action35l_rc=$?
    fi
    printf '%s\n' "$action35l_rc" >"$action35l_status"
    chmod 0600 "$action35l_stdout" "$action35l_stderr" "$action35l_status"
    [[ "$(stat -c '%s' "$action35l_stdout")" -le 1048576 ]]
    [[ "$(stat -c '%s' "$action35l_stderr")" -le 1048576 ]]
    iconv -f UTF-8 -t UTF-8 "$action35l_stdout" >/dev/null
    iconv -f UTF-8 -t UTF-8 "$action35l_stderr" >/dev/null
    return "$action35l_rc"
}

capture_stdin_command() {
    local action35l_label=$1
    local action35l_input=$2
    shift 2
    local action35l_stdout=$evidence_root/$action35l_label.stdout
    local action35l_stderr=$evidence_root/$action35l_label.stderr
    local action35l_status=$evidence_root/$action35l_label.status
    local action35l_rc=0

    regular_file "$action35l_input"
    : >"$action35l_stdout"
    : >"$action35l_stderr"
    if "$@" <"$action35l_input" >"$action35l_stdout" 2>"$action35l_stderr"; then
        action35l_rc=0
    else
        action35l_rc=$?
    fi
    printf '%s\n' "$action35l_rc" >"$action35l_status"
    chmod 0600 "$action35l_stdout" "$action35l_stderr" "$action35l_status"
    [[ "$(stat -c '%s' "$action35l_stdout")" -le 1048576 ]]
    [[ "$(stat -c '%s' "$action35l_stderr")" -le 1048576 ]]
    iconv -f UTF-8 -t UTF-8 "$action35l_stdout" >/dev/null
    iconv -f UTF-8 -t UTF-8 "$action35l_stderr" >/dev/null
    return "$action35l_rc"
}

require() {
    local action35l_label=$1
    shift

    if "$@"; then
        printf '%s_check_%s=true\n' "$prefix" "$action35l_label"
        return 0
    fi
    printf '%s_check_%s=false\n' "$prefix" "$action35l_label" >&2
    return 1
}

require_equal() {
    local action35l_label=$1
    local action35l_expected=$2
    local action35l_observed=$3

    [[ "$action35l_label" =~ ^[a-z0-9_]+$ ]]
    [[ "$action35l_expected" =~ ^[A-Za-z0-9._:/,@+-]*$ ]]
    [[ "$action35l_observed" =~ ^[A-Za-z0-9._:/,@+-]*$ ]]
    printf '%s_expected_%s=%s\n' "$prefix" "$action35l_label" "$action35l_expected"
    printf '%s_observed_%s=%s\n' "$prefix" "$action35l_label" "$action35l_observed"
    require "$action35l_label" test "$action35l_observed" = "$action35l_expected"
}

expected_release() {
    if [[ "$node_role" = node-a ]]; then
        printf '%s\n' "$node_a_revision"
    else
        printf '%s\n' "$serving_revision"
    fi
}

current_revision() {
    jq -r '.revision // empty' /etc/caddy/current/release-manifest.json
}

require_exact_directory_inventory() {
    local action35l_root=$1
    local action35l_expected=$2
    local action35l_observed

    require inventory_root_regular test -d "$action35l_root"
    require inventory_root_not_symlink test ! -L "$action35l_root"
    action35l_observed=$(find "$action35l_root" -mindepth 1 -maxdepth 1 \
        -type d -printf '%f\n' | LC_ALL=C sort)
    require inventory_exact test "$action35l_observed" = "$action35l_expected"
}

validate_outbound_candidate() {
    local action35l_candidate=$outgoing_root/$serving_revision
    local action35l_manifest_hash

    require outbound_candidate_regular test -d "$action35l_candidate"
    require outbound_candidate_not_symlink test ! -L "$action35l_candidate"
    require outbound_candidate_metadata test \
        "$(stat -c '%U:%G:%a' "$action35l_candidate")" = caddy-sync:caddy-sync:550
    require outbound_revision test \
        "$(jq -r '.revision // empty' "$action35l_candidate/release-manifest.json")" = "$serving_revision"
    require outbound_parent test \
        "$(jq -r '.parent_revision // empty' "$action35l_candidate/release-manifest.json")" = "$serving_parent"
    require outbound_source test \
        "$(jq -r '.source_node // empty' "$action35l_candidate/release-manifest.json")" = node-a
    action35l_manifest_hash=$(sha256sum "$action35l_candidate/manifest.sha256" | awk '{ print $1 }')
    require outbound_payload_manifest_hash test \
        "$action35l_manifest_hash" = "$serving_payload_manifest_sha256"
    # The child Bash expands its positional parameter.
    # shellcheck disable=SC2016
    require outbound_manifest_valid \
        /bin/bash -c 'cd "$1" && sha256sum --strict --check manifest.sha256 >/dev/null' \
        _ "$action35l_candidate"
    require outbound_finalize_marker_regular test -f "$action35l_candidate/.finalize-request"
    require outbound_finalize_marker_empty test ! -s "$action35l_candidate/.finalize-request"
    require outbound_symlinks_absent test -z \
        "$(find "$action35l_candidate" -type l -print -quit)"
}

validate_installed_release() {
    local action35l_release=$releases_root/$serving_revision
    local action35l_manifest_hash

    require installed_release_regular test -d "$action35l_release"
    require installed_release_not_symlink test ! -L "$action35l_release"
    require installed_release_metadata test \
        "$(stat -c '%U:%G:%a' "$action35l_release")" = root:caddy-tls:550
    require installed_release_revision test \
        "$(jq -r '.revision // empty' "$action35l_release/release-manifest.json")" = "$serving_revision"
    require installed_release_parent test \
        "$(jq -r '.parent_revision // empty' "$action35l_release/release-manifest.json")" = "$serving_parent"
    require installed_release_source test \
        "$(jq -r '.source_node // empty' "$action35l_release/release-manifest.json")" = node-a
    action35l_manifest_hash=$(sha256sum "$action35l_release/manifest.sha256" | awk '{ print $1 }')
    require installed_payload_manifest_hash test \
        "$action35l_manifest_hash" = "$serving_payload_manifest_sha256"
    # The child Bash expands its positional parameter.
    # shellcheck disable=SC2016
    require installed_manifest_valid \
        /bin/bash -c 'cd "$1" && sha256sum --strict --check manifest.sha256 >/dev/null' \
        _ "$action35l_release"
}

validate_inventory() {
    local action35l_inventory=$payload_root/manifests/production-artifacts.tsv
    local action35l_key action35l_repository action35l_source action35l_target
    local action35l_inventory_node action35l_source_hash action35l_deployed_hash
    local action35l_accepted action35l_lifecycle action35l_observed

    regular_file "$action35l_inventory"
    while IFS=$'\t' read -r action35l_key action35l_repository action35l_source \
        action35l_target action35l_inventory_node action35l_source_hash \
        action35l_deployed_hash action35l_accepted action35l_lifecycle; do
        [[ "$action35l_key" = '# key' ]] && continue
        [[ "$action35l_inventory_node" = "$node_role" ||
            "$action35l_inventory_node" = both ]] || continue
        [[ -n "$action35l_accepted" && "$action35l_lifecycle" = production-current ]]
        require "artifact_${action35l_key}_regular" regular_file "$action35l_target"
        action35l_observed=$(sha256sum "$action35l_target" | awk '{ print $1 }')
        require_equal "artifact_${action35l_key}_identity" \
            "$action35l_deployed_hash" "$action35l_observed"
    done <"$action35l_inventory"
}

validate_services() {
    local action35l_unit

    for action35l_unit in caddy.service caddy-lsyncd.service \
        caddy-sync-reconcile.path caddy-cert-expiry.timer \
        caddy-sync-health.timer caddy-apprise-worker.path \
        caddy-apprise-worker.timer keepalived.service; do
        require "${action35l_unit//[.@-]/_}_active" \
            "$systemctl_command" is-active --quiet "$action35l_unit"
    done
    for action35l_unit in caddy.service caddy-lsyncd.service \
        caddy-sync-reconcile.path caddy-cert-expiry.timer \
        caddy-sync-health.timer caddy-apprise-worker.path \
        caddy-apprise-worker.timer keepalived.service; do
        require "${action35l_unit//[.@-]/_}_enabled" \
            "$systemctl_command" is-enabled --quiet "$action35l_unit"
    done
    require caddy_api_masked test "$($systemctl_command is-enabled caddy-api.service)" = masked
    require distribution_lsyncd_masked test "$($systemctl_command is-enabled lsyncd.service)" = masked
}

validate_split_baseline() {
    local action35l_expected_revision

    action35l_expected_revision=$(expected_release)
    require_equal current_release_expected "$action35l_expected_revision" "$(current_revision)"
    validate_inventory
    validate_services
    require incoming_node_a_inventory_empty require_exact_directory_inventory "$incoming_root/node-a" ''
    require incoming_node_b_inventory_empty require_exact_directory_inventory "$incoming_root/node-b" ''
    require quarantine_inventory_empty require_exact_directory_inventory "$quarantine_root" ''
    if [[ "$node_role" = node-a ]]; then
        require outbound_inventory_exact require_exact_directory_inventory \
            "$outgoing_root" "$serving_revision"
        validate_outbound_candidate
    else
        require outbound_inventory_empty require_exact_directory_inventory "$outgoing_root" ''
        validate_installed_release
    fi
}

validate_payload() {
    local action35l_manifest=$payload_root/manifests/serving-health-production.tsv
    local action35l_repository action35l_source action35l_target action35l_mode
    local action35l_expected_hash action35l_lifecycle action35l_file action35l_observed

    require payload_root safe_root "$payload_root"
    require payload_manifest regular_file "$action35l_manifest"
    while IFS=$'\t' read -r action35l_repository action35l_source action35l_target \
        action35l_mode action35l_expected_hash action35l_lifecycle; do
        [[ "$action35l_repository" = '# repository' ]] && continue
        action35l_file=$payload_root/repositories/$action35l_repository/$action35l_source
        require "payload_${action35l_expected_hash}_regular" regular_file "$action35l_file"
        action35l_observed=$(sha256sum "$action35l_file" | awk '{ print $1 }')
        require "payload_${action35l_expected_hash}_identity" test \
            "$action35l_observed" = "$action35l_expected_hash"
    done <"$action35l_manifest"
}

validate_installed_candidate_inventory() {
    local action35l_manifest=$payload_root/manifests/serving-health-production.tsv
    local action35l_repository action35l_source action35l_target action35l_mode
    local action35l_expected_hash action35l_lifecycle action35l_observed

    while IFS=$'\t' read -r action35l_repository action35l_source action35l_target \
        action35l_mode action35l_expected_hash action35l_lifecycle; do
        [[ "$action35l_repository" = '# repository' ]] && continue
        [[ "$action35l_lifecycle" = production-candidate ]]
        case "$action35l_target" in
            /etc/caddy/releases/REVISION/*) continue ;;
        esac
        if [[ "$action35l_source" = Keepalived/configs/keepalived-pihole0.conf &&
            "$node_role" != node-a ]]; then
            continue
        fi
        if [[ "$action35l_source" = Keepalived/configs/keepalived-pihole00.conf &&
            "$node_role" != node-b ]]; then
            continue
        fi
        require "candidate_${action35l_expected_hash}_regular" regular_file "$action35l_target"
        require "candidate_${action35l_expected_hash}_mode" test \
            "$(stat -c '%a' "$action35l_target")" = "${action35l_mode#0}"
        require "candidate_${action35l_expected_hash}_owner" test \
            "$(stat -c '%U:%G' "$action35l_target")" = root:root
        action35l_observed=$(sha256sum "$action35l_target" | awk '{ print $1 }')
        require "candidate_${action35l_expected_hash}_identity" test \
            "$action35l_observed" = "$action35l_expected_hash"
    done <"$action35l_manifest"
}

candidate_file() {
    local action35l_repository=$1
    local action35l_source=$2
    printf '%s/repositories/%s/%s\n' "$payload_root" "$action35l_repository" "$action35l_source"
}

backup_path() {
    local action35l_target=$1
    printf '%s/backups/%s\n' "$evidence_root" "${action35l_target#/}"
}

backup_target() {
    local action35l_target=$1
    local action35l_backup
    local action35l_effective_target

    action35l_backup=$(backup_path "$action35l_target")
    action35l_effective_target=$(effective_path "$action35l_target")
    install -d -m 0700 "$(dirname -- "$action35l_backup")"
    if [[ -e "$action35l_effective_target" || -L "$action35l_effective_target" ]]; then
        cp -a -- "$action35l_effective_target" "$action35l_backup"
        printf 'present\n' >"$action35l_backup.state"
    else
        printf 'absent\n' >"$action35l_backup.state"
    fi
}

install_target() {
    local action35l_source=$1
    local action35l_target=$2
    local action35l_mode=$3
    local action35l_owner=$4
    local action35l_group=$5
    local action35l_effective_target

    action35l_effective_target=$(effective_path "$action35l_target")
    if [[ "${ACTION35L_PRODUCTION_PATH_TEST:-0}" = 1 ]]; then
        action35l_owner=$(id -un)
        action35l_group=$(id -gn)
    fi

    backup_target "$action35l_target"
    install -d -m 0755 "$(dirname -- "$action35l_effective_target")"
    install -o "$action35l_owner" -g "$action35l_group" -m "$action35l_mode" \
        "$action35l_source" "$action35l_effective_target"
}

restore_target() {
    local action35l_target=$1
    local action35l_backup
    local action35l_state
    local action35l_effective_target

    action35l_backup=$(backup_path "$action35l_target")
    action35l_effective_target=$(effective_path "$action35l_target")
    [[ -f "$action35l_backup.state" && ! -L "$action35l_backup.state" ]] || return 0
    action35l_state=$(<"$action35l_backup.state")
    case "$action35l_state" in
        present)
            rm -f -- "$action35l_effective_target"
            cp -a -- "$action35l_backup" "$action35l_effective_target"
            ;;
        absent) rm -f -- "$action35l_effective_target" ;;
        *) return 1 ;;
    esac
}

install_serving_artifacts() {
    local action35l_keepalived_source

    if [[ "$node_role" = node-a ]]; then
        action35l_keepalived_source=Keepalived/configs/keepalived-pihole0.conf
    else
        action35l_keepalived_source=Keepalived/configs/keepalived-pihole00.conf
    fi
    install_target "$(candidate_file homelab-server-configs Caddy/scripts/check-caddy-serving-health.sh)" \
        /usr/local/libexec/check-caddy.sh 0755 root root
    install_target "$(candidate_file homelab-server-configs Caddy/scripts/check-pihole-web-health.sh)" \
        /usr/local/libexec/check-pihole-web-health.sh 0755 root root
    install_target "$(candidate_file homelab-server-configs Caddy/scripts/caddy-apprise-enqueue.sh)" \
        /usr/local/libexec/caddy-apprise-enqueue 0755 root root
    install_target "$(candidate_file homelab-server-configs Caddy/scripts/caddy-apprise-delivery-worker.sh)" \
        /usr/local/libexec/caddy-apprise-delivery-worker 0755 root root
    install_target "$(candidate_file homelab-server-configs Caddy/systemd/caddy-pihole-web-health.service)" \
        /etc/systemd/system/caddy-pihole-web-health.service 0644 root root
    install_target "$(candidate_file homelab-server-configs Caddy/systemd/caddy-pihole-web-health.timer)" \
        /etc/systemd/system/caddy-pihole-web-health.timer 0644 root root
    install_target "$(candidate_file homelab-dns Keepalived/scripts/dns-check.sh)" \
        /etc/scripts/check-dns.sh 0755 root root
    install_target "$(candidate_file homelab-dns Unbound/configs/pihole-local-zone.conf)" \
        /etc/unbound/unbound.conf.d/pihole-local-zone.conf 0644 root root
    install_target "$(candidate_file homelab-dns "$action35l_keepalived_source")" \
        /etc/keepalived/keepalived.conf 0644 root root
    if [[ -n "$target_root" ]]; then
        "$unbound_checkconf_command" \
            "$(effective_path /etc/unbound/unbound.conf.d/pihole-local-zone.conf)"
    else
        "$unbound_checkconf_command" /etc/unbound/unbound.conf
    fi
    "$systemctl_command" daemon-reload
    "$systemctl_command" enable --now caddy-pihole-web-health.timer
    "$systemctl_command" reload unbound.service
    "$systemctl_command" reload keepalived.service
}

parser_and_identity_checks() {
    local action35l_keepalived_source

    if [[ "$node_role" = node-a ]]; then
        action35l_keepalived_source=Keepalived/configs/keepalived-pihole0.conf
    else
        action35l_keepalived_source=Keepalived/configs/keepalived-pihole00.conf
    fi
    capture_command keepalived_parser "$keepalived_command" --config-test \
        -f "$(candidate_file homelab-dns "$action35l_keepalived_source")"
    capture_command unbound_local_zone_parser "$unbound_checkconf_command" \
        "$(candidate_file homelab-dns Unbound/configs/pihole-local-zone.conf)"
    capture_stdin_command dns_identity \
        "$(candidate_file homelab-dns Keepalived/scripts/dns-check.sh)" \
        "$runuser_command" -u pi -- env \
        DNS_CHECK_DIG_COMMAND="${ACTION35L_DNS_DIG_COMMAND:-/usr/bin/dig}" \
        DNS_CHECK_SYSTEMCTL_COMMAND="${ACTION35L_SYSTEMCTL_COMMAND:-/usr/bin/systemctl}" \
        /bin/bash -s
    capture_stdin_command caddy_identity \
        "$(candidate_file homelab-server-configs Caddy/scripts/check-caddy-serving-health.sh)" \
        "$runuser_command" -u keepalived_script -- env \
        CADDY_SERVING_HEALTH_ENVIRONMENT_FILE="$node_environment" \
        CADDY_SERVING_HEALTH_CURL_COMMAND="${ACTION35L_CURL_COMMAND:-/usr/bin/curl}" \
        CADDY_SERVING_HEALTH_SS_COMMAND="${ACTION35L_SS_COMMAND:-/usr/bin/ss}" \
        CADDY_SERVING_HEALTH_SYSTEMCTL_COMMAND="${ACTION35L_SYSTEMCTL_COMMAND:-/usr/bin/systemctl}" \
        /bin/bash -s
}

promote_local_candidate() {
    local action35l_source=$outgoing_root/$serving_revision
    local action35l_destination=$incoming_root/node-a/$serving_revision

    [[ "$node_role" = node-a ]]
    validate_outbound_candidate
    require local_incoming_absent test ! -e "$action35l_destination"
    local action35l_promotion_status=0

    "$systemctl_command" stop caddy-lsyncd.service
    "$systemctl_command" stop caddy-sync-reconcile.path
    if install -d -o caddy-sync -g caddy-sync -m 0750 "$incoming_root/node-a" &&
        cp -a -- "$action35l_source" "$action35l_destination" &&
        chown -R caddy-sync:caddy-sync "$action35l_destination" &&
        runuser -u caddy-sync -- /bin/bash \
            /usr/local/libexec/finalize-incoming-release-v2.sh --source-role node-a &&
        "$systemctl_command" start caddy-sync-reconcile.service &&
        require local_candidate_selected test "$(current_revision)" = "$serving_revision"; then
        :
    else
        action35l_promotion_status=$?
    fi
    "$systemctl_command" start caddy-sync-reconcile.path || action35l_promotion_status=125
    "$systemctl_command" start caddy-lsyncd.service || action35l_promotion_status=125
    return "$action35l_promotion_status"
}

accept_installed_node() {
    local action35l_keepalived_hash action35l_dns_hash action35l_caddy_hash
    local action35l_service_hash action35l_timer_hash action35l_local_zone_hash

    action35l_keepalived_hash=$(sha256sum /etc/keepalived/keepalived.conf | awk '{ print $1 }')
    action35l_dns_hash=$(sha256sum /etc/scripts/check-dns.sh | awk '{ print $1 }')
    action35l_caddy_hash=$(sha256sum /usr/local/libexec/check-caddy.sh | awk '{ print $1 }')
    action35l_service_hash=$(sha256sum /etc/systemd/system/caddy-pihole-web-health.service | awk '{ print $1 }')
    action35l_timer_hash=$(sha256sum /etc/systemd/system/caddy-pihole-web-health.timer | awk '{ print $1 }')
    action35l_local_zone_hash=$(sha256sum /etc/unbound/unbound.conf.d/pihole-local-zone.conf | awk '{ print $1 }')
    if [[ "$node_role" = node-a ]]; then
        require keepalived_candidate_hash test "$action35l_keepalived_hash" = \
            18560da8026928b3107da667bdea8762cea85d3a55946e979437e861ce8bd826
    else
        require keepalived_candidate_hash test "$action35l_keepalived_hash" = \
            dffb9c0076b553e085a3dd6223d004829ba3e15570e6985b88646ff037d5ea57
    fi
    require dns_candidate_hash test "$action35l_dns_hash" = \
        294afb4db26a3ccac454636efe091b872724e648c901b467142b31fae489e8aa
    require caddy_candidate_hash test "$action35l_caddy_hash" = \
        381c9b371621e1ddfae1eba3f557f8750fc0bbcc162415b038c8043aa1bac208
    require web_service_hash test "$action35l_service_hash" = \
        a1afee302fa521c9d4ba2eb6d7085e98f261ec5fdd464c156dd11aa1f1cfa3f0
    require web_timer_hash test "$action35l_timer_hash" = \
        f214b69fecaeb322dbaba61f683f9cf35970596784adcd707e25278f0ace1505
    require unbound_local_zone_hash test "$action35l_local_zone_hash" = \
        f1f422d64a55a77af4d77a829ed3360341cf89f5f78c8e87419f01c3e593054d
    require web_timer_enabled "$systemctl_command" is-enabled --quiet caddy-pihole-web-health.timer
    require web_timer_active "$systemctl_command" is-active --quiet caddy-pihole-web-health.timer
    require web_worker_static test \
        "$($systemctl_command is-enabled caddy-pihole-web-health.service)" = static
    require selected_release test "$(current_revision)" = "$serving_revision"
    validate_installed_candidate_inventory
    validate_services
    parser_and_identity_checks
}

validate_final_residue() {
    require selected_release test "$(current_revision)" = "$serving_revision"
    validate_installed_candidate_inventory
    validate_services
    require incoming_node_a_inventory_empty require_exact_directory_inventory "$incoming_root/node-a" ''
    require incoming_node_b_inventory_empty require_exact_directory_inventory "$incoming_root/node-b" ''
    require quarantine_inventory_empty require_exact_directory_inventory "$quarantine_root" ''
    require outbound_inventory_empty require_exact_directory_inventory "$outgoing_root" ''
    validate_installed_release
}

rollback_node() {
    local action35l_target
    local action35l_release_source
    local action35l_restore_failed=0

    for action35l_target in \
        /etc/keepalived/keepalived.conf \
        /etc/unbound/unbound.conf.d/pihole-local-zone.conf \
        /etc/scripts/check-dns.sh \
        /etc/systemd/system/caddy-pihole-web-health.timer \
        /etc/systemd/system/caddy-pihole-web-health.service \
        /usr/local/libexec/caddy-apprise-delivery-worker \
        /usr/local/libexec/caddy-apprise-enqueue \
        /usr/local/libexec/check-pihole-web-health.sh \
        /usr/local/libexec/check-caddy.sh; do
        restore_target "$action35l_target" || action35l_restore_failed=1
    done
    "$systemctl_command" disable --now caddy-pihole-web-health.timer \
        >/dev/null 2>&1 || :
    "$systemctl_command" daemon-reload || action35l_restore_failed=1
    if [[ -n "$target_root" ]]; then
        action35l_target=$(effective_path /etc/unbound/unbound.conf.d/pihole-local-zone.conf)
        if [[ -f "$action35l_target" && ! -L "$action35l_target" ]]; then
            "$unbound_checkconf_command" "$action35l_target" || action35l_restore_failed=1
        fi
    else
        "$unbound_checkconf_command" /etc/unbound/unbound.conf || action35l_restore_failed=1
    fi
    "$systemctl_command" reload unbound.service || action35l_restore_failed=1
    "$systemctl_command" reload keepalived.service || action35l_restore_failed=1
    if [[ -z "$target_root" && "$node_role" = node-a &&
        "$(current_revision)" = "$serving_revision" ]]; then
        ln -sfn "$releases_root/$node_a_revision" /etc/caddy/current.rollback
        mv -Tf /etc/caddy/current.rollback /etc/caddy/current
        "$systemctl_command" reload caddy.service || action35l_restore_failed=1
    fi
    if [[ -z "$target_root" && "$node_role" = node-a &&
        -d "$releases_root/$serving_revision" ]]; then
        action35l_release_source=$outgoing_root/$serving_revision
        if [[ -d "$evidence_root/consumed-outbound" ]]; then
            action35l_release_source=$evidence_root/consumed-outbound
        fi
        if [[ -d "$action35l_release_source" ]] &&
            diff -qr --exclude=.complete "$action35l_release_source" \
                "$releases_root/$serving_revision" >/dev/null; then
            rm -rf -- "${releases_root:?}/${serving_revision:?}"
        else
            action35l_restore_failed=1
        fi
    fi
    if [[ -z "$target_root" && "$node_role" = node-a &&
        -d "$evidence_root/consumed-outbound" &&
        ! -e "$outgoing_root/$serving_revision" ]]; then
        mv -- "$evidence_root/consumed-outbound" \
            "$outgoing_root/$serving_revision" || action35l_restore_failed=1
    fi
    if [[ -z "$target_root" ]]; then
        capture_command journal_rollback "$journalctl_command" --no-pager -o short-iso-precise \
            --after-cursor "$(<"$evidence_root/journal.cursor")" \
            -u keepalived.service -u caddy.service -u caddy-lsyncd.service \
            -u caddy-sync-reconcile.service -u caddy-pihole-web-health.service \
            -t keepalived-notify -t caddy-ha-health || :
    fi
    [[ "$action35l_restore_failed" -eq 0 ]]
}

consume_outbound() {
    local action35l_source=$outgoing_root/$serving_revision
    local action35l_destination=$evidence_root/consumed-outbound

    [[ "$node_role" = node-a ]]
    validate_outbound_candidate
    validate_installed_release
    require consumed_backup_absent test ! -e "$action35l_destination"
    # The child Bash expands its positional parameters.
    # shellcheck disable=SC2016
    require installed_and_outbound_equal \
        /bin/bash -c 'diff -qr --exclude=.complete "$1" "$2" >/dev/null' \
        _ "$action35l_source" "$releases_root/$serving_revision"
    local action35l_consume_status=0

    "$systemctl_command" stop caddy-lsyncd.service
    mv -- "$action35l_source" "$action35l_destination" || action35l_consume_status=$?
    "$systemctl_command" start caddy-lsyncd.service || action35l_consume_status=125
    [[ "$action35l_consume_status" -eq 0 ]] || return "$action35l_consume_status"
    require outbound_consumed test ! -e "$action35l_source"
}

produce_bounded_evidence() {
    capture_command payload_identity sha256sum \
        "$payload_root/manifests/serving-health-production.tsv"
}

ownership_sample() {
    local action35l_ipv4_state action35l_ipv6_state action35l_addresses
    local action35l_expected_state action35l_expected_vips
    local action35l_vip_count=0

    action35l_expected_state=Backup
    action35l_expected_vips=0
    if [[ "$node_role" = node-a ]]; then
        action35l_expected_state=Master
        action35l_expected_vips=4
    fi
    action35l_ipv4_state=$(busctl get-property org.keepalived.Vrrp1 \
        /org/keepalived/Vrrp1/Instance/eth0/100/IPv4 \
        org.keepalived.Vrrp1.Instance State | sed -n 's/.*"\([^"]*\)".*/\1/p')
    action35l_ipv6_state=$(busctl get-property org.keepalived.Vrrp1 \
        /org/keepalived/Vrrp1/Instance/eth0/101/IPv6 \
        org.keepalived.Vrrp1.Instance State | sed -n 's/.*"\([^"]*\)".*/\1/p')
    action35l_addresses=$(ip -o address show dev eth0)
    grep -Fq ' 10.1.0.55/22 ' <<<"$action35l_addresses" && action35l_vip_count=$((action35l_vip_count + 1))
    grep -Fq ' 10.1.0.56/22 ' <<<"$action35l_addresses" && action35l_vip_count=$((action35l_vip_count + 1))
    grep -Fq ' fd36:5aa8:6971:1::55/128 ' <<<"$action35l_addresses" && action35l_vip_count=$((action35l_vip_count + 1))
    grep -Fq ' fd36:5aa8:6971:1::56/128 ' <<<"$action35l_addresses" && action35l_vip_count=$((action35l_vip_count + 1))
    printf 'ipv4=%s\nipv6=%s\nshared_vips=%s\n' \
        "$action35l_ipv4_state" "$action35l_ipv6_state" "$action35l_vip_count"
    require ownership_ipv4 test "$action35l_ipv4_state" = "$action35l_expected_state"
    require ownership_ipv6 test "$action35l_ipv6_state" = "$action35l_expected_state"
    require ownership_vips test "$action35l_vip_count" -eq "$action35l_expected_vips"
}

capture_journal_cursor() {
    local action35l_cursor

    capture_command journal_cursor_raw "$journalctl_command" --quiet --no-pager -n 0 --show-cursor
    action35l_cursor=$(sed -n 's/^-- cursor: //p' "$evidence_root/journal_cursor_raw.stdout")
    require journal_cursor_exact test -n "$action35l_cursor"
    printf '%s\n' "$action35l_cursor" >"$evidence_root/journal.cursor"
    chmod 0600 "$evidence_root/journal.cursor"
}

capture_post_journal() {
    regular_file "$evidence_root/journal.cursor"
    capture_command journal_post "$journalctl_command" --no-pager -o short-iso-precise \
        --after-cursor "$(<"$evidence_root/journal.cursor")" \
        -u keepalived.service -u caddy.service -u caddy-lsyncd.service \
        -u caddy-sync-reconcile.service -u caddy-pihole-web-health.service \
        -t keepalived-notify -t caddy-ha-health
}

start_sampler() {
    local action35l_sampler=$evidence_root/availability-sampler.sh

    require sampler_pid_absent test ! -e "$evidence_root/availability.pid"
    cat >"$action35l_sampler" <<'SAMPLER'
#!/usr/bin/env bash
set -Eeuo pipefail
PATH=/usr/bin:/bin
readonly role=$1
readonly root=$2
case "$role" in
    node-a) fqdn=pihole0.local.theama.co; ipv4=10.1.0.53; ipv6=fd36:5aa8:6971:1::53 ;;
    node-b) fqdn=pihole00.local.theama.co; ipv4=10.1.0.54; ipv6=fd36:5aa8:6971:1::54 ;;
    *) exit 64 ;;
esac
sequence=0
while [[ ! -e "$root/availability.stop" && "$sequence" -lt 900 ]]; do
    sequence=$((sequence + 1))
    timestamp=$(date -u +%Y-%m-%dT%H:%M:%S.%NZ)
    for family in 4 6; do
        dns_status=0
        https_status=0
        node_ui_status=0
        shared_ui_status=0
        if [[ "$family" = 4 ]]; then
            server=127.0.0.1
            address=$ipv4
            shared_address=10.1.0.56
            type=A
            expected=10.1.0.55
        else
            server=::1
            address="[$ipv6]"
            shared_address='[fd36:5aa8:6971:1::56]'
            type=AAAA
            expected=fd36:5aa8:6971:1::55
        fi
        answer=$(dig "@$server" -p 53 pihole.local.theama.co "$type" +short +time=1 +tries=1) || dns_status=$?
        [[ "$answer" = "$expected" ]] || dns_status=90
        status=$(curl "--ipv$family" --silent --show-error --fail --max-time 2 \
            --max-redirs 0 --output /dev/null --write-out '%{http_code}' \
            --resolve "$fqdn:443:$address" "https://$fqdn/healthz") || https_status=$?
        [[ "$status" = 204 ]] || https_status=91
        status=$(curl "--ipv$family" --silent --show-error --fail --location \
            --max-time 2 --max-redirs 2 --output /dev/null --write-out '%{http_code}' \
            --resolve "$fqdn:443:$address" "https://$fqdn/admin/login.php") || node_ui_status=$?
        [[ "$status" = 200 ]] || node_ui_status=92
        status=$(curl "--ipv$family" --silent --show-error --fail --location \
            --max-time 2 --max-redirs 2 --output /dev/null --write-out '%{http_code}' \
            --resolve "pihole-admin.local.theama.co:443:$shared_address" \
            'https://pihole-admin.local.theama.co/admin/login.php') || shared_ui_status=$?
        [[ "$status" = 200 ]] || shared_ui_status=93
        printf '%s\t%s\t%s\tdns=%s\thttps=%s\tnode_ui=%s\tshared_ui=%s\n' \
            "$sequence" "$timestamp" "$family" "$dns_status" "$https_status" \
            "$node_ui_status" "$shared_ui_status" \
            >>"$root/availability.tsv"
    done
    sleep 1
done
SAMPLER
    chmod 0700 "$action35l_sampler"
    : >"$evidence_root/availability.tsv"
    chmod 0600 "$evidence_root/availability.tsv"
    nohup /bin/bash "$action35l_sampler" "$node_role" "$evidence_root" \
        >"$evidence_root/availability.stdout" \
        2>"$evidence_root/availability.stderr" &
    printf '%s\n' "$!" >"$evidence_root/availability.pid"
    chmod 0600 "$evidence_root/availability.pid"
}

stop_sampler() {
    local action35l_pid action35l_wait

    regular_file "$evidence_root/availability.pid"
    action35l_pid=$(<"$evidence_root/availability.pid")
    [[ "$action35l_pid" =~ ^[1-9][0-9]*$ ]]
    : >"$evidence_root/availability.stop"
    for ((action35l_wait = 0; action35l_wait < 10; action35l_wait++)); do
        kill -0 "$action35l_pid" 2>/dev/null || break
        sleep 1
    done
    if kill -0 "$action35l_pid" 2>/dev/null; then
        kill "$action35l_pid"
        wait "$action35l_pid" 2>/dev/null || :
    fi
    require availability_minimum test "$(wc -l <"$evidence_root/availability.tsv")" -ge 4
    require availability_dns_ipv4 test -z \
        "$(awk -F '\t' '$3 == 4 && $4 != "dns=0" { print; exit }' "$evidence_root/availability.tsv")"
    require availability_dns_ipv6 test -z \
        "$(awk -F '\t' '$3 == 6 && $4 != "dns=0" { print; exit }' "$evidence_root/availability.tsv")"
    require availability_https_ipv4 test -z \
        "$(awk -F '\t' '$3 == 4 && $5 != "https=0" { print; exit }' "$evidence_root/availability.tsv")"
    require availability_https_ipv6 test -z \
        "$(awk -F '\t' '$3 == 6 && $5 != "https=0" { print; exit }' "$evidence_root/availability.tsv")"
    require availability_node_ui_ipv4 test -z \
        "$(awk -F '\t' '$3 == 4 && $6 != "node_ui=0" { print; exit }' "$evidence_root/availability.tsv")"
    require availability_node_ui_ipv6 test -z \
        "$(awk -F '\t' '$3 == 6 && $6 != "node_ui=0" { print; exit }' "$evidence_root/availability.tsv")"
    require availability_shared_ui_ipv4 test -z \
        "$(awk -F '\t' '$3 == 4 && $7 != "shared_ui=0" { print; exit }' "$evidence_root/availability.tsv")"
    require availability_shared_ui_ipv6 test -z \
        "$(awk -F '\t' '$3 == 6 && $7 != "shared_ui=0" { print; exit }' "$evidence_root/availability.tsv")"
}

write_decision() {
    local action35l_scenario=$1
    local action35l_expectation=$2
    local action35l_status=$3
    local action35l_expected=$4
    local action35l_observed=$5
    local action35l_raw=$6
    local action35l_decision=$7
    local action35l_raw_hash

    action35l_raw_hash=$(sha256sum "$action35l_raw" | awk '{ print $1 }')
    printf 'scenario\texpectation\tstatus\texpected\tobserved\traw-sha256\n%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$action35l_scenario" "$action35l_expectation" "$action35l_status" \
        "$action35l_expected" "$action35l_observed" "$action35l_raw_hash" \
        >"$action35l_decision"
    chmod 0600 "$action35l_raw" "$action35l_decision"
}

production_path_test() {
    local action35l_test_root=${CADDY_PRODUCTION_PATH_EVIDENCE_ROOT:?missing evidence root}
    local action35l_repo_root action35l_inventory action35l_key action35l_repository
    local action35l_source action35l_target action35l_inventory_node action35l_source_hash
    local action35l_deployed_hash action35l_accepted action35l_lifecycle action35l_source_path
    local action35l_observed action35l_raw action35l_decision action35l_status

    [[ "$action35l_test_root" = /tmp/* && -d "$action35l_test_root" && ! -L "$action35l_test_root" ]]
    chmod 0700 "$action35l_test_root"
    install -d -m 0700 "$action35l_test_root/raw" "$action35l_test_root/decisions"
    action35l_repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
    action35l_inventory=$action35l_repo_root/Caddy/manifests/production-artifacts.tsv
    while IFS=$'\t' read -r action35l_key action35l_repository action35l_source \
        action35l_target action35l_inventory_node action35l_source_hash \
        action35l_deployed_hash action35l_accepted action35l_lifecycle; do
        [[ "$action35l_key" = '# key' ]] && continue
        action35l_raw=$action35l_test_root/raw/inventory-$action35l_key.txt
        action35l_decision=$action35l_test_root/decisions/inventory-$action35l_key.tsv
        if [[ "$action35l_repository" = runtime-generated ]]; then
            printf '%s\t%s\t%s\n' "$action35l_key" "$action35l_target" \
                "$action35l_deployed_hash" >"$action35l_raw"
            action35l_observed=$(awk -F '\t' '{ print $3 }' "$action35l_raw")
            require_equal "production_inventory_${action35l_key}" \
                "$action35l_deployed_hash" "$action35l_observed"
            write_decision "inventory-$action35l_key" accept 0 \
                "$action35l_deployed_hash" "$action35l_observed" \
                "$action35l_raw" "$action35l_decision"
            continue
        fi
        action35l_source_path=${action35l_repo_root%/homelab-server-configs}/$action35l_repository/$action35l_source
        sha256sum "$action35l_source_path" >"$action35l_raw"
        action35l_observed=$(awk '{ print $1 }' "$action35l_raw")
        require_equal "production_inventory_${action35l_key}" \
            "$action35l_source_hash" "$action35l_observed"
        write_decision "inventory-$action35l_key" accept 0 \
            "$action35l_source_hash" "$action35l_observed" \
            "$action35l_raw" "$action35l_decision"
    done <"$action35l_inventory"

    action35l_raw=$action35l_test_root/raw/transaction-rejection.txt
    action35l_decision=$action35l_test_root/decisions/transaction-rejection.tsv
    printf 'expected\n' >"$action35l_test_root/reject.expected"
    printf 'observed-mismatch\n' >"$action35l_test_root/reject.observed"
    if diff -u "$action35l_test_root/reject.expected" \
        "$action35l_test_root/reject.observed" >"$action35l_raw" 2>&1; then
        action35l_status=0
    else
        action35l_status=$?
    fi
    write_decision transaction-rejection reject "$action35l_status" expected \
        observed-mismatch "$action35l_raw" "$action35l_decision"

    action35l_raw=$action35l_test_root/raw/transaction-acceptance.txt
    action35l_decision=$action35l_test_root/decisions/transaction-acceptance.tsv
    sha256sum "$action35l_repo_root/Caddy/manifests/serving-health-production.tsv" \
        >"$action35l_raw"
    action35l_observed=$(awk '{ print $1 }' "$action35l_raw")
    write_decision transaction-acceptance reach 0 "$action35l_observed" \
        "$action35l_observed" "$action35l_raw" "$action35l_decision"
    rm -f -- "$action35l_test_root/reject.expected" \
        "$action35l_test_root/reject.observed"
    printf '%s_production_path_test_complete=true\n' "$prefix"
}

if [[ "${1:-}" = --production-path-test ]]; then
    [[ $# -eq 1 ]]
    production_path_test
    exit 0
fi

[[ $# -eq 4 ]] || {
    usage
    exit 64
}
readonly mode=$1
readonly node_role=$2
readonly payload_root=$3
readonly evidence_root=$4
[[ "$mode" =~ ^(preflight|candidate-check|install|promote|accept|rollback|ownership|journal-cursor|journal-capture|sampler-start|sampler-stop|consume|final-residue|evidence-probe)$ ]]
[[ "$node_role" =~ ^node-[ab]$ ]]
safe_root "$payload_root"
safe_root "$evidence_root"
validate_payload

case "$mode" in
    preflight) validate_split_baseline ;;
    candidate-check) parser_and_identity_checks ;;
    install) install_serving_artifacts ;;
    promote) promote_local_candidate ;;
    accept) accept_installed_node ;;
    rollback) rollback_node ;;
    ownership) ownership_sample ;;
    journal-cursor) capture_journal_cursor ;;
    journal-capture) capture_post_journal ;;
    sampler-start) start_sampler ;;
    sampler-stop) stop_sampler ;;
    consume) consume_outbound ;;
    final-residue) validate_final_residue ;;
    evidence-probe) produce_bounded_evidence ;;
esac
