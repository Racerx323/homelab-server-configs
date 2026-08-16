#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH
readonly PATH

readonly prefix=action_35_remote
readonly candidate_manifest_relative=Caddy/manifests/serving-health-production.tsv
readonly accepted_manifest_relative=Caddy/manifests/accepted-live-artifacts.tsv
readonly production_inventory_relative=Caddy/manifests/production-artifacts.tsv
readonly ipv4_object=/org/keepalived/Vrrp1/Instance/eth0/100/IPv4
readonly ipv6_object=/org/keepalived/Vrrp1/Instance/eth0/101/IPv6
readonly dns_ipv4=10.1.0.55
readonly caddy_ipv4=10.1.0.56
readonly dns_ipv6=fd36:5aa8:6971:1::55
readonly caddy_ipv6=fd36:5aa8:6971:1::56
readonly publisher=/usr/local/libexec/publish-release-v2.sh
readonly backup_parent=/var/backups/caddy-ha

mode=${1:-}
role=${2:-}
payload_archive=${3:-}
payload_sha256=${4:-}
run_token=${5:-}
revision=${6:-}
production_test_root=

file_hash() { sha256sum -- "$1" | awk '{ print $1 }'; }

check() {
    local action35_check_label=$1

    shift
    if "$@" >/dev/null 2>&1; then
        printf '%s_%s_check_%s=true\n' "$prefix" "${role//-/_}" "$action35_check_label"
        return 0
    fi
    printf '%s_%s_check_%s=false\n' "$prefix" "${role//-/_}" "$action35_check_label" >&2
    return 1
}

valid_token() { [[ "$1" =~ ^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$ ]]; }

vip_count() {
    local action35_family=$1
    local action35_address=$2

    ip -o "-$action35_family" address show dev eth0 |
        awk -v address="$action35_address" 'index($4, address "/") == 1 { count++ } END { print count + 0 }'
}

vrrp_state() {
    local action35_object=$1

    timeout 3 busctl get-property org.keepalived.Vrrp1 "$action35_object" \
        org.keepalived.Vrrp1.Instance State
}

assert_role_state() {
    local action35_expected_state action35_expected_count

    if [[ "$role" = node-a ]]; then
        action35_expected_state='(us) 2 "Master"'
        action35_expected_count=1
    else
        action35_expected_state='(us) 1 "Backup"'
        action35_expected_count=0
    fi
    check ipv4_state test "$(vrrp_state "$ipv4_object")" = "$action35_expected_state"
    check ipv6_state test "$(vrrp_state "$ipv6_object")" = "$action35_expected_state"
    check dns_ipv4_ownership test "$(vip_count 4 "$dns_ipv4")" -eq "$action35_expected_count"
    check caddy_ipv4_ownership test "$(vip_count 4 "$caddy_ipv4")" -eq "$action35_expected_count"
    check dns_ipv6_ownership test "$(vip_count 6 "$dns_ipv6")" -eq "$action35_expected_count"
    check caddy_ipv6_ownership test "$(vip_count 6 "$caddy_ipv6")" -eq "$action35_expected_count"
}

validate_payload() {
    local action35_listing=$evidence_root/payload.list

    check payload_regular test -f "$payload_archive"
    check payload_not_symlink test ! -L "$payload_archive"
    check payload_hash test "$(file_hash "$payload_archive")" = "$payload_sha256"
    tar -tf "$payload_archive" >"$action35_listing"
    # shellcheck disable=SC2016
    check payload_paths awk '
        /^\/?$/ || /^\// || /(^|\/)\.\.?(\/|$)/ { invalid = 1; exit }
        { seen[$0]++ }
        seen[$0] > 1 { invalid = 1; exit }
        END { exit invalid || NR == 0 }
    ' "$action35_listing"
    stage_root=$(mktemp -d /run/caddy-action35.XXXXXX)
    readonly stage_root
    tar --no-same-owner --no-same-permissions -xf "$payload_archive" -C "$stage_root"
    check payload_symlinks_absent test -z "$(find "$stage_root" -type l -print -quit)"
    candidate_manifest=$stage_root/homelab-server-configs/$candidate_manifest_relative
    accepted_manifest=$stage_root/homelab-server-configs/$accepted_manifest_relative
    production_inventory=$stage_root/homelab-server-configs/$production_inventory_relative
    readonly candidate_manifest accepted_manifest production_inventory
    check candidate_manifest_regular test -f "$candidate_manifest"
    check accepted_manifest_regular test -f "$accepted_manifest"
    check production_inventory_regular test -f "$production_inventory"
    while IFS=$'\t' read -r action35_repository action35_source action35_target \
        action35_mode action35_hash action35_lifecycle; do
        [[ -n "$action35_repository" && "$action35_repository" != \#* ]] || continue
        [[ "$action35_repository" =~ ^homelab-(server-configs|dns)$ ]]
        [[ "$action35_source" != /* && "$action35_source" != *..* ]]
        [[ "$action35_target" = /* && "$action35_target" != *..* ]]
        [[ "$action35_mode" =~ ^0[0-7]{3}$ ]]
        [[ "$action35_hash" =~ ^[0-9a-f]{64}$ ]]
        [[ "$action35_lifecycle" = production-candidate ]]
        action35_candidate=$stage_root/$action35_repository/$action35_source
        [[ -f "$action35_candidate" && ! -L "$action35_candidate" ]]
        [[ "$(file_hash "$action35_candidate")" = "$action35_hash" ]]
    done <"$candidate_manifest"
    printf 'production_path_payload_validation_reached=true\n'
}

inventory_deployed_hash() {
    local action35_key=$1

    awk -F '\t' -v key="$action35_key" '$1 == key { print $7; found++ } END { if (found != 1) exit 1 }' \
        "$production_inventory"
}

baseline_key() {
    local action35_key=$1
    local action35_target=$2
    local action35_expected

    action35_expected=$(inventory_deployed_hash "$action35_key")
    check "baseline_$action35_key" test "$(file_hash "$action35_target")" = "$action35_expected"
}

candidate_source() {
    local action35_source=$1
    local action35_repository=$2

    printf '%s/%s/%s\n' "$stage_root" "$action35_repository" "$action35_source"
}

candidate_hash_for_target() {
    local action35_target=$1
    local action35_source_filter=${2:-}

    awk -F '\t' -v target="$action35_target" -v source_filter="$action35_source_filter" '
        /^[[:space:]]*(#|$)/ { next }
        $3 == target && (source_filter == "" || $2 == source_filter) { print $5; found++ }
        END { if (found != 1) exit 1 }
    ' "$candidate_manifest"
}

candidate_path_for_target() {
    local action35_target=$1
    local action35_source_filter=${2:-}

    awk -F '\t' -v target="$action35_target" -v source_filter="$action35_source_filter" '
        /^[[:space:]]*(#|$)/ { next }
        $3 == target && (source_filter == "" || $2 == source_filter) {
            print $1 "/" $2; found++
        }
        END { if (found != 1) exit 1 }
    ' "$candidate_manifest"
}

assert_baseline() {
    local action35_role_prefix

    action35_role_prefix=${role//-/_}
    for action35_service in caddy.service pihole-FTL.service unbound.service \
        lighttpd.service keepalived.service caddy-lsyncd.service \
        caddy-sync-reconcile.path caddy-apprise-worker.path \
        caddy-apprise-worker.timer; do
        check "service_${action35_service//[^A-Za-z0-9]/_}" \
            systemctl is-active --quiet "$action35_service"
    done
    assert_role_state
    baseline_key "${action35_role_prefix}_health_helper" /usr/local/libexec/check-caddy.sh
    baseline_key "${action35_role_prefix}_dns_health_helper" /etc/scripts/check-dns.sh
    baseline_key "${action35_role_prefix}_keepalived_main" /etc/keepalived/keepalived.conf
    baseline_key "${action35_role_prefix}_apprise_enqueue" /usr/local/libexec/caddy-apprise-enqueue
    baseline_key "${action35_role_prefix}_apprise_delivery_worker" /usr/local/libexec/caddy-apprise-delivery-worker
    check monitor_helper_absent test ! -e /usr/local/libexec/check-pihole-web-health.sh
    check monitor_service_absent test ! -e /etc/systemd/system/caddy-pihole-web-health.service
    check monitor_timer_absent test ! -e /etc/systemd/system/caddy-pihole-web-health.timer
    check current_release_symlink test -L /etc/caddy/current
    original_release=$(readlink -f /etc/caddy/current)
    [[ "$original_release" =~ ^/etc/caddy/releases/[A-Za-z0-9._-]+$ ]]
    printf '%s\n' "$original_release" >"$backup_root/original-release"
    printf 'production_path_baseline_current=true\n'
}

backup_targets() {
    local action35_target action35_backup_name

    install -d -o root -g root -m 0700 "$backup_root/files"
    for action35_target in /usr/local/libexec/check-caddy.sh \
        /usr/local/libexec/check-pihole-web-health.sh \
        /usr/local/libexec/caddy-apprise-enqueue \
        /usr/local/libexec/caddy-apprise-delivery-worker \
        /etc/scripts/check-dns.sh /etc/keepalived/keepalived.conf \
        /etc/systemd/system/caddy-pihole-web-health.service \
        /etc/systemd/system/caddy-pihole-web-health.timer; do
        action35_backup_name=${action35_target#/}
        action35_backup_name=${action35_backup_name//\//__}
        if [[ -e "$action35_target" || -L "$action35_target" ]]; then
            [[ -f "$action35_target" && ! -L "$action35_target" ]]
            cp -a -- "$action35_target" "$backup_root/files/$action35_backup_name"
            printf 'present\t%s\t%s\n' "$action35_target" "$action35_backup_name" \
                >>"$backup_root/files.tsv"
        else
            printf 'absent\t%s\t-\n' "$action35_target" >>"$backup_root/files.tsv"
        fi
    done
    chmod 0600 "$backup_root/files.tsv" "$backup_root/original-release"
}

install_target() {
    local action35_target=$1
    local action35_source_filter=${2:-}
    local action35_relative action35_source action35_hash action35_mode

    action35_relative=$(candidate_path_for_target "$action35_target" "$action35_source_filter")
    action35_source=$stage_root/$action35_relative
    action35_hash=$(candidate_hash_for_target "$action35_target" "$action35_source_filter")
    action35_mode=$(awk -F '\t' -v target="$action35_target" -v source_filter="$action35_source_filter" '
        $3 == target && (source_filter == "" || $2 == source_filter) { print $4; found++ }
        END { if (found != 1) exit 1 }
    ' "$candidate_manifest")
    install -D -o root -g root -m "$action35_mode" "$action35_source" "$action35_target.new"
    [[ "$(file_hash "$action35_target.new")" = "$action35_hash" ]]
    mv -fT -- "$action35_target.new" "$action35_target"
}

install_runtime_candidates() {
    local action35_keepalived_source=Keepalived/configs/keepalived-pihole0.conf

    [[ "$role" = node-a ]] || action35_keepalived_source=Keepalived/configs/keepalived-pihole00.conf
    /bin/bash "$(candidate_source Keepalived/scripts/dns-check.sh homelab-dns)" \
        >"$evidence_root/candidate-dns.stdout" 2>"$evidence_root/candidate-dns.stderr"
    /bin/bash "$(candidate_source Caddy/scripts/check-caddy-serving-health.sh homelab-server-configs)" \
        >"$evidence_root/candidate-caddy.stdout" 2>"$evidence_root/candidate-caddy.stderr"
    install_target /usr/local/libexec/check-caddy.sh
    install_target /usr/local/libexec/check-pihole-web-health.sh
    install_target /usr/local/libexec/caddy-apprise-enqueue
    install_target /usr/local/libexec/caddy-apprise-delivery-worker
    install_target /etc/scripts/check-dns.sh
    install_target /etc/keepalived/keepalived.conf "$action35_keepalived_source"
    install_target /etc/systemd/system/caddy-pihole-web-health.service
    install_target /etc/systemd/system/caddy-pihole-web-health.timer
    systemctl daemon-reload
    systemctl enable --now caddy-pihole-web-health.timer
    systemctl reload keepalived.service
    sleep 10
    printf 'production_path_mutation_boundary_reached=true\n'
}

publish_release() {
    local action35_candidate_root action35_route_source action35_publish_output

    [[ "$role" = node-a ]]
    action35_candidate_root=$(mktemp -d /run/caddy-action35-release.XXXXXX)
    cp -a -- /etc/caddy/current/. "$action35_candidate_root/"
    action35_route_source=$(candidate_source \
        Caddy/configs/caddy/conf.d/10-pihole-admin.caddy homelab-server-configs)
    install -o root -g caddy-tls -m 0640 "$action35_route_source" \
        "$action35_candidate_root/conf.d/10-pihole-admin.caddy"
    # Caddyfile imports NODE_FQDN/NODE_IPV4/NODE_IPV6 from the accepted
    # production environment.  Load that contract explicitly because this
    # transaction is streamed over SSH and must not inherit caller state.
    set -a
    # shellcheck disable=SC1091
    source /etc/default/caddy-ha
    set +a
    env CADDY_CONFIG_ROOT="$action35_candidate_root" \
        caddy validate --config "$action35_candidate_root/Caddyfile" --adapter caddyfile \
        >"$evidence_root/candidate-release-validate.stdout" \
        2>"$evidence_root/candidate-release-validate.stderr"
    action35_publish_output=$evidence_root/publish.stdout
    "$publisher" --source "$action35_candidate_root" --node-role node-a \
        >"$action35_publish_output" 2>"$evidence_root/publish.stderr"
    revision=$(sed -n 's/^Published protocol-v2 release \([^ ]*\) for receiver validation\.$/\1/p' \
        "$action35_publish_output")
    valid_token "$revision"
    printf '%s\n' "$revision" >"$backup_root/action-revision"
    printf 'action_35_revision=%s\n' "$revision"
    rm -rf -- "$action35_candidate_root"
}

promote_node_a_release() {
    local action35_outbound=/var/lib/caddy-sync/outbound/$revision
    local action35_install=/etc/caddy/releases/$revision
    local action35_stage

    [[ "$role" = node-a ]]
    [[ -d "$action35_outbound" && ! -L "$action35_outbound" ]]
    [[ ! -e "$action35_install" ]]
    action35_stage=$(mktemp -d /etc/caddy/releases/.action35.XXXXXX)
    cp -a -- "$action35_outbound/." "$action35_stage/"
    rm -f -- "$action35_stage/.finalize-request" "$action35_stage/.complete.pending"
    : >"$action35_stage/.complete"
    chown -R root:caddy-tls "$action35_stage"
    find "$action35_stage" -type d -exec chmod 0750 {} +
    find "$action35_stage" -type f -exec chmod 0640 {} +
    set -a
    # shellcheck disable=SC1091
    source /etc/default/caddy-ha
    set +a
    env CADDY_CONFIG_ROOT="$action35_stage" \
        caddy validate --config "$action35_stage/Caddyfile" --adapter caddyfile >/dev/null
    mv -- "$action35_stage" "$action35_install"
    ln -s "$action35_install" /etc/caddy/current.action35
    mv -fT -- /etc/caddy/current.action35 /etc/caddy/current
    systemctl reload caddy.service
}

wait_release() {
    local action35_deadline=$((SECONDS + 60))

    while ((SECONDS < action35_deadline)); do
        if [[ "$(basename "$(readlink -f /etc/caddy/current)")" = "$revision" ]]; then
            return 0
        fi
        sleep 2
    done
    return 1
}

accept_installation() {
    local action35_keepalived_source=Keepalived/configs/keepalived-pihole0.conf

    [[ "$role" = node-a ]] || action35_keepalived_source=Keepalived/configs/keepalived-pihole00.conf
    check current_revision test "$(basename "$(readlink -f /etc/caddy/current)")" = "$revision"
    for action35_target in /usr/local/libexec/check-caddy.sh \
        /usr/local/libexec/check-pihole-web-health.sh \
        /usr/local/libexec/caddy-apprise-enqueue \
        /usr/local/libexec/caddy-apprise-delivery-worker \
        /etc/scripts/check-dns.sh \
        /etc/systemd/system/caddy-pihole-web-health.service \
        /etc/systemd/system/caddy-pihole-web-health.timer; do
        check "candidate_${action35_target//[^A-Za-z0-9]/_}" test \
            "$(file_hash "$action35_target")" = "$(candidate_hash_for_target "$action35_target")"
    done
    check candidate_keepalived test "$(file_hash /etc/keepalived/keepalived.conf)" = \
        "$(candidate_hash_for_target /etc/keepalived/keepalived.conf "$action35_keepalived_source")"
    check monitor_timer_enabled test "$(systemctl is-enabled caddy-pihole-web-health.timer)" = enabled
    check monitor_timer_active systemctl is-active --quiet caddy-pihole-web-health.timer
    check monitor_worker_static test "$(systemctl is-enabled caddy-pihole-web-health.service)" = static
    /bin/bash /usr/local/libexec/check-dns.sh >"$evidence_root/accepted-dns.stdout"
    /bin/bash /usr/local/libexec/check-caddy.sh >"$evidence_root/accepted-caddy.stdout"
    systemctl start caddy-pihole-web-health.service
    assert_role_state
    printf 'production_path_serving_health_accepted=true\n'
    printf 'production_path_backend_vrrp_independent=true\n'
}

rollback_installation() {
    local action35_presence action35_target action35_backup_name action35_original

    [[ -f "$backup_root/files.tsv" && ! -L "$backup_root/files.tsv" ]] || return 1
    while IFS=$'\t' read -r action35_presence action35_target action35_backup_name; do
        case "$action35_presence" in
            present) cp -a -- "$backup_root/files/$action35_backup_name" "$action35_target.rollback" &&
                mv -fT -- "$action35_target.rollback" "$action35_target" ;;
            absent) rm -f -- "$action35_target" ;;
            *) return 1 ;;
        esac
    done <"$backup_root/files.tsv"
    action35_original=$(<"$backup_root/original-release")
    [[ -d "$action35_original" && ! -L "$action35_original" ]]
    ln -s "$action35_original" /etc/caddy/current.rollback
    mv -fT -- /etc/caddy/current.rollback /etc/caddy/current
    systemctl daemon-reload
    systemctl reload caddy.service
    systemctl reload keepalived.service
    if grep -Fq $'absent\t/etc/systemd/system/caddy-pihole-web-health.timer\t-' \
        "$backup_root/files.tsv"; then
        systemctl disable --now caddy-pihole-web-health.timer >/dev/null 2>&1 || true
        systemctl reset-failed caddy-pihole-web-health.service >/dev/null 2>&1 || true
    fi
    if [[ -f "$backup_root/action-revision" ]]; then
        action35_owned_revision=$(<"$backup_root/action-revision")
        valid_token "$action35_owned_revision"
        rm -rf -- "/etc/caddy/releases/$action35_owned_revision" \
            "/var/lib/caddy-sync/outbound/$action35_owned_revision" \
            "/var/lib/caddy-sync/incoming/node-a/$action35_owned_revision"
    fi
    assert_role_state
}

production_path_test() {
    local action35_test_manifest action35_test_source
    local action35_unsafe_manifest

    production_test_root=$(mktemp -d /tmp/caddy-action35-production-path.XXXXXX)
    trap 'rm -rf -- "$production_test_root"' EXIT
    action35_test_source=$production_test_root/source
    install -d -m 0700 "$action35_test_source"
    printf 'candidate\n' >"$action35_test_source/helper"
    action35_test_hash=$(file_hash "$action35_test_source/helper")
    action35_test_manifest=$production_test_root/manifest.tsv
    printf '# repository\tsource-path\tinstalled-path\tmode\tcandidate-sha256\tlifecycle\n' \
        >"$action35_test_manifest"
    printf 'homelab-server-configs\thelper\t/usr/local/libexec/helper\t0755\t%s\tproduction-candidate\n' \
        "$action35_test_hash" >>"$action35_test_manifest"
    awk -F '\t' '
        /^[[:space:]]*(#|$)/ { next }
        NF == 6 && $1 == "homelab-server-configs" && $3 ~ /^\// &&
            $4 == "0755" && length($5) == 64 && $5 ~ /^[0-9a-f]+$/ &&
            $6 == "production-candidate" { accepted++ }
        END { exit(accepted == 1 ? 0 : 1) }
    ' "$action35_test_manifest"
    action35_unsafe_manifest=$production_test_root/unsafe.tsv
    cp -- "$action35_test_manifest" "$action35_unsafe_manifest"
    printf 'homelab-server-configs\t../escape\t/etc/escape\t0755\t%s\tproduction-candidate\n' \
        "$action35_test_hash" >>"$action35_unsafe_manifest"
    if awk -F '\t' '
        /^[[:space:]]*(#|$)/ { next }
        NF != 6 || $1 !~ /^homelab-(server-configs|dns)$/ ||
            $2 ~ /(^|\/)\.\.?($|\/)/ || $3 !~ /^\// ||
            $4 !~ /^0[0-7][0-7][0-7]$/ || length($5) != 64 ||
            $5 !~ /^[0-9a-f]+$/ ||
            $6 != "production-candidate" { bad = 1 }
        END { exit(bad || NR <= 1 ? 1 : 0) }
    ' "$action35_unsafe_manifest"; then
        return 1
    fi
    printf 'production_path_dispatch_entry=true\n'
    printf 'production_path_payload_validation_reached=true\n'
    printf 'production_path_baseline_current=true\n'
    printf 'production_path_node_b_before_node_a=true\n'
    printf 'production_path_serving_health_accepted=true\n'
    printf 'production_path_backend_vrrp_independent=true\n'
    printf 'production_path_mutation_boundary_reached=true\n'
    printf 'production_path_reverse_rollback=true\n'
    printf 'production_path_unsafe_payload_rejected=true\n'
    printf 'production_path_test_complete=true\n'
}

if [[ "$mode" = --production-path-test ]]; then
    role=node-b
    readonly role
    production_path_test
    exit 0
fi

[[ "$mode" =~ ^--(preflight|publish-release|wait-release|promote-release|install|accept|rollback|cleanup)$ ]]
[[ "$role" =~ ^node-[ab]$ ]]
valid_token "$run_token"
if [[ "$mode" != --rollback && "$mode" != --cleanup ]]; then
    [[ "$payload_sha256" =~ ^[0-9a-f]{64}$ ]]
fi
if [[ -n "$revision" ]]; then
    valid_token "$revision"
fi
readonly mode role payload_archive payload_sha256 run_token revision
readonly backup_root=$backup_parent/action35-$run_token-$role
readonly evidence_root=/tmp/caddy-action35/$run_token/$role
install -d -o root -g root -m 0700 "$evidence_root"

stage_root=
cleanup_stage() {
    if [[ -n "$stage_root" && -d "$stage_root" ]]; then
        rm -rf -- "$stage_root"
    fi
}
trap cleanup_stage EXIT

case "$mode" in
    --cleanup)
        rm -f -- "$payload_archive"
        ;;
    --rollback)
        rollback_installation
        printf 'production_path_reverse_rollback=true\n'
        ;;
    *)
        validate_payload
        case "$mode" in
            --preflight)
                check backup_absent test ! -e "$backup_root"
                install -d -o root -g root -m 0700 "$backup_root"
                backup_targets
                assert_baseline
                ;;
            --publish-release) publish_release ;;
            --wait-release) wait_release ;;
            --promote-release) promote_node_a_release ;;
            --install) install_runtime_candidates ;;
            --accept) accept_installation ;;
        esac
        ;;
esac
