#!/usr/bin/env bash
# shellcheck disable=SC2016 # The captured Bash predicate expands only inside its child shell.

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH
readonly PATH

readonly action35h_prefix=action_35h
readonly action35h_expected_manifest_sha256=a18548725713feecff66e760f774d3204a213b7d38b9c0c014e635d3a74bdcff
readonly action35h_node_evidence=/tmp/caddy-action35h

action35h_node_role=
action35h_payload=
action35h_test_root=
action35h_mode=apply
action35h_mutated=false
action35h_backup=
action35h_preflight=

if [[ "${1:-}" = --production-path-test && $# -eq 1 ]]; then
    action35h_self_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
    readonly action35h_self_directory
    exec /bin/bash "$action35h_self_directory/../tests/coupled-serving-health-deployment-regression.sh" \
        --entrypoint transaction
fi

action35h_usage() {
    printf 'Usage: %s --node-role node-a|node-b --payload DIRECTORY [--production-path-test ROOT]\n' "${0##*/}" >&2
}

action35h_check() {
    local action35h_label=$1

    shift
    if "$@"; then
        printf '%s_check_%s=true\n' "$action35h_prefix" "$action35h_label"
        return 0
    fi
    printf '%s_check_%s=false\n' "$action35h_prefix" "$action35h_label" >&2
    return 1
}

action35h_root_path() {
    local action35h_path=$1

    if [[ -n "$action35h_test_root" ]]; then
        printf '%s%s' "${action35h_test_root%/}" "$action35h_path"
    else
        printf '%s' "$action35h_path"
    fi
}

action35h_systemctl() {
    if [[ -n "$action35h_test_root" ]]; then
        /bin/bash "$action35h_test_root/bin/systemctl" "$@"
    else
        systemctl "$@"
    fi
}

action35h_keepalived_parser() {
    local action35h_config=$1

    if [[ -n "$action35h_test_root" ]]; then
        /bin/bash "$action35h_test_root/bin/keepalived" --config-test --use-file="$action35h_config"
    else
        keepalived --config-test --use-file="$action35h_config"
    fi
}

action35h_ownership_snapshot() {
    if [[ -n "$action35h_test_root" ]]; then
        /bin/bash "$action35h_test_root/bin/ownership" "$action35h_node_role"
        return
    fi
    local action35h_ipv4_state action35h_ipv6_state action35h_vip_count
    action35h_ipv4_state=$(timeout 2 busctl get-property org.keepalived.Vrrp1 \
        /org/keepalived/Vrrp1/Instance/eth0/100/IPv4 org.keepalived.Vrrp1.Instance State)
    action35h_ipv6_state=$(timeout 2 busctl get-property org.keepalived.Vrrp1 \
        /org/keepalived/Vrrp1/Instance/eth0/101/IPv6 org.keepalived.Vrrp1.Instance State)
    case "$action35h_ipv4_state" in
        *'"Master"') action35h_ipv4_state=Master ;;
        *'"Backup"') action35h_ipv4_state=Backup ;;
        *) return 1 ;;
    esac
    case "$action35h_ipv6_state" in
        *'"Master"') action35h_ipv6_state=Master ;;
        *'"Backup"') action35h_ipv6_state=Backup ;;
        *) return 1 ;;
    esac
    action35h_vip_count=$(
        ip -o address show dev eth0 |
            awk '$4 ~ /^(10\.1\.0\.(55|56)\/22|fd36:5aa8:6971:1::(55|56)\/128)$/ { count++ } END { print count + 0 }'
    )
    printf 'ipv4=%s ipv6=%s vip_count=%s\n' \
        "$action35h_ipv4_state" "$action35h_ipv6_state" "$action35h_vip_count"
}

action35h_run_as() {
    local action35h_identity=$1

    shift
    if [[ -n "$action35h_test_root" ]]; then
        {
            printf '%s\t' "$action35h_identity"
            printf '%q ' "$@"
            printf '\n'
        } >>"$action35h_test_root/calls/identities.tsv"
        env \
            DNS_CHECK_DIG_COMMAND="$action35h_test_root/bin/dig" \
            DNS_CHECK_SYSTEMCTL_COMMAND="$action35h_test_root/bin/systemctl" \
            CADDY_SERVING_HEALTH_ENVIRONMENT_FILE="$action35h_test_root/etc/default/caddy-ha" \
            CADDY_SERVING_HEALTH_CURL_COMMAND="$action35h_test_root/bin/curl" \
            CADDY_SERVING_HEALTH_SS_COMMAND="$action35h_test_root/bin/ss" \
            CADDY_SERVING_HEALTH_SYSTEMCTL_COMMAND="$action35h_test_root/bin/systemctl" \
            PIHOLE_WEB_HEALTH_ENVIRONMENT_FILE="$action35h_test_root/etc/default/caddy-ha" \
            PIHOLE_WEB_HEALTH_STATE_DIRECTORY="$action35h_test_root/var/lib/caddy-pihole-web-health" \
            PIHOLE_WEB_HEALTH_RUNTIME_DIRECTORY="$action35h_test_root/run/caddy-pihole-web-health" \
            PIHOLE_WEB_HEALTH_ENQUEUE_COMMAND="$action35h_test_root/bin/enqueue" \
            PIHOLE_WEB_HEALTH_CURL_COMMAND="$action35h_test_root/bin/curl" \
            PIHOLE_WEB_HEALTH_SYSTEMCTL_COMMAND="$action35h_test_root/bin/systemctl" \
            "$@"
    else
        runuser --user "$action35h_identity" -- "$@"
    fi
}

action35h_capture() {
    local action35h_label=$1

    shift
    local action35h_stdout action35h_stderr action35h_status=0
    action35h_stdout=$action35h_evidence/$action35h_label.stdout
    action35h_stderr=$action35h_evidence/$action35h_label.stderr
    : >"$action35h_stdout"
    : >"$action35h_stderr"
    "$@" >"$action35h_stdout" 2>"$action35h_stderr" || action35h_status=$?
    printf '%s\n' "$action35h_status" >"$action35h_evidence/$action35h_label.status"
    [[ -f "$action35h_stdout" && ! -L "$action35h_stdout" ]] || return 1
    [[ -f "$action35h_stderr" && ! -L "$action35h_stderr" ]] || return 1
    return "$action35h_status"
}

action35h_require_regular() {
    local action35h_path=$1
    local action35h_mode=${2:-}

    [[ -f "$action35h_path" && ! -L "$action35h_path" ]] || return 1
    [[ -z "$action35h_mode" || "$(stat -c '%a' "$action35h_path")" = "$action35h_mode" ]]
}

action35h_validate_payload() {
    local action35h_line action35h_repository action35h_source action35h_target
    local action35h_mode action35h_hash action35h_lifecycle action35h_source_path

    action35h_require_regular "$action35h_payload/serving-health-production.tsv" || return 1
    [[ "$(sed -n '1p' "$action35h_payload/serving-health-production.tsv")" = $'# repository\tsource-path\tinstalled-path\tmode\tcandidate-sha256\tlifecycle' ]] || return 1
    while IFS=$'\t' read -r action35h_repository action35h_source action35h_target \
        action35h_mode action35h_hash action35h_lifecycle; do
        [[ -n "$action35h_repository" && "$action35h_repository" != \#* ]] || continue
        [[ "$action35h_repository" =~ ^homelab-(server-configs|dns)$ ]] || return 1
        [[ "$action35h_source" != *..* && "$action35h_target" = /* ]] || return 1
        [[ "$action35h_mode" =~ ^0[0-7]{3}$ && "$action35h_hash" =~ ^[0-9a-f]{64}$ ]] || return 1
        [[ "$action35h_lifecycle" = production-candidate ]] || return 1
        action35h_source_path=$action35h_payload/files/$action35h_repository/$action35h_source
        action35h_require_regular "$action35h_source_path" || return 1
        [[ "$(sha256sum "$action35h_source_path" | awk '{ print $1 }')" = "$action35h_hash" ]] || return 1
        printf '%s\t%s\t%s\n' "$action35h_target" "$action35h_hash" "$action35h_mode" \
            >>"$action35h_evidence/payload-identities.tsv"
        action35h_line=true
    done <"$action35h_payload/serving-health-production.tsv"
    [[ "${action35h_line:-false}" = true ]]
}

action35h_validate_baseline() {
    local action35h_expected_state=$action35h_payload/current-live-state.tsv
    local action35h_current_link
    local action35h_key action35h_repository action35h_source action35h_installed
    local action35h_inventory_node action35h_source_hash action35h_deployed_hash
    local action35h_accepted_action action35h_lifecycle action35h_installed_path

    action35h_require_regular "$action35h_expected_state" || return 1
    action35h_require_regular "$action35h_payload/production-artifacts.tsv" || return 1
    action35h_check baseline_manifest_identity test \
        "$(sha256sum "$action35h_expected_state" | awk '{ print $1 }')" = "$action35h_expected_manifest_sha256" || return 1
    for action35h_unit in caddy.service caddy-lsyncd.service caddy-sync-reconcile.path \
        caddy-apprise-worker.path caddy-apprise-worker.timer keepalived.service \
        pihole-FTL.service unbound.service lighttpd.service; do
        action35h_capture "baseline-${action35h_unit//./-}" \
            action35h_systemctl is-active --quiet "$action35h_unit" || return 1
    done
    for action35h_unit in caddy.service caddy-lsyncd.service caddy-sync-reconcile.path \
        caddy-apprise-worker.path caddy-apprise-worker.timer; do
        action35h_capture "enabled-${action35h_unit//./-}" \
            action35h_systemctl is-enabled --quiet "$action35h_unit" || return 1
    done
    action35h_current_link=$(action35h_root_path /etc/caddy/current)
    [[ -L "$action35h_current_link" ]] || return 1
    readlink -f -- "$action35h_current_link" >"$action35h_evidence/original-release.path"
    action35h_require_regular "$(<"$action35h_evidence/original-release.path")/release-manifest.json" || return 1
    action35h_capture baseline-residue /bin/bash -c \
        'test -z "$(find "$1" -mindepth 1 -maxdepth 1 -name "action35h-*" -print -quit 2>/dev/null)"' \
        _ "$(action35h_root_path /var/lib/caddy-sync/incoming)" || return 1
    while IFS=$'\t' read -r action35h_key action35h_repository action35h_source \
        action35h_installed action35h_inventory_node action35h_source_hash \
        action35h_deployed_hash action35h_accepted_action action35h_lifecycle; do
        [[ -n "$action35h_key" && "$action35h_key" != \#* ]] || continue
        [[ "$action35h_inventory_node" = "$action35h_node_role" ]] || continue
        : "$action35h_repository" "$action35h_source" "$action35h_source_hash"
        [[ "$action35h_lifecycle" = production-current && "$action35h_installed" = /* ]] || return 1
        [[ "$action35h_deployed_hash" =~ ^[0-9a-f]{64}$ ]] || return 1
        action35h_installed_path=$(action35h_root_path "$action35h_installed")
        action35h_require_regular "$action35h_installed_path" || return 1
        [[ "$(sha256sum "$action35h_installed_path" | awk '{ print $1 }')" = "$action35h_deployed_hash" ]] || return 1
        printf '%s\t%s\t%s\n' "$action35h_key" "$action35h_deployed_hash" \
            "$action35h_accepted_action" >>"$action35h_evidence/baseline-identities.tsv"
    done <"$action35h_payload/production-artifacts.tsv"
    printf '%s_check_baseline_complete=true\n' "$action35h_prefix"
}

action35h_validate_candidates() {
    local action35h_keepalived action35h_dns action35h_caddy action35h_web

    action35h_keepalived=$action35h_payload/files/homelab-dns/Keepalived/configs/keepalived-pihole0.conf
    [[ "$action35h_node_role" = node-b ]] &&
        action35h_keepalived=$action35h_payload/files/homelab-dns/Keepalived/configs/keepalived-pihole00.conf
    action35h_dns=$action35h_payload/files/homelab-dns/Keepalived/scripts/dns-check.sh
    action35h_caddy=$action35h_payload/files/homelab-server-configs/Caddy/scripts/check-caddy-serving-health.sh
    action35h_web=$action35h_payload/files/homelab-server-configs/Caddy/scripts/check-pihole-web-health.sh
    action35h_preflight=$(action35h_root_path "/tmp/caddy-action35h-preflight/$action35h_node_role")
    [[ ! -e "$action35h_preflight" ]] || return 1
    install -d -m 0755 "$action35h_preflight/bin" "$action35h_preflight/state" \
        "$action35h_preflight/run"
    install -m 0755 "$action35h_dns" "$action35h_preflight/bin/check-dns.sh"
    install -m 0755 "$action35h_caddy" "$action35h_preflight/bin/check-caddy.sh"
    install -m 0755 "$action35h_web" "$action35h_preflight/bin/check-pihole-web-health.sh"
    action35h_capture keepalived-parser action35h_keepalived_parser "$action35h_keepalived" || return 1
    action35h_capture dns-service-identity action35h_run_as pi \
        /bin/bash "$action35h_preflight/bin/check-dns.sh" || return 1
    action35h_capture caddy-service-identity action35h_run_as keepalived_script \
        /usr/bin/timeout 2 /bin/bash "$action35h_preflight/bin/check-caddy.sh" || return 1
    if [[ -n "$action35h_test_root" ]]; then
        action35h_capture web-service-identity action35h_run_as pi \
            /bin/bash "$action35h_preflight/bin/check-pihole-web-health.sh" || return 1
    else
        chown -R pi:pi "$action35h_preflight/state" "$action35h_preflight/run"
        action35h_capture web-service-identity runuser --user pi -- env \
            PIHOLE_WEB_HEALTH_STATE_DIRECTORY="$action35h_preflight/state" \
            PIHOLE_WEB_HEALTH_RUNTIME_DIRECTORY="$action35h_preflight/run" \
            PIHOLE_WEB_HEALTH_ENQUEUE_COMMAND=/usr/bin/true \
            /bin/bash "$action35h_preflight/bin/check-pihole-web-health.sh" || return 1
    fi
    grep -Fq 'check=127_0_0_1_53_A status=0 answer=10.1.0.55' \
        "$action35h_evidence/dns-service-identity.stdout" || return 1
    grep -Fq 'check=__1_5335_AAAA status=0 answer=fd36:5aa8:6971:1::55' \
        "$action35h_evidence/dns-service-identity.stdout" || return 1
    grep -Fxq 'caddy_serving_health_complete=true' \
        "$action35h_evidence/caddy-service-identity.stdout" || return 1
    find "$action35h_preflight" -xdev -mindepth 1 -delete
    rmdir "$action35h_preflight"
    rmdir "$(dirname -- "$action35h_preflight")" 2>/dev/null || :
    printf '%s_check_candidate_validation_complete=true\n' "$action35h_prefix"
}

action35h_backup_current() {
    local action35h_destination
    local action35h_timer_status=0

    action35h_backup=$(action35h_root_path "/var/backups/caddy-action35h/$action35h_node_role")
    [[ ! -e "$action35h_backup" ]] || return 1
    install -d -m 0700 "$action35h_backup"
    for action35h_destination in /etc/scripts/check-dns.sh /usr/local/libexec/check-caddy.sh \
        /usr/local/libexec/check-pihole-web-health.sh /etc/systemd/system/caddy-pihole-web-health.service \
        /etc/systemd/system/caddy-pihole-web-health.timer /etc/keepalived/keepalived.conf; do
        local action35h_existing
        action35h_existing=$(action35h_root_path "$action35h_destination")
        if [[ -f "$action35h_existing" && ! -L "$action35h_existing" ]]; then
            cp -a -- "$action35h_existing" \
                "$action35h_backup/${action35h_destination//\//_}"
        else
            : >"$action35h_backup/${action35h_destination//\//_}.absent"
        fi
    done
    action35h_systemctl is-enabled --quiet caddy-pihole-web-health.timer ||
        action35h_timer_status=$?
    printf '%s\n' "$action35h_timer_status" >"$action35h_backup/timer-enabled.status"
    action35h_timer_status=0
    action35h_systemctl is-active --quiet caddy-pihole-web-health.timer ||
        action35h_timer_status=$?
    printf '%s\n' "$action35h_timer_status" >"$action35h_backup/timer-active.status"
    printf '%s_check_backup_complete=true\n' "$action35h_prefix"
}

action35h_install_candidates() {
    local action35h_repository action35h_source action35h_target action35h_mode
    local action35h_hash action35h_lifecycle action35h_source_path action35h_destination

    while IFS=$'\t' read -r action35h_repository action35h_source action35h_target \
        action35h_mode action35h_hash action35h_lifecycle; do
        [[ -n "$action35h_repository" && "$action35h_repository" != \#* ]] || continue
        case "$action35h_target" in
            */keepalived.conf)
                [[ "$action35h_node_role" = node-a && "$action35h_source" = *pihole0.conf ]] ||
                    [[ "$action35h_node_role" = node-b && "$action35h_source" = *pihole00.conf ]] || continue
                ;;
            */releases/REVISION/*) continue ;;
        esac
        action35h_source_path=$action35h_payload/files/$action35h_repository/$action35h_source
        action35h_destination=$(action35h_root_path "$action35h_target")
        install -d -m 0755 "$(dirname -- "$action35h_destination")"
        install -m "$action35h_mode" "$action35h_source_path" "$action35h_destination"
        [[ "$(sha256sum "$action35h_destination" | awk '{ print $1 }')" = "$action35h_hash" ]] || return 1
    done <"$action35h_payload/serving-health-production.tsv"
    action35h_mutated=true
    printf '1\n' >"$action35h_evidence/mutation-count"
    action35h_capture daemon-reload action35h_systemctl daemon-reload || return 1
    action35h_capture backend-timer-enable action35h_systemctl enable --now \
        caddy-pihole-web-health.timer || return 1
    action35h_capture keepalived-reload action35h_systemctl reload keepalived.service || return 1
    printf '%s_check_mutation_complete=true\n' "$action35h_prefix"
}

action35h_accept() {
    local action35h_sample
    local action35h_expected_ownership='ipv4=Backup ipv6=Backup vip_count=0'
    local action35h_stable=0

    [[ "$action35h_node_role" = node-b ]] ||
        action35h_expected_ownership='ipv4=Master ipv6=Master vip_count=4'

    for action35h_sample in $(seq 1 30); do
        action35h_capture "post-dns-$action35h_sample" action35h_run_as pi \
            /bin/bash "$(action35h_root_path /etc/scripts/check-dns.sh)" || return 1
        action35h_capture "post-caddy-$action35h_sample" action35h_run_as keepalived_script \
            /usr/bin/timeout 2 /bin/bash "$(action35h_root_path /usr/local/libexec/check-caddy.sh)" || return 1
        action35h_capture "ownership-$action35h_sample" action35h_ownership_snapshot || return 1
        if grep -Fxq "$action35h_expected_ownership" \
            "$action35h_evidence/ownership-$action35h_sample.stdout"; then
            action35h_stable=$((action35h_stable + 1))
        else
            action35h_stable=0
        fi
        [[ "$action35h_stable" -lt 3 ]] || break
        sleep 1
    done
    [[ "$action35h_stable" -eq 3 ]] || return 1
    action35h_capture timer-active action35h_systemctl is-active --quiet \
        caddy-pihole-web-health.timer || return 1
    action35h_capture timer-enabled action35h_systemctl is-enabled --quiet \
        caddy-pihole-web-health.timer || return 1
    if [[ -n "$action35h_test_root" ]]; then
        action35h_capture journal-after-cursor /bin/bash "$action35h_test_root/bin/journalctl" \
            --after-cursor "$(<"$action35h_evidence/journal.cursor")" --no-pager || return 1
    else
        action35h_capture journal-after-cursor journalctl \
            --after-cursor "$(<"$action35h_evidence/journal.cursor")" --no-pager || return 1
    fi
    if grep -Eiq 'simultaneous[_ -]ownership|script.*timed out|unsafe|secret' \
        "$action35h_evidence/journal-after-cursor.stdout"; then
        return 1
    fi
    printf '%s_check_acceptance_complete=true\n' "$action35h_prefix"
}

action35h_rollback() {
    local action35h_destination action35h_saved action35h_absent
    local action35h_temporary

    [[ "$action35h_mutated" = true ]] || return 0
    if [[ "$(<"$action35h_backup/timer-enabled.status")" -ne 0 ]]; then
        action35h_systemctl disable --now caddy-pihole-web-health.timer \
            >/dev/null 2>&1 || return 1
    fi
    for action35h_destination in /etc/scripts/check-dns.sh /usr/local/libexec/check-caddy.sh \
        /usr/local/libexec/check-pihole-web-health.sh /etc/systemd/system/caddy-pihole-web-health.service \
        /etc/systemd/system/caddy-pihole-web-health.timer /etc/keepalived/keepalived.conf; do
        action35h_saved=$action35h_backup/${action35h_destination//\//_}
        action35h_absent=$action35h_saved.absent
        if [[ -f "$action35h_saved" && ! -L "$action35h_saved" ]]; then
            action35h_temporary=$(action35h_root_path "$action35h_destination.rollback-action35h")
            [[ ! -e "$action35h_temporary" && ! -L "$action35h_temporary" ]] || return 1
            cp -a -- "$action35h_saved" "$action35h_temporary"
            mv -fT -- "$action35h_temporary" "$(action35h_root_path "$action35h_destination")"
        elif [[ -f "$action35h_absent" && ! -L "$action35h_absent" ]]; then
            rm -f -- "$(action35h_root_path "$action35h_destination")"
        else
            return 1
        fi
    done
    action35h_systemctl daemon-reload >/dev/null 2>&1 || return 1
    if [[ "$(<"$action35h_backup/timer-enabled.status")" -eq 0 ]]; then
        action35h_systemctl enable caddy-pihole-web-health.timer >/dev/null 2>&1 || return 1
    fi
    if [[ "$(<"$action35h_backup/timer-active.status")" -eq 0 ]]; then
        action35h_systemctl start caddy-pihole-web-health.timer >/dev/null 2>&1 || return 1
    fi
    action35h_systemctl reload keepalived.service >/dev/null 2>&1 || return 1
    printf '%s_check_rollback_complete=true\n' "$action35h_prefix"
}

action35h_cleanup() {
    local action35h_status=$?

    if [[ -n "$action35h_preflight" && -d "$action35h_preflight" && ! -L "$action35h_preflight" ]]; then
        find "$action35h_preflight" -xdev -mindepth 1 -delete || :
        rmdir "$action35h_preflight" 2>/dev/null || :
        rmdir "$(dirname -- "$action35h_preflight")" 2>/dev/null || :
    fi
    if ((action35h_status != 0)) && [[ "$action35h_mutated" = true ]]; then
        if ! action35h_rollback; then
            exit 125
        fi
    fi
    exit "$action35h_status"
}

while (($#)); do
    case "$1" in
        --node-role)
            action35h_node_role=${2:-}
            shift 2
            ;;
        --payload)
            action35h_payload=${2:-}
            shift 2
            ;;
        --production-path-test)
            action35h_test_root=${2:-}
            shift 2
            ;;
        --rollback-existing)
            action35h_mode=rollback
            shift
            ;;
        *)
            action35h_usage
            exit 64
            ;;
    esac
done

[[ "$action35h_node_role" =~ ^node-[ab]$ ]] || {
    action35h_usage
    exit 64
}
if [[ "$action35h_mode" = apply ]]; then
    [[ -d "$action35h_payload" && ! -L "$action35h_payload" ]] || exit 64
fi
if [[ -n "$action35h_test_root" ]]; then
    [[ "$action35h_test_root" = /tmp/* && -d "$action35h_test_root" && ! -L "$action35h_test_root" ]] || exit 64
fi

action35h_evidence=$(action35h_root_path "$action35h_node_evidence/$action35h_node_role")
readonly action35h_evidence
if [[ "$action35h_mode" = rollback ]]; then
    action35h_backup=$(action35h_root_path "/var/backups/caddy-action35h/$action35h_node_role")
    [[ -d "$action35h_backup" && ! -L "$action35h_backup" ]] || exit 1
    action35h_mutated=true
    action35h_rollback
    exit 0
fi
[[ ! -e "$action35h_evidence" ]] || exit 1
install -d -m 0700 "$action35h_evidence"
printf '0\n' >"$action35h_evidence/mutation-count"
if [[ -n "$action35h_test_root" ]]; then
    /bin/bash "$action35h_test_root/bin/journalctl" --show-cursor --no-pager \
        >"$action35h_evidence/journal.cursor"
else
    journalctl --show-cursor --no-pager >"$action35h_evidence/journal.cursor"
fi
trap action35h_cleanup EXIT INT TERM

action35h_check payload_contract action35h_validate_payload
action35h_validate_baseline
action35h_validate_candidates
action35h_backup_current
action35h_install_candidates
action35h_accept
action35h_check residue_absent test -z \
    "$(find "$(action35h_root_path /var/lib/caddy-sync/incoming)" -mindepth 1 -maxdepth 1 -name 'action35h-*' -print -quit 2>/dev/null)"
printf '%s_check_complete=true\n' "$action35h_prefix"
