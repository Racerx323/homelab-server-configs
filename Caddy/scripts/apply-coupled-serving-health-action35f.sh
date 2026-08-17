#!/usr/bin/env bash
# shellcheck disable=SC2016 # The captured Bash predicate expands only inside its child shell.

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH
readonly PATH

readonly action35f_prefix=action_35f
readonly action35f_expected_manifest_sha256=86f71fba1b126754fa560ddf49f569c2b06f85ab603a9a24f59921d1064da087
readonly action35f_node_evidence=/tmp/caddy-action35f

action35f_node_role=
action35f_payload=
action35f_test_root=
action35f_mode=apply
action35f_mutated=false
action35f_backup=
action35f_preflight=

if [[ "${1:-}" = --production-path-test && $# -eq 1 ]]; then
    action35f_self_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
    readonly action35f_self_directory
    exec /bin/bash "$action35f_self_directory/../tests/coupled-serving-health-deployment-regression.sh" \
        --entrypoint transaction
fi

action35f_usage() {
    printf 'Usage: %s --node-role node-a|node-b --payload DIRECTORY [--production-path-test ROOT]\n' "${0##*/}" >&2
}

action35f_check() {
    local action35f_label=$1

    shift
    if "$@"; then
        printf '%s_check_%s=true\n' "$action35f_prefix" "$action35f_label"
        return 0
    fi
    printf '%s_check_%s=false\n' "$action35f_prefix" "$action35f_label" >&2
    return 1
}

action35f_root_path() {
    local action35f_path=$1

    if [[ -n "$action35f_test_root" ]]; then
        printf '%s%s' "${action35f_test_root%/}" "$action35f_path"
    else
        printf '%s' "$action35f_path"
    fi
}

action35f_systemctl() {
    if [[ -n "$action35f_test_root" ]]; then
        /bin/bash "$action35f_test_root/bin/systemctl" "$@"
    else
        systemctl "$@"
    fi
}

action35f_keepalived_parser() {
    local action35f_config=$1

    if [[ -n "$action35f_test_root" ]]; then
        /bin/bash "$action35f_test_root/bin/keepalived" --config-test --use-file="$action35f_config"
    else
        keepalived --config-test --use-file="$action35f_config"
    fi
}

action35f_ownership_snapshot() {
    if [[ -n "$action35f_test_root" ]]; then
        /bin/bash "$action35f_test_root/bin/ownership" "$action35f_node_role"
        return
    fi
    local action35f_ipv4_state action35f_ipv6_state action35f_vip_count
    action35f_ipv4_state=$(timeout 2 busctl get-property org.keepalived.Vrrp1 \
        /org/keepalived/Vrrp1/Instance/eth0/100/IPv4 org.keepalived.Vrrp1.Instance State)
    action35f_ipv6_state=$(timeout 2 busctl get-property org.keepalived.Vrrp1 \
        /org/keepalived/Vrrp1/Instance/eth0/101/IPv6 org.keepalived.Vrrp1.Instance State)
    case "$action35f_ipv4_state" in
        *'"Master"') action35f_ipv4_state=Master ;;
        *'"Backup"') action35f_ipv4_state=Backup ;;
        *) return 1 ;;
    esac
    case "$action35f_ipv6_state" in
        *'"Master"') action35f_ipv6_state=Master ;;
        *'"Backup"') action35f_ipv6_state=Backup ;;
        *) return 1 ;;
    esac
    action35f_vip_count=$(
        ip -o address show dev eth0 |
            awk '$4 ~ /^(10\.1\.0\.(55|56)\/22|fd36:5aa8:6971:1::(55|56)\/128)$/ { count++ } END { print count + 0 }'
    )
    printf 'ipv4=%s ipv6=%s vip_count=%s\n' \
        "$action35f_ipv4_state" "$action35f_ipv6_state" "$action35f_vip_count"
}

action35f_run_as() {
    local action35f_identity=$1

    shift
    if [[ -n "$action35f_test_root" ]]; then
        {
            printf '%s\t' "$action35f_identity"
            printf '%q ' "$@"
            printf '\n'
        } >>"$action35f_test_root/calls/identities.tsv"
        env \
            DNS_CHECK_DIG_COMMAND="$action35f_test_root/bin/dig" \
            DNS_CHECK_SYSTEMCTL_COMMAND="$action35f_test_root/bin/systemctl" \
            CADDY_SERVING_HEALTH_ENVIRONMENT_FILE="$action35f_test_root/etc/default/caddy-ha" \
            CADDY_SERVING_HEALTH_CURL_COMMAND="$action35f_test_root/bin/curl" \
            CADDY_SERVING_HEALTH_SS_COMMAND="$action35f_test_root/bin/ss" \
            CADDY_SERVING_HEALTH_SYSTEMCTL_COMMAND="$action35f_test_root/bin/systemctl" \
            PIHOLE_WEB_HEALTH_ENVIRONMENT_FILE="$action35f_test_root/etc/default/caddy-ha" \
            PIHOLE_WEB_HEALTH_STATE_DIRECTORY="$action35f_test_root/var/lib/caddy-pihole-web-health" \
            PIHOLE_WEB_HEALTH_RUNTIME_DIRECTORY="$action35f_test_root/run/caddy-pihole-web-health" \
            PIHOLE_WEB_HEALTH_ENQUEUE_COMMAND="$action35f_test_root/bin/enqueue" \
            PIHOLE_WEB_HEALTH_CURL_COMMAND="$action35f_test_root/bin/curl" \
            PIHOLE_WEB_HEALTH_SYSTEMCTL_COMMAND="$action35f_test_root/bin/systemctl" \
            "$@"
    else
        runuser --user "$action35f_identity" -- "$@"
    fi
}

action35f_capture() {
    local action35f_label=$1

    shift
    local action35f_stdout action35f_stderr action35f_status=0
    action35f_stdout=$action35f_evidence/$action35f_label.stdout
    action35f_stderr=$action35f_evidence/$action35f_label.stderr
    : >"$action35f_stdout"
    : >"$action35f_stderr"
    "$@" >"$action35f_stdout" 2>"$action35f_stderr" || action35f_status=$?
    printf '%s\n' "$action35f_status" >"$action35f_evidence/$action35f_label.status"
    [[ -f "$action35f_stdout" && ! -L "$action35f_stdout" ]] || return 1
    [[ -f "$action35f_stderr" && ! -L "$action35f_stderr" ]] || return 1
    return "$action35f_status"
}

action35f_require_regular() {
    local action35f_path=$1
    local action35f_mode=${2:-}

    [[ -f "$action35f_path" && ! -L "$action35f_path" ]] || return 1
    [[ -z "$action35f_mode" || "$(stat -c '%a' "$action35f_path")" = "$action35f_mode" ]]
}

action35f_validate_payload() {
    local action35f_line action35f_repository action35f_source action35f_target
    local action35f_mode action35f_hash action35f_lifecycle action35f_source_path

    action35f_require_regular "$action35f_payload/serving-health-production.tsv" || return 1
    [[ "$(sed -n '1p' "$action35f_payload/serving-health-production.tsv")" = $'# repository\tsource-path\tinstalled-path\tmode\tcandidate-sha256\tlifecycle' ]] || return 1
    while IFS=$'\t' read -r action35f_repository action35f_source action35f_target \
        action35f_mode action35f_hash action35f_lifecycle; do
        [[ -n "$action35f_repository" && "$action35f_repository" != \#* ]] || continue
        [[ "$action35f_repository" =~ ^homelab-(server-configs|dns)$ ]] || return 1
        [[ "$action35f_source" != *..* && "$action35f_target" = /* ]] || return 1
        [[ "$action35f_mode" =~ ^0[0-7]{3}$ && "$action35f_hash" =~ ^[0-9a-f]{64}$ ]] || return 1
        [[ "$action35f_lifecycle" = production-candidate ]] || return 1
        action35f_source_path=$action35f_payload/files/$action35f_repository/$action35f_source
        action35f_require_regular "$action35f_source_path" || return 1
        [[ "$(sha256sum "$action35f_source_path" | awk '{ print $1 }')" = "$action35f_hash" ]] || return 1
        printf '%s\t%s\t%s\n' "$action35f_target" "$action35f_hash" "$action35f_mode" \
            >>"$action35f_evidence/payload-identities.tsv"
        action35f_line=true
    done <"$action35f_payload/serving-health-production.tsv"
    [[ "${action35f_line:-false}" = true ]]
}

action35f_validate_baseline() {
    local action35f_expected_state=$action35f_payload/current-live-state.tsv
    local action35f_current_link
    local action35f_key action35f_repository action35f_source action35f_installed
    local action35f_inventory_node action35f_source_hash action35f_deployed_hash
    local action35f_accepted_action action35f_lifecycle action35f_installed_path

    action35f_require_regular "$action35f_expected_state" || return 1
    action35f_require_regular "$action35f_payload/production-artifacts.tsv" || return 1
    action35f_check baseline_manifest_identity test \
        "$(sha256sum "$action35f_expected_state" | awk '{ print $1 }')" = "$action35f_expected_manifest_sha256" || return 1
    for action35f_unit in caddy.service caddy-lsyncd.service caddy-sync-reconcile.path \
        caddy-apprise-worker.path caddy-apprise-worker.timer keepalived.service \
        pihole-FTL.service unbound.service lighttpd.service; do
        action35f_capture "baseline-${action35f_unit//./-}" \
            action35f_systemctl is-active --quiet "$action35f_unit" || return 1
    done
    for action35f_unit in caddy.service caddy-lsyncd.service caddy-sync-reconcile.path \
        caddy-apprise-worker.path caddy-apprise-worker.timer; do
        action35f_capture "enabled-${action35f_unit//./-}" \
            action35f_systemctl is-enabled --quiet "$action35f_unit" || return 1
    done
    action35f_current_link=$(action35f_root_path /etc/caddy/current)
    [[ -L "$action35f_current_link" ]] || return 1
    readlink -f -- "$action35f_current_link" >"$action35f_evidence/original-release.path"
    action35f_require_regular "$(<"$action35f_evidence/original-release.path")/release-manifest.json" || return 1
    action35f_capture baseline-residue /bin/bash -c \
        'test -z "$(find "$1" -mindepth 1 -maxdepth 1 -name "action35f-*" -print -quit 2>/dev/null)"' \
        _ "$(action35f_root_path /var/lib/caddy-sync/incoming)" || return 1
    while IFS=$'\t' read -r action35f_key action35f_repository action35f_source \
        action35f_installed action35f_inventory_node action35f_source_hash \
        action35f_deployed_hash action35f_accepted_action action35f_lifecycle; do
        [[ -n "$action35f_key" && "$action35f_key" != \#* ]] || continue
        [[ "$action35f_inventory_node" = "$action35f_node_role" ]] || continue
        : "$action35f_repository" "$action35f_source" "$action35f_source_hash"
        [[ "$action35f_lifecycle" = production-current && "$action35f_installed" = /* ]] || return 1
        [[ "$action35f_deployed_hash" =~ ^[0-9a-f]{64}$ ]] || return 1
        action35f_installed_path=$(action35f_root_path "$action35f_installed")
        action35f_require_regular "$action35f_installed_path" || return 1
        [[ "$(sha256sum "$action35f_installed_path" | awk '{ print $1 }')" = "$action35f_deployed_hash" ]] || return 1
        printf '%s\t%s\t%s\n' "$action35f_key" "$action35f_deployed_hash" \
            "$action35f_accepted_action" >>"$action35f_evidence/baseline-identities.tsv"
    done <"$action35f_payload/production-artifacts.tsv"
    printf '%s_check_baseline_complete=true\n' "$action35f_prefix"
}

action35f_validate_candidates() {
    local action35f_keepalived action35f_dns action35f_caddy action35f_web

    action35f_keepalived=$action35f_payload/files/homelab-dns/Keepalived/configs/keepalived-pihole0.conf
    [[ "$action35f_node_role" = node-b ]] &&
        action35f_keepalived=$action35f_payload/files/homelab-dns/Keepalived/configs/keepalived-pihole00.conf
    action35f_dns=$action35f_payload/files/homelab-dns/Keepalived/scripts/dns-check.sh
    action35f_caddy=$action35f_payload/files/homelab-server-configs/Caddy/scripts/check-caddy-serving-health.sh
    action35f_web=$action35f_payload/files/homelab-server-configs/Caddy/scripts/check-pihole-web-health.sh
    action35f_preflight=$(action35f_root_path "/tmp/caddy-action35f-preflight/$action35f_node_role")
    [[ ! -e "$action35f_preflight" ]] || return 1
    install -d -m 0755 "$action35f_preflight/bin" "$action35f_preflight/state" \
        "$action35f_preflight/run"
    install -m 0755 "$action35f_dns" "$action35f_preflight/bin/check-dns.sh"
    install -m 0755 "$action35f_caddy" "$action35f_preflight/bin/check-caddy.sh"
    install -m 0755 "$action35f_web" "$action35f_preflight/bin/check-pihole-web-health.sh"
    action35f_capture keepalived-parser action35f_keepalived_parser "$action35f_keepalived" || return 1
    action35f_capture dns-service-identity action35f_run_as pi \
        /bin/bash "$action35f_preflight/bin/check-dns.sh" || return 1
    action35f_capture caddy-service-identity action35f_run_as keepalived_script \
        /usr/bin/timeout 2 /bin/bash "$action35f_preflight/bin/check-caddy.sh" || return 1
    if [[ -n "$action35f_test_root" ]]; then
        action35f_capture web-service-identity action35f_run_as pi \
            /bin/bash "$action35f_preflight/bin/check-pihole-web-health.sh" || return 1
    else
        chown -R pi:pi "$action35f_preflight/state" "$action35f_preflight/run"
        action35f_capture web-service-identity runuser --user pi -- env \
            PIHOLE_WEB_HEALTH_STATE_DIRECTORY="$action35f_preflight/state" \
            PIHOLE_WEB_HEALTH_RUNTIME_DIRECTORY="$action35f_preflight/run" \
            PIHOLE_WEB_HEALTH_ENQUEUE_COMMAND=/usr/bin/true \
            /bin/bash "$action35f_preflight/bin/check-pihole-web-health.sh" || return 1
    fi
    grep -Fq 'check=127_0_0_1_53_A status=0 answer=10.1.0.55' \
        "$action35f_evidence/dns-service-identity.stdout" || return 1
    grep -Fq 'check=__1_5335_AAAA status=0 answer=fd36:5aa8:6971:1::55' \
        "$action35f_evidence/dns-service-identity.stdout" || return 1
    grep -Fxq 'caddy_serving_health_complete=true' \
        "$action35f_evidence/caddy-service-identity.stdout" || return 1
    find "$action35f_preflight" -xdev -mindepth 1 -delete
    rmdir "$action35f_preflight"
    rmdir "$(dirname -- "$action35f_preflight")" 2>/dev/null || :
    printf '%s_check_candidate_validation_complete=true\n' "$action35f_prefix"
}

action35f_backup_current() {
    local action35f_destination
    local action35f_timer_status=0

    action35f_backup=$(action35f_root_path "/var/backups/caddy-action35f/$action35f_node_role")
    [[ ! -e "$action35f_backup" ]] || return 1
    install -d -m 0700 "$action35f_backup"
    for action35f_destination in /etc/scripts/check-dns.sh /usr/local/libexec/check-caddy.sh \
        /usr/local/libexec/check-pihole-web-health.sh /etc/systemd/system/caddy-pihole-web-health.service \
        /etc/systemd/system/caddy-pihole-web-health.timer /etc/keepalived/keepalived.conf; do
        local action35f_existing
        action35f_existing=$(action35f_root_path "$action35f_destination")
        if [[ -f "$action35f_existing" && ! -L "$action35f_existing" ]]; then
            cp -a -- "$action35f_existing" \
                "$action35f_backup/${action35f_destination//\//_}"
        else
            : >"$action35f_backup/${action35f_destination//\//_}.absent"
        fi
    done
    action35f_systemctl is-enabled --quiet caddy-pihole-web-health.timer ||
        action35f_timer_status=$?
    printf '%s\n' "$action35f_timer_status" >"$action35f_backup/timer-enabled.status"
    action35f_timer_status=0
    action35f_systemctl is-active --quiet caddy-pihole-web-health.timer ||
        action35f_timer_status=$?
    printf '%s\n' "$action35f_timer_status" >"$action35f_backup/timer-active.status"
    printf '%s_check_backup_complete=true\n' "$action35f_prefix"
}

action35f_install_candidates() {
    local action35f_repository action35f_source action35f_target action35f_mode
    local action35f_hash action35f_lifecycle action35f_source_path action35f_destination

    while IFS=$'\t' read -r action35f_repository action35f_source action35f_target \
        action35f_mode action35f_hash action35f_lifecycle; do
        [[ -n "$action35f_repository" && "$action35f_repository" != \#* ]] || continue
        case "$action35f_target" in
            */keepalived.conf)
                [[ "$action35f_node_role" = node-a && "$action35f_source" = *pihole0.conf ]] ||
                    [[ "$action35f_node_role" = node-b && "$action35f_source" = *pihole00.conf ]] || continue
                ;;
            */releases/REVISION/*) continue ;;
        esac
        action35f_source_path=$action35f_payload/files/$action35f_repository/$action35f_source
        action35f_destination=$(action35f_root_path "$action35f_target")
        install -d -m 0755 "$(dirname -- "$action35f_destination")"
        install -m "$action35f_mode" "$action35f_source_path" "$action35f_destination"
        [[ "$(sha256sum "$action35f_destination" | awk '{ print $1 }')" = "$action35f_hash" ]] || return 1
    done <"$action35f_payload/serving-health-production.tsv"
    action35f_mutated=true
    printf '1\n' >"$action35f_evidence/mutation-count"
    action35f_capture daemon-reload action35f_systemctl daemon-reload || return 1
    action35f_capture backend-timer-enable action35f_systemctl enable --now \
        caddy-pihole-web-health.timer || return 1
    action35f_capture keepalived-reload action35f_systemctl reload keepalived.service || return 1
    printf '%s_check_mutation_complete=true\n' "$action35f_prefix"
}

action35f_accept() {
    local action35f_sample
    local action35f_expected_ownership='ipv4=Backup ipv6=Backup vip_count=0'
    local action35f_stable=0

    [[ "$action35f_node_role" = node-b ]] ||
        action35f_expected_ownership='ipv4=Master ipv6=Master vip_count=4'

    for action35f_sample in $(seq 1 30); do
        action35f_capture "post-dns-$action35f_sample" action35f_run_as pi \
            /bin/bash "$(action35f_root_path /etc/scripts/check-dns.sh)" || return 1
        action35f_capture "post-caddy-$action35f_sample" action35f_run_as keepalived_script \
            /usr/bin/timeout 2 /bin/bash "$(action35f_root_path /usr/local/libexec/check-caddy.sh)" || return 1
        action35f_capture "ownership-$action35f_sample" action35f_ownership_snapshot || return 1
        if grep -Fxq "$action35f_expected_ownership" \
            "$action35f_evidence/ownership-$action35f_sample.stdout"; then
            action35f_stable=$((action35f_stable + 1))
        else
            action35f_stable=0
        fi
        [[ "$action35f_stable" -lt 3 ]] || break
        sleep 1
    done
    [[ "$action35f_stable" -eq 3 ]] || return 1
    action35f_capture timer-active action35f_systemctl is-active --quiet \
        caddy-pihole-web-health.timer || return 1
    action35f_capture timer-enabled action35f_systemctl is-enabled --quiet \
        caddy-pihole-web-health.timer || return 1
    if [[ -n "$action35f_test_root" ]]; then
        action35f_capture journal-after-cursor /bin/bash "$action35f_test_root/bin/journalctl" \
            --after-cursor "$(<"$action35f_evidence/journal.cursor")" --no-pager || return 1
    else
        action35f_capture journal-after-cursor journalctl \
            --after-cursor "$(<"$action35f_evidence/journal.cursor")" --no-pager || return 1
    fi
    if grep -Eiq 'simultaneous[_ -]ownership|script.*timed out|unsafe|secret' \
        "$action35f_evidence/journal-after-cursor.stdout"; then
        return 1
    fi
    printf '%s_check_acceptance_complete=true\n' "$action35f_prefix"
}

action35f_rollback() {
    local action35f_destination action35f_saved action35f_absent
    local action35f_temporary

    [[ "$action35f_mutated" = true ]] || return 0
    if [[ "$(<"$action35f_backup/timer-enabled.status")" -ne 0 ]]; then
        action35f_systemctl disable --now caddy-pihole-web-health.timer \
            >/dev/null 2>&1 || return 1
    fi
    for action35f_destination in /etc/scripts/check-dns.sh /usr/local/libexec/check-caddy.sh \
        /usr/local/libexec/check-pihole-web-health.sh /etc/systemd/system/caddy-pihole-web-health.service \
        /etc/systemd/system/caddy-pihole-web-health.timer /etc/keepalived/keepalived.conf; do
        action35f_saved=$action35f_backup/${action35f_destination//\//_}
        action35f_absent=$action35f_saved.absent
        if [[ -f "$action35f_saved" && ! -L "$action35f_saved" ]]; then
            action35f_temporary=$(action35f_root_path "$action35f_destination.rollback-action35f")
            [[ ! -e "$action35f_temporary" && ! -L "$action35f_temporary" ]] || return 1
            cp -a -- "$action35f_saved" "$action35f_temporary"
            mv -fT -- "$action35f_temporary" "$(action35f_root_path "$action35f_destination")"
        elif [[ -f "$action35f_absent" && ! -L "$action35f_absent" ]]; then
            rm -f -- "$(action35f_root_path "$action35f_destination")"
        else
            return 1
        fi
    done
    action35f_systemctl daemon-reload >/dev/null 2>&1 || return 1
    if [[ "$(<"$action35f_backup/timer-enabled.status")" -eq 0 ]]; then
        action35f_systemctl enable caddy-pihole-web-health.timer >/dev/null 2>&1 || return 1
    fi
    if [[ "$(<"$action35f_backup/timer-active.status")" -eq 0 ]]; then
        action35f_systemctl start caddy-pihole-web-health.timer >/dev/null 2>&1 || return 1
    fi
    action35f_systemctl reload keepalived.service >/dev/null 2>&1 || return 1
    printf '%s_check_rollback_complete=true\n' "$action35f_prefix"
}

action35f_cleanup() {
    local action35f_status=$?

    if [[ -n "$action35f_preflight" && -d "$action35f_preflight" && ! -L "$action35f_preflight" ]]; then
        find "$action35f_preflight" -xdev -mindepth 1 -delete || :
        rmdir "$action35f_preflight" 2>/dev/null || :
        rmdir "$(dirname -- "$action35f_preflight")" 2>/dev/null || :
    fi
    if ((action35f_status != 0)) && [[ "$action35f_mutated" = true ]]; then
        if ! action35f_rollback; then
            exit 125
        fi
    fi
    exit "$action35f_status"
}

while (($#)); do
    case "$1" in
        --node-role)
            action35f_node_role=${2:-}
            shift 2
            ;;
        --payload)
            action35f_payload=${2:-}
            shift 2
            ;;
        --production-path-test)
            action35f_test_root=${2:-}
            shift 2
            ;;
        --rollback-existing)
            action35f_mode=rollback
            shift
            ;;
        *)
            action35f_usage
            exit 64
            ;;
    esac
done

[[ "$action35f_node_role" =~ ^node-[ab]$ ]] || {
    action35f_usage
    exit 64
}
if [[ "$action35f_mode" = apply ]]; then
    [[ -d "$action35f_payload" && ! -L "$action35f_payload" ]] || exit 64
fi
if [[ -n "$action35f_test_root" ]]; then
    [[ "$action35f_test_root" = /tmp/* && -d "$action35f_test_root" && ! -L "$action35f_test_root" ]] || exit 64
fi

action35f_evidence=$(action35f_root_path "$action35f_node_evidence/$action35f_node_role")
readonly action35f_evidence
if [[ "$action35f_mode" = rollback ]]; then
    action35f_backup=$(action35f_root_path "/var/backups/caddy-action35f/$action35f_node_role")
    [[ -d "$action35f_backup" && ! -L "$action35f_backup" ]] || exit 1
    action35f_mutated=true
    action35f_rollback
    exit 0
fi
[[ ! -e "$action35f_evidence" ]] || exit 1
install -d -m 0700 "$action35f_evidence"
printf '0\n' >"$action35f_evidence/mutation-count"
if [[ -n "$action35f_test_root" ]]; then
    /bin/bash "$action35f_test_root/bin/journalctl" --show-cursor --no-pager \
        >"$action35f_evidence/journal.cursor"
else
    journalctl --show-cursor --no-pager >"$action35f_evidence/journal.cursor"
fi
trap action35f_cleanup EXIT INT TERM

action35f_check payload_contract action35f_validate_payload
action35f_validate_baseline
action35f_validate_candidates
action35f_backup_current
action35f_install_candidates
action35f_accept
action35f_check residue_absent test -z \
    "$(find "$(action35f_root_path /var/lib/caddy-sync/incoming)" -mindepth 1 -maxdepth 1 -name 'action35f-*' -print -quit 2>/dev/null)"
printf '%s_check_complete=true\n' "$action35f_prefix"
