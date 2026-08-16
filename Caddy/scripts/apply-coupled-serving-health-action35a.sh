#!/usr/bin/env bash
# shellcheck disable=SC2016 # The captured Bash predicate expands only inside its child shell.

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH
readonly PATH

readonly action35a_prefix=action_35a
readonly action35a_expected_manifest_sha256=86f71fba1b126754fa560ddf49f569c2b06f85ab603a9a24f59921d1064da087
readonly action35a_node_evidence=/tmp/caddy-action35a

action35a_node_role=
action35a_payload=
action35a_test_root=
action35a_mode=apply
action35a_mutated=false
action35a_backup=
action35a_preflight=

if [[ "${1:-}" = --production-path-test && $# -eq 1 ]]; then
    action35a_self_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
    readonly action35a_self_directory
    exec /bin/bash "$action35a_self_directory/../tests/coupled-serving-health-deployment-regression.sh" \
        --entrypoint transaction
fi

action35a_usage() {
    printf 'Usage: %s --node-role node-a|node-b --payload DIRECTORY [--production-path-test ROOT]\n' "${0##*/}" >&2
}

action35a_check() {
    local action35a_label=$1

    shift
    if "$@"; then
        printf '%s_check_%s=true\n' "$action35a_prefix" "$action35a_label"
        return 0
    fi
    printf '%s_check_%s=false\n' "$action35a_prefix" "$action35a_label" >&2
    return 1
}

action35a_root_path() {
    local action35a_path=$1

    if [[ -n "$action35a_test_root" ]]; then
        printf '%s%s' "${action35a_test_root%/}" "$action35a_path"
    else
        printf '%s' "$action35a_path"
    fi
}

action35a_systemctl() {
    if [[ -n "$action35a_test_root" ]]; then
        /bin/bash "$action35a_test_root/bin/systemctl" "$@"
    else
        systemctl "$@"
    fi
}

action35a_keepalived_parser() {
    local action35a_config=$1

    if [[ -n "$action35a_test_root" ]]; then
        /bin/bash "$action35a_test_root/bin/keepalived" --config-test --use-file="$action35a_config"
    else
        keepalived --config-test --use-file="$action35a_config"
    fi
}

action35a_ownership_snapshot() {
    if [[ -n "$action35a_test_root" ]]; then
        /bin/bash "$action35a_test_root/bin/ownership" "$action35a_node_role"
        return
    fi
    local action35a_ipv4_state action35a_ipv6_state action35a_vip_count
    action35a_ipv4_state=$(timeout 2 busctl get-property org.keepalived.Vrrp1 \
        /org/keepalived/Vrrp1/Instance/eth0/100/IPv4 org.keepalived.Vrrp1.Instance State)
    action35a_ipv6_state=$(timeout 2 busctl get-property org.keepalived.Vrrp1 \
        /org/keepalived/Vrrp1/Instance/eth0/101/IPv6 org.keepalived.Vrrp1.Instance State)
    action35a_vip_count=$(
        ip -o address show dev eth0 |
            awk '$4 ~ /^(10\.1\.0\.(55|56)\/22|fd36:5aa8:6971:1::(55|56)\/128)$/ { count++ } END { print count + 0 }'
    )
    printf 'ipv4=%s ipv6=%s vip_count=%s\n' \
        "$action35a_ipv4_state" "$action35a_ipv6_state" "$action35a_vip_count"
}

action35a_run_as() {
    local action35a_identity=$1

    shift
    if [[ -n "$action35a_test_root" ]]; then
        {
            printf '%s\t' "$action35a_identity"
            printf '%q ' "$@"
            printf '\n'
        } >>"$action35a_test_root/calls/identities.tsv"
        env \
            DNS_CHECK_DIG_COMMAND="$action35a_test_root/bin/dig" \
            DNS_CHECK_SYSTEMCTL_COMMAND="$action35a_test_root/bin/systemctl" \
            CADDY_SERVING_HEALTH_ENVIRONMENT_FILE="$action35a_test_root/etc/default/caddy-ha" \
            CADDY_SERVING_HEALTH_CURL_COMMAND="$action35a_test_root/bin/curl" \
            CADDY_SERVING_HEALTH_SS_COMMAND="$action35a_test_root/bin/ss" \
            CADDY_SERVING_HEALTH_SYSTEMCTL_COMMAND="$action35a_test_root/bin/systemctl" \
            PIHOLE_WEB_HEALTH_ENVIRONMENT_FILE="$action35a_test_root/etc/default/caddy-ha" \
            PIHOLE_WEB_HEALTH_STATE_DIRECTORY="$action35a_test_root/var/lib/caddy-pihole-web-health" \
            PIHOLE_WEB_HEALTH_RUNTIME_DIRECTORY="$action35a_test_root/run/caddy-pihole-web-health" \
            PIHOLE_WEB_HEALTH_ENQUEUE_COMMAND="$action35a_test_root/bin/enqueue" \
            PIHOLE_WEB_HEALTH_CURL_COMMAND="$action35a_test_root/bin/curl" \
            PIHOLE_WEB_HEALTH_SYSTEMCTL_COMMAND="$action35a_test_root/bin/systemctl" \
            "$@"
    else
        runuser --user "$action35a_identity" -- "$@"
    fi
}

action35a_capture() {
    local action35a_label=$1

    shift
    local action35a_stdout action35a_stderr action35a_status=0
    action35a_stdout=$action35a_evidence/$action35a_label.stdout
    action35a_stderr=$action35a_evidence/$action35a_label.stderr
    : >"$action35a_stdout"
    : >"$action35a_stderr"
    "$@" >"$action35a_stdout" 2>"$action35a_stderr" || action35a_status=$?
    printf '%s\n' "$action35a_status" >"$action35a_evidence/$action35a_label.status"
    [[ -f "$action35a_stdout" && ! -L "$action35a_stdout" ]] || return 1
    [[ -f "$action35a_stderr" && ! -L "$action35a_stderr" ]] || return 1
    return "$action35a_status"
}

action35a_require_regular() {
    local action35a_path=$1
    local action35a_mode=${2:-}

    [[ -f "$action35a_path" && ! -L "$action35a_path" ]] || return 1
    [[ -z "$action35a_mode" || "$(stat -c '%a' "$action35a_path")" = "$action35a_mode" ]]
}

action35a_validate_payload() {
    local action35a_line action35a_repository action35a_source action35a_target
    local action35a_mode action35a_hash action35a_lifecycle action35a_source_path

    action35a_require_regular "$action35a_payload/serving-health-production.tsv" || return 1
    [[ "$(sed -n '1p' "$action35a_payload/serving-health-production.tsv")" = $'# repository\tsource-path\tinstalled-path\tmode\tcandidate-sha256\tlifecycle' ]] || return 1
    while IFS=$'\t' read -r action35a_repository action35a_source action35a_target \
        action35a_mode action35a_hash action35a_lifecycle; do
        [[ -n "$action35a_repository" && "$action35a_repository" != \#* ]] || continue
        [[ "$action35a_repository" =~ ^homelab-(server-configs|dns)$ ]] || return 1
        [[ "$action35a_source" != *..* && "$action35a_target" = /* ]] || return 1
        [[ "$action35a_mode" =~ ^0[0-7]{3}$ && "$action35a_hash" =~ ^[0-9a-f]{64}$ ]] || return 1
        [[ "$action35a_lifecycle" = production-candidate ]] || return 1
        action35a_source_path=$action35a_payload/files/$action35a_repository/$action35a_source
        action35a_require_regular "$action35a_source_path" || return 1
        [[ "$(sha256sum "$action35a_source_path" | awk '{ print $1 }')" = "$action35a_hash" ]] || return 1
        printf '%s\t%s\t%s\n' "$action35a_target" "$action35a_hash" "$action35a_mode" \
            >>"$action35a_evidence/payload-identities.tsv"
        action35a_line=true
    done <"$action35a_payload/serving-health-production.tsv"
    [[ "${action35a_line:-false}" = true ]]
}

action35a_validate_baseline() {
    local action35a_expected_state=$action35a_payload/current-live-state.tsv
    local action35a_current_link
    local action35a_key action35a_repository action35a_source action35a_installed
    local action35a_inventory_node action35a_source_hash action35a_deployed_hash
    local action35a_accepted_action action35a_lifecycle action35a_installed_path

    action35a_require_regular "$action35a_expected_state" || return 1
    action35a_require_regular "$action35a_payload/production-artifacts.tsv" || return 1
    action35a_check baseline_manifest_identity test \
        "$(sha256sum "$action35a_expected_state" | awk '{ print $1 }')" = "$action35a_expected_manifest_sha256" || return 1
    for action35a_unit in caddy.service caddy-lsyncd.service caddy-sync-reconcile.path \
        caddy-apprise-worker.path caddy-apprise-worker.timer keepalived.service \
        pihole-FTL.service unbound.service lighttpd.service; do
        action35a_capture "baseline-${action35a_unit//./-}" \
            action35a_systemctl is-active --quiet "$action35a_unit" || return 1
    done
    for action35a_unit in caddy.service caddy-lsyncd.service caddy-sync-reconcile.path \
        caddy-apprise-worker.path caddy-apprise-worker.timer; do
        action35a_capture "enabled-${action35a_unit//./-}" \
            action35a_systemctl is-enabled --quiet "$action35a_unit" || return 1
    done
    action35a_current_link=$(action35a_root_path /etc/caddy/current)
    [[ -L "$action35a_current_link" ]] || return 1
    readlink -f -- "$action35a_current_link" >"$action35a_evidence/original-release.path"
    action35a_require_regular "$(<"$action35a_evidence/original-release.path")/release-manifest.json" || return 1
    action35a_capture baseline-residue /bin/bash -c \
        'test -z "$(find "$1" -mindepth 1 -maxdepth 1 -name "action35a-*" -print -quit 2>/dev/null)"' \
        _ "$(action35a_root_path /var/lib/caddy-sync/incoming)" || return 1
    while IFS=$'\t' read -r action35a_key action35a_repository action35a_source \
        action35a_installed action35a_inventory_node action35a_source_hash \
        action35a_deployed_hash action35a_accepted_action action35a_lifecycle; do
        [[ -n "$action35a_key" && "$action35a_key" != \#* ]] || continue
        [[ "$action35a_inventory_node" = "$action35a_node_role" ]] || continue
        : "$action35a_repository" "$action35a_source" "$action35a_source_hash"
        [[ "$action35a_lifecycle" = production-current && "$action35a_installed" = /* ]] || return 1
        [[ "$action35a_deployed_hash" =~ ^[0-9a-f]{64}$ ]] || return 1
        action35a_installed_path=$(action35a_root_path "$action35a_installed")
        action35a_require_regular "$action35a_installed_path" || return 1
        [[ "$(sha256sum "$action35a_installed_path" | awk '{ print $1 }')" = "$action35a_deployed_hash" ]] || return 1
        printf '%s\t%s\t%s\n' "$action35a_key" "$action35a_deployed_hash" \
            "$action35a_accepted_action" >>"$action35a_evidence/baseline-identities.tsv"
    done <"$action35a_payload/production-artifacts.tsv"
    printf '%s_check_baseline_complete=true\n' "$action35a_prefix"
}

action35a_validate_candidates() {
    local action35a_keepalived action35a_dns action35a_caddy action35a_web

    action35a_keepalived=$action35a_payload/files/homelab-dns/Keepalived/configs/keepalived-pihole0.conf
    [[ "$action35a_node_role" = node-b ]] &&
        action35a_keepalived=$action35a_payload/files/homelab-dns/Keepalived/configs/keepalived-pihole00.conf
    action35a_dns=$action35a_payload/files/homelab-dns/Keepalived/scripts/dns-check.sh
    action35a_caddy=$action35a_payload/files/homelab-server-configs/Caddy/scripts/check-caddy-serving-health.sh
    action35a_web=$action35a_payload/files/homelab-server-configs/Caddy/scripts/check-pihole-web-health.sh
    action35a_preflight=$(action35a_root_path "/tmp/caddy-action35a-preflight/$action35a_node_role")
    [[ ! -e "$action35a_preflight" ]] || return 1
    install -d -m 0755 "$action35a_preflight/bin" "$action35a_preflight/state" \
        "$action35a_preflight/run"
    install -m 0755 "$action35a_dns" "$action35a_preflight/bin/check-dns.sh"
    install -m 0755 "$action35a_caddy" "$action35a_preflight/bin/check-caddy.sh"
    install -m 0755 "$action35a_web" "$action35a_preflight/bin/check-pihole-web-health.sh"
    action35a_capture keepalived-parser action35a_keepalived_parser "$action35a_keepalived" || return 1
    action35a_capture dns-service-identity action35a_run_as pi \
        /bin/bash "$action35a_preflight/bin/check-dns.sh" || return 1
    action35a_capture caddy-service-identity action35a_run_as keepalived_script \
        /usr/bin/timeout 2 /bin/bash "$action35a_preflight/bin/check-caddy.sh" || return 1
    if [[ -n "$action35a_test_root" ]]; then
        action35a_capture web-service-identity action35a_run_as pi \
            /bin/bash "$action35a_preflight/bin/check-pihole-web-health.sh" || return 1
    else
        chown -R pi:pi "$action35a_preflight/state" "$action35a_preflight/run"
        action35a_capture web-service-identity runuser --user pi -- env \
            PIHOLE_WEB_HEALTH_STATE_DIRECTORY="$action35a_preflight/state" \
            PIHOLE_WEB_HEALTH_RUNTIME_DIRECTORY="$action35a_preflight/run" \
            PIHOLE_WEB_HEALTH_ENQUEUE_COMMAND=/usr/bin/true \
            /bin/bash "$action35a_preflight/bin/check-pihole-web-health.sh" || return 1
    fi
    grep -Fq 'check=127_0_0_1_53_A status=0 answer=10.1.0.55' \
        "$action35a_evidence/dns-service-identity.stdout" || return 1
    grep -Fq 'check=__1_5335_AAAA status=0 answer=fd36:5aa8:6971:1::55' \
        "$action35a_evidence/dns-service-identity.stdout" || return 1
    grep -Fxq 'caddy_serving_health_complete=true' \
        "$action35a_evidence/caddy-service-identity.stdout" || return 1
    find "$action35a_preflight" -xdev -mindepth 1 -delete
    rmdir "$action35a_preflight"
    rmdir "$(dirname -- "$action35a_preflight")" 2>/dev/null || :
    printf '%s_check_candidate_validation_complete=true\n' "$action35a_prefix"
}

action35a_backup_current() {
    local action35a_destination

    action35a_backup=$(action35a_root_path "/var/backups/caddy-action35a/$action35a_node_role")
    [[ ! -e "$action35a_backup" ]] || return 1
    install -d -m 0700 "$action35a_backup"
    for action35a_destination in /etc/scripts/check-dns.sh /usr/local/libexec/check-caddy.sh \
        /usr/local/libexec/check-pihole-web-health.sh /etc/systemd/system/caddy-pihole-web-health.service \
        /etc/systemd/system/caddy-pihole-web-health.timer /etc/keepalived/keepalived.conf; do
        local action35a_existing
        action35a_existing=$(action35a_root_path "$action35a_destination")
        if [[ -f "$action35a_existing" && ! -L "$action35a_existing" ]]; then
            install -m 0600 "$action35a_existing" \
                "$action35a_backup/${action35a_destination//\//_}"
        else
            : >"$action35a_backup/${action35a_destination//\//_}.absent"
        fi
    done
    printf '%s_check_backup_complete=true\n' "$action35a_prefix"
}

action35a_install_candidates() {
    local action35a_repository action35a_source action35a_target action35a_mode
    local action35a_hash action35a_lifecycle action35a_source_path action35a_destination

    while IFS=$'\t' read -r action35a_repository action35a_source action35a_target \
        action35a_mode action35a_hash action35a_lifecycle; do
        [[ -n "$action35a_repository" && "$action35a_repository" != \#* ]] || continue
        case "$action35a_target" in
            */keepalived.conf)
                [[ "$action35a_node_role" = node-a && "$action35a_source" = *pihole0.conf ]] ||
                    [[ "$action35a_node_role" = node-b && "$action35a_source" = *pihole00.conf ]] || continue
                ;;
            */releases/REVISION/*) continue ;;
        esac
        action35a_source_path=$action35a_payload/files/$action35a_repository/$action35a_source
        action35a_destination=$(action35a_root_path "$action35a_target")
        install -d -m 0755 "$(dirname -- "$action35a_destination")"
        install -m "$action35a_mode" "$action35a_source_path" "$action35a_destination"
        [[ "$(sha256sum "$action35a_destination" | awk '{ print $1 }')" = "$action35a_hash" ]] || return 1
    done <"$action35a_payload/serving-health-production.tsv"
    action35a_mutated=true
    printf '1\n' >"$action35a_evidence/mutation-count"
    action35a_capture daemon-reload action35a_systemctl daemon-reload || return 1
    action35a_capture backend-timer-enable action35a_systemctl enable --now \
        caddy-pihole-web-health.timer || return 1
    action35a_capture keepalived-reload action35a_systemctl reload keepalived.service || return 1
    printf '%s_check_mutation_complete=true\n' "$action35a_prefix"
}

action35a_accept() {
    local action35a_sample
    local action35a_expected_ownership='ipv4=Backup ipv6=Backup vip_count=0'

    [[ "$action35a_node_role" = node-b ]] ||
        action35a_expected_ownership='ipv4=Master ipv6=Master vip_count=4'

    for action35a_sample in 1 2 3; do
        action35a_capture "post-dns-$action35a_sample" action35a_run_as pi \
            /bin/bash "$(action35a_root_path /etc/scripts/check-dns.sh)" || return 1
        action35a_capture "post-caddy-$action35a_sample" action35a_run_as keepalived_script \
            /usr/bin/timeout 2 /bin/bash "$(action35a_root_path /usr/local/libexec/check-caddy.sh)" || return 1
        action35a_capture "ownership-$action35a_sample" action35a_ownership_snapshot || return 1
        grep -Fxq "$action35a_expected_ownership" \
            "$action35a_evidence/ownership-$action35a_sample.stdout" || return 1
    done
    action35a_capture timer-active action35a_systemctl is-active --quiet \
        caddy-pihole-web-health.timer || return 1
    action35a_capture timer-enabled action35a_systemctl is-enabled --quiet \
        caddy-pihole-web-health.timer || return 1
    if [[ -n "$action35a_test_root" ]]; then
        action35a_capture journal-after-cursor /bin/bash "$action35a_test_root/bin/journalctl" \
            --after-cursor "$(<"$action35a_evidence/journal.cursor")" --no-pager || return 1
    else
        action35a_capture journal-after-cursor journalctl \
            --after-cursor "$(<"$action35a_evidence/journal.cursor")" --no-pager || return 1
    fi
    if grep -Eiq 'simultaneous[_ -]ownership|script.*timed out|unsafe|secret' \
        "$action35a_evidence/journal-after-cursor.stdout"; then
        return 1
    fi
    printf '%s_check_acceptance_complete=true\n' "$action35a_prefix"
}

action35a_rollback() {
    local action35a_destination action35a_saved action35a_absent

    [[ "$action35a_mutated" = true ]] || return 0
    for action35a_destination in /etc/scripts/check-dns.sh /usr/local/libexec/check-caddy.sh \
        /usr/local/libexec/check-pihole-web-health.sh /etc/systemd/system/caddy-pihole-web-health.service \
        /etc/systemd/system/caddy-pihole-web-health.timer /etc/keepalived/keepalived.conf; do
        action35a_saved=$action35a_backup/${action35a_destination//\//_}
        action35a_absent=$action35a_saved.absent
        if [[ -f "$action35a_saved" && ! -L "$action35a_saved" ]]; then
            install -m 0644 "$action35a_saved" "$(action35a_root_path "$action35a_destination")"
        elif [[ -f "$action35a_absent" && ! -L "$action35a_absent" ]]; then
            rm -f -- "$(action35a_root_path "$action35a_destination")"
        else
            return 1
        fi
    done
    action35a_systemctl daemon-reload >/dev/null 2>&1 || return 1
    action35a_systemctl reload keepalived.service >/dev/null 2>&1 || return 1
    printf '%s_check_rollback_complete=true\n' "$action35a_prefix"
}

action35a_cleanup() {
    local action35a_status=$?

    if [[ -n "$action35a_preflight" && -d "$action35a_preflight" && ! -L "$action35a_preflight" ]]; then
        find "$action35a_preflight" -xdev -mindepth 1 -delete || :
        rmdir "$action35a_preflight" 2>/dev/null || :
        rmdir "$(dirname -- "$action35a_preflight")" 2>/dev/null || :
    fi
    if ((action35a_status != 0)) && [[ "$action35a_mutated" = true ]]; then
        if ! action35a_rollback; then
            exit 125
        fi
    fi
    exit "$action35a_status"
}

while (($#)); do
    case "$1" in
        --node-role)
            action35a_node_role=${2:-}
            shift 2
            ;;
        --payload)
            action35a_payload=${2:-}
            shift 2
            ;;
        --production-path-test)
            action35a_test_root=${2:-}
            shift 2
            ;;
        --rollback-existing)
            action35a_mode=rollback
            shift
            ;;
        *)
            action35a_usage
            exit 64
            ;;
    esac
done

[[ "$action35a_node_role" =~ ^node-[ab]$ ]] || {
    action35a_usage
    exit 64
}
if [[ "$action35a_mode" = apply ]]; then
    [[ -d "$action35a_payload" && ! -L "$action35a_payload" ]] || exit 64
fi
if [[ -n "$action35a_test_root" ]]; then
    [[ "$action35a_test_root" = /tmp/* && -d "$action35a_test_root" && ! -L "$action35a_test_root" ]] || exit 64
fi

action35a_evidence=$(action35a_root_path "$action35a_node_evidence/$action35a_node_role")
readonly action35a_evidence
if [[ "$action35a_mode" = rollback ]]; then
    action35a_backup=$(action35a_root_path "/var/backups/caddy-action35a/$action35a_node_role")
    [[ -d "$action35a_backup" && ! -L "$action35a_backup" ]] || exit 1
    action35a_mutated=true
    action35a_rollback
    exit 0
fi
[[ ! -e "$action35a_evidence" ]] || exit 1
install -d -m 0700 "$action35a_evidence"
printf '0\n' >"$action35a_evidence/mutation-count"
if [[ -n "$action35a_test_root" ]]; then
    /bin/bash "$action35a_test_root/bin/journalctl" --show-cursor --no-pager \
        >"$action35a_evidence/journal.cursor"
else
    journalctl --show-cursor --no-pager >"$action35a_evidence/journal.cursor"
fi
trap action35a_cleanup EXIT INT TERM

action35a_check payload_contract action35a_validate_payload
action35a_validate_baseline
action35a_validate_candidates
action35a_backup_current
action35a_install_candidates
action35a_accept
action35a_check residue_absent test -z \
    "$(find "$(action35a_root_path /var/lib/caddy-sync/incoming)" -mindepth 1 -maxdepth 1 -name 'action35a-*' -print -quit 2>/dev/null)"
printf '%s_check_complete=true\n' "$action35a_prefix"
