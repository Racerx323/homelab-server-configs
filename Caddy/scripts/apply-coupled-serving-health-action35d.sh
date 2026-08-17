#!/usr/bin/env bash
# shellcheck disable=SC2016 # The captured Bash predicate expands only inside its child shell.

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH
readonly PATH

readonly action35d_prefix=action_35d
readonly action35d_expected_manifest_sha256=86f71fba1b126754fa560ddf49f569c2b06f85ab603a9a24f59921d1064da087
readonly action35d_node_evidence=/tmp/caddy-action35d

action35d_node_role=
action35d_payload=
action35d_test_root=
action35d_mode=apply
action35d_mutated=false
action35d_backup=
action35d_preflight=

if [[ "${1:-}" = --production-path-test && $# -eq 1 ]]; then
    action35d_self_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
    readonly action35d_self_directory
    exec /bin/bash "$action35d_self_directory/../tests/coupled-serving-health-deployment-regression.sh" \
        --entrypoint transaction
fi

action35d_usage() {
    printf 'Usage: %s --node-role node-a|node-b --payload DIRECTORY [--production-path-test ROOT]\n' "${0##*/}" >&2
}

action35d_check() {
    local action35d_label=$1

    shift
    if "$@"; then
        printf '%s_check_%s=true\n' "$action35d_prefix" "$action35d_label"
        return 0
    fi
    printf '%s_check_%s=false\n' "$action35d_prefix" "$action35d_label" >&2
    return 1
}

action35d_root_path() {
    local action35d_path=$1

    if [[ -n "$action35d_test_root" ]]; then
        printf '%s%s' "${action35d_test_root%/}" "$action35d_path"
    else
        printf '%s' "$action35d_path"
    fi
}

action35d_systemctl() {
    if [[ -n "$action35d_test_root" ]]; then
        /bin/bash "$action35d_test_root/bin/systemctl" "$@"
    else
        systemctl "$@"
    fi
}

action35d_keepalived_parser() {
    local action35d_config=$1

    if [[ -n "$action35d_test_root" ]]; then
        /bin/bash "$action35d_test_root/bin/keepalived" --config-test --use-file="$action35d_config"
    else
        keepalived --config-test --use-file="$action35d_config"
    fi
}

action35d_ownership_snapshot() {
    if [[ -n "$action35d_test_root" ]]; then
        /bin/bash "$action35d_test_root/bin/ownership" "$action35d_node_role"
        return
    fi
    local action35d_ipv4_state action35d_ipv6_state action35d_vip_count
    action35d_ipv4_state=$(timeout 2 busctl get-property org.keepalived.Vrrp1 \
        /org/keepalived/Vrrp1/Instance/eth0/100/IPv4 org.keepalived.Vrrp1.Instance State)
    action35d_ipv6_state=$(timeout 2 busctl get-property org.keepalived.Vrrp1 \
        /org/keepalived/Vrrp1/Instance/eth0/101/IPv6 org.keepalived.Vrrp1.Instance State)
    case "$action35d_ipv4_state" in
        *'"Master"') action35d_ipv4_state=Master ;;
        *'"Backup"') action35d_ipv4_state=Backup ;;
        *) return 1 ;;
    esac
    case "$action35d_ipv6_state" in
        *'"Master"') action35d_ipv6_state=Master ;;
        *'"Backup"') action35d_ipv6_state=Backup ;;
        *) return 1 ;;
    esac
    action35d_vip_count=$(
        ip -o address show dev eth0 |
            awk '$4 ~ /^(10\.1\.0\.(55|56)\/22|fd36:5aa8:6971:1::(55|56)\/128)$/ { count++ } END { print count + 0 }'
    )
    printf 'ipv4=%s ipv6=%s vip_count=%s\n' \
        "$action35d_ipv4_state" "$action35d_ipv6_state" "$action35d_vip_count"
}

action35d_run_as() {
    local action35d_identity=$1

    shift
    if [[ -n "$action35d_test_root" ]]; then
        {
            printf '%s\t' "$action35d_identity"
            printf '%q ' "$@"
            printf '\n'
        } >>"$action35d_test_root/calls/identities.tsv"
        env \
            DNS_CHECK_DIG_COMMAND="$action35d_test_root/bin/dig" \
            DNS_CHECK_SYSTEMCTL_COMMAND="$action35d_test_root/bin/systemctl" \
            CADDY_SERVING_HEALTH_ENVIRONMENT_FILE="$action35d_test_root/etc/default/caddy-ha" \
            CADDY_SERVING_HEALTH_CURL_COMMAND="$action35d_test_root/bin/curl" \
            CADDY_SERVING_HEALTH_SS_COMMAND="$action35d_test_root/bin/ss" \
            CADDY_SERVING_HEALTH_SYSTEMCTL_COMMAND="$action35d_test_root/bin/systemctl" \
            PIHOLE_WEB_HEALTH_ENVIRONMENT_FILE="$action35d_test_root/etc/default/caddy-ha" \
            PIHOLE_WEB_HEALTH_STATE_DIRECTORY="$action35d_test_root/var/lib/caddy-pihole-web-health" \
            PIHOLE_WEB_HEALTH_RUNTIME_DIRECTORY="$action35d_test_root/run/caddy-pihole-web-health" \
            PIHOLE_WEB_HEALTH_ENQUEUE_COMMAND="$action35d_test_root/bin/enqueue" \
            PIHOLE_WEB_HEALTH_CURL_COMMAND="$action35d_test_root/bin/curl" \
            PIHOLE_WEB_HEALTH_SYSTEMCTL_COMMAND="$action35d_test_root/bin/systemctl" \
            "$@"
    else
        runuser --user "$action35d_identity" -- "$@"
    fi
}

action35d_capture() {
    local action35d_label=$1

    shift
    local action35d_stdout action35d_stderr action35d_status=0
    action35d_stdout=$action35d_evidence/$action35d_label.stdout
    action35d_stderr=$action35d_evidence/$action35d_label.stderr
    : >"$action35d_stdout"
    : >"$action35d_stderr"
    "$@" >"$action35d_stdout" 2>"$action35d_stderr" || action35d_status=$?
    printf '%s\n' "$action35d_status" >"$action35d_evidence/$action35d_label.status"
    [[ -f "$action35d_stdout" && ! -L "$action35d_stdout" ]] || return 1
    [[ -f "$action35d_stderr" && ! -L "$action35d_stderr" ]] || return 1
    return "$action35d_status"
}

action35d_require_regular() {
    local action35d_path=$1
    local action35d_mode=${2:-}

    [[ -f "$action35d_path" && ! -L "$action35d_path" ]] || return 1
    [[ -z "$action35d_mode" || "$(stat -c '%a' "$action35d_path")" = "$action35d_mode" ]]
}

action35d_validate_payload() {
    local action35d_line action35d_repository action35d_source action35d_target
    local action35d_mode action35d_hash action35d_lifecycle action35d_source_path

    action35d_require_regular "$action35d_payload/serving-health-production.tsv" || return 1
    [[ "$(sed -n '1p' "$action35d_payload/serving-health-production.tsv")" = $'# repository\tsource-path\tinstalled-path\tmode\tcandidate-sha256\tlifecycle' ]] || return 1
    while IFS=$'\t' read -r action35d_repository action35d_source action35d_target \
        action35d_mode action35d_hash action35d_lifecycle; do
        [[ -n "$action35d_repository" && "$action35d_repository" != \#* ]] || continue
        [[ "$action35d_repository" =~ ^homelab-(server-configs|dns)$ ]] || return 1
        [[ "$action35d_source" != *..* && "$action35d_target" = /* ]] || return 1
        [[ "$action35d_mode" =~ ^0[0-7]{3}$ && "$action35d_hash" =~ ^[0-9a-f]{64}$ ]] || return 1
        [[ "$action35d_lifecycle" = production-candidate ]] || return 1
        action35d_source_path=$action35d_payload/files/$action35d_repository/$action35d_source
        action35d_require_regular "$action35d_source_path" || return 1
        [[ "$(sha256sum "$action35d_source_path" | awk '{ print $1 }')" = "$action35d_hash" ]] || return 1
        printf '%s\t%s\t%s\n' "$action35d_target" "$action35d_hash" "$action35d_mode" \
            >>"$action35d_evidence/payload-identities.tsv"
        action35d_line=true
    done <"$action35d_payload/serving-health-production.tsv"
    [[ "${action35d_line:-false}" = true ]]
}

action35d_validate_baseline() {
    local action35d_expected_state=$action35d_payload/current-live-state.tsv
    local action35d_current_link
    local action35d_key action35d_repository action35d_source action35d_installed
    local action35d_inventory_node action35d_source_hash action35d_deployed_hash
    local action35d_accepted_action action35d_lifecycle action35d_installed_path

    action35d_require_regular "$action35d_expected_state" || return 1
    action35d_require_regular "$action35d_payload/production-artifacts.tsv" || return 1
    action35d_check baseline_manifest_identity test \
        "$(sha256sum "$action35d_expected_state" | awk '{ print $1 }')" = "$action35d_expected_manifest_sha256" || return 1
    for action35d_unit in caddy.service caddy-lsyncd.service caddy-sync-reconcile.path \
        caddy-apprise-worker.path caddy-apprise-worker.timer keepalived.service \
        pihole-FTL.service unbound.service lighttpd.service; do
        action35d_capture "baseline-${action35d_unit//./-}" \
            action35d_systemctl is-active --quiet "$action35d_unit" || return 1
    done
    for action35d_unit in caddy.service caddy-lsyncd.service caddy-sync-reconcile.path \
        caddy-apprise-worker.path caddy-apprise-worker.timer; do
        action35d_capture "enabled-${action35d_unit//./-}" \
            action35d_systemctl is-enabled --quiet "$action35d_unit" || return 1
    done
    action35d_current_link=$(action35d_root_path /etc/caddy/current)
    [[ -L "$action35d_current_link" ]] || return 1
    readlink -f -- "$action35d_current_link" >"$action35d_evidence/original-release.path"
    action35d_require_regular "$(<"$action35d_evidence/original-release.path")/release-manifest.json" || return 1
    action35d_capture baseline-residue /bin/bash -c \
        'test -z "$(find "$1" -mindepth 1 -maxdepth 1 -name "action35d-*" -print -quit 2>/dev/null)"' \
        _ "$(action35d_root_path /var/lib/caddy-sync/incoming)" || return 1
    while IFS=$'\t' read -r action35d_key action35d_repository action35d_source \
        action35d_installed action35d_inventory_node action35d_source_hash \
        action35d_deployed_hash action35d_accepted_action action35d_lifecycle; do
        [[ -n "$action35d_key" && "$action35d_key" != \#* ]] || continue
        [[ "$action35d_inventory_node" = "$action35d_node_role" ]] || continue
        : "$action35d_repository" "$action35d_source" "$action35d_source_hash"
        [[ "$action35d_lifecycle" = production-current && "$action35d_installed" = /* ]] || return 1
        [[ "$action35d_deployed_hash" =~ ^[0-9a-f]{64}$ ]] || return 1
        action35d_installed_path=$(action35d_root_path "$action35d_installed")
        action35d_require_regular "$action35d_installed_path" || return 1
        [[ "$(sha256sum "$action35d_installed_path" | awk '{ print $1 }')" = "$action35d_deployed_hash" ]] || return 1
        printf '%s\t%s\t%s\n' "$action35d_key" "$action35d_deployed_hash" \
            "$action35d_accepted_action" >>"$action35d_evidence/baseline-identities.tsv"
    done <"$action35d_payload/production-artifacts.tsv"
    printf '%s_check_baseline_complete=true\n' "$action35d_prefix"
}

action35d_validate_candidates() {
    local action35d_keepalived action35d_dns action35d_caddy action35d_web

    action35d_keepalived=$action35d_payload/files/homelab-dns/Keepalived/configs/keepalived-pihole0.conf
    [[ "$action35d_node_role" = node-b ]] &&
        action35d_keepalived=$action35d_payload/files/homelab-dns/Keepalived/configs/keepalived-pihole00.conf
    action35d_dns=$action35d_payload/files/homelab-dns/Keepalived/scripts/dns-check.sh
    action35d_caddy=$action35d_payload/files/homelab-server-configs/Caddy/scripts/check-caddy-serving-health.sh
    action35d_web=$action35d_payload/files/homelab-server-configs/Caddy/scripts/check-pihole-web-health.sh
    action35d_preflight=$(action35d_root_path "/tmp/caddy-action35d-preflight/$action35d_node_role")
    [[ ! -e "$action35d_preflight" ]] || return 1
    install -d -m 0755 "$action35d_preflight/bin" "$action35d_preflight/state" \
        "$action35d_preflight/run"
    install -m 0755 "$action35d_dns" "$action35d_preflight/bin/check-dns.sh"
    install -m 0755 "$action35d_caddy" "$action35d_preflight/bin/check-caddy.sh"
    install -m 0755 "$action35d_web" "$action35d_preflight/bin/check-pihole-web-health.sh"
    action35d_capture keepalived-parser action35d_keepalived_parser "$action35d_keepalived" || return 1
    action35d_capture dns-service-identity action35d_run_as pi \
        /bin/bash "$action35d_preflight/bin/check-dns.sh" || return 1
    action35d_capture caddy-service-identity action35d_run_as keepalived_script \
        /usr/bin/timeout 2 /bin/bash "$action35d_preflight/bin/check-caddy.sh" || return 1
    if [[ -n "$action35d_test_root" ]]; then
        action35d_capture web-service-identity action35d_run_as pi \
            /bin/bash "$action35d_preflight/bin/check-pihole-web-health.sh" || return 1
    else
        chown -R pi:pi "$action35d_preflight/state" "$action35d_preflight/run"
        action35d_capture web-service-identity runuser --user pi -- env \
            PIHOLE_WEB_HEALTH_STATE_DIRECTORY="$action35d_preflight/state" \
            PIHOLE_WEB_HEALTH_RUNTIME_DIRECTORY="$action35d_preflight/run" \
            PIHOLE_WEB_HEALTH_ENQUEUE_COMMAND=/usr/bin/true \
            /bin/bash "$action35d_preflight/bin/check-pihole-web-health.sh" || return 1
    fi
    grep -Fq 'check=127_0_0_1_53_A status=0 answer=10.1.0.55' \
        "$action35d_evidence/dns-service-identity.stdout" || return 1
    grep -Fq 'check=__1_5335_AAAA status=0 answer=fd36:5aa8:6971:1::55' \
        "$action35d_evidence/dns-service-identity.stdout" || return 1
    grep -Fxq 'caddy_serving_health_complete=true' \
        "$action35d_evidence/caddy-service-identity.stdout" || return 1
    find "$action35d_preflight" -xdev -mindepth 1 -delete
    rmdir "$action35d_preflight"
    rmdir "$(dirname -- "$action35d_preflight")" 2>/dev/null || :
    printf '%s_check_candidate_validation_complete=true\n' "$action35d_prefix"
}

action35d_backup_current() {
    local action35d_destination
    local action35d_timer_status=0

    action35d_backup=$(action35d_root_path "/var/backups/caddy-action35d/$action35d_node_role")
    [[ ! -e "$action35d_backup" ]] || return 1
    install -d -m 0700 "$action35d_backup"
    for action35d_destination in /etc/scripts/check-dns.sh /usr/local/libexec/check-caddy.sh \
        /usr/local/libexec/check-pihole-web-health.sh /etc/systemd/system/caddy-pihole-web-health.service \
        /etc/systemd/system/caddy-pihole-web-health.timer /etc/keepalived/keepalived.conf; do
        local action35d_existing
        action35d_existing=$(action35d_root_path "$action35d_destination")
        if [[ -f "$action35d_existing" && ! -L "$action35d_existing" ]]; then
            cp -a -- "$action35d_existing" \
                "$action35d_backup/${action35d_destination//\//_}"
        else
            : >"$action35d_backup/${action35d_destination//\//_}.absent"
        fi
    done
    action35d_systemctl is-enabled --quiet caddy-pihole-web-health.timer ||
        action35d_timer_status=$?
    printf '%s\n' "$action35d_timer_status" >"$action35d_backup/timer-enabled.status"
    action35d_timer_status=0
    action35d_systemctl is-active --quiet caddy-pihole-web-health.timer ||
        action35d_timer_status=$?
    printf '%s\n' "$action35d_timer_status" >"$action35d_backup/timer-active.status"
    printf '%s_check_backup_complete=true\n' "$action35d_prefix"
}

action35d_install_candidates() {
    local action35d_repository action35d_source action35d_target action35d_mode
    local action35d_hash action35d_lifecycle action35d_source_path action35d_destination

    while IFS=$'\t' read -r action35d_repository action35d_source action35d_target \
        action35d_mode action35d_hash action35d_lifecycle; do
        [[ -n "$action35d_repository" && "$action35d_repository" != \#* ]] || continue
        case "$action35d_target" in
            */keepalived.conf)
                [[ "$action35d_node_role" = node-a && "$action35d_source" = *pihole0.conf ]] ||
                    [[ "$action35d_node_role" = node-b && "$action35d_source" = *pihole00.conf ]] || continue
                ;;
            */releases/REVISION/*) continue ;;
        esac
        action35d_source_path=$action35d_payload/files/$action35d_repository/$action35d_source
        action35d_destination=$(action35d_root_path "$action35d_target")
        install -d -m 0755 "$(dirname -- "$action35d_destination")"
        install -m "$action35d_mode" "$action35d_source_path" "$action35d_destination"
        [[ "$(sha256sum "$action35d_destination" | awk '{ print $1 }')" = "$action35d_hash" ]] || return 1
    done <"$action35d_payload/serving-health-production.tsv"
    action35d_mutated=true
    printf '1\n' >"$action35d_evidence/mutation-count"
    action35d_capture daemon-reload action35d_systemctl daemon-reload || return 1
    action35d_capture backend-timer-enable action35d_systemctl enable --now \
        caddy-pihole-web-health.timer || return 1
    action35d_capture keepalived-reload action35d_systemctl reload keepalived.service || return 1
    printf '%s_check_mutation_complete=true\n' "$action35d_prefix"
}

action35d_accept() {
    local action35d_sample
    local action35d_expected_ownership='ipv4=Backup ipv6=Backup vip_count=0'
    local action35d_stable=0

    [[ "$action35d_node_role" = node-b ]] ||
        action35d_expected_ownership='ipv4=Master ipv6=Master vip_count=4'

    for action35d_sample in $(seq 1 30); do
        action35d_capture "post-dns-$action35d_sample" action35d_run_as pi \
            /bin/bash "$(action35d_root_path /etc/scripts/check-dns.sh)" || return 1
        action35d_capture "post-caddy-$action35d_sample" action35d_run_as keepalived_script \
            /usr/bin/timeout 2 /bin/bash "$(action35d_root_path /usr/local/libexec/check-caddy.sh)" || return 1
        action35d_capture "ownership-$action35d_sample" action35d_ownership_snapshot || return 1
        if grep -Fxq "$action35d_expected_ownership" \
            "$action35d_evidence/ownership-$action35d_sample.stdout"; then
            action35d_stable=$((action35d_stable + 1))
        else
            action35d_stable=0
        fi
        [[ "$action35d_stable" -lt 3 ]] || break
        sleep 1
    done
    [[ "$action35d_stable" -eq 3 ]] || return 1
    action35d_capture timer-active action35d_systemctl is-active --quiet \
        caddy-pihole-web-health.timer || return 1
    action35d_capture timer-enabled action35d_systemctl is-enabled --quiet \
        caddy-pihole-web-health.timer || return 1
    if [[ -n "$action35d_test_root" ]]; then
        action35d_capture journal-after-cursor /bin/bash "$action35d_test_root/bin/journalctl" \
            --after-cursor "$(<"$action35d_evidence/journal.cursor")" --no-pager || return 1
    else
        action35d_capture journal-after-cursor journalctl \
            --after-cursor "$(<"$action35d_evidence/journal.cursor")" --no-pager || return 1
    fi
    if grep -Eiq 'simultaneous[_ -]ownership|script.*timed out|unsafe|secret' \
        "$action35d_evidence/journal-after-cursor.stdout"; then
        return 1
    fi
    printf '%s_check_acceptance_complete=true\n' "$action35d_prefix"
}

action35d_rollback() {
    local action35d_destination action35d_saved action35d_absent
    local action35d_temporary

    [[ "$action35d_mutated" = true ]] || return 0
    if [[ "$(<"$action35d_backup/timer-enabled.status")" -ne 0 ]]; then
        action35d_systemctl disable --now caddy-pihole-web-health.timer \
            >/dev/null 2>&1 || return 1
    fi
    for action35d_destination in /etc/scripts/check-dns.sh /usr/local/libexec/check-caddy.sh \
        /usr/local/libexec/check-pihole-web-health.sh /etc/systemd/system/caddy-pihole-web-health.service \
        /etc/systemd/system/caddy-pihole-web-health.timer /etc/keepalived/keepalived.conf; do
        action35d_saved=$action35d_backup/${action35d_destination//\//_}
        action35d_absent=$action35d_saved.absent
        if [[ -f "$action35d_saved" && ! -L "$action35d_saved" ]]; then
            action35d_temporary=$(action35d_root_path "$action35d_destination.rollback-action35d")
            [[ ! -e "$action35d_temporary" && ! -L "$action35d_temporary" ]] || return 1
            cp -a -- "$action35d_saved" "$action35d_temporary"
            mv -fT -- "$action35d_temporary" "$(action35d_root_path "$action35d_destination")"
        elif [[ -f "$action35d_absent" && ! -L "$action35d_absent" ]]; then
            rm -f -- "$(action35d_root_path "$action35d_destination")"
        else
            return 1
        fi
    done
    action35d_systemctl daemon-reload >/dev/null 2>&1 || return 1
    if [[ "$(<"$action35d_backup/timer-enabled.status")" -eq 0 ]]; then
        action35d_systemctl enable caddy-pihole-web-health.timer >/dev/null 2>&1 || return 1
    fi
    if [[ "$(<"$action35d_backup/timer-active.status")" -eq 0 ]]; then
        action35d_systemctl start caddy-pihole-web-health.timer >/dev/null 2>&1 || return 1
    fi
    action35d_systemctl reload keepalived.service >/dev/null 2>&1 || return 1
    printf '%s_check_rollback_complete=true\n' "$action35d_prefix"
}

action35d_cleanup() {
    local action35d_status=$?

    if [[ -n "$action35d_preflight" && -d "$action35d_preflight" && ! -L "$action35d_preflight" ]]; then
        find "$action35d_preflight" -xdev -mindepth 1 -delete || :
        rmdir "$action35d_preflight" 2>/dev/null || :
        rmdir "$(dirname -- "$action35d_preflight")" 2>/dev/null || :
    fi
    if ((action35d_status != 0)) && [[ "$action35d_mutated" = true ]]; then
        if ! action35d_rollback; then
            exit 125
        fi
    fi
    exit "$action35d_status"
}

while (($#)); do
    case "$1" in
        --node-role)
            action35d_node_role=${2:-}
            shift 2
            ;;
        --payload)
            action35d_payload=${2:-}
            shift 2
            ;;
        --production-path-test)
            action35d_test_root=${2:-}
            shift 2
            ;;
        --rollback-existing)
            action35d_mode=rollback
            shift
            ;;
        *)
            action35d_usage
            exit 64
            ;;
    esac
done

[[ "$action35d_node_role" =~ ^node-[ab]$ ]] || {
    action35d_usage
    exit 64
}
if [[ "$action35d_mode" = apply ]]; then
    [[ -d "$action35d_payload" && ! -L "$action35d_payload" ]] || exit 64
fi
if [[ -n "$action35d_test_root" ]]; then
    [[ "$action35d_test_root" = /tmp/* && -d "$action35d_test_root" && ! -L "$action35d_test_root" ]] || exit 64
fi

action35d_evidence=$(action35d_root_path "$action35d_node_evidence/$action35d_node_role")
readonly action35d_evidence
if [[ "$action35d_mode" = rollback ]]; then
    action35d_backup=$(action35d_root_path "/var/backups/caddy-action35d/$action35d_node_role")
    [[ -d "$action35d_backup" && ! -L "$action35d_backup" ]] || exit 1
    action35d_mutated=true
    action35d_rollback
    exit 0
fi
[[ ! -e "$action35d_evidence" ]] || exit 1
install -d -m 0700 "$action35d_evidence"
printf '0\n' >"$action35d_evidence/mutation-count"
if [[ -n "$action35d_test_root" ]]; then
    /bin/bash "$action35d_test_root/bin/journalctl" --show-cursor --no-pager \
        >"$action35d_evidence/journal.cursor"
else
    journalctl --show-cursor --no-pager >"$action35d_evidence/journal.cursor"
fi
trap action35d_cleanup EXIT INT TERM

action35d_check payload_contract action35d_validate_payload
action35d_validate_baseline
action35d_validate_candidates
action35d_backup_current
action35d_install_candidates
action35d_accept
action35d_check residue_absent test -z \
    "$(find "$(action35d_root_path /var/lib/caddy-sync/incoming)" -mindepth 1 -maxdepth 1 -name 'action35d-*' -print -quit 2>/dev/null)"
printf '%s_check_complete=true\n' "$action35d_prefix"
