#!/usr/bin/env bash
# shellcheck disable=SC2016 # The captured Bash predicate expands only inside its child shell.

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH
readonly PATH

readonly action35b_prefix=action_35b
readonly action35b_expected_manifest_sha256=86f71fba1b126754fa560ddf49f569c2b06f85ab603a9a24f59921d1064da087
readonly action35b_node_evidence=/tmp/caddy-action35b

action35b_node_role=
action35b_payload=
action35b_test_root=
action35b_mode=apply
action35b_mutated=false
action35b_backup=
action35b_preflight=

if [[ "${1:-}" = --production-path-test && $# -eq 1 ]]; then
    action35b_self_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
    readonly action35b_self_directory
    exec /bin/bash "$action35b_self_directory/../tests/coupled-serving-health-deployment-regression.sh" \
        --entrypoint transaction
fi

action35b_usage() {
    printf 'Usage: %s --node-role node-a|node-b --payload DIRECTORY [--production-path-test ROOT]\n' "${0##*/}" >&2
}

action35b_check() {
    local action35b_label=$1

    shift
    if "$@"; then
        printf '%s_check_%s=true\n' "$action35b_prefix" "$action35b_label"
        return 0
    fi
    printf '%s_check_%s=false\n' "$action35b_prefix" "$action35b_label" >&2
    return 1
}

action35b_root_path() {
    local action35b_path=$1

    if [[ -n "$action35b_test_root" ]]; then
        printf '%s%s' "${action35b_test_root%/}" "$action35b_path"
    else
        printf '%s' "$action35b_path"
    fi
}

action35b_systemctl() {
    if [[ -n "$action35b_test_root" ]]; then
        /bin/bash "$action35b_test_root/bin/systemctl" "$@"
    else
        systemctl "$@"
    fi
}

action35b_keepalived_parser() {
    local action35b_config=$1

    if [[ -n "$action35b_test_root" ]]; then
        /bin/bash "$action35b_test_root/bin/keepalived" --config-test --use-file="$action35b_config"
    else
        keepalived --config-test --use-file="$action35b_config"
    fi
}

action35b_ownership_snapshot() {
    if [[ -n "$action35b_test_root" ]]; then
        /bin/bash "$action35b_test_root/bin/ownership" "$action35b_node_role"
        return
    fi
    local action35b_ipv4_state action35b_ipv6_state action35b_vip_count
    action35b_ipv4_state=$(timeout 2 busctl get-property org.keepalived.Vrrp1 \
        /org/keepalived/Vrrp1/Instance/eth0/100/IPv4 org.keepalived.Vrrp1.Instance State)
    action35b_ipv6_state=$(timeout 2 busctl get-property org.keepalived.Vrrp1 \
        /org/keepalived/Vrrp1/Instance/eth0/101/IPv6 org.keepalived.Vrrp1.Instance State)
    case "$action35b_ipv4_state" in
        *'"Master"') action35b_ipv4_state=Master ;;
        *'"Backup"') action35b_ipv4_state=Backup ;;
        *) return 1 ;;
    esac
    case "$action35b_ipv6_state" in
        *'"Master"') action35b_ipv6_state=Master ;;
        *'"Backup"') action35b_ipv6_state=Backup ;;
        *) return 1 ;;
    esac
    action35b_vip_count=$(
        ip -o address show dev eth0 |
            awk '$4 ~ /^(10\.1\.0\.(55|56)\/22|fd36:5aa8:6971:1::(55|56)\/128)$/ { count++ } END { print count + 0 }'
    )
    printf 'ipv4=%s ipv6=%s vip_count=%s\n' \
        "$action35b_ipv4_state" "$action35b_ipv6_state" "$action35b_vip_count"
}

action35b_run_as() {
    local action35b_identity=$1

    shift
    if [[ -n "$action35b_test_root" ]]; then
        {
            printf '%s\t' "$action35b_identity"
            printf '%q ' "$@"
            printf '\n'
        } >>"$action35b_test_root/calls/identities.tsv"
        env \
            DNS_CHECK_DIG_COMMAND="$action35b_test_root/bin/dig" \
            DNS_CHECK_SYSTEMCTL_COMMAND="$action35b_test_root/bin/systemctl" \
            CADDY_SERVING_HEALTH_ENVIRONMENT_FILE="$action35b_test_root/etc/default/caddy-ha" \
            CADDY_SERVING_HEALTH_CURL_COMMAND="$action35b_test_root/bin/curl" \
            CADDY_SERVING_HEALTH_SS_COMMAND="$action35b_test_root/bin/ss" \
            CADDY_SERVING_HEALTH_SYSTEMCTL_COMMAND="$action35b_test_root/bin/systemctl" \
            PIHOLE_WEB_HEALTH_ENVIRONMENT_FILE="$action35b_test_root/etc/default/caddy-ha" \
            PIHOLE_WEB_HEALTH_STATE_DIRECTORY="$action35b_test_root/var/lib/caddy-pihole-web-health" \
            PIHOLE_WEB_HEALTH_RUNTIME_DIRECTORY="$action35b_test_root/run/caddy-pihole-web-health" \
            PIHOLE_WEB_HEALTH_ENQUEUE_COMMAND="$action35b_test_root/bin/enqueue" \
            PIHOLE_WEB_HEALTH_CURL_COMMAND="$action35b_test_root/bin/curl" \
            PIHOLE_WEB_HEALTH_SYSTEMCTL_COMMAND="$action35b_test_root/bin/systemctl" \
            "$@"
    else
        runuser --user "$action35b_identity" -- "$@"
    fi
}

action35b_capture() {
    local action35b_label=$1

    shift
    local action35b_stdout action35b_stderr action35b_status=0
    action35b_stdout=$action35b_evidence/$action35b_label.stdout
    action35b_stderr=$action35b_evidence/$action35b_label.stderr
    : >"$action35b_stdout"
    : >"$action35b_stderr"
    "$@" >"$action35b_stdout" 2>"$action35b_stderr" || action35b_status=$?
    printf '%s\n' "$action35b_status" >"$action35b_evidence/$action35b_label.status"
    [[ -f "$action35b_stdout" && ! -L "$action35b_stdout" ]] || return 1
    [[ -f "$action35b_stderr" && ! -L "$action35b_stderr" ]] || return 1
    return "$action35b_status"
}

action35b_require_regular() {
    local action35b_path=$1
    local action35b_mode=${2:-}

    [[ -f "$action35b_path" && ! -L "$action35b_path" ]] || return 1
    [[ -z "$action35b_mode" || "$(stat -c '%a' "$action35b_path")" = "$action35b_mode" ]]
}

action35b_validate_payload() {
    local action35b_line action35b_repository action35b_source action35b_target
    local action35b_mode action35b_hash action35b_lifecycle action35b_source_path

    action35b_require_regular "$action35b_payload/serving-health-production.tsv" || return 1
    [[ "$(sed -n '1p' "$action35b_payload/serving-health-production.tsv")" = $'# repository\tsource-path\tinstalled-path\tmode\tcandidate-sha256\tlifecycle' ]] || return 1
    while IFS=$'\t' read -r action35b_repository action35b_source action35b_target \
        action35b_mode action35b_hash action35b_lifecycle; do
        [[ -n "$action35b_repository" && "$action35b_repository" != \#* ]] || continue
        [[ "$action35b_repository" =~ ^homelab-(server-configs|dns)$ ]] || return 1
        [[ "$action35b_source" != *..* && "$action35b_target" = /* ]] || return 1
        [[ "$action35b_mode" =~ ^0[0-7]{3}$ && "$action35b_hash" =~ ^[0-9a-f]{64}$ ]] || return 1
        [[ "$action35b_lifecycle" = production-candidate ]] || return 1
        action35b_source_path=$action35b_payload/files/$action35b_repository/$action35b_source
        action35b_require_regular "$action35b_source_path" || return 1
        [[ "$(sha256sum "$action35b_source_path" | awk '{ print $1 }')" = "$action35b_hash" ]] || return 1
        printf '%s\t%s\t%s\n' "$action35b_target" "$action35b_hash" "$action35b_mode" \
            >>"$action35b_evidence/payload-identities.tsv"
        action35b_line=true
    done <"$action35b_payload/serving-health-production.tsv"
    [[ "${action35b_line:-false}" = true ]]
}

action35b_validate_baseline() {
    local action35b_expected_state=$action35b_payload/current-live-state.tsv
    local action35b_current_link
    local action35b_key action35b_repository action35b_source action35b_installed
    local action35b_inventory_node action35b_source_hash action35b_deployed_hash
    local action35b_accepted_action action35b_lifecycle action35b_installed_path

    action35b_require_regular "$action35b_expected_state" || return 1
    action35b_require_regular "$action35b_payload/production-artifacts.tsv" || return 1
    action35b_check baseline_manifest_identity test \
        "$(sha256sum "$action35b_expected_state" | awk '{ print $1 }')" = "$action35b_expected_manifest_sha256" || return 1
    for action35b_unit in caddy.service caddy-lsyncd.service caddy-sync-reconcile.path \
        caddy-apprise-worker.path caddy-apprise-worker.timer keepalived.service \
        pihole-FTL.service unbound.service lighttpd.service; do
        action35b_capture "baseline-${action35b_unit//./-}" \
            action35b_systemctl is-active --quiet "$action35b_unit" || return 1
    done
    for action35b_unit in caddy.service caddy-lsyncd.service caddy-sync-reconcile.path \
        caddy-apprise-worker.path caddy-apprise-worker.timer; do
        action35b_capture "enabled-${action35b_unit//./-}" \
            action35b_systemctl is-enabled --quiet "$action35b_unit" || return 1
    done
    action35b_current_link=$(action35b_root_path /etc/caddy/current)
    [[ -L "$action35b_current_link" ]] || return 1
    readlink -f -- "$action35b_current_link" >"$action35b_evidence/original-release.path"
    action35b_require_regular "$(<"$action35b_evidence/original-release.path")/release-manifest.json" || return 1
    action35b_capture baseline-residue /bin/bash -c \
        'test -z "$(find "$1" -mindepth 1 -maxdepth 1 -name "action35b-*" -print -quit 2>/dev/null)"' \
        _ "$(action35b_root_path /var/lib/caddy-sync/incoming)" || return 1
    while IFS=$'\t' read -r action35b_key action35b_repository action35b_source \
        action35b_installed action35b_inventory_node action35b_source_hash \
        action35b_deployed_hash action35b_accepted_action action35b_lifecycle; do
        [[ -n "$action35b_key" && "$action35b_key" != \#* ]] || continue
        [[ "$action35b_inventory_node" = "$action35b_node_role" ]] || continue
        : "$action35b_repository" "$action35b_source" "$action35b_source_hash"
        [[ "$action35b_lifecycle" = production-current && "$action35b_installed" = /* ]] || return 1
        [[ "$action35b_deployed_hash" =~ ^[0-9a-f]{64}$ ]] || return 1
        action35b_installed_path=$(action35b_root_path "$action35b_installed")
        action35b_require_regular "$action35b_installed_path" || return 1
        [[ "$(sha256sum "$action35b_installed_path" | awk '{ print $1 }')" = "$action35b_deployed_hash" ]] || return 1
        printf '%s\t%s\t%s\n' "$action35b_key" "$action35b_deployed_hash" \
            "$action35b_accepted_action" >>"$action35b_evidence/baseline-identities.tsv"
    done <"$action35b_payload/production-artifacts.tsv"
    printf '%s_check_baseline_complete=true\n' "$action35b_prefix"
}

action35b_validate_candidates() {
    local action35b_keepalived action35b_dns action35b_caddy action35b_web

    action35b_keepalived=$action35b_payload/files/homelab-dns/Keepalived/configs/keepalived-pihole0.conf
    [[ "$action35b_node_role" = node-b ]] &&
        action35b_keepalived=$action35b_payload/files/homelab-dns/Keepalived/configs/keepalived-pihole00.conf
    action35b_dns=$action35b_payload/files/homelab-dns/Keepalived/scripts/dns-check.sh
    action35b_caddy=$action35b_payload/files/homelab-server-configs/Caddy/scripts/check-caddy-serving-health.sh
    action35b_web=$action35b_payload/files/homelab-server-configs/Caddy/scripts/check-pihole-web-health.sh
    action35b_preflight=$(action35b_root_path "/tmp/caddy-action35b-preflight/$action35b_node_role")
    [[ ! -e "$action35b_preflight" ]] || return 1
    install -d -m 0755 "$action35b_preflight/bin" "$action35b_preflight/state" \
        "$action35b_preflight/run"
    install -m 0755 "$action35b_dns" "$action35b_preflight/bin/check-dns.sh"
    install -m 0755 "$action35b_caddy" "$action35b_preflight/bin/check-caddy.sh"
    install -m 0755 "$action35b_web" "$action35b_preflight/bin/check-pihole-web-health.sh"
    action35b_capture keepalived-parser action35b_keepalived_parser "$action35b_keepalived" || return 1
    action35b_capture dns-service-identity action35b_run_as pi \
        /bin/bash "$action35b_preflight/bin/check-dns.sh" || return 1
    action35b_capture caddy-service-identity action35b_run_as keepalived_script \
        /usr/bin/timeout 2 /bin/bash "$action35b_preflight/bin/check-caddy.sh" || return 1
    if [[ -n "$action35b_test_root" ]]; then
        action35b_capture web-service-identity action35b_run_as pi \
            /bin/bash "$action35b_preflight/bin/check-pihole-web-health.sh" || return 1
    else
        chown -R pi:pi "$action35b_preflight/state" "$action35b_preflight/run"
        action35b_capture web-service-identity runuser --user pi -- env \
            PIHOLE_WEB_HEALTH_STATE_DIRECTORY="$action35b_preflight/state" \
            PIHOLE_WEB_HEALTH_RUNTIME_DIRECTORY="$action35b_preflight/run" \
            PIHOLE_WEB_HEALTH_ENQUEUE_COMMAND=/usr/bin/true \
            /bin/bash "$action35b_preflight/bin/check-pihole-web-health.sh" || return 1
    fi
    grep -Fq 'check=127_0_0_1_53_A status=0 answer=10.1.0.55' \
        "$action35b_evidence/dns-service-identity.stdout" || return 1
    grep -Fq 'check=__1_5335_AAAA status=0 answer=fd36:5aa8:6971:1::55' \
        "$action35b_evidence/dns-service-identity.stdout" || return 1
    grep -Fxq 'caddy_serving_health_complete=true' \
        "$action35b_evidence/caddy-service-identity.stdout" || return 1
    find "$action35b_preflight" -xdev -mindepth 1 -delete
    rmdir "$action35b_preflight"
    rmdir "$(dirname -- "$action35b_preflight")" 2>/dev/null || :
    printf '%s_check_candidate_validation_complete=true\n' "$action35b_prefix"
}

action35b_backup_current() {
    local action35b_destination
    local action35b_timer_status=0

    action35b_backup=$(action35b_root_path "/var/backups/caddy-action35b/$action35b_node_role")
    [[ ! -e "$action35b_backup" ]] || return 1
    install -d -m 0700 "$action35b_backup"
    for action35b_destination in /etc/scripts/check-dns.sh /usr/local/libexec/check-caddy.sh \
        /usr/local/libexec/check-pihole-web-health.sh /etc/systemd/system/caddy-pihole-web-health.service \
        /etc/systemd/system/caddy-pihole-web-health.timer /etc/keepalived/keepalived.conf; do
        local action35b_existing
        action35b_existing=$(action35b_root_path "$action35b_destination")
        if [[ -f "$action35b_existing" && ! -L "$action35b_existing" ]]; then
            cp -a -- "$action35b_existing" \
                "$action35b_backup/${action35b_destination//\//_}"
        else
            : >"$action35b_backup/${action35b_destination//\//_}.absent"
        fi
    done
    action35b_systemctl is-enabled --quiet caddy-pihole-web-health.timer ||
        action35b_timer_status=$?
    printf '%s\n' "$action35b_timer_status" >"$action35b_backup/timer-enabled.status"
    action35b_timer_status=0
    action35b_systemctl is-active --quiet caddy-pihole-web-health.timer ||
        action35b_timer_status=$?
    printf '%s\n' "$action35b_timer_status" >"$action35b_backup/timer-active.status"
    printf '%s_check_backup_complete=true\n' "$action35b_prefix"
}

action35b_install_candidates() {
    local action35b_repository action35b_source action35b_target action35b_mode
    local action35b_hash action35b_lifecycle action35b_source_path action35b_destination

    while IFS=$'\t' read -r action35b_repository action35b_source action35b_target \
        action35b_mode action35b_hash action35b_lifecycle; do
        [[ -n "$action35b_repository" && "$action35b_repository" != \#* ]] || continue
        case "$action35b_target" in
            */keepalived.conf)
                [[ "$action35b_node_role" = node-a && "$action35b_source" = *pihole0.conf ]] ||
                    [[ "$action35b_node_role" = node-b && "$action35b_source" = *pihole00.conf ]] || continue
                ;;
            */releases/REVISION/*) continue ;;
        esac
        action35b_source_path=$action35b_payload/files/$action35b_repository/$action35b_source
        action35b_destination=$(action35b_root_path "$action35b_target")
        install -d -m 0755 "$(dirname -- "$action35b_destination")"
        install -m "$action35b_mode" "$action35b_source_path" "$action35b_destination"
        [[ "$(sha256sum "$action35b_destination" | awk '{ print $1 }')" = "$action35b_hash" ]] || return 1
    done <"$action35b_payload/serving-health-production.tsv"
    action35b_mutated=true
    printf '1\n' >"$action35b_evidence/mutation-count"
    action35b_capture daemon-reload action35b_systemctl daemon-reload || return 1
    action35b_capture backend-timer-enable action35b_systemctl enable --now \
        caddy-pihole-web-health.timer || return 1
    action35b_capture keepalived-reload action35b_systemctl reload keepalived.service || return 1
    printf '%s_check_mutation_complete=true\n' "$action35b_prefix"
}

action35b_accept() {
    local action35b_sample
    local action35b_expected_ownership='ipv4=Backup ipv6=Backup vip_count=0'
    local action35b_stable=0

    [[ "$action35b_node_role" = node-b ]] ||
        action35b_expected_ownership='ipv4=Master ipv6=Master vip_count=4'

    for action35b_sample in $(seq 1 30); do
        action35b_capture "post-dns-$action35b_sample" action35b_run_as pi \
            /bin/bash "$(action35b_root_path /etc/scripts/check-dns.sh)" || return 1
        action35b_capture "post-caddy-$action35b_sample" action35b_run_as keepalived_script \
            /usr/bin/timeout 2 /bin/bash "$(action35b_root_path /usr/local/libexec/check-caddy.sh)" || return 1
        action35b_capture "ownership-$action35b_sample" action35b_ownership_snapshot || return 1
        if grep -Fxq "$action35b_expected_ownership" \
            "$action35b_evidence/ownership-$action35b_sample.stdout"; then
            action35b_stable=$((action35b_stable + 1))
        else
            action35b_stable=0
        fi
        [[ "$action35b_stable" -lt 3 ]] || break
        sleep 1
    done
    [[ "$action35b_stable" -eq 3 ]] || return 1
    action35b_capture timer-active action35b_systemctl is-active --quiet \
        caddy-pihole-web-health.timer || return 1
    action35b_capture timer-enabled action35b_systemctl is-enabled --quiet \
        caddy-pihole-web-health.timer || return 1
    if [[ -n "$action35b_test_root" ]]; then
        action35b_capture journal-after-cursor /bin/bash "$action35b_test_root/bin/journalctl" \
            --after-cursor "$(<"$action35b_evidence/journal.cursor")" --no-pager || return 1
    else
        action35b_capture journal-after-cursor journalctl \
            --after-cursor "$(<"$action35b_evidence/journal.cursor")" --no-pager || return 1
    fi
    if grep -Eiq 'simultaneous[_ -]ownership|script.*timed out|unsafe|secret' \
        "$action35b_evidence/journal-after-cursor.stdout"; then
        return 1
    fi
    printf '%s_check_acceptance_complete=true\n' "$action35b_prefix"
}

action35b_rollback() {
    local action35b_destination action35b_saved action35b_absent
    local action35b_temporary

    [[ "$action35b_mutated" = true ]] || return 0
    if [[ "$(<"$action35b_backup/timer-enabled.status")" -ne 0 ]]; then
        action35b_systemctl disable --now caddy-pihole-web-health.timer \
            >/dev/null 2>&1 || return 1
    fi
    for action35b_destination in /etc/scripts/check-dns.sh /usr/local/libexec/check-caddy.sh \
        /usr/local/libexec/check-pihole-web-health.sh /etc/systemd/system/caddy-pihole-web-health.service \
        /etc/systemd/system/caddy-pihole-web-health.timer /etc/keepalived/keepalived.conf; do
        action35b_saved=$action35b_backup/${action35b_destination//\//_}
        action35b_absent=$action35b_saved.absent
        if [[ -f "$action35b_saved" && ! -L "$action35b_saved" ]]; then
            action35b_temporary=$(action35b_root_path "$action35b_destination.rollback-action35b")
            [[ ! -e "$action35b_temporary" && ! -L "$action35b_temporary" ]] || return 1
            cp -a -- "$action35b_saved" "$action35b_temporary"
            mv -fT -- "$action35b_temporary" "$(action35b_root_path "$action35b_destination")"
        elif [[ -f "$action35b_absent" && ! -L "$action35b_absent" ]]; then
            rm -f -- "$(action35b_root_path "$action35b_destination")"
        else
            return 1
        fi
    done
    action35b_systemctl daemon-reload >/dev/null 2>&1 || return 1
    if [[ "$(<"$action35b_backup/timer-enabled.status")" -eq 0 ]]; then
        action35b_systemctl enable caddy-pihole-web-health.timer >/dev/null 2>&1 || return 1
    fi
    if [[ "$(<"$action35b_backup/timer-active.status")" -eq 0 ]]; then
        action35b_systemctl start caddy-pihole-web-health.timer >/dev/null 2>&1 || return 1
    fi
    action35b_systemctl reload keepalived.service >/dev/null 2>&1 || return 1
    printf '%s_check_rollback_complete=true\n' "$action35b_prefix"
}

action35b_cleanup() {
    local action35b_status=$?

    if [[ -n "$action35b_preflight" && -d "$action35b_preflight" && ! -L "$action35b_preflight" ]]; then
        find "$action35b_preflight" -xdev -mindepth 1 -delete || :
        rmdir "$action35b_preflight" 2>/dev/null || :
        rmdir "$(dirname -- "$action35b_preflight")" 2>/dev/null || :
    fi
    if ((action35b_status != 0)) && [[ "$action35b_mutated" = true ]]; then
        if ! action35b_rollback; then
            exit 125
        fi
    fi
    exit "$action35b_status"
}

while (($#)); do
    case "$1" in
        --node-role)
            action35b_node_role=${2:-}
            shift 2
            ;;
        --payload)
            action35b_payload=${2:-}
            shift 2
            ;;
        --production-path-test)
            action35b_test_root=${2:-}
            shift 2
            ;;
        --rollback-existing)
            action35b_mode=rollback
            shift
            ;;
        *)
            action35b_usage
            exit 64
            ;;
    esac
done

[[ "$action35b_node_role" =~ ^node-[ab]$ ]] || {
    action35b_usage
    exit 64
}
if [[ "$action35b_mode" = apply ]]; then
    [[ -d "$action35b_payload" && ! -L "$action35b_payload" ]] || exit 64
fi
if [[ -n "$action35b_test_root" ]]; then
    [[ "$action35b_test_root" = /tmp/* && -d "$action35b_test_root" && ! -L "$action35b_test_root" ]] || exit 64
fi

action35b_evidence=$(action35b_root_path "$action35b_node_evidence/$action35b_node_role")
readonly action35b_evidence
if [[ "$action35b_mode" = rollback ]]; then
    action35b_backup=$(action35b_root_path "/var/backups/caddy-action35b/$action35b_node_role")
    [[ -d "$action35b_backup" && ! -L "$action35b_backup" ]] || exit 1
    action35b_mutated=true
    action35b_rollback
    exit 0
fi
[[ ! -e "$action35b_evidence" ]] || exit 1
install -d -m 0700 "$action35b_evidence"
printf '0\n' >"$action35b_evidence/mutation-count"
if [[ -n "$action35b_test_root" ]]; then
    /bin/bash "$action35b_test_root/bin/journalctl" --show-cursor --no-pager \
        >"$action35b_evidence/journal.cursor"
else
    journalctl --show-cursor --no-pager >"$action35b_evidence/journal.cursor"
fi
trap action35b_cleanup EXIT INT TERM

action35b_check payload_contract action35b_validate_payload
action35b_validate_baseline
action35b_validate_candidates
action35b_backup_current
action35b_install_candidates
action35b_accept
action35b_check residue_absent test -z \
    "$(find "$(action35b_root_path /var/lib/caddy-sync/incoming)" -mindepth 1 -maxdepth 1 -name 'action35b-*' -print -quit 2>/dev/null)"
printf '%s_check_complete=true\n' "$action35b_prefix"
