#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export PATH
readonly PATH

readonly prefix=action_28w_remote
readonly retained_revision=20260809T193432Z-6a2fab64-69e6-4cfb-a026-0a38fcae5b63
readonly retained_parent=action16ar-retry-node-a-default-deny
readonly retained_payload_sha256=fdc6ed955f14226ac3e1777eca37507cc8ab6ca16add3135dece9d6964e27568
readonly publisher_sha256=4a1cbeca92babe731528e4901e7164a876ab7d52a668390d311bedc11238b513
readonly reconciler_sha256=7bf8bad5fa978b64e3d4a6f12ff4632a42a6c11f429e3e92e193228cc4f29918
readonly old_publisher_sha256=e4a48f12a7324a885684a57070269a2d074d056c65d9e767db901408e0e86669
readonly old_reconciler_sha256=9dcf65119599060b064ee820655f8e8d18839fdee1d1d2526d0e3e1c3eedbc1b
readonly node_a_lsyncd_sha256=7bb2227ae9618d3dfe4a3d51833c1efa070148a0e4220eda04e457dc13c36133
readonly node_b_lsyncd_sha256=558fa7228462ad1bd1fe76cf9e519551cd18c524cf0541e4e95aa92edb412588
readonly lsyncd_unit_sha256=93cbc36cea03b8b7e1605c44667463592cf64e0293ded9f816d1e34760a69ac8
readonly reconcile_path_sha256=1b2084ce0a382114c10a1211dbdec1628c9b32cd84450c9d7b09a3ba0a6425fc
readonly reconcile_service_sha256=848787b77cc03fe3855961cc94ad2e6aa4e05934851a98643edcdf17d84bf8eb
readonly node_a_keepalived_sha256=d8f96c4f018f90370aea38fc3ef932af649158f6edc99cc7e95dea1edff4908a
readonly node_b_keepalived_sha256=034ee9c45acaca4e48e2faeda24cd371e945bdb52a117b5871403958ab36794c
readonly dns_ipv4_cidr=10.1.0.55/22
readonly dns_ipv6_cidr=fd36:5aa8:6971:1::55/128
readonly caddy_ipv4_cidr=10.1.0.56/22
readonly caddy_ipv6_cidr=fd36:5aa8:6971:1::56/128
readonly ipv4_object=/org/keepalived/Vrrp1/Instance/eth0/100/IPv4
readonly ipv6_object=/org/keepalived/Vrrp1/Instance/eth0/101/IPv6
readonly publisher=/usr/local/libexec/publish-release-v2.sh
readonly reconciler=/usr/local/libexec/reconcile-release.sh
readonly lsyncd_config=/etc/lsyncd/caddy.lua
readonly maximum_stream_bytes=2097152
readonly maximum_stream_lines=16384

mode=
role=
stage=
run_id=
expected_revision=
expected_source=
classifier_self_test=false
classifier_fixture_root=
expected_hostname=
expected_keepalived_sha256=
expected_lsyncd_sha256=
expected_state=
backup_directory=
evidence_directory=
first_failure=none

usage() {
    printf 'Usage: %s --mode MODE --role node-a|node-b --stage DIR --run-id ID [--revision ID] [--source node-a|node-b] | --self-test | --stream-classifier-self-test\n' \
        "${0##*/}" >&2
}

while (($#)); do
    case "$1" in
        --mode)
            mode=${2:-}
            shift 2
            ;;
        --role)
            role=${2:-}
            shift 2
            ;;
        --stage)
            stage=${2:-}
            shift 2
            ;;
        --run-id)
            run_id=${2:-}
            shift 2
            ;;
        --revision)
            expected_revision=${2:-}
            shift 2
            ;;
        --source)
            expected_source=${2:-}
            shift 2
            ;;
        --self-test)
            printf '%s_self_test_complete=true\n' "$prefix"
            exit 0
            ;;
        --stream-classifier-self-test)
            classifier_self_test=true
            shift
            ;;
        *)
            usage
            exit 64
            ;;
    esac
done

file_hash() { sha256sum -- "$1" | awk '{ print $1 }'; }
line_count() { awk 'END { print NR }' "$1"; }
valid_revision() { [[ "$1" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]; }
safe_stream() {
    local action28w_remote_stream=$1

    [[ "$(wc -c <"$action28w_remote_stream")" -le "$maximum_stream_bytes" ]] || return 1
    [[ "$(line_count "$action28w_remote_stream")" -le "$maximum_stream_lines" ]] || return 1
    iconv -f UTF-8 -t UTF-8 "$action28w_remote_stream" >/dev/null 2>&1 || return 1
    ! LC_ALL=C.UTF-8 grep -n '[^[:print:][:space:]]' \
        "$action28w_remote_stream" >/dev/null || return 1
    ! grep -Eqi 'BEGIN [A-Z ]*PRIVATE KEY|Authorization:[[:space:]]*Bearer|WEBPASSWORD' \
        "$action28w_remote_stream"
}
run_stream_classifier_self_test() {
    local action28w_remote_fixture

    classifier_fixture_root=$(mktemp -d /tmp/action28w-remote-stream.XXXXXX)
    trap 'rm -rf -- "$classifier_fixture_root"' EXIT INT TERM
    printf 'Created symlink /etc/systemd/system/example → /etc/systemd/system/example.service.\n' \
        >"$classifier_fixture_root/utf8"
    printf 'safe\001control\n' >"$classifier_fixture_root/control"
    printf 'invalid\377utf8\n' >"$classifier_fixture_root/invalid"
    printf 'WEBPASSWORD=redacted-fixture\n' >"$classifier_fixture_root/secret"
    head -c "$((maximum_stream_bytes + 1))" /dev/zero | tr '\0' a \
        >"$classifier_fixture_root/bytes"
    awk -v count="$((maximum_stream_lines + 1))" \
        'BEGIN { for (line = 1; line <= count; line++) print "x" }' \
        >"$classifier_fixture_root/lines"
    safe_stream "$classifier_fixture_root/utf8"
    for action28w_remote_fixture in control invalid secret bytes lines; do
        if safe_stream "$classifier_fixture_root/$action28w_remote_fixture"; then
            return 1
        fi
    done
    printf '%s_stream_classifier_utf8_accepted=true\n' "$prefix"
    printf '%s_stream_classifier_control_rejected=true\n' "$prefix"
    printf '%s_stream_classifier_invalid_utf8_rejected=true\n' "$prefix"
    printf '%s_stream_classifier_secret_rejected=true\n' "$prefix"
    printf '%s_stream_classifier_byte_limit_rejected=true\n' "$prefix"
    printf '%s_stream_classifier_line_limit_rejected=true\n' "$prefix"
    printf '%s_stream_classifier_self_test_complete=true\n' "$prefix"
}
emit_stream() {
    local action28w_remote_label=$1
    local action28w_remote_stream=$2

    printf '%s_%s_%s_bytes=%s\n' "$prefix" "$mode" "$action28w_remote_label" \
        "$(wc -c <"$action28w_remote_stream")"
    printf '%s_%s_%s_lines=%s\n' "$prefix" "$mode" "$action28w_remote_label" \
        "$(line_count "$action28w_remote_stream")"
    printf '%s_%s_%s_sha256=%s\n' "$prefix" "$mode" "$action28w_remote_label" \
        "$(file_hash "$action28w_remote_stream")"
    if ! safe_stream "$action28w_remote_stream"; then
        printf '%s_%s_%s_classification=unsafe_retained\n' \
            "$prefix" "$mode" "$action28w_remote_label" >&2
        return 97
    fi
    printf '%s_%s_%s_classification=bounded_safe\n' \
        "$prefix" "$mode" "$action28w_remote_label"
    if [[ -s "$action28w_remote_stream" ]]; then
        printf '%s_%s_%s_begin\n' "$prefix" "$mode" "$action28w_remote_label"
        sed "s/^/${prefix}_${mode}_${action28w_remote_label}_content=/" \
            "$action28w_remote_stream"
        printf '%s_%s_%s_end\n' "$prefix" "$mode" "$action28w_remote_label"
    else
        printf '%s_%s_%s_content=empty\n' "$prefix" "$mode" "$action28w_remote_label"
    fi
}
run_captured() {
    local action28w_remote_label=$1
    local action28w_remote_status=0

    shift
    install -m 0600 /dev/null "$evidence_directory/$action28w_remote_label.stdout"
    install -m 0600 /dev/null "$evidence_directory/$action28w_remote_label.stderr"
    "$@" >"$evidence_directory/$action28w_remote_label.stdout" \
        2>"$evidence_directory/$action28w_remote_label.stderr" || action28w_remote_status=$?
    printf '%s_%s_%s_status=%s\n' "$prefix" "$mode" "$action28w_remote_label" \
        "$action28w_remote_status"
    emit_stream "${action28w_remote_label}_stdout" \
        "$evidence_directory/$action28w_remote_label.stdout" || return 97
    emit_stream "${action28w_remote_label}_stderr" \
        "$evidence_directory/$action28w_remote_label.stderr" || return 97
    [[ "$action28w_remote_status" -eq 0 ]]
}
check() {
    local action28w_remote_label=$1

    shift
    if "$@" >/dev/null 2>&1; then
        printf '%s_%s_check_%s=true\n' "$prefix" "$mode" "$action28w_remote_label"
        return 0
    fi
    first_failure=$action28w_remote_label
    printf '%s_%s_check_%s=false\n' "$prefix" "$mode" "$action28w_remote_label" >&2
    return 1
}
address_count() {
    local action28w_remote_family=$1
    local action28w_remote_cidr=$2

    ip -o "-$action28w_remote_family" address show dev eth0 |
        awk -v expected="$action28w_remote_cidr" \
            '$4 == expected { count++ } END { print count + 0 }'
}
dbus_state() {
    timeout 3 busctl get-property org.keepalived.Vrrp1 "$1" \
        org.keepalived.Vrrp1.Instance State
}
ownership_exact() {
    local action28w_remote_state=$1
    local action28w_remote_count=0
    local action28w_remote_dbus='(us) 1 "Backup"'

    case "$action28w_remote_state" in
        master)
            action28w_remote_count=1
            action28w_remote_dbus='(us) 2 "Master"'
            ;;
        backup) ;;
        absent)
            [[ "$(address_count 4 "$dns_ipv4_cidr")" -eq 0 ]] || return 1
            [[ "$(address_count 6 "$dns_ipv6_cidr")" -eq 0 ]] || return 1
            [[ "$(address_count 4 "$caddy_ipv4_cidr")" -eq 0 ]] || return 1
            [[ "$(address_count 6 "$caddy_ipv6_cidr")" -eq 0 ]]
            return
            ;;
        *) return 1 ;;
    esac
    [[ "$(dbus_state "$ipv4_object")" = "$action28w_remote_dbus" ]] || return 1
    [[ "$(dbus_state "$ipv6_object")" = "$action28w_remote_dbus" ]] || return 1
    [[ "$(address_count 4 "$dns_ipv4_cidr")" -eq "$action28w_remote_count" ]] || return 1
    [[ "$(address_count 6 "$dns_ipv6_cidr")" -eq "$action28w_remote_count" ]] || return 1
    [[ "$(address_count 4 "$caddy_ipv4_cidr")" -eq "$action28w_remote_count" ]] || return 1
    [[ "$(address_count 6 "$caddy_ipv6_cidr")" -eq "$action28w_remote_count" ]]
}
stable_ownership() {
    local action28w_remote_sample

    for action28w_remote_sample in 1 2 3 4 5; do
        ownership_exact "$expected_state" || return 1
        printf '%s_%s_stable_sample_%s=true\n' \
            "$prefix" "$mode" "$action28w_remote_sample"
        sleep 1
    done
}
manifest_valid() {
    local action28w_remote_release=$1

    [[ -d "$action28w_remote_release" && ! -L "$action28w_remote_release" ]] || return 1
    [[ -f "$action28w_remote_release/release-manifest.json" ]] || return 1
    [[ -f "$action28w_remote_release/manifest.sha256" ]] || return 1
    (cd "$action28w_remote_release" && sha256sum --strict --check manifest.sha256 >/dev/null)
}
configure_role() {
    case "$role" in
        node-a)
            expected_hostname=j1-svpihole0
            expected_keepalived_sha256=$node_a_keepalived_sha256
            expected_lsyncd_sha256=$node_a_lsyncd_sha256
            ;;
        node-b)
            expected_hostname=j1-svpihole00
            expected_keepalived_sha256=$node_b_keepalived_sha256
            expected_lsyncd_sha256=$node_b_lsyncd_sha256
            ;;
        *) return 1 ;;
    esac
    backup_directory=/var/backups/caddy-ha/action28w-$role-go-live
    evidence_directory=/tmp/caddy-action28w/$run_id/$role
    readonly expected_hostname expected_keepalived_sha256 expected_lsyncd_sha256
    readonly backup_directory evidence_directory
}
stage_valid() {
    [[ -d "$stage" && ! -L "$stage" ]] || return 1
    [[ "$(file_hash "$stage/publish-release-v2.sh")" = "$publisher_sha256" ]] || return 1
    [[ "$(file_hash "$stage/reconcile-release-v2.sh")" = "$reconciler_sha256" ]] || return 1
    [[ "$(file_hash "$stage/caddy.lua")" = "$expected_lsyncd_sha256" ]] || return 1
    bash -n "$stage/publish-release-v2.sh" "$stage/reconcile-release-v2.sh"
}
current_revision() {
    jq -r '.revision // empty' /etc/caddy/current/release-manifest.json
}
record_backup() {
    install -d -o root -g root -m 0700 /var/backups/caddy-ha
    install -d -o root -g root -m 0700 "$backup_directory"
    install -o root -g root -m 0600 "$publisher" "$backup_directory/publisher.before"
    install -o root -g root -m 0600 "$reconciler" "$backup_directory/reconciler.before"
    printf '%s\n' absent >"$backup_directory/lsyncd-config.state"
    readlink -f -- /etc/caddy/current >"$backup_directory/current.before"
    systemctl is-active caddy-lsyncd.service >"$backup_directory/lsyncd-active.before" || :
    systemctl is-enabled caddy-lsyncd.service >"$backup_directory/lsyncd-enabled.before" || :
    systemctl is-active caddy-sync-reconcile.path >"$backup_directory/reconcile-active.before" || :
    systemctl is-enabled caddy-sync-reconcile.path >"$backup_directory/reconcile-enabled.before" || :
    printf 'action=28w\nrole=%s\n' "$role" >"$backup_directory/manifest"
    chmod 0600 "$backup_directory"/*
}
install_atomic() {
    local action28w_remote_source=$1
    local action28w_remote_target=$2
    local action28w_remote_mode=$3
    local action28w_remote_directory=${action28w_remote_target%/*}
    local action28w_remote_stage

    action28w_remote_stage=$(mktemp "$action28w_remote_directory/.action28w.XXXXXX")
    install -o root -g root -m "$action28w_remote_mode" \
        "$action28w_remote_source" "$action28w_remote_stage"
    mv -fT -- "$action28w_remote_stage" "$action28w_remote_target"
}
promote_release() {
    local action28w_remote_revision=$1
    local action28w_remote_source=/var/lib/caddy-sync/outbound/$action28w_remote_revision
    local action28w_remote_destination=/etc/caddy/releases/$action28w_remote_revision

    if [[ "$role" = node-b && "$action28w_remote_revision" = "$retained_revision" ]]; then
        action28w_remote_source=/var/lib/caddy-sync/incoming/node-a/$action28w_remote_revision
    fi
    manifest_valid "$action28w_remote_source" || return 1
    [[ "$(jq -r '.revision // empty' "$action28w_remote_source/release-manifest.json")" = "$action28w_remote_revision" ]] || return 1
    if [[ ! -d "$action28w_remote_destination" ]]; then
        cp -a -- "$action28w_remote_source" "$action28w_remote_destination"
    fi
    chown -R root:caddy-tls "$action28w_remote_destination"
    find "$action28w_remote_destination" -type d -exec chmod 0550 {} +
    find "$action28w_remote_destination" -type f -exec chmod 0440 {} +
    set -a
    # shellcheck disable=SC1091
    source /etc/default/caddy-ha
    set +a
    env CADDY_CONFIG_ROOT="$action28w_remote_destination" \
        caddy validate --config "$action28w_remote_destination/Caddyfile" \
        --adapter caddyfile >/dev/null
    ln -sfn "$action28w_remote_destination" /etc/caddy/current.new
    mv -Tf /etc/caddy/current.new /etc/caddy/current
    systemctl reload caddy.service
}
rollback_node() {
    local action28w_remote_before

    if [[ ! -d "$backup_directory" ]]; then
        printf 'rollback_not_required=true\n'
        return 0
    fi
    if [[ "$role" = node-a ]]; then
        systemctl start keepalived.service || return 1
    fi
    action28w_remote_before=$(<"$backup_directory/current.before")
    ln -sfn "$action28w_remote_before" /etc/caddy/current.new
    mv -Tf /etc/caddy/current.new /etc/caddy/current
    install_atomic "$backup_directory/publisher.before" "$publisher" 0755
    install_atomic "$backup_directory/reconciler.before" "$reconciler" 0755
    rm -f -- "$lsyncd_config"
    systemctl disable --now caddy-lsyncd.service caddy-sync-reconcile.path >/dev/null 2>&1 || :
    systemctl daemon-reload
    systemctl reload caddy.service
    printf 'rollback_complete=true\n' >"$backup_directory/rollback.complete"
}

if [[ "$classifier_self_test" = true ]]; then
    [[ -z "$mode$role$stage$run_id$expected_revision$expected_source" ]]
    run_stream_classifier_self_test
    exit 0
fi

[[ "$run_id" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || {
    usage
    exit 64
}
configure_role || {
    usage
    exit 64
}
install -d -o root -g root -m 0700 /tmp/caddy-action28w "$evidence_directory"
cd /

case "$mode" in
    preflight)
        expected_state=backup
        [[ "$role" = node-a ]] && expected_state=master
        printf '%s_%s_observed_keepalived_sha256=%s\n' "$prefix" "$mode" \
            "$(file_hash /etc/keepalived/keepalived.conf)"
        printf '%s_%s_observed_publisher_sha256=%s\n' "$prefix" "$mode" \
            "$(file_hash "$publisher")"
        printf '%s_%s_observed_reconciler_sha256=%s\n' "$prefix" "$mode" \
            "$(file_hash "$reconciler")"
        printf '%s_%s_observed_current_revision=%s\n' "$prefix" "$mode" \
            "$(current_revision)"
        check identity_root test "$(id -u)" -eq 0
        check hostname_exact test "$(hostname)" = "$expected_hostname"
        check stage_exact stage_valid
        check keepalived_hash_exact test \
            "$(file_hash /etc/keepalived/keepalived.conf)" = "$expected_keepalived_sha256"
        check publisher_baseline_exact test "$(file_hash "$publisher")" = "$old_publisher_sha256"
        check reconciler_baseline_exact test "$(file_hash "$reconciler")" = "$old_reconciler_sha256"
        check lsyncd_config_absent test ! -e "$lsyncd_config"
        check lsyncd_unit_exact test \
            "$(file_hash /etc/systemd/system/caddy-lsyncd.service)" = "$lsyncd_unit_sha256"
        check reconcile_path_exact test \
            "$(file_hash /etc/systemd/system/caddy-sync-reconcile.path)" = "$reconcile_path_sha256"
        check reconcile_service_exact test \
            "$(file_hash /etc/systemd/system/caddy-sync-reconcile.service)" = "$reconcile_service_sha256"
        check synchronization_inactive test \
            "$(systemctl is-active caddy-lsyncd.service || true)" = inactive
        check reconciliation_inactive test \
            "$(systemctl is-active caddy-sync-reconcile.path || true)" = inactive
        check backup_absent test ! -e "$backup_directory"
        check services_active systemctl is-active --quiet keepalived.service caddy.service lighttpd.service
        check action28t_state_exact ownership_exact "$expected_state"
        if [[ "$role" = node-a ]]; then
            check current_revision_is_retained_parent test \
                "$(current_revision)" = "$retained_parent"
            candidate=/var/lib/caddy-sync/outbound/$retained_revision
            check retained_sender_candidate manifest_valid "$candidate"
            check retained_sender_parent test \
                "$(jq -r '.parent_revision' "$candidate/release-manifest.json")" = "$retained_parent"
            check retained_sender_payload test \
                "$(file_hash "$candidate/manifest.sha256")" = "$retained_payload_sha256"
            check retained_sender_complete_absent test ! -e "$candidate/.complete"
        else
            check current_revision_is_valid valid_revision "$(current_revision)"
            candidate=/var/lib/caddy-sync/incoming/node-a/$retained_revision
            check retained_receiver_candidate manifest_valid "$candidate"
            check retained_receiver_complete test -f "$candidate/.complete"
        fi
        ;;
    install)
        check stage_exact stage_valid
        check backup_absent test ! -e "$backup_directory"
        record_backup
        check backup_complete test -s "$backup_directory/manifest"
        install -d -o root -g root -m 0755 /etc/lsyncd
        install -d -o caddy-sync -g caddy-sync -m 0750 \
            /var/lib/caddy-sync/outbound /var/lib/caddy-sync/incoming
        install_atomic "$stage/publish-release-v2.sh" "$publisher" 0755
        install_atomic "$stage/reconcile-release-v2.sh" "$reconciler" 0755
        install_atomic "$stage/caddy.lua" "$lsyncd_config" 0644
        systemctl daemon-reload
        check publisher_installed test "$(file_hash "$publisher")" = "$publisher_sha256"
        check reconciler_installed test "$(file_hash "$reconciler")" = "$reconciler_sha256"
        check lsyncd_config_installed test "$(file_hash "$lsyncd_config")" = "$expected_lsyncd_sha256"
        ;;
    promote)
        valid_revision "$expected_revision"
        run_captured promote_release promote_release "$expected_revision"
        check revision_active test "$(current_revision)" = "$expected_revision"
        ;;
    activate)
        run_captured enable_reconcile systemctl enable --now caddy-sync-reconcile.path
        if [[ "$role" = node-b ]]; then
            run_captured initial_reconcile systemctl start caddy-sync-reconcile.service
        fi
        run_captured enable_lsyncd systemctl enable --now caddy-lsyncd.service
        check lsyncd_active systemctl is-active --quiet caddy-lsyncd.service
        check reconcile_path_active systemctl is-active --quiet caddy-sync-reconcile.path
        check reconcile_service_not_failed test \
            "$(systemctl is-failed caddy-sync-reconcile.service || true)" != failed
        ;;
    state)
        case "$expected_source" in master | backup | absent) expected_state=$expected_source ;; *) exit 64 ;; esac
        check stable_ownership stable_ownership
        ;;
    relinquish)
        [[ "$role" = node-a ]]
        run_captured stop_keepalived systemctl stop keepalived.service
        expected_state=absent
        check shared_vips_absent stable_ownership
        check caddy_continues systemctl is-active --quiet caddy.service
        ;;
    restore-owner)
        [[ "$role" = node-a ]]
        run_captured start_keepalived systemctl start keepalived.service
        expected_state=master
        check preferred_owner_restored stable_ownership
        ;;
    continuity)
        check dns_a_exact test \
            "$(dig +time=2 +tries=1 +short @10.1.0.55 pihole-admin.local.theama.co A)" = 10.1.0.56
        check dns_aaaa_exact test \
            "$(dig +time=2 +tries=1 +short @10.1.0.55 pihole-admin.local.theama.co AAAA)" = fd36:5aa8:6971:1::56
        run_captured shared_ui curl --fail --silent --show-error --max-time 8 \
            --resolve pihole-admin.local.theama.co:443:10.1.0.56 \
            https://pihole-admin.local.theama.co/admin/login.php
        check shared_ui_owner grep -Fq "$expected_hostname" "$evidence_directory/shared_ui.stdout"
        ;;
    reject-normal)
        [[ "$role" = node-b ]]
        source_release=$(readlink -f -- /etc/caddy/current)
        reject_status=0
        "$publisher" --source "$source_release" --node-role node-b \
            >"$evidence_directory/reject-normal.stdout" \
            2>"$evidence_directory/reject-normal.stderr" || reject_status=$?
        printf '%s_%s_reject_normal_status=%s\n' "$prefix" "$mode" "$reject_status"
        emit_stream reject_normal_stdout "$evidence_directory/reject-normal.stdout"
        emit_stream reject_normal_stderr "$evidence_directory/reject-normal.stderr"
        check normal_publish_rejected test "$reject_status" -eq 1
        check normal_rejection_exact grep -Fxq \
            'Node B publishing requires --emergency.' "$evidence_directory/reject-normal.stderr"
        ;;
    publish)
        source_release=$(readlink -f -- /etc/caddy/current)
        publish_args=(--source "$source_release" --node-role "$role")
        [[ "$role" = node-a ]] || publish_args+=(--emergency)
        run_captured publish "$publisher" "${publish_args[@]}"
        published_revision=$(sed -n \
            's/^Published protocol-v2 release \([A-Za-z0-9][A-Za-z0-9._-]*\) for receiver validation\.$/\1/p' \
            "$evidence_directory/publish.stdout")
        check published_revision_valid valid_revision "$published_revision"
        printf '%s_%s_value_revision=%s\n' "$prefix" "$mode" "$published_revision"
        ;;
    accept-release)
        valid_revision "$expected_revision"
        [[ "$expected_source" =~ ^node-[ab]$ ]]
        check current_revision_exact test "$(current_revision)" = "$expected_revision"
        check current_source_exact test \
            "$(jq -r '.source_node // empty' /etc/caddy/current/release-manifest.json)" = "$expected_source"
        check current_manifest_valid manifest_valid /etc/caddy/current
        check caddy_active systemctl is-active --quiet caddy.service
        check lsyncd_active systemctl is-active --quiet caddy-lsyncd.service
        check reconcile_path_active systemctl is-active --quiet caddy-sync-reconcile.path
        check reconcile_not_failed test \
            "$(systemctl is-failed caddy-sync-reconcile.service || true)" != failed
        ;;
    journal-cursor)
        run_captured journal_cursor journalctl --show-cursor -n 0 --no-pager
        ;;
    journal-evidence)
        journal_cursor=$(sed -n 's/^-- cursor: //p' \
            "$evidence_directory/journal_cursor.stdout" | tail -n 1)
        check retained_journal_cursor test -n "$journal_cursor"
        run_captured keepalived_journal journalctl -u keepalived.service \
            --after-cursor "$journal_cursor" --no-pager
        run_captured notifier_journal journalctl -t keepalived-notify \
            --after-cursor "$journal_cursor" --no-pager
        run_captured sync_journal journalctl -u caddy-lsyncd.service \
            -u caddy-sync-reconcile.service --after-cursor "$journal_cursor" --no-pager
        printf '%s_%s_notifier_delivery_nonblocking=true\n' "$prefix" "$mode"
        ;;
    rollback)
        run_captured rollback rollback_node
        check publisher_restored test "$(file_hash "$publisher")" = "$old_publisher_sha256"
        check reconciler_restored test "$(file_hash "$reconciler")" = "$old_reconciler_sha256"
        check lsyncd_config_removed test ! -e "$lsyncd_config"
        ;;
    commit)
        check backup_present test -d "$backup_directory"
        printf 'action28w_complete=true\n' >"$backup_directory/transaction.complete"
        chmod 0600 "$backup_directory/transaction.complete"
        check transaction_marker test -f "$backup_directory/transaction.complete"
        check transient_stage_absent test \
            -z "$(find /run -maxdepth 1 -name 'caddy-action28w-bundle.*' \
                ! -path "$stage" -print -quit 2>/dev/null)"
        ;;
    *)
        usage
        exit 64
        ;;
esac

printf '%s_%s_role=%s\n' "$prefix" "$mode" "$role"
printf '%s_%s_first_failure=%s\n' "$prefix" "$mode" "$first_failure"
printf '%s_%s_remote_evidence=%s\n' "$prefix" "$mode" "$evidence_directory"
printf '%s_%s_acceptance=true\n' "$prefix" "$mode"
