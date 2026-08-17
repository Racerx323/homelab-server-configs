#!/usr/bin/env bash
# shellcheck disable=SC2016 # The captured Bash predicate expands only inside its child shell.

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH
readonly PATH

readonly action35c_prefix=action_35c
readonly action35c_expected_manifest_sha256=86f71fba1b126754fa560ddf49f569c2b06f85ab603a9a24f59921d1064da087
readonly action35c_node_evidence=/tmp/caddy-action35c

action35c_node_role=
action35c_payload=
action35c_test_root=
action35c_mode=apply
action35c_mutated=false
action35c_backup=
action35c_preflight=

if [[ "${1:-}" = --production-path-test && $# -eq 1 ]]; then
    action35c_self_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
    readonly action35c_self_directory
    exec /bin/bash "$action35c_self_directory/../tests/coupled-serving-health-deployment-regression.sh" \
        --entrypoint transaction
fi

action35c_usage() {
    printf 'Usage: %s --node-role node-a|node-b --payload DIRECTORY [--production-path-test ROOT]\n' "${0##*/}" >&2
}

action35c_check() {
    local action35c_label=$1

    shift
    if "$@"; then
        printf '%s_check_%s=true\n' "$action35c_prefix" "$action35c_label"
        return 0
    fi
    printf '%s_check_%s=false\n' "$action35c_prefix" "$action35c_label" >&2
    return 1
}

action35c_root_path() {
    local action35c_path=$1

    if [[ -n "$action35c_test_root" ]]; then
        printf '%s%s' "${action35c_test_root%/}" "$action35c_path"
    else
        printf '%s' "$action35c_path"
    fi
}

action35c_systemctl() {
    if [[ -n "$action35c_test_root" ]]; then
        /bin/bash "$action35c_test_root/bin/systemctl" "$@"
    else
        systemctl "$@"
    fi
}

action35c_keepalived_parser() {
    local action35c_config=$1

    if [[ -n "$action35c_test_root" ]]; then
        /bin/bash "$action35c_test_root/bin/keepalived" --config-test --use-file="$action35c_config"
    else
        keepalived --config-test --use-file="$action35c_config"
    fi
}

action35c_ownership_snapshot() {
    if [[ -n "$action35c_test_root" ]]; then
        /bin/bash "$action35c_test_root/bin/ownership" "$action35c_node_role"
        return
    fi
    local action35c_ipv4_state action35c_ipv6_state action35c_vip_count
    action35c_ipv4_state=$(timeout 2 busctl get-property org.keepalived.Vrrp1 \
        /org/keepalived/Vrrp1/Instance/eth0/100/IPv4 org.keepalived.Vrrp1.Instance State)
    action35c_ipv6_state=$(timeout 2 busctl get-property org.keepalived.Vrrp1 \
        /org/keepalived/Vrrp1/Instance/eth0/101/IPv6 org.keepalived.Vrrp1.Instance State)
    case "$action35c_ipv4_state" in
        *'"Master"') action35c_ipv4_state=Master ;;
        *'"Backup"') action35c_ipv4_state=Backup ;;
        *) return 1 ;;
    esac
    case "$action35c_ipv6_state" in
        *'"Master"') action35c_ipv6_state=Master ;;
        *'"Backup"') action35c_ipv6_state=Backup ;;
        *) return 1 ;;
    esac
    action35c_vip_count=$(
        ip -o address show dev eth0 |
            awk '$4 ~ /^(10\.1\.0\.(55|56)\/22|fd36:5aa8:6971:1::(55|56)\/128)$/ { count++ } END { print count + 0 }'
    )
    printf 'ipv4=%s ipv6=%s vip_count=%s\n' \
        "$action35c_ipv4_state" "$action35c_ipv6_state" "$action35c_vip_count"
}

action35c_run_as() {
    local action35c_identity=$1

    shift
    if [[ -n "$action35c_test_root" ]]; then
        {
            printf '%s\t' "$action35c_identity"
            printf '%q ' "$@"
            printf '\n'
        } >>"$action35c_test_root/calls/identities.tsv"
        env \
            DNS_CHECK_DIG_COMMAND="$action35c_test_root/bin/dig" \
            DNS_CHECK_SYSTEMCTL_COMMAND="$action35c_test_root/bin/systemctl" \
            CADDY_SERVING_HEALTH_ENVIRONMENT_FILE="$action35c_test_root/etc/default/caddy-ha" \
            CADDY_SERVING_HEALTH_CURL_COMMAND="$action35c_test_root/bin/curl" \
            CADDY_SERVING_HEALTH_SS_COMMAND="$action35c_test_root/bin/ss" \
            CADDY_SERVING_HEALTH_SYSTEMCTL_COMMAND="$action35c_test_root/bin/systemctl" \
            PIHOLE_WEB_HEALTH_ENVIRONMENT_FILE="$action35c_test_root/etc/default/caddy-ha" \
            PIHOLE_WEB_HEALTH_STATE_DIRECTORY="$action35c_test_root/var/lib/caddy-pihole-web-health" \
            PIHOLE_WEB_HEALTH_RUNTIME_DIRECTORY="$action35c_test_root/run/caddy-pihole-web-health" \
            PIHOLE_WEB_HEALTH_ENQUEUE_COMMAND="$action35c_test_root/bin/enqueue" \
            PIHOLE_WEB_HEALTH_CURL_COMMAND="$action35c_test_root/bin/curl" \
            PIHOLE_WEB_HEALTH_SYSTEMCTL_COMMAND="$action35c_test_root/bin/systemctl" \
            "$@"
    else
        runuser --user "$action35c_identity" -- "$@"
    fi
}

action35c_capture() {
    local action35c_label=$1

    shift
    local action35c_stdout action35c_stderr action35c_status=0
    action35c_stdout=$action35c_evidence/$action35c_label.stdout
    action35c_stderr=$action35c_evidence/$action35c_label.stderr
    : >"$action35c_stdout"
    : >"$action35c_stderr"
    "$@" >"$action35c_stdout" 2>"$action35c_stderr" || action35c_status=$?
    printf '%s\n' "$action35c_status" >"$action35c_evidence/$action35c_label.status"
    [[ -f "$action35c_stdout" && ! -L "$action35c_stdout" ]] || return 1
    [[ -f "$action35c_stderr" && ! -L "$action35c_stderr" ]] || return 1
    return "$action35c_status"
}

action35c_require_regular() {
    local action35c_path=$1
    local action35c_mode=${2:-}

    [[ -f "$action35c_path" && ! -L "$action35c_path" ]] || return 1
    [[ -z "$action35c_mode" || "$(stat -c '%a' "$action35c_path")" = "$action35c_mode" ]]
}

action35c_validate_payload() {
    local action35c_line action35c_repository action35c_source action35c_target
    local action35c_mode action35c_hash action35c_lifecycle action35c_source_path

    action35c_require_regular "$action35c_payload/serving-health-production.tsv" || return 1
    [[ "$(sed -n '1p' "$action35c_payload/serving-health-production.tsv")" = $'# repository\tsource-path\tinstalled-path\tmode\tcandidate-sha256\tlifecycle' ]] || return 1
    while IFS=$'\t' read -r action35c_repository action35c_source action35c_target \
        action35c_mode action35c_hash action35c_lifecycle; do
        [[ -n "$action35c_repository" && "$action35c_repository" != \#* ]] || continue
        [[ "$action35c_repository" =~ ^homelab-(server-configs|dns)$ ]] || return 1
        [[ "$action35c_source" != *..* && "$action35c_target" = /* ]] || return 1
        [[ "$action35c_mode" =~ ^0[0-7]{3}$ && "$action35c_hash" =~ ^[0-9a-f]{64}$ ]] || return 1
        [[ "$action35c_lifecycle" = production-candidate ]] || return 1
        action35c_source_path=$action35c_payload/files/$action35c_repository/$action35c_source
        action35c_require_regular "$action35c_source_path" || return 1
        [[ "$(sha256sum "$action35c_source_path" | awk '{ print $1 }')" = "$action35c_hash" ]] || return 1
        printf '%s\t%s\t%s\n' "$action35c_target" "$action35c_hash" "$action35c_mode" \
            >>"$action35c_evidence/payload-identities.tsv"
        action35c_line=true
    done <"$action35c_payload/serving-health-production.tsv"
    [[ "${action35c_line:-false}" = true ]]
}

action35c_validate_baseline() {
    local action35c_expected_state=$action35c_payload/current-live-state.tsv
    local action35c_current_link
    local action35c_key action35c_repository action35c_source action35c_installed
    local action35c_inventory_node action35c_source_hash action35c_deployed_hash
    local action35c_accepted_action action35c_lifecycle action35c_installed_path

    action35c_require_regular "$action35c_expected_state" || return 1
    action35c_require_regular "$action35c_payload/production-artifacts.tsv" || return 1
    action35c_check baseline_manifest_identity test \
        "$(sha256sum "$action35c_expected_state" | awk '{ print $1 }')" = "$action35c_expected_manifest_sha256" || return 1
    for action35c_unit in caddy.service caddy-lsyncd.service caddy-sync-reconcile.path \
        caddy-apprise-worker.path caddy-apprise-worker.timer keepalived.service \
        pihole-FTL.service unbound.service lighttpd.service; do
        action35c_capture "baseline-${action35c_unit//./-}" \
            action35c_systemctl is-active --quiet "$action35c_unit" || return 1
    done
    for action35c_unit in caddy.service caddy-lsyncd.service caddy-sync-reconcile.path \
        caddy-apprise-worker.path caddy-apprise-worker.timer; do
        action35c_capture "enabled-${action35c_unit//./-}" \
            action35c_systemctl is-enabled --quiet "$action35c_unit" || return 1
    done
    action35c_current_link=$(action35c_root_path /etc/caddy/current)
    [[ -L "$action35c_current_link" ]] || return 1
    readlink -f -- "$action35c_current_link" >"$action35c_evidence/original-release.path"
    action35c_require_regular "$(<"$action35c_evidence/original-release.path")/release-manifest.json" || return 1
    action35c_capture baseline-residue /bin/bash -c \
        'test -z "$(find "$1" -mindepth 1 -maxdepth 1 -name "action35c-*" -print -quit 2>/dev/null)"' \
        _ "$(action35c_root_path /var/lib/caddy-sync/incoming)" || return 1
    while IFS=$'\t' read -r action35c_key action35c_repository action35c_source \
        action35c_installed action35c_inventory_node action35c_source_hash \
        action35c_deployed_hash action35c_accepted_action action35c_lifecycle; do
        [[ -n "$action35c_key" && "$action35c_key" != \#* ]] || continue
        [[ "$action35c_inventory_node" = "$action35c_node_role" ]] || continue
        : "$action35c_repository" "$action35c_source" "$action35c_source_hash"
        [[ "$action35c_lifecycle" = production-current && "$action35c_installed" = /* ]] || return 1
        [[ "$action35c_deployed_hash" =~ ^[0-9a-f]{64}$ ]] || return 1
        action35c_installed_path=$(action35c_root_path "$action35c_installed")
        action35c_require_regular "$action35c_installed_path" || return 1
        [[ "$(sha256sum "$action35c_installed_path" | awk '{ print $1 }')" = "$action35c_deployed_hash" ]] || return 1
        printf '%s\t%s\t%s\n' "$action35c_key" "$action35c_deployed_hash" \
            "$action35c_accepted_action" >>"$action35c_evidence/baseline-identities.tsv"
    done <"$action35c_payload/production-artifacts.tsv"
    printf '%s_check_baseline_complete=true\n' "$action35c_prefix"
}

action35c_validate_candidates() {
    local action35c_keepalived action35c_dns action35c_caddy action35c_web

    action35c_keepalived=$action35c_payload/files/homelab-dns/Keepalived/configs/keepalived-pihole0.conf
    [[ "$action35c_node_role" = node-b ]] &&
        action35c_keepalived=$action35c_payload/files/homelab-dns/Keepalived/configs/keepalived-pihole00.conf
    action35c_dns=$action35c_payload/files/homelab-dns/Keepalived/scripts/dns-check.sh
    action35c_caddy=$action35c_payload/files/homelab-server-configs/Caddy/scripts/check-caddy-serving-health.sh
    action35c_web=$action35c_payload/files/homelab-server-configs/Caddy/scripts/check-pihole-web-health.sh
    action35c_preflight=$(action35c_root_path "/tmp/caddy-action35c-preflight/$action35c_node_role")
    [[ ! -e "$action35c_preflight" ]] || return 1
    install -d -m 0755 "$action35c_preflight/bin" "$action35c_preflight/state" \
        "$action35c_preflight/run"
    install -m 0755 "$action35c_dns" "$action35c_preflight/bin/check-dns.sh"
    install -m 0755 "$action35c_caddy" "$action35c_preflight/bin/check-caddy.sh"
    install -m 0755 "$action35c_web" "$action35c_preflight/bin/check-pihole-web-health.sh"
    action35c_capture keepalived-parser action35c_keepalived_parser "$action35c_keepalived" || return 1
    action35c_capture dns-service-identity action35c_run_as pi \
        /bin/bash "$action35c_preflight/bin/check-dns.sh" || return 1
    action35c_capture caddy-service-identity action35c_run_as keepalived_script \
        /usr/bin/timeout 2 /bin/bash "$action35c_preflight/bin/check-caddy.sh" || return 1
    if [[ -n "$action35c_test_root" ]]; then
        action35c_capture web-service-identity action35c_run_as pi \
            /bin/bash "$action35c_preflight/bin/check-pihole-web-health.sh" || return 1
    else
        chown -R pi:pi "$action35c_preflight/state" "$action35c_preflight/run"
        action35c_capture web-service-identity runuser --user pi -- env \
            PIHOLE_WEB_HEALTH_STATE_DIRECTORY="$action35c_preflight/state" \
            PIHOLE_WEB_HEALTH_RUNTIME_DIRECTORY="$action35c_preflight/run" \
            PIHOLE_WEB_HEALTH_ENQUEUE_COMMAND=/usr/bin/true \
            /bin/bash "$action35c_preflight/bin/check-pihole-web-health.sh" || return 1
    fi
    grep -Fq 'check=127_0_0_1_53_A status=0 answer=10.1.0.55' \
        "$action35c_evidence/dns-service-identity.stdout" || return 1
    grep -Fq 'check=__1_5335_AAAA status=0 answer=fd36:5aa8:6971:1::55' \
        "$action35c_evidence/dns-service-identity.stdout" || return 1
    grep -Fxq 'caddy_serving_health_complete=true' \
        "$action35c_evidence/caddy-service-identity.stdout" || return 1
    find "$action35c_preflight" -xdev -mindepth 1 -delete
    rmdir "$action35c_preflight"
    rmdir "$(dirname -- "$action35c_preflight")" 2>/dev/null || :
    printf '%s_check_candidate_validation_complete=true\n' "$action35c_prefix"
}

action35c_backup_current() {
    local action35c_destination
    local action35c_timer_status=0

    action35c_backup=$(action35c_root_path "/var/backups/caddy-action35c/$action35c_node_role")
    [[ ! -e "$action35c_backup" ]] || return 1
    install -d -m 0700 "$action35c_backup"
    for action35c_destination in /etc/scripts/check-dns.sh /usr/local/libexec/check-caddy.sh \
        /usr/local/libexec/check-pihole-web-health.sh /etc/systemd/system/caddy-pihole-web-health.service \
        /etc/systemd/system/caddy-pihole-web-health.timer /etc/keepalived/keepalived.conf; do
        local action35c_existing
        action35c_existing=$(action35c_root_path "$action35c_destination")
        if [[ -f "$action35c_existing" && ! -L "$action35c_existing" ]]; then
            cp -a -- "$action35c_existing" \
                "$action35c_backup/${action35c_destination//\//_}"
        else
            : >"$action35c_backup/${action35c_destination//\//_}.absent"
        fi
    done
    action35c_systemctl is-enabled --quiet caddy-pihole-web-health.timer ||
        action35c_timer_status=$?
    printf '%s\n' "$action35c_timer_status" >"$action35c_backup/timer-enabled.status"
    action35c_timer_status=0
    action35c_systemctl is-active --quiet caddy-pihole-web-health.timer ||
        action35c_timer_status=$?
    printf '%s\n' "$action35c_timer_status" >"$action35c_backup/timer-active.status"
    printf '%s_check_backup_complete=true\n' "$action35c_prefix"
}

action35c_install_candidates() {
    local action35c_repository action35c_source action35c_target action35c_mode
    local action35c_hash action35c_lifecycle action35c_source_path action35c_destination

    while IFS=$'\t' read -r action35c_repository action35c_source action35c_target \
        action35c_mode action35c_hash action35c_lifecycle; do
        [[ -n "$action35c_repository" && "$action35c_repository" != \#* ]] || continue
        case "$action35c_target" in
            */keepalived.conf)
                [[ "$action35c_node_role" = node-a && "$action35c_source" = *pihole0.conf ]] ||
                    [[ "$action35c_node_role" = node-b && "$action35c_source" = *pihole00.conf ]] || continue
                ;;
            */releases/REVISION/*) continue ;;
        esac
        action35c_source_path=$action35c_payload/files/$action35c_repository/$action35c_source
        action35c_destination=$(action35c_root_path "$action35c_target")
        install -d -m 0755 "$(dirname -- "$action35c_destination")"
        install -m "$action35c_mode" "$action35c_source_path" "$action35c_destination"
        [[ "$(sha256sum "$action35c_destination" | awk '{ print $1 }')" = "$action35c_hash" ]] || return 1
    done <"$action35c_payload/serving-health-production.tsv"
    action35c_mutated=true
    printf '1\n' >"$action35c_evidence/mutation-count"
    action35c_capture daemon-reload action35c_systemctl daemon-reload || return 1
    action35c_capture backend-timer-enable action35c_systemctl enable --now \
        caddy-pihole-web-health.timer || return 1
    action35c_capture keepalived-reload action35c_systemctl reload keepalived.service || return 1
    printf '%s_check_mutation_complete=true\n' "$action35c_prefix"
}

action35c_accept() {
    local action35c_sample
    local action35c_expected_ownership='ipv4=Backup ipv6=Backup vip_count=0'
    local action35c_stable=0

    [[ "$action35c_node_role" = node-b ]] ||
        action35c_expected_ownership='ipv4=Master ipv6=Master vip_count=4'

    for action35c_sample in $(seq 1 30); do
        action35c_capture "post-dns-$action35c_sample" action35c_run_as pi \
            /bin/bash "$(action35c_root_path /etc/scripts/check-dns.sh)" || return 1
        action35c_capture "post-caddy-$action35c_sample" action35c_run_as keepalived_script \
            /usr/bin/timeout 2 /bin/bash "$(action35c_root_path /usr/local/libexec/check-caddy.sh)" || return 1
        action35c_capture "ownership-$action35c_sample" action35c_ownership_snapshot || return 1
        if grep -Fxq "$action35c_expected_ownership" \
            "$action35c_evidence/ownership-$action35c_sample.stdout"; then
            action35c_stable=$((action35c_stable + 1))
        else
            action35c_stable=0
        fi
        [[ "$action35c_stable" -lt 3 ]] || break
        sleep 1
    done
    [[ "$action35c_stable" -eq 3 ]] || return 1
    action35c_capture timer-active action35c_systemctl is-active --quiet \
        caddy-pihole-web-health.timer || return 1
    action35c_capture timer-enabled action35c_systemctl is-enabled --quiet \
        caddy-pihole-web-health.timer || return 1
    if [[ -n "$action35c_test_root" ]]; then
        action35c_capture journal-after-cursor /bin/bash "$action35c_test_root/bin/journalctl" \
            --after-cursor "$(<"$action35c_evidence/journal.cursor")" --no-pager || return 1
    else
        action35c_capture journal-after-cursor journalctl \
            --after-cursor "$(<"$action35c_evidence/journal.cursor")" --no-pager || return 1
    fi
    if grep -Eiq 'simultaneous[_ -]ownership|script.*timed out|unsafe|secret' \
        "$action35c_evidence/journal-after-cursor.stdout"; then
        return 1
    fi
    printf '%s_check_acceptance_complete=true\n' "$action35c_prefix"
}

action35c_rollback() {
    local action35c_destination action35c_saved action35c_absent
    local action35c_temporary

    [[ "$action35c_mutated" = true ]] || return 0
    if [[ "$(<"$action35c_backup/timer-enabled.status")" -ne 0 ]]; then
        action35c_systemctl disable --now caddy-pihole-web-health.timer \
            >/dev/null 2>&1 || return 1
    fi
    for action35c_destination in /etc/scripts/check-dns.sh /usr/local/libexec/check-caddy.sh \
        /usr/local/libexec/check-pihole-web-health.sh /etc/systemd/system/caddy-pihole-web-health.service \
        /etc/systemd/system/caddy-pihole-web-health.timer /etc/keepalived/keepalived.conf; do
        action35c_saved=$action35c_backup/${action35c_destination//\//_}
        action35c_absent=$action35c_saved.absent
        if [[ -f "$action35c_saved" && ! -L "$action35c_saved" ]]; then
            action35c_temporary=$(action35c_root_path "$action35c_destination.rollback-action35c")
            [[ ! -e "$action35c_temporary" && ! -L "$action35c_temporary" ]] || return 1
            cp -a -- "$action35c_saved" "$action35c_temporary"
            mv -fT -- "$action35c_temporary" "$(action35c_root_path "$action35c_destination")"
        elif [[ -f "$action35c_absent" && ! -L "$action35c_absent" ]]; then
            rm -f -- "$(action35c_root_path "$action35c_destination")"
        else
            return 1
        fi
    done
    action35c_systemctl daemon-reload >/dev/null 2>&1 || return 1
    if [[ "$(<"$action35c_backup/timer-enabled.status")" -eq 0 ]]; then
        action35c_systemctl enable caddy-pihole-web-health.timer >/dev/null 2>&1 || return 1
    fi
    if [[ "$(<"$action35c_backup/timer-active.status")" -eq 0 ]]; then
        action35c_systemctl start caddy-pihole-web-health.timer >/dev/null 2>&1 || return 1
    fi
    action35c_systemctl reload keepalived.service >/dev/null 2>&1 || return 1
    printf '%s_check_rollback_complete=true\n' "$action35c_prefix"
}

action35c_cleanup() {
    local action35c_status=$?

    if [[ -n "$action35c_preflight" && -d "$action35c_preflight" && ! -L "$action35c_preflight" ]]; then
        find "$action35c_preflight" -xdev -mindepth 1 -delete || :
        rmdir "$action35c_preflight" 2>/dev/null || :
        rmdir "$(dirname -- "$action35c_preflight")" 2>/dev/null || :
    fi
    if ((action35c_status != 0)) && [[ "$action35c_mutated" = true ]]; then
        if ! action35c_rollback; then
            exit 125
        fi
    fi
    exit "$action35c_status"
}

while (($#)); do
    case "$1" in
        --node-role)
            action35c_node_role=${2:-}
            shift 2
            ;;
        --payload)
            action35c_payload=${2:-}
            shift 2
            ;;
        --production-path-test)
            action35c_test_root=${2:-}
            shift 2
            ;;
        --rollback-existing)
            action35c_mode=rollback
            shift
            ;;
        *)
            action35c_usage
            exit 64
            ;;
    esac
done

[[ "$action35c_node_role" =~ ^node-[ab]$ ]] || {
    action35c_usage
    exit 64
}
if [[ "$action35c_mode" = apply ]]; then
    [[ -d "$action35c_payload" && ! -L "$action35c_payload" ]] || exit 64
fi
if [[ -n "$action35c_test_root" ]]; then
    [[ "$action35c_test_root" = /tmp/* && -d "$action35c_test_root" && ! -L "$action35c_test_root" ]] || exit 64
fi

action35c_evidence=$(action35c_root_path "$action35c_node_evidence/$action35c_node_role")
readonly action35c_evidence
if [[ "$action35c_mode" = rollback ]]; then
    action35c_backup=$(action35c_root_path "/var/backups/caddy-action35c/$action35c_node_role")
    [[ -d "$action35c_backup" && ! -L "$action35c_backup" ]] || exit 1
    action35c_mutated=true
    action35c_rollback
    exit 0
fi
[[ ! -e "$action35c_evidence" ]] || exit 1
install -d -m 0700 "$action35c_evidence"
printf '0\n' >"$action35c_evidence/mutation-count"
if [[ -n "$action35c_test_root" ]]; then
    /bin/bash "$action35c_test_root/bin/journalctl" --show-cursor --no-pager \
        >"$action35c_evidence/journal.cursor"
else
    journalctl --show-cursor --no-pager >"$action35c_evidence/journal.cursor"
fi
trap action35c_cleanup EXIT INT TERM

action35c_check payload_contract action35c_validate_payload
action35c_validate_baseline
action35c_validate_candidates
action35c_backup_current
action35c_install_candidates
action35c_accept
action35c_check residue_absent test -z \
    "$(find "$(action35c_root_path /var/lib/caddy-sync/incoming)" -mindepth 1 -maxdepth 1 -name 'action35c-*' -print -quit 2>/dev/null)"
printf '%s_check_complete=true\n' "$action35c_prefix"
