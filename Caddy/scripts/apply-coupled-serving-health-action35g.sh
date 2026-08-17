#!/usr/bin/env bash
# shellcheck disable=SC2016 # The captured Bash predicate expands only inside its child shell.

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH
readonly PATH

readonly action35g_prefix=action_35g
readonly action35g_expected_manifest_sha256=86f71fba1b126754fa560ddf49f569c2b06f85ab603a9a24f59921d1064da087
readonly action35g_node_evidence=/tmp/caddy-action35g

action35g_node_role=
action35g_payload=
action35g_test_root=
action35g_mode=apply
action35g_mutated=false
action35g_backup=
action35g_preflight=

if [[ "${1:-}" = --production-path-test && $# -eq 1 ]]; then
    action35g_self_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
    readonly action35g_self_directory
    exec /bin/bash "$action35g_self_directory/../tests/coupled-serving-health-deployment-regression.sh" \
        --entrypoint transaction
fi

action35g_usage() {
    printf 'Usage: %s --node-role node-a|node-b --payload DIRECTORY [--production-path-test ROOT]\n' "${0##*/}" >&2
}

action35g_check() {
    local action35g_label=$1

    shift
    if "$@"; then
        printf '%s_check_%s=true\n' "$action35g_prefix" "$action35g_label"
        return 0
    fi
    printf '%s_check_%s=false\n' "$action35g_prefix" "$action35g_label" >&2
    return 1
}

action35g_root_path() {
    local action35g_path=$1

    if [[ -n "$action35g_test_root" ]]; then
        printf '%s%s' "${action35g_test_root%/}" "$action35g_path"
    else
        printf '%s' "$action35g_path"
    fi
}

action35g_systemctl() {
    if [[ -n "$action35g_test_root" ]]; then
        /bin/bash "$action35g_test_root/bin/systemctl" "$@"
    else
        systemctl "$@"
    fi
}

action35g_keepalived_parser() {
    local action35g_config=$1

    if [[ -n "$action35g_test_root" ]]; then
        /bin/bash "$action35g_test_root/bin/keepalived" --config-test --use-file="$action35g_config"
    else
        keepalived --config-test --use-file="$action35g_config"
    fi
}

action35g_ownership_snapshot() {
    if [[ -n "$action35g_test_root" ]]; then
        /bin/bash "$action35g_test_root/bin/ownership" "$action35g_node_role"
        return
    fi
    local action35g_ipv4_state action35g_ipv6_state action35g_vip_count
    action35g_ipv4_state=$(timeout 2 busctl get-property org.keepalived.Vrrp1 \
        /org/keepalived/Vrrp1/Instance/eth0/100/IPv4 org.keepalived.Vrrp1.Instance State)
    action35g_ipv6_state=$(timeout 2 busctl get-property org.keepalived.Vrrp1 \
        /org/keepalived/Vrrp1/Instance/eth0/101/IPv6 org.keepalived.Vrrp1.Instance State)
    case "$action35g_ipv4_state" in
        *'"Master"') action35g_ipv4_state=Master ;;
        *'"Backup"') action35g_ipv4_state=Backup ;;
        *) return 1 ;;
    esac
    case "$action35g_ipv6_state" in
        *'"Master"') action35g_ipv6_state=Master ;;
        *'"Backup"') action35g_ipv6_state=Backup ;;
        *) return 1 ;;
    esac
    action35g_vip_count=$(
        ip -o address show dev eth0 |
            awk '$4 ~ /^(10\.1\.0\.(55|56)\/22|fd36:5aa8:6971:1::(55|56)\/128)$/ { count++ } END { print count + 0 }'
    )
    printf 'ipv4=%s ipv6=%s vip_count=%s\n' \
        "$action35g_ipv4_state" "$action35g_ipv6_state" "$action35g_vip_count"
}

action35g_run_as() {
    local action35g_identity=$1

    shift
    if [[ -n "$action35g_test_root" ]]; then
        {
            printf '%s\t' "$action35g_identity"
            printf '%q ' "$@"
            printf '\n'
        } >>"$action35g_test_root/calls/identities.tsv"
        env \
            DNS_CHECK_DIG_COMMAND="$action35g_test_root/bin/dig" \
            DNS_CHECK_SYSTEMCTL_COMMAND="$action35g_test_root/bin/systemctl" \
            CADDY_SERVING_HEALTH_ENVIRONMENT_FILE="$action35g_test_root/etc/default/caddy-ha" \
            CADDY_SERVING_HEALTH_CURL_COMMAND="$action35g_test_root/bin/curl" \
            CADDY_SERVING_HEALTH_SS_COMMAND="$action35g_test_root/bin/ss" \
            CADDY_SERVING_HEALTH_SYSTEMCTL_COMMAND="$action35g_test_root/bin/systemctl" \
            PIHOLE_WEB_HEALTH_ENVIRONMENT_FILE="$action35g_test_root/etc/default/caddy-ha" \
            PIHOLE_WEB_HEALTH_STATE_DIRECTORY="$action35g_test_root/var/lib/caddy-pihole-web-health" \
            PIHOLE_WEB_HEALTH_RUNTIME_DIRECTORY="$action35g_test_root/run/caddy-pihole-web-health" \
            PIHOLE_WEB_HEALTH_ENQUEUE_COMMAND="$action35g_test_root/bin/enqueue" \
            PIHOLE_WEB_HEALTH_CURL_COMMAND="$action35g_test_root/bin/curl" \
            PIHOLE_WEB_HEALTH_SYSTEMCTL_COMMAND="$action35g_test_root/bin/systemctl" \
            "$@"
    else
        runuser --user "$action35g_identity" -- "$@"
    fi
}

action35g_capture() {
    local action35g_label=$1

    shift
    local action35g_stdout action35g_stderr action35g_status=0
    action35g_stdout=$action35g_evidence/$action35g_label.stdout
    action35g_stderr=$action35g_evidence/$action35g_label.stderr
    : >"$action35g_stdout"
    : >"$action35g_stderr"
    "$@" >"$action35g_stdout" 2>"$action35g_stderr" || action35g_status=$?
    printf '%s\n' "$action35g_status" >"$action35g_evidence/$action35g_label.status"
    [[ -f "$action35g_stdout" && ! -L "$action35g_stdout" ]] || return 1
    [[ -f "$action35g_stderr" && ! -L "$action35g_stderr" ]] || return 1
    return "$action35g_status"
}

action35g_require_regular() {
    local action35g_path=$1
    local action35g_mode=${2:-}

    [[ -f "$action35g_path" && ! -L "$action35g_path" ]] || return 1
    [[ -z "$action35g_mode" || "$(stat -c '%a' "$action35g_path")" = "$action35g_mode" ]]
}

action35g_validate_payload() {
    local action35g_line action35g_repository action35g_source action35g_target
    local action35g_mode action35g_hash action35g_lifecycle action35g_source_path

    action35g_require_regular "$action35g_payload/serving-health-production.tsv" || return 1
    [[ "$(sed -n '1p' "$action35g_payload/serving-health-production.tsv")" = $'# repository\tsource-path\tinstalled-path\tmode\tcandidate-sha256\tlifecycle' ]] || return 1
    while IFS=$'\t' read -r action35g_repository action35g_source action35g_target \
        action35g_mode action35g_hash action35g_lifecycle; do
        [[ -n "$action35g_repository" && "$action35g_repository" != \#* ]] || continue
        [[ "$action35g_repository" =~ ^homelab-(server-configs|dns)$ ]] || return 1
        [[ "$action35g_source" != *..* && "$action35g_target" = /* ]] || return 1
        [[ "$action35g_mode" =~ ^0[0-7]{3}$ && "$action35g_hash" =~ ^[0-9a-f]{64}$ ]] || return 1
        [[ "$action35g_lifecycle" = production-candidate ]] || return 1
        action35g_source_path=$action35g_payload/files/$action35g_repository/$action35g_source
        action35g_require_regular "$action35g_source_path" || return 1
        [[ "$(sha256sum "$action35g_source_path" | awk '{ print $1 }')" = "$action35g_hash" ]] || return 1
        printf '%s\t%s\t%s\n' "$action35g_target" "$action35g_hash" "$action35g_mode" \
            >>"$action35g_evidence/payload-identities.tsv"
        action35g_line=true
    done <"$action35g_payload/serving-health-production.tsv"
    [[ "${action35g_line:-false}" = true ]]
}

action35g_validate_baseline() {
    local action35g_expected_state=$action35g_payload/current-live-state.tsv
    local action35g_current_link
    local action35g_key action35g_repository action35g_source action35g_installed
    local action35g_inventory_node action35g_source_hash action35g_deployed_hash
    local action35g_accepted_action action35g_lifecycle action35g_installed_path

    action35g_require_regular "$action35g_expected_state" || return 1
    action35g_require_regular "$action35g_payload/production-artifacts.tsv" || return 1
    action35g_check baseline_manifest_identity test \
        "$(sha256sum "$action35g_expected_state" | awk '{ print $1 }')" = "$action35g_expected_manifest_sha256" || return 1
    for action35g_unit in caddy.service caddy-lsyncd.service caddy-sync-reconcile.path \
        caddy-apprise-worker.path caddy-apprise-worker.timer keepalived.service \
        pihole-FTL.service unbound.service lighttpd.service; do
        action35g_capture "baseline-${action35g_unit//./-}" \
            action35g_systemctl is-active --quiet "$action35g_unit" || return 1
    done
    for action35g_unit in caddy.service caddy-lsyncd.service caddy-sync-reconcile.path \
        caddy-apprise-worker.path caddy-apprise-worker.timer; do
        action35g_capture "enabled-${action35g_unit//./-}" \
            action35g_systemctl is-enabled --quiet "$action35g_unit" || return 1
    done
    action35g_current_link=$(action35g_root_path /etc/caddy/current)
    [[ -L "$action35g_current_link" ]] || return 1
    readlink -f -- "$action35g_current_link" >"$action35g_evidence/original-release.path"
    action35g_require_regular "$(<"$action35g_evidence/original-release.path")/release-manifest.json" || return 1
    action35g_capture baseline-residue /bin/bash -c \
        'test -z "$(find "$1" -mindepth 1 -maxdepth 1 -name "action35g-*" -print -quit 2>/dev/null)"' \
        _ "$(action35g_root_path /var/lib/caddy-sync/incoming)" || return 1
    while IFS=$'\t' read -r action35g_key action35g_repository action35g_source \
        action35g_installed action35g_inventory_node action35g_source_hash \
        action35g_deployed_hash action35g_accepted_action action35g_lifecycle; do
        [[ -n "$action35g_key" && "$action35g_key" != \#* ]] || continue
        [[ "$action35g_inventory_node" = "$action35g_node_role" ]] || continue
        : "$action35g_repository" "$action35g_source" "$action35g_source_hash"
        [[ "$action35g_lifecycle" = production-current && "$action35g_installed" = /* ]] || return 1
        [[ "$action35g_deployed_hash" =~ ^[0-9a-f]{64}$ ]] || return 1
        action35g_installed_path=$(action35g_root_path "$action35g_installed")
        action35g_require_regular "$action35g_installed_path" || return 1
        [[ "$(sha256sum "$action35g_installed_path" | awk '{ print $1 }')" = "$action35g_deployed_hash" ]] || return 1
        printf '%s\t%s\t%s\n' "$action35g_key" "$action35g_deployed_hash" \
            "$action35g_accepted_action" >>"$action35g_evidence/baseline-identities.tsv"
    done <"$action35g_payload/production-artifacts.tsv"
    printf '%s_check_baseline_complete=true\n' "$action35g_prefix"
}

action35g_validate_candidates() {
    local action35g_keepalived action35g_dns action35g_caddy action35g_web

    action35g_keepalived=$action35g_payload/files/homelab-dns/Keepalived/configs/keepalived-pihole0.conf
    [[ "$action35g_node_role" = node-b ]] &&
        action35g_keepalived=$action35g_payload/files/homelab-dns/Keepalived/configs/keepalived-pihole00.conf
    action35g_dns=$action35g_payload/files/homelab-dns/Keepalived/scripts/dns-check.sh
    action35g_caddy=$action35g_payload/files/homelab-server-configs/Caddy/scripts/check-caddy-serving-health.sh
    action35g_web=$action35g_payload/files/homelab-server-configs/Caddy/scripts/check-pihole-web-health.sh
    action35g_preflight=$(action35g_root_path "/tmp/caddy-action35g-preflight/$action35g_node_role")
    [[ ! -e "$action35g_preflight" ]] || return 1
    install -d -m 0755 "$action35g_preflight/bin" "$action35g_preflight/state" \
        "$action35g_preflight/run"
    install -m 0755 "$action35g_dns" "$action35g_preflight/bin/check-dns.sh"
    install -m 0755 "$action35g_caddy" "$action35g_preflight/bin/check-caddy.sh"
    install -m 0755 "$action35g_web" "$action35g_preflight/bin/check-pihole-web-health.sh"
    action35g_capture keepalived-parser action35g_keepalived_parser "$action35g_keepalived" || return 1
    action35g_capture dns-service-identity action35g_run_as pi \
        /bin/bash "$action35g_preflight/bin/check-dns.sh" || return 1
    action35g_capture caddy-service-identity action35g_run_as keepalived_script \
        /usr/bin/timeout 2 /bin/bash "$action35g_preflight/bin/check-caddy.sh" || return 1
    if [[ -n "$action35g_test_root" ]]; then
        action35g_capture web-service-identity action35g_run_as pi \
            /bin/bash "$action35g_preflight/bin/check-pihole-web-health.sh" || return 1
    else
        chown -R pi:pi "$action35g_preflight/state" "$action35g_preflight/run"
        action35g_capture web-service-identity runuser --user pi -- env \
            PIHOLE_WEB_HEALTH_STATE_DIRECTORY="$action35g_preflight/state" \
            PIHOLE_WEB_HEALTH_RUNTIME_DIRECTORY="$action35g_preflight/run" \
            PIHOLE_WEB_HEALTH_ENQUEUE_COMMAND=/usr/bin/true \
            /bin/bash "$action35g_preflight/bin/check-pihole-web-health.sh" || return 1
    fi
    grep -Fq 'check=127_0_0_1_53_A status=0 answer=10.1.0.55' \
        "$action35g_evidence/dns-service-identity.stdout" || return 1
    grep -Fq 'check=__1_5335_AAAA status=0 answer=fd36:5aa8:6971:1::55' \
        "$action35g_evidence/dns-service-identity.stdout" || return 1
    grep -Fxq 'caddy_serving_health_complete=true' \
        "$action35g_evidence/caddy-service-identity.stdout" || return 1
    find "$action35g_preflight" -xdev -mindepth 1 -delete
    rmdir "$action35g_preflight"
    rmdir "$(dirname -- "$action35g_preflight")" 2>/dev/null || :
    printf '%s_check_candidate_validation_complete=true\n' "$action35g_prefix"
}

action35g_backup_current() {
    local action35g_destination
    local action35g_timer_status=0

    action35g_backup=$(action35g_root_path "/var/backups/caddy-action35g/$action35g_node_role")
    [[ ! -e "$action35g_backup" ]] || return 1
    install -d -m 0700 "$action35g_backup"
    for action35g_destination in /etc/scripts/check-dns.sh /usr/local/libexec/check-caddy.sh \
        /usr/local/libexec/check-pihole-web-health.sh /etc/systemd/system/caddy-pihole-web-health.service \
        /etc/systemd/system/caddy-pihole-web-health.timer /etc/keepalived/keepalived.conf; do
        local action35g_existing
        action35g_existing=$(action35g_root_path "$action35g_destination")
        if [[ -f "$action35g_existing" && ! -L "$action35g_existing" ]]; then
            cp -a -- "$action35g_existing" \
                "$action35g_backup/${action35g_destination//\//_}"
        else
            : >"$action35g_backup/${action35g_destination//\//_}.absent"
        fi
    done
    action35g_systemctl is-enabled --quiet caddy-pihole-web-health.timer ||
        action35g_timer_status=$?
    printf '%s\n' "$action35g_timer_status" >"$action35g_backup/timer-enabled.status"
    action35g_timer_status=0
    action35g_systemctl is-active --quiet caddy-pihole-web-health.timer ||
        action35g_timer_status=$?
    printf '%s\n' "$action35g_timer_status" >"$action35g_backup/timer-active.status"
    printf '%s_check_backup_complete=true\n' "$action35g_prefix"
}

action35g_install_candidates() {
    local action35g_repository action35g_source action35g_target action35g_mode
    local action35g_hash action35g_lifecycle action35g_source_path action35g_destination

    while IFS=$'\t' read -r action35g_repository action35g_source action35g_target \
        action35g_mode action35g_hash action35g_lifecycle; do
        [[ -n "$action35g_repository" && "$action35g_repository" != \#* ]] || continue
        case "$action35g_target" in
            */keepalived.conf)
                [[ "$action35g_node_role" = node-a && "$action35g_source" = *pihole0.conf ]] ||
                    [[ "$action35g_node_role" = node-b && "$action35g_source" = *pihole00.conf ]] || continue
                ;;
            */releases/REVISION/*) continue ;;
        esac
        action35g_source_path=$action35g_payload/files/$action35g_repository/$action35g_source
        action35g_destination=$(action35g_root_path "$action35g_target")
        install -d -m 0755 "$(dirname -- "$action35g_destination")"
        install -m "$action35g_mode" "$action35g_source_path" "$action35g_destination"
        [[ "$(sha256sum "$action35g_destination" | awk '{ print $1 }')" = "$action35g_hash" ]] || return 1
    done <"$action35g_payload/serving-health-production.tsv"
    action35g_mutated=true
    printf '1\n' >"$action35g_evidence/mutation-count"
    action35g_capture daemon-reload action35g_systemctl daemon-reload || return 1
    action35g_capture backend-timer-enable action35g_systemctl enable --now \
        caddy-pihole-web-health.timer || return 1
    action35g_capture keepalived-reload action35g_systemctl reload keepalived.service || return 1
    printf '%s_check_mutation_complete=true\n' "$action35g_prefix"
}

action35g_accept() {
    local action35g_sample
    local action35g_expected_ownership='ipv4=Backup ipv6=Backup vip_count=0'
    local action35g_stable=0

    [[ "$action35g_node_role" = node-b ]] ||
        action35g_expected_ownership='ipv4=Master ipv6=Master vip_count=4'

    for action35g_sample in $(seq 1 30); do
        action35g_capture "post-dns-$action35g_sample" action35g_run_as pi \
            /bin/bash "$(action35g_root_path /etc/scripts/check-dns.sh)" || return 1
        action35g_capture "post-caddy-$action35g_sample" action35g_run_as keepalived_script \
            /usr/bin/timeout 2 /bin/bash "$(action35g_root_path /usr/local/libexec/check-caddy.sh)" || return 1
        action35g_capture "ownership-$action35g_sample" action35g_ownership_snapshot || return 1
        if grep -Fxq "$action35g_expected_ownership" \
            "$action35g_evidence/ownership-$action35g_sample.stdout"; then
            action35g_stable=$((action35g_stable + 1))
        else
            action35g_stable=0
        fi
        [[ "$action35g_stable" -lt 3 ]] || break
        sleep 1
    done
    [[ "$action35g_stable" -eq 3 ]] || return 1
    action35g_capture timer-active action35g_systemctl is-active --quiet \
        caddy-pihole-web-health.timer || return 1
    action35g_capture timer-enabled action35g_systemctl is-enabled --quiet \
        caddy-pihole-web-health.timer || return 1
    if [[ -n "$action35g_test_root" ]]; then
        action35g_capture journal-after-cursor /bin/bash "$action35g_test_root/bin/journalctl" \
            --after-cursor "$(<"$action35g_evidence/journal.cursor")" --no-pager || return 1
    else
        action35g_capture journal-after-cursor journalctl \
            --after-cursor "$(<"$action35g_evidence/journal.cursor")" --no-pager || return 1
    fi
    if grep -Eiq 'simultaneous[_ -]ownership|script.*timed out|unsafe|secret' \
        "$action35g_evidence/journal-after-cursor.stdout"; then
        return 1
    fi
    printf '%s_check_acceptance_complete=true\n' "$action35g_prefix"
}

action35g_rollback() {
    local action35g_destination action35g_saved action35g_absent
    local action35g_temporary

    [[ "$action35g_mutated" = true ]] || return 0
    if [[ "$(<"$action35g_backup/timer-enabled.status")" -ne 0 ]]; then
        action35g_systemctl disable --now caddy-pihole-web-health.timer \
            >/dev/null 2>&1 || return 1
    fi
    for action35g_destination in /etc/scripts/check-dns.sh /usr/local/libexec/check-caddy.sh \
        /usr/local/libexec/check-pihole-web-health.sh /etc/systemd/system/caddy-pihole-web-health.service \
        /etc/systemd/system/caddy-pihole-web-health.timer /etc/keepalived/keepalived.conf; do
        action35g_saved=$action35g_backup/${action35g_destination//\//_}
        action35g_absent=$action35g_saved.absent
        if [[ -f "$action35g_saved" && ! -L "$action35g_saved" ]]; then
            action35g_temporary=$(action35g_root_path "$action35g_destination.rollback-action35g")
            [[ ! -e "$action35g_temporary" && ! -L "$action35g_temporary" ]] || return 1
            cp -a -- "$action35g_saved" "$action35g_temporary"
            mv -fT -- "$action35g_temporary" "$(action35g_root_path "$action35g_destination")"
        elif [[ -f "$action35g_absent" && ! -L "$action35g_absent" ]]; then
            rm -f -- "$(action35g_root_path "$action35g_destination")"
        else
            return 1
        fi
    done
    action35g_systemctl daemon-reload >/dev/null 2>&1 || return 1
    if [[ "$(<"$action35g_backup/timer-enabled.status")" -eq 0 ]]; then
        action35g_systemctl enable caddy-pihole-web-health.timer >/dev/null 2>&1 || return 1
    fi
    if [[ "$(<"$action35g_backup/timer-active.status")" -eq 0 ]]; then
        action35g_systemctl start caddy-pihole-web-health.timer >/dev/null 2>&1 || return 1
    fi
    action35g_systemctl reload keepalived.service >/dev/null 2>&1 || return 1
    printf '%s_check_rollback_complete=true\n' "$action35g_prefix"
}

action35g_cleanup() {
    local action35g_status=$?

    if [[ -n "$action35g_preflight" && -d "$action35g_preflight" && ! -L "$action35g_preflight" ]]; then
        find "$action35g_preflight" -xdev -mindepth 1 -delete || :
        rmdir "$action35g_preflight" 2>/dev/null || :
        rmdir "$(dirname -- "$action35g_preflight")" 2>/dev/null || :
    fi
    if ((action35g_status != 0)) && [[ "$action35g_mutated" = true ]]; then
        if ! action35g_rollback; then
            exit 125
        fi
    fi
    exit "$action35g_status"
}

while (($#)); do
    case "$1" in
        --node-role)
            action35g_node_role=${2:-}
            shift 2
            ;;
        --payload)
            action35g_payload=${2:-}
            shift 2
            ;;
        --production-path-test)
            action35g_test_root=${2:-}
            shift 2
            ;;
        --rollback-existing)
            action35g_mode=rollback
            shift
            ;;
        *)
            action35g_usage
            exit 64
            ;;
    esac
done

[[ "$action35g_node_role" =~ ^node-[ab]$ ]] || {
    action35g_usage
    exit 64
}
if [[ "$action35g_mode" = apply ]]; then
    [[ -d "$action35g_payload" && ! -L "$action35g_payload" ]] || exit 64
fi
if [[ -n "$action35g_test_root" ]]; then
    [[ "$action35g_test_root" = /tmp/* && -d "$action35g_test_root" && ! -L "$action35g_test_root" ]] || exit 64
fi

action35g_evidence=$(action35g_root_path "$action35g_node_evidence/$action35g_node_role")
readonly action35g_evidence
if [[ "$action35g_mode" = rollback ]]; then
    action35g_backup=$(action35g_root_path "/var/backups/caddy-action35g/$action35g_node_role")
    [[ -d "$action35g_backup" && ! -L "$action35g_backup" ]] || exit 1
    action35g_mutated=true
    action35g_rollback
    exit 0
fi
[[ ! -e "$action35g_evidence" ]] || exit 1
install -d -m 0700 "$action35g_evidence"
printf '0\n' >"$action35g_evidence/mutation-count"
if [[ -n "$action35g_test_root" ]]; then
    /bin/bash "$action35g_test_root/bin/journalctl" --show-cursor --no-pager \
        >"$action35g_evidence/journal.cursor"
else
    journalctl --show-cursor --no-pager >"$action35g_evidence/journal.cursor"
fi
trap action35g_cleanup EXIT INT TERM

action35g_check payload_contract action35g_validate_payload
action35g_validate_baseline
action35g_validate_candidates
action35g_backup_current
action35g_install_candidates
action35g_accept
action35g_check residue_absent test -z \
    "$(find "$(action35g_root_path /var/lib/caddy-sync/incoming)" -mindepth 1 -maxdepth 1 -name 'action35g-*' -print -quit 2>/dev/null)"
printf '%s_check_complete=true\n' "$action35g_prefix"
