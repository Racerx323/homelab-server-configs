#!/usr/bin/env bash
# shellcheck disable=SC2016 # The captured Bash predicate expands only inside its child shell.

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH
readonly PATH

readonly action35e_prefix=action_35e
readonly action35e_expected_manifest_sha256=86f71fba1b126754fa560ddf49f569c2b06f85ab603a9a24f59921d1064da087
readonly action35e_node_evidence=/tmp/caddy-action35e

action35e_node_role=
action35e_payload=
action35e_test_root=
action35e_mode=apply
action35e_mutated=false
action35e_backup=
action35e_preflight=

if [[ "${1:-}" = --production-path-test && $# -eq 1 ]]; then
    action35e_self_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
    readonly action35e_self_directory
    exec /bin/bash "$action35e_self_directory/../tests/coupled-serving-health-deployment-regression.sh" \
        --entrypoint transaction
fi

action35e_usage() {
    printf 'Usage: %s --node-role node-a|node-b --payload DIRECTORY [--production-path-test ROOT]\n' "${0##*/}" >&2
}

action35e_check() {
    local action35e_label=$1

    shift
    if "$@"; then
        printf '%s_check_%s=true\n' "$action35e_prefix" "$action35e_label"
        return 0
    fi
    printf '%s_check_%s=false\n' "$action35e_prefix" "$action35e_label" >&2
    return 1
}

action35e_root_path() {
    local action35e_path=$1

    if [[ -n "$action35e_test_root" ]]; then
        printf '%s%s' "${action35e_test_root%/}" "$action35e_path"
    else
        printf '%s' "$action35e_path"
    fi
}

action35e_systemctl() {
    if [[ -n "$action35e_test_root" ]]; then
        /bin/bash "$action35e_test_root/bin/systemctl" "$@"
    else
        systemctl "$@"
    fi
}

action35e_keepalived_parser() {
    local action35e_config=$1

    if [[ -n "$action35e_test_root" ]]; then
        /bin/bash "$action35e_test_root/bin/keepalived" --config-test --use-file="$action35e_config"
    else
        keepalived --config-test --use-file="$action35e_config"
    fi
}

action35e_ownership_snapshot() {
    if [[ -n "$action35e_test_root" ]]; then
        /bin/bash "$action35e_test_root/bin/ownership" "$action35e_node_role"
        return
    fi
    local action35e_ipv4_state action35e_ipv6_state action35e_vip_count
    action35e_ipv4_state=$(timeout 2 busctl get-property org.keepalived.Vrrp1 \
        /org/keepalived/Vrrp1/Instance/eth0/100/IPv4 org.keepalived.Vrrp1.Instance State)
    action35e_ipv6_state=$(timeout 2 busctl get-property org.keepalived.Vrrp1 \
        /org/keepalived/Vrrp1/Instance/eth0/101/IPv6 org.keepalived.Vrrp1.Instance State)
    case "$action35e_ipv4_state" in
        *'"Master"') action35e_ipv4_state=Master ;;
        *'"Backup"') action35e_ipv4_state=Backup ;;
        *) return 1 ;;
    esac
    case "$action35e_ipv6_state" in
        *'"Master"') action35e_ipv6_state=Master ;;
        *'"Backup"') action35e_ipv6_state=Backup ;;
        *) return 1 ;;
    esac
    action35e_vip_count=$(
        ip -o address show dev eth0 |
            awk '$4 ~ /^(10\.1\.0\.(55|56)\/22|fd36:5aa8:6971:1::(55|56)\/128)$/ { count++ } END { print count + 0 }'
    )
    printf 'ipv4=%s ipv6=%s vip_count=%s\n' \
        "$action35e_ipv4_state" "$action35e_ipv6_state" "$action35e_vip_count"
}

action35e_run_as() {
    local action35e_identity=$1

    shift
    if [[ -n "$action35e_test_root" ]]; then
        {
            printf '%s\t' "$action35e_identity"
            printf '%q ' "$@"
            printf '\n'
        } >>"$action35e_test_root/calls/identities.tsv"
        env \
            DNS_CHECK_DIG_COMMAND="$action35e_test_root/bin/dig" \
            DNS_CHECK_SYSTEMCTL_COMMAND="$action35e_test_root/bin/systemctl" \
            CADDY_SERVING_HEALTH_ENVIRONMENT_FILE="$action35e_test_root/etc/default/caddy-ha" \
            CADDY_SERVING_HEALTH_CURL_COMMAND="$action35e_test_root/bin/curl" \
            CADDY_SERVING_HEALTH_SS_COMMAND="$action35e_test_root/bin/ss" \
            CADDY_SERVING_HEALTH_SYSTEMCTL_COMMAND="$action35e_test_root/bin/systemctl" \
            PIHOLE_WEB_HEALTH_ENVIRONMENT_FILE="$action35e_test_root/etc/default/caddy-ha" \
            PIHOLE_WEB_HEALTH_STATE_DIRECTORY="$action35e_test_root/var/lib/caddy-pihole-web-health" \
            PIHOLE_WEB_HEALTH_RUNTIME_DIRECTORY="$action35e_test_root/run/caddy-pihole-web-health" \
            PIHOLE_WEB_HEALTH_ENQUEUE_COMMAND="$action35e_test_root/bin/enqueue" \
            PIHOLE_WEB_HEALTH_CURL_COMMAND="$action35e_test_root/bin/curl" \
            PIHOLE_WEB_HEALTH_SYSTEMCTL_COMMAND="$action35e_test_root/bin/systemctl" \
            "$@"
    else
        runuser --user "$action35e_identity" -- "$@"
    fi
}

action35e_capture() {
    local action35e_label=$1

    shift
    local action35e_stdout action35e_stderr action35e_status=0
    action35e_stdout=$action35e_evidence/$action35e_label.stdout
    action35e_stderr=$action35e_evidence/$action35e_label.stderr
    : >"$action35e_stdout"
    : >"$action35e_stderr"
    "$@" >"$action35e_stdout" 2>"$action35e_stderr" || action35e_status=$?
    printf '%s\n' "$action35e_status" >"$action35e_evidence/$action35e_label.status"
    [[ -f "$action35e_stdout" && ! -L "$action35e_stdout" ]] || return 1
    [[ -f "$action35e_stderr" && ! -L "$action35e_stderr" ]] || return 1
    return "$action35e_status"
}

action35e_require_regular() {
    local action35e_path=$1
    local action35e_mode=${2:-}

    [[ -f "$action35e_path" && ! -L "$action35e_path" ]] || return 1
    [[ -z "$action35e_mode" || "$(stat -c '%a' "$action35e_path")" = "$action35e_mode" ]]
}

action35e_validate_payload() {
    local action35e_line action35e_repository action35e_source action35e_target
    local action35e_mode action35e_hash action35e_lifecycle action35e_source_path

    action35e_require_regular "$action35e_payload/serving-health-production.tsv" || return 1
    [[ "$(sed -n '1p' "$action35e_payload/serving-health-production.tsv")" = $'# repository\tsource-path\tinstalled-path\tmode\tcandidate-sha256\tlifecycle' ]] || return 1
    while IFS=$'\t' read -r action35e_repository action35e_source action35e_target \
        action35e_mode action35e_hash action35e_lifecycle; do
        [[ -n "$action35e_repository" && "$action35e_repository" != \#* ]] || continue
        [[ "$action35e_repository" =~ ^homelab-(server-configs|dns)$ ]] || return 1
        [[ "$action35e_source" != *..* && "$action35e_target" = /* ]] || return 1
        [[ "$action35e_mode" =~ ^0[0-7]{3}$ && "$action35e_hash" =~ ^[0-9a-f]{64}$ ]] || return 1
        [[ "$action35e_lifecycle" = production-candidate ]] || return 1
        action35e_source_path=$action35e_payload/files/$action35e_repository/$action35e_source
        action35e_require_regular "$action35e_source_path" || return 1
        [[ "$(sha256sum "$action35e_source_path" | awk '{ print $1 }')" = "$action35e_hash" ]] || return 1
        printf '%s\t%s\t%s\n' "$action35e_target" "$action35e_hash" "$action35e_mode" \
            >>"$action35e_evidence/payload-identities.tsv"
        action35e_line=true
    done <"$action35e_payload/serving-health-production.tsv"
    [[ "${action35e_line:-false}" = true ]]
}

action35e_validate_baseline() {
    local action35e_expected_state=$action35e_payload/current-live-state.tsv
    local action35e_current_link
    local action35e_key action35e_repository action35e_source action35e_installed
    local action35e_inventory_node action35e_source_hash action35e_deployed_hash
    local action35e_accepted_action action35e_lifecycle action35e_installed_path

    action35e_require_regular "$action35e_expected_state" || return 1
    action35e_require_regular "$action35e_payload/production-artifacts.tsv" || return 1
    action35e_check baseline_manifest_identity test \
        "$(sha256sum "$action35e_expected_state" | awk '{ print $1 }')" = "$action35e_expected_manifest_sha256" || return 1
    for action35e_unit in caddy.service caddy-lsyncd.service caddy-sync-reconcile.path \
        caddy-apprise-worker.path caddy-apprise-worker.timer keepalived.service \
        pihole-FTL.service unbound.service lighttpd.service; do
        action35e_capture "baseline-${action35e_unit//./-}" \
            action35e_systemctl is-active --quiet "$action35e_unit" || return 1
    done
    for action35e_unit in caddy.service caddy-lsyncd.service caddy-sync-reconcile.path \
        caddy-apprise-worker.path caddy-apprise-worker.timer; do
        action35e_capture "enabled-${action35e_unit//./-}" \
            action35e_systemctl is-enabled --quiet "$action35e_unit" || return 1
    done
    action35e_current_link=$(action35e_root_path /etc/caddy/current)
    [[ -L "$action35e_current_link" ]] || return 1
    readlink -f -- "$action35e_current_link" >"$action35e_evidence/original-release.path"
    action35e_require_regular "$(<"$action35e_evidence/original-release.path")/release-manifest.json" || return 1
    action35e_capture baseline-residue /bin/bash -c \
        'test -z "$(find "$1" -mindepth 1 -maxdepth 1 -name "action35e-*" -print -quit 2>/dev/null)"' \
        _ "$(action35e_root_path /var/lib/caddy-sync/incoming)" || return 1
    while IFS=$'\t' read -r action35e_key action35e_repository action35e_source \
        action35e_installed action35e_inventory_node action35e_source_hash \
        action35e_deployed_hash action35e_accepted_action action35e_lifecycle; do
        [[ -n "$action35e_key" && "$action35e_key" != \#* ]] || continue
        [[ "$action35e_inventory_node" = "$action35e_node_role" ]] || continue
        : "$action35e_repository" "$action35e_source" "$action35e_source_hash"
        [[ "$action35e_lifecycle" = production-current && "$action35e_installed" = /* ]] || return 1
        [[ "$action35e_deployed_hash" =~ ^[0-9a-f]{64}$ ]] || return 1
        action35e_installed_path=$(action35e_root_path "$action35e_installed")
        action35e_require_regular "$action35e_installed_path" || return 1
        [[ "$(sha256sum "$action35e_installed_path" | awk '{ print $1 }')" = "$action35e_deployed_hash" ]] || return 1
        printf '%s\t%s\t%s\n' "$action35e_key" "$action35e_deployed_hash" \
            "$action35e_accepted_action" >>"$action35e_evidence/baseline-identities.tsv"
    done <"$action35e_payload/production-artifacts.tsv"
    printf '%s_check_baseline_complete=true\n' "$action35e_prefix"
}

action35e_validate_candidates() {
    local action35e_keepalived action35e_dns action35e_caddy action35e_web

    action35e_keepalived=$action35e_payload/files/homelab-dns/Keepalived/configs/keepalived-pihole0.conf
    [[ "$action35e_node_role" = node-b ]] &&
        action35e_keepalived=$action35e_payload/files/homelab-dns/Keepalived/configs/keepalived-pihole00.conf
    action35e_dns=$action35e_payload/files/homelab-dns/Keepalived/scripts/dns-check.sh
    action35e_caddy=$action35e_payload/files/homelab-server-configs/Caddy/scripts/check-caddy-serving-health.sh
    action35e_web=$action35e_payload/files/homelab-server-configs/Caddy/scripts/check-pihole-web-health.sh
    action35e_preflight=$(action35e_root_path "/tmp/caddy-action35e-preflight/$action35e_node_role")
    [[ ! -e "$action35e_preflight" ]] || return 1
    install -d -m 0755 "$action35e_preflight/bin" "$action35e_preflight/state" \
        "$action35e_preflight/run"
    install -m 0755 "$action35e_dns" "$action35e_preflight/bin/check-dns.sh"
    install -m 0755 "$action35e_caddy" "$action35e_preflight/bin/check-caddy.sh"
    install -m 0755 "$action35e_web" "$action35e_preflight/bin/check-pihole-web-health.sh"
    action35e_capture keepalived-parser action35e_keepalived_parser "$action35e_keepalived" || return 1
    action35e_capture dns-service-identity action35e_run_as pi \
        /bin/bash "$action35e_preflight/bin/check-dns.sh" || return 1
    action35e_capture caddy-service-identity action35e_run_as keepalived_script \
        /usr/bin/timeout 2 /bin/bash "$action35e_preflight/bin/check-caddy.sh" || return 1
    if [[ -n "$action35e_test_root" ]]; then
        action35e_capture web-service-identity action35e_run_as pi \
            /bin/bash "$action35e_preflight/bin/check-pihole-web-health.sh" || return 1
    else
        chown -R pi:pi "$action35e_preflight/state" "$action35e_preflight/run"
        action35e_capture web-service-identity runuser --user pi -- env \
            PIHOLE_WEB_HEALTH_STATE_DIRECTORY="$action35e_preflight/state" \
            PIHOLE_WEB_HEALTH_RUNTIME_DIRECTORY="$action35e_preflight/run" \
            PIHOLE_WEB_HEALTH_ENQUEUE_COMMAND=/usr/bin/true \
            /bin/bash "$action35e_preflight/bin/check-pihole-web-health.sh" || return 1
    fi
    grep -Fq 'check=127_0_0_1_53_A status=0 answer=10.1.0.55' \
        "$action35e_evidence/dns-service-identity.stdout" || return 1
    grep -Fq 'check=__1_5335_AAAA status=0 answer=fd36:5aa8:6971:1::55' \
        "$action35e_evidence/dns-service-identity.stdout" || return 1
    grep -Fxq 'caddy_serving_health_complete=true' \
        "$action35e_evidence/caddy-service-identity.stdout" || return 1
    find "$action35e_preflight" -xdev -mindepth 1 -delete
    rmdir "$action35e_preflight"
    rmdir "$(dirname -- "$action35e_preflight")" 2>/dev/null || :
    printf '%s_check_candidate_validation_complete=true\n' "$action35e_prefix"
}

action35e_backup_current() {
    local action35e_destination
    local action35e_timer_status=0

    action35e_backup=$(action35e_root_path "/var/backups/caddy-action35e/$action35e_node_role")
    [[ ! -e "$action35e_backup" ]] || return 1
    install -d -m 0700 "$action35e_backup"
    for action35e_destination in /etc/scripts/check-dns.sh /usr/local/libexec/check-caddy.sh \
        /usr/local/libexec/check-pihole-web-health.sh /etc/systemd/system/caddy-pihole-web-health.service \
        /etc/systemd/system/caddy-pihole-web-health.timer /etc/keepalived/keepalived.conf; do
        local action35e_existing
        action35e_existing=$(action35e_root_path "$action35e_destination")
        if [[ -f "$action35e_existing" && ! -L "$action35e_existing" ]]; then
            cp -a -- "$action35e_existing" \
                "$action35e_backup/${action35e_destination//\//_}"
        else
            : >"$action35e_backup/${action35e_destination//\//_}.absent"
        fi
    done
    action35e_systemctl is-enabled --quiet caddy-pihole-web-health.timer ||
        action35e_timer_status=$?
    printf '%s\n' "$action35e_timer_status" >"$action35e_backup/timer-enabled.status"
    action35e_timer_status=0
    action35e_systemctl is-active --quiet caddy-pihole-web-health.timer ||
        action35e_timer_status=$?
    printf '%s\n' "$action35e_timer_status" >"$action35e_backup/timer-active.status"
    printf '%s_check_backup_complete=true\n' "$action35e_prefix"
}

action35e_install_candidates() {
    local action35e_repository action35e_source action35e_target action35e_mode
    local action35e_hash action35e_lifecycle action35e_source_path action35e_destination

    while IFS=$'\t' read -r action35e_repository action35e_source action35e_target \
        action35e_mode action35e_hash action35e_lifecycle; do
        [[ -n "$action35e_repository" && "$action35e_repository" != \#* ]] || continue
        case "$action35e_target" in
            */keepalived.conf)
                [[ "$action35e_node_role" = node-a && "$action35e_source" = *pihole0.conf ]] ||
                    [[ "$action35e_node_role" = node-b && "$action35e_source" = *pihole00.conf ]] || continue
                ;;
            */releases/REVISION/*) continue ;;
        esac
        action35e_source_path=$action35e_payload/files/$action35e_repository/$action35e_source
        action35e_destination=$(action35e_root_path "$action35e_target")
        install -d -m 0755 "$(dirname -- "$action35e_destination")"
        install -m "$action35e_mode" "$action35e_source_path" "$action35e_destination"
        [[ "$(sha256sum "$action35e_destination" | awk '{ print $1 }')" = "$action35e_hash" ]] || return 1
    done <"$action35e_payload/serving-health-production.tsv"
    action35e_mutated=true
    printf '1\n' >"$action35e_evidence/mutation-count"
    action35e_capture daemon-reload action35e_systemctl daemon-reload || return 1
    action35e_capture backend-timer-enable action35e_systemctl enable --now \
        caddy-pihole-web-health.timer || return 1
    action35e_capture keepalived-reload action35e_systemctl reload keepalived.service || return 1
    printf '%s_check_mutation_complete=true\n' "$action35e_prefix"
}

action35e_accept() {
    local action35e_sample
    local action35e_expected_ownership='ipv4=Backup ipv6=Backup vip_count=0'
    local action35e_stable=0

    [[ "$action35e_node_role" = node-b ]] ||
        action35e_expected_ownership='ipv4=Master ipv6=Master vip_count=4'

    for action35e_sample in $(seq 1 30); do
        action35e_capture "post-dns-$action35e_sample" action35e_run_as pi \
            /bin/bash "$(action35e_root_path /etc/scripts/check-dns.sh)" || return 1
        action35e_capture "post-caddy-$action35e_sample" action35e_run_as keepalived_script \
            /usr/bin/timeout 2 /bin/bash "$(action35e_root_path /usr/local/libexec/check-caddy.sh)" || return 1
        action35e_capture "ownership-$action35e_sample" action35e_ownership_snapshot || return 1
        if grep -Fxq "$action35e_expected_ownership" \
            "$action35e_evidence/ownership-$action35e_sample.stdout"; then
            action35e_stable=$((action35e_stable + 1))
        else
            action35e_stable=0
        fi
        [[ "$action35e_stable" -lt 3 ]] || break
        sleep 1
    done
    [[ "$action35e_stable" -eq 3 ]] || return 1
    action35e_capture timer-active action35e_systemctl is-active --quiet \
        caddy-pihole-web-health.timer || return 1
    action35e_capture timer-enabled action35e_systemctl is-enabled --quiet \
        caddy-pihole-web-health.timer || return 1
    if [[ -n "$action35e_test_root" ]]; then
        action35e_capture journal-after-cursor /bin/bash "$action35e_test_root/bin/journalctl" \
            --after-cursor "$(<"$action35e_evidence/journal.cursor")" --no-pager || return 1
    else
        action35e_capture journal-after-cursor journalctl \
            --after-cursor "$(<"$action35e_evidence/journal.cursor")" --no-pager || return 1
    fi
    if grep -Eiq 'simultaneous[_ -]ownership|script.*timed out|unsafe|secret' \
        "$action35e_evidence/journal-after-cursor.stdout"; then
        return 1
    fi
    printf '%s_check_acceptance_complete=true\n' "$action35e_prefix"
}

action35e_rollback() {
    local action35e_destination action35e_saved action35e_absent
    local action35e_temporary

    [[ "$action35e_mutated" = true ]] || return 0
    if [[ "$(<"$action35e_backup/timer-enabled.status")" -ne 0 ]]; then
        action35e_systemctl disable --now caddy-pihole-web-health.timer \
            >/dev/null 2>&1 || return 1
    fi
    for action35e_destination in /etc/scripts/check-dns.sh /usr/local/libexec/check-caddy.sh \
        /usr/local/libexec/check-pihole-web-health.sh /etc/systemd/system/caddy-pihole-web-health.service \
        /etc/systemd/system/caddy-pihole-web-health.timer /etc/keepalived/keepalived.conf; do
        action35e_saved=$action35e_backup/${action35e_destination//\//_}
        action35e_absent=$action35e_saved.absent
        if [[ -f "$action35e_saved" && ! -L "$action35e_saved" ]]; then
            action35e_temporary=$(action35e_root_path "$action35e_destination.rollback-action35e")
            [[ ! -e "$action35e_temporary" && ! -L "$action35e_temporary" ]] || return 1
            cp -a -- "$action35e_saved" "$action35e_temporary"
            mv -fT -- "$action35e_temporary" "$(action35e_root_path "$action35e_destination")"
        elif [[ -f "$action35e_absent" && ! -L "$action35e_absent" ]]; then
            rm -f -- "$(action35e_root_path "$action35e_destination")"
        else
            return 1
        fi
    done
    action35e_systemctl daemon-reload >/dev/null 2>&1 || return 1
    if [[ "$(<"$action35e_backup/timer-enabled.status")" -eq 0 ]]; then
        action35e_systemctl enable caddy-pihole-web-health.timer >/dev/null 2>&1 || return 1
    fi
    if [[ "$(<"$action35e_backup/timer-active.status")" -eq 0 ]]; then
        action35e_systemctl start caddy-pihole-web-health.timer >/dev/null 2>&1 || return 1
    fi
    action35e_systemctl reload keepalived.service >/dev/null 2>&1 || return 1
    printf '%s_check_rollback_complete=true\n' "$action35e_prefix"
}

action35e_cleanup() {
    local action35e_status=$?

    if [[ -n "$action35e_preflight" && -d "$action35e_preflight" && ! -L "$action35e_preflight" ]]; then
        find "$action35e_preflight" -xdev -mindepth 1 -delete || :
        rmdir "$action35e_preflight" 2>/dev/null || :
        rmdir "$(dirname -- "$action35e_preflight")" 2>/dev/null || :
    fi
    if ((action35e_status != 0)) && [[ "$action35e_mutated" = true ]]; then
        if ! action35e_rollback; then
            exit 125
        fi
    fi
    exit "$action35e_status"
}

while (($#)); do
    case "$1" in
        --node-role)
            action35e_node_role=${2:-}
            shift 2
            ;;
        --payload)
            action35e_payload=${2:-}
            shift 2
            ;;
        --production-path-test)
            action35e_test_root=${2:-}
            shift 2
            ;;
        --rollback-existing)
            action35e_mode=rollback
            shift
            ;;
        *)
            action35e_usage
            exit 64
            ;;
    esac
done

[[ "$action35e_node_role" =~ ^node-[ab]$ ]] || {
    action35e_usage
    exit 64
}
if [[ "$action35e_mode" = apply ]]; then
    [[ -d "$action35e_payload" && ! -L "$action35e_payload" ]] || exit 64
fi
if [[ -n "$action35e_test_root" ]]; then
    [[ "$action35e_test_root" = /tmp/* && -d "$action35e_test_root" && ! -L "$action35e_test_root" ]] || exit 64
fi

action35e_evidence=$(action35e_root_path "$action35e_node_evidence/$action35e_node_role")
readonly action35e_evidence
if [[ "$action35e_mode" = rollback ]]; then
    action35e_backup=$(action35e_root_path "/var/backups/caddy-action35e/$action35e_node_role")
    [[ -d "$action35e_backup" && ! -L "$action35e_backup" ]] || exit 1
    action35e_mutated=true
    action35e_rollback
    exit 0
fi
[[ ! -e "$action35e_evidence" ]] || exit 1
install -d -m 0700 "$action35e_evidence"
printf '0\n' >"$action35e_evidence/mutation-count"
if [[ -n "$action35e_test_root" ]]; then
    /bin/bash "$action35e_test_root/bin/journalctl" --show-cursor --no-pager \
        >"$action35e_evidence/journal.cursor"
else
    journalctl --show-cursor --no-pager >"$action35e_evidence/journal.cursor"
fi
trap action35e_cleanup EXIT INT TERM

action35e_check payload_contract action35e_validate_payload
action35e_validate_baseline
action35e_validate_candidates
action35e_backup_current
action35e_install_candidates
action35e_accept
action35e_check residue_absent test -z \
    "$(find "$(action35e_root_path /var/lib/caddy-sync/incoming)" -mindepth 1 -maxdepth 1 -name 'action35e-*' -print -quit 2>/dev/null)"
printf '%s_check_complete=true\n' "$action35e_prefix"
