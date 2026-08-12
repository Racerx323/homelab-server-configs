#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export PATH
readonly PATH

readonly prefix=action_28ad_remote
readonly retained_revision=20260809T193432Z-6a2fab64-69e6-4cfb-a026-0a38fcae5b63
readonly retained_parent=action16ar-retry-node-a-default-deny
readonly retained_payload_sha256=fdc6ed955f14226ac3e1777eca37507cc8ab6ca16add3135dece9d6964e27568
readonly historical_revision=action17p-node-a-to-node-b-bootstrap
readonly historical_release_manifest_sha256=81afa957c65b4f8a3f539b0018ebd700b0c926812f1b1e18b2ea7ade0be0e1b3
readonly historical_payload_manifest_sha256=f4dc87dab7075c4b20ed2acafb4969b757534bad49f5b47c85de4474d17175c8
readonly historical_incoming=/var/lib/caddy-sync/incoming/node-a/$historical_revision
readonly historical_quarantine=/var/lib/caddy-sync/quarantine/node-a-$historical_revision
readonly publisher_sha256=4a1cbeca92babe731528e4901e7164a876ab7d52a668390d311bedc11238b513
readonly reconciler_sha256=31d6a08dd4a65543003ef13d0d8a18c8aa3c025521c35bfdfb14c6b50a39be3d
readonly finalizer_sha256=fcff15db5b4ea971846a798028f40d2dce86db9cc331825d046dd5321d5f33bd
readonly old_publisher_sha256=e4a48f12a7324a885684a57070269a2d074d056c65d9e767db901408e0e86669
readonly old_reconciler_sha256=9dcf65119599060b064ee820655f8e8d18839fdee1d1d2526d0e3e1c3eedbc1b
readonly old_finalizer_sha256=15d858774a17369f31261f7f94bea72d575f269fdb3e8e991534f66dd4f4902d
readonly node_a_lsyncd_sha256=d09a5d74434ed5ec4c48f65f718907c583461f9124e6309b20417c7f748f2365
readonly node_b_lsyncd_sha256=cae04b74475a567e75f4ec4e9e4db305990f45df2c0dede1439f3e945a22c136
readonly lsyncd_unit_sha256=93cbc36cea03b8b7e1605c44667463592cf64e0293ded9f816d1e34760a69ac8
readonly old_reconcile_path_sha256=1b2084ce0a382114c10a1211dbdec1628c9b32cd84450c9d7b09a3ba0a6425fc
readonly reconcile_path_sha256=c8c11582580326300035c1b6e8dc97cb6b90052683b57836cc3afdcdd436f295
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
readonly finalizer=/usr/local/libexec/finalize-incoming-release-v2.sh
readonly reconcile_path=/etc/systemd/system/caddy-sync-reconcile.path
readonly lsyncd_config=/etc/lsyncd/caddy.lua
readonly releases_root=/etc/caddy/releases
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
quarantine_self_test=false
quarantine_fixture_root=
manifest_boundary_self_test=false
manifest_fixture_root=
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
        --historical-quarantine-self-test)
            quarantine_self_test=true
            shift
            ;;
        --manifest-boundary-self-test)
            manifest_boundary_self_test=true
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
    local action28ad_remote_stream=$1

    [[ "$(wc -c <"$action28ad_remote_stream")" -le "$maximum_stream_bytes" ]] || return 1
    [[ "$(line_count "$action28ad_remote_stream")" -le "$maximum_stream_lines" ]] || return 1
    iconv -f UTF-8 -t UTF-8 "$action28ad_remote_stream" >/dev/null 2>&1 || return 1
    ! LC_ALL=C.UTF-8 grep -n '[^[:print:][:space:]]' \
        "$action28ad_remote_stream" >/dev/null || return 1
    ! grep -Eqi 'BEGIN [A-Z ]*PRIVATE KEY|Authorization:[[:space:]]*Bearer|WEBPASSWORD' \
        "$action28ad_remote_stream"
}
run_stream_classifier_self_test() {
    local action28ad_remote_fixture

    classifier_fixture_root=$(mktemp -d /tmp/action28ad-remote-stream.XXXXXX)
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
    for action28ad_remote_fixture in control invalid secret bytes lines; do
        if safe_stream "$classifier_fixture_root/$action28ad_remote_fixture"; then
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
    local action28ad_remote_label=$1
    local action28ad_remote_stream=$2

    printf '%s_%s_%s_bytes=%s\n' "$prefix" "$mode" "$action28ad_remote_label" \
        "$(wc -c <"$action28ad_remote_stream")"
    printf '%s_%s_%s_lines=%s\n' "$prefix" "$mode" "$action28ad_remote_label" \
        "$(line_count "$action28ad_remote_stream")"
    printf '%s_%s_%s_sha256=%s\n' "$prefix" "$mode" "$action28ad_remote_label" \
        "$(file_hash "$action28ad_remote_stream")"
    if ! safe_stream "$action28ad_remote_stream"; then
        printf '%s_%s_%s_classification=unsafe_retained\n' \
            "$prefix" "$mode" "$action28ad_remote_label" >&2
        return 97
    fi
    printf '%s_%s_%s_classification=bounded_safe\n' \
        "$prefix" "$mode" "$action28ad_remote_label"
    if [[ -s "$action28ad_remote_stream" ]]; then
        printf '%s_%s_%s_begin\n' "$prefix" "$mode" "$action28ad_remote_label"
        sed "s/^/${prefix}_${mode}_${action28ad_remote_label}_content=/" \
            "$action28ad_remote_stream"
        printf '%s_%s_%s_end\n' "$prefix" "$mode" "$action28ad_remote_label"
    else
        printf '%s_%s_%s_content=empty\n' "$prefix" "$mode" "$action28ad_remote_label"
    fi
}
run_captured() {
    local action28ad_remote_label=$1
    local action28ad_remote_status=0

    shift
    install -m 0600 /dev/null "$evidence_directory/$action28ad_remote_label.stdout"
    install -m 0600 /dev/null "$evidence_directory/$action28ad_remote_label.stderr"
    "$@" >"$evidence_directory/$action28ad_remote_label.stdout" \
        2>"$evidence_directory/$action28ad_remote_label.stderr" || action28ad_remote_status=$?
    printf '%s_%s_%s_status=%s\n' "$prefix" "$mode" "$action28ad_remote_label" \
        "$action28ad_remote_status"
    emit_stream "${action28ad_remote_label}_stdout" \
        "$evidence_directory/$action28ad_remote_label.stdout" || return 97
    emit_stream "${action28ad_remote_label}_stderr" \
        "$evidence_directory/$action28ad_remote_label.stderr" || return 97
    [[ "$action28ad_remote_status" -eq 0 ]]
}
lsyncd_stability() {
    local action28ad_remote_sample
    local action28ad_remote_active
    local action28ad_remote_sub
    local action28ad_remote_result
    local action28ad_remote_pid
    local action28ad_remote_restarts

    for action28ad_remote_sample in 1 2 3 4 5; do
        action28ad_remote_active=$(systemctl show caddy-lsyncd.service \
            --property ActiveState --value) || return 1
        action28ad_remote_sub=$(systemctl show caddy-lsyncd.service \
            --property SubState --value) || return 1
        action28ad_remote_result=$(systemctl show caddy-lsyncd.service \
            --property Result --value) || return 1
        action28ad_remote_pid=$(systemctl show caddy-lsyncd.service \
            --property MainPID --value) || return 1
        action28ad_remote_restarts=$(systemctl show caddy-lsyncd.service \
            --property NRestarts --value) || return 1
        printf 'sample=%s active=%s sub=%s result=%s pid=%s restarts=%s\n' \
            "$action28ad_remote_sample" "$action28ad_remote_active" \
            "$action28ad_remote_sub" "$action28ad_remote_result" \
            "$action28ad_remote_pid" "$action28ad_remote_restarts"
        [[ "$action28ad_remote_active" = active ]] || return 1
        [[ "$action28ad_remote_sub" = running ]] || return 1
        [[ "$action28ad_remote_result" = success ]] || return 1
        [[ "$action28ad_remote_pid" =~ ^[1-9][0-9]*$ ]] || return 1
        [[ "$action28ad_remote_restarts" =~ ^[0-9]+$ ]] || return 1
        [[ "$action28ad_remote_sample" -eq 5 ]] || sleep 1
    done
}
check() {
    local action28ad_remote_label=$1

    shift
    if "$@" >/dev/null 2>&1; then
        printf '%s_%s_check_%s=true\n' "$prefix" "$mode" "$action28ad_remote_label"
        return 0
    fi
    first_failure=$action28ad_remote_label
    printf '%s_%s_check_%s=false\n' "$prefix" "$mode" "$action28ad_remote_label" >&2
    return 1
}
address_count() {
    local action28ad_remote_family=$1
    local action28ad_remote_cidr=$2

    ip -o "-$action28ad_remote_family" address show dev eth0 |
        awk -v expected="$action28ad_remote_cidr" \
            '$4 == expected { count++ } END { print count + 0 }'
}
dbus_state() {
    timeout 3 busctl get-property org.keepalived.Vrrp1 "$1" \
        org.keepalived.Vrrp1.Instance State
}
ownership_exact() {
    local action28ad_remote_state=$1
    local action28ad_remote_count=0
    local action28ad_remote_dbus='(us) 1 "Backup"'

    case "$action28ad_remote_state" in
        master)
            action28ad_remote_count=1
            action28ad_remote_dbus='(us) 2 "Master"'
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
    [[ "$(dbus_state "$ipv4_object")" = "$action28ad_remote_dbus" ]] || return 1
    [[ "$(dbus_state "$ipv6_object")" = "$action28ad_remote_dbus" ]] || return 1
    [[ "$(address_count 4 "$dns_ipv4_cidr")" -eq "$action28ad_remote_count" ]] || return 1
    [[ "$(address_count 6 "$dns_ipv6_cidr")" -eq "$action28ad_remote_count" ]] || return 1
    [[ "$(address_count 4 "$caddy_ipv4_cidr")" -eq "$action28ad_remote_count" ]] || return 1
    [[ "$(address_count 6 "$caddy_ipv6_cidr")" -eq "$action28ad_remote_count" ]]
}
stable_ownership() {
    local action28ad_remote_sample

    for action28ad_remote_sample in 1 2 3 4 5; do
        ownership_exact "$expected_state" || return 1
        printf '%s_%s_stable_sample_%s=true\n' \
            "$prefix" "$mode" "$action28ad_remote_sample"
        sleep 1
    done
}
manifest_valid() {
    local action28ad_remote_release=$1

    # conditional-validator-explicit-failures-begin
    [[ -d "$action28ad_remote_release" && ! -L "$action28ad_remote_release" ]] || return 1
    [[ -f "$action28ad_remote_release/release-manifest.json" ]] || return 1
    [[ -f "$action28ad_remote_release/manifest.sha256" ]] || return 1
    [[ ! -e "$action28ad_remote_release/.complete.pending" && ! -L "$action28ad_remote_release/.complete.pending" ]] || return 1
    manifest_paths_safe "$action28ad_remote_release/manifest.sha256" || return 1
    manifest_file_set_matches "$action28ad_remote_release" || return 1
    (cd "$action28ad_remote_release" &&
        sha256sum --strict --check manifest.sha256 >/dev/null 2>&1) || return 1
    # conditional-validator-explicit-failures-end
}
resolve_current_release_path() {
    local action28ad_remote_current=$1
    local action28ad_remote_release_root=$2
    local action28ad_remote_revision=$3
    local action28ad_remote_resolved

    # conditional-validator-explicit-failures-begin
    valid_revision "$action28ad_remote_revision" || return 1
    [[ -d "$action28ad_remote_release_root" &&
        ! -L "$action28ad_remote_release_root" ]] || return 1
    action28ad_remote_resolved=$(readlink -f -- "$action28ad_remote_current") || return 1
    [[ "$action28ad_remote_resolved" = "$action28ad_remote_release_root/$action28ad_remote_revision" ]] || return 1
    [[ -d "$action28ad_remote_resolved" &&
        ! -L "$action28ad_remote_resolved" ]] || return 1
    printf '%s\n' "$action28ad_remote_resolved"
    # conditional-validator-explicit-failures-end
}
manifest_paths_safe() {
    local action28ad_remote_manifest=$1

    # conditional-validator-explicit-failures-begin
    awk '
        length($0) == 0 { bad = 1; next }
        {
            hash = substr($0, 1, 64)
            separator = substr($0, 65, 2)
            path = substr($0, 67)
            if (length(hash) != 64 ||
                hash !~ /^[0-9a-f]+$/ ||
                separator != "  " ||
                path !~ /^[.][/][^[:cntrl:]]+$/ ||
                path ~ /(^|[/])[.][.]([/]|$)/ ||
                path ~ /[/][/]/ ||
                path ~ /[/][.]([/]|$)/ ||
                path ~ /[/]$/) {
                bad = 1
            }
        }
        END { exit bad ? 1 : 0 }
    ' "$action28ad_remote_manifest" || return 1
    # conditional-validator-explicit-failures-end
}
manifest_file_set_matches() {
    local action28ad_remote_release=$1
    local action28ad_remote_expected
    local action28ad_remote_observed
    local action28ad_remote_status=0

    # conditional-validator-explicit-failures-begin
    action28ad_remote_expected=$(mktemp /tmp/action28ad-manifest-expected.XXXXXX) || return 1
    action28ad_remote_observed=$(mktemp /tmp/action28ad-manifest-observed.XXXXXX) || {
        rm -f -- "$action28ad_remote_expected"
        return 1
    }
    awk '{ print substr($0, 67) }' \
        "$action28ad_remote_release/manifest.sha256" |
        LC_ALL=C sort -u >"$action28ad_remote_expected"
    (
        cd "$action28ad_remote_release"
        find . -type f \
            ! -path ./manifest.sha256 \
            ! -path ./.finalize-request \
            ! -path ./.complete \
            ! -path ./.complete.pending \
            -print |
            LC_ALL=C sort
    ) >"$action28ad_remote_observed"
    if ! cmp -s "$action28ad_remote_expected" "$action28ad_remote_observed"; then
        action28ad_remote_status=1
    fi
    rm -f -- "$action28ad_remote_expected" "$action28ad_remote_observed"
    [[ "$action28ad_remote_status" -eq 0 ]] || return 1
    # conditional-validator-explicit-failures-end
}
release_payload_equal() {
    local action28ad_remote_left=$1
    local action28ad_remote_right=$2

    # conditional-validator-explicit-failures-begin
    manifest_valid "$action28ad_remote_left" || return 1
    manifest_valid "$action28ad_remote_right" || return 1
    cmp -s "$action28ad_remote_left/release-manifest.json" "$action28ad_remote_right/release-manifest.json" || return 1
    cmp -s "$action28ad_remote_left/manifest.sha256" "$action28ad_remote_right/manifest.sha256" || return 1
    # conditional-validator-explicit-failures-end
}
lsyncd_baseline_state_valid() {
    local action28ad_remote_state=$1

    # conditional-validator-explicit-failures-begin
    [[ "$action28ad_remote_state" = inactive || "$action28ad_remote_state" = failed ]] || return 1
    # conditional-validator-explicit-failures-end
}
retained_destination_restored() {
    local action28ad_remote_state=$1
    local action28ad_remote_destination=$2

    # conditional-validator-explicit-failures-begin
    case "$action28ad_remote_state" in
        present)
            [[ -d "$action28ad_remote_destination" && ! -L "$action28ad_remote_destination" ]] || return 1
            ;;
        absent)
            [[ ! -e "$action28ad_remote_destination" && ! -L "$action28ad_remote_destination" ]] || return 1
            ;;
        *) return 1 ;;
    esac
    # conditional-validator-explicit-failures-end
}
run_manifest_boundary_self_test() {
    local action28ad_remote_source
    local action28ad_remote_equal
    local action28ad_remote_drift
    local action28ad_remote_extra
    local action28ad_remote_current
    local action28ad_remote_resolved
    local action28ad_remote_releases

    manifest_fixture_root=$(mktemp -d /tmp/action28ad-manifest-boundary.XXXXXX)
    trap 'rm -rf -- "$manifest_fixture_root"' EXIT INT TERM
    action28ad_remote_releases=$manifest_fixture_root/releases
    action28ad_remote_source=$action28ad_remote_releases/fixture
    action28ad_remote_equal=$manifest_fixture_root/equal
    action28ad_remote_drift=$manifest_fixture_root/drift
    action28ad_remote_extra=$manifest_fixture_root/extra
    mkdir -p "$action28ad_remote_source/conf.d"
    printf 'fixture\n' >"$action28ad_remote_source/conf.d/site.caddy"
    printf '{"revision":"fixture","source_node":"node-a"}\n' \
        >"$action28ad_remote_source/release-manifest.json"
    (
        cd "$action28ad_remote_source"
        find . -type f ! -path ./manifest.sha256 -print0 |
            LC_ALL=C sort -z |
            xargs -0 sha256sum
    ) >"$action28ad_remote_source/manifest.sha256"
    : >"$action28ad_remote_source/.finalize-request"
    cp -a "$action28ad_remote_source" "$action28ad_remote_equal"
    cp -a "$action28ad_remote_source" "$action28ad_remote_drift"
    cp -a "$action28ad_remote_source" "$action28ad_remote_extra"
    printf 'drift\n' >"$action28ad_remote_drift/conf.d/site.caddy"
    printf 'extra\n' >"$action28ad_remote_extra/unmanifested"
    manifest_valid "$action28ad_remote_source"
    printf '%s_manifest_boundary_valid_source_accepted=true\n' "$prefix"
    release_payload_equal "$action28ad_remote_source" "$action28ad_remote_equal"
    printf '%s_manifest_boundary_equal_payload_accepted=true\n' "$prefix"
    if manifest_valid "$action28ad_remote_drift"; then
        return 1
    fi
    printf '%s_manifest_boundary_hash_drift_rejected=true\n' "$prefix"
    if manifest_valid "$action28ad_remote_extra"; then
        return 1
    fi
    printf '%s_manifest_boundary_unmanifested_file_rejected=true\n' "$prefix"
    if release_payload_equal "$action28ad_remote_source" "$action28ad_remote_drift"; then
        return 1
    fi
    printf '%s_manifest_boundary_unequal_payload_rejected=true\n' "$prefix"
    lsyncd_baseline_state_valid inactive
    lsyncd_baseline_state_valid failed
    if lsyncd_baseline_state_valid active; then
        return 1
    fi
    printf '%s_manifest_boundary_failed_and_inactive_baselines_accepted=true\n' "$prefix"
    printf '%s_manifest_boundary_active_baseline_rejected=true\n' "$prefix"
    action28ad_remote_current=$manifest_fixture_root/current
    ln -s -- "$action28ad_remote_source" "$action28ad_remote_current"
    action28ad_remote_resolved=$(resolve_current_release_path \
        "$action28ad_remote_current" "$action28ad_remote_releases" fixture)
    [[ "$action28ad_remote_resolved" = "$action28ad_remote_source" ]]
    manifest_valid "$action28ad_remote_resolved"
    if manifest_valid "$action28ad_remote_current"; then
        return 1
    fi
    if resolve_current_release_path \
        "$action28ad_remote_current" "$action28ad_remote_releases" wrong-revision \
        >/dev/null 2>&1; then
        return 1
    fi
    printf '%s_manifest_boundary_current_symlink_resolved=true\n' "$prefix"
    printf '%s_manifest_boundary_resolved_manifest_accepted=true\n' "$prefix"
    printf '%s_manifest_boundary_direct_symlink_rejected=true\n' "$prefix"
    printf '%s_manifest_boundary_wrong_target_rejected=true\n' "$prefix"
    printf '%s_manifest_boundary_self_test_complete=true\n' "$prefix"
}
historical_quarantine_valid() {
    local action28ad_remote_incoming=$1
    local action28ad_remote_quarantine=$2
    local action28ad_remote_release_manifest_sha256=$3
    local action28ad_remote_payload_manifest_sha256=$4

    [[ ! -e "$action28ad_remote_incoming" && ! -L "$action28ad_remote_incoming" ]] || return 1
    manifest_valid "$action28ad_remote_quarantine" || return 1
    [[ "$(file_hash "$action28ad_remote_quarantine/release-manifest.json")" = "$action28ad_remote_release_manifest_sha256" ]] || return 1
    [[ "$(file_hash "$action28ad_remote_quarantine/manifest.sha256")" = "$action28ad_remote_payload_manifest_sha256" ]] || return 1
    [[ "$(jq -r '.revision // empty' \
        "$action28ad_remote_quarantine/release-manifest.json")" = "$historical_revision" ]] || return 1
    [[ "$(jq -r '.source_node // empty' \
        "$action28ad_remote_quarantine/release-manifest.json")" = node-a ]] || return 1
    [[ -f "$action28ad_remote_quarantine/.finalize-request" &&
        ! -L "$action28ad_remote_quarantine/.finalize-request" &&
        ! -s "$action28ad_remote_quarantine/.finalize-request" ]] || return 1
    [[ -f "$action28ad_remote_quarantine/.complete" &&
        ! -L "$action28ad_remote_quarantine/.complete" &&
        ! -s "$action28ad_remote_quarantine/.complete" ]] || return 1
    [[ ! -e "$action28ad_remote_quarantine/.complete.pending" &&
        ! -L "$action28ad_remote_quarantine/.complete.pending" ]] || return 1
    [[ -z "$(find "$action28ad_remote_quarantine" -type l -print -quit)" ]] || return 1
    [[ -z "$(find "$action28ad_remote_quarantine" ! -type d ! -type f -print -quit)" ]] || return 1
    [[ -z "$(find "$action28ad_remote_quarantine" -type f -links +1 -print -quit)" ]] || return 1
    [[ -z "$(find "$action28ad_remote_quarantine" -type d ! -perm 0550 -print -quit)" ]] || return 1
    [[ -z "$(find "$action28ad_remote_quarantine" -type f ! -perm 0440 -print -quit)" ]]
}
run_historical_quarantine_self_test() {
    local action28ad_remote_fixture_incoming
    local action28ad_remote_fixture_quarantine
    local action28ad_remote_fixture_release_hash
    local action28ad_remote_fixture_payload_hash

    quarantine_fixture_root=$(mktemp -d /tmp/action28ad-quarantine.XXXXXX)
    trap 'chmod -R u+rwX -- "$quarantine_fixture_root" 2>/dev/null || :; rm -rf -- "$quarantine_fixture_root"' EXIT INT TERM
    action28ad_remote_fixture_incoming=$quarantine_fixture_root/incoming/$historical_revision
    action28ad_remote_fixture_quarantine=$quarantine_fixture_root/quarantine/node-a-$historical_revision
    mkdir -p "$action28ad_remote_fixture_quarantine"
    printf '{"revision":"%s","parent_revision":"obsolete","source_node":"node-a"}\n' \
        "$historical_revision" >"$action28ad_remote_fixture_quarantine/release-manifest.json"
    printf 'fixture\n' >"$action28ad_remote_fixture_quarantine/Caddyfile"
    : >"$action28ad_remote_fixture_quarantine/.finalize-request"
    : >"$action28ad_remote_fixture_quarantine/.complete"
    (
        cd "$action28ad_remote_fixture_quarantine"
        sha256sum ./Caddyfile ./release-manifest.json >manifest.sha256
    )
    chmod 0440 "$action28ad_remote_fixture_quarantine"/* \
        "$action28ad_remote_fixture_quarantine"/.finalize-request \
        "$action28ad_remote_fixture_quarantine"/.complete
    chmod 0550 "$action28ad_remote_fixture_quarantine"
    action28ad_remote_fixture_release_hash=$(file_hash \
        "$action28ad_remote_fixture_quarantine/release-manifest.json")
    action28ad_remote_fixture_payload_hash=$(file_hash \
        "$action28ad_remote_fixture_quarantine/manifest.sha256")
    historical_quarantine_valid "$action28ad_remote_fixture_incoming" \
        "$action28ad_remote_fixture_quarantine" \
        "$action28ad_remote_fixture_release_hash" \
        "$action28ad_remote_fixture_payload_hash"
    mkdir -p "$action28ad_remote_fixture_incoming"
    if historical_quarantine_valid "$action28ad_remote_fixture_incoming" \
        "$action28ad_remote_fixture_quarantine" \
        "$action28ad_remote_fixture_release_hash" \
        "$action28ad_remote_fixture_payload_hash"; then
        return 1
    fi
    rmdir "$action28ad_remote_fixture_incoming"
    chmod 0644 "$action28ad_remote_fixture_quarantine/Caddyfile"
    if historical_quarantine_valid "$action28ad_remote_fixture_incoming" \
        "$action28ad_remote_fixture_quarantine" \
        "$action28ad_remote_fixture_release_hash" \
        "$action28ad_remote_fixture_payload_hash"; then
        return 1
    fi
    printf '%s_historical_quarantine_valid_accepted=true\n' "$prefix"
    printf '%s_historical_incoming_present_rejected=true\n' "$prefix"
    printf '%s_historical_quarantine_mode_drift_rejected=true\n' "$prefix"
    printf '%s_historical_quarantine_self_test_complete=true\n' "$prefix"
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
    backup_directory=/var/backups/caddy-ha/action28ad-$role-go-live
    evidence_directory=/tmp/caddy-action28ad/$run_id/$role
    readonly expected_hostname expected_keepalived_sha256 expected_lsyncd_sha256
    readonly backup_directory evidence_directory
}
stage_valid() {
    [[ -d "$stage" && ! -L "$stage" ]] || return 1
    [[ "$(file_hash "$stage/publish-release-v2.sh")" = "$publisher_sha256" ]] || return 1
    [[ "$(file_hash "$stage/reconcile-release-v2.sh")" = "$reconciler_sha256" ]] || return 1
    [[ "$(file_hash "$stage/finalize-incoming-release-v2.sh")" = "$finalizer_sha256" ]] || return 1
    [[ "$(file_hash "$stage/caddy-sync-reconcile.path")" = "$reconcile_path_sha256" ]] || return 1
    [[ "$(file_hash "$stage/caddy.lua")" = "$expected_lsyncd_sha256" ]] || return 1
    bash -n "$stage/publish-release-v2.sh" "$stage/reconcile-release-v2.sh" \
        "$stage/finalize-incoming-release-v2.sh"
}
current_revision() {
    jq -r '.revision // empty' /etc/caddy/current/release-manifest.json
}
record_backup() {
    local action28ad_remote_retained_destination=$releases_root/$retained_revision

    install -d -o root -g root -m 0700 /var/backups/caddy-ha
    install -d -o root -g root -m 0700 "$backup_directory"
    install -o root -g root -m 0600 "$publisher" "$backup_directory/publisher.before"
    install -o root -g root -m 0600 "$reconciler" "$backup_directory/reconciler.before"
    install -o root -g root -m 0600 "$finalizer" "$backup_directory/finalizer.before"
    install -o root -g root -m 0600 "$reconcile_path" \
        "$backup_directory/reconcile-path.before"
    printf '%s\n' absent >"$backup_directory/lsyncd-config.state"
    readlink -f -- /etc/caddy/current >"$backup_directory/current.before"
    systemctl is-active caddy-lsyncd.service >"$backup_directory/lsyncd-active.before" || :
    systemctl is-enabled caddy-lsyncd.service >"$backup_directory/lsyncd-enabled.before" || :
    systemctl is-active caddy-sync-reconcile.path >"$backup_directory/reconcile-active.before" || :
    systemctl is-enabled caddy-sync-reconcile.path >"$backup_directory/reconcile-enabled.before" || :
    if [[ -e "$action28ad_remote_retained_destination" ||
        -L "$action28ad_remote_retained_destination" ]]; then
        [[ -d "$action28ad_remote_retained_destination" &&
            ! -L "$action28ad_remote_retained_destination" ]] || return 1
        printf '%s\n' present >"$backup_directory/retained-destination.state"
    else
        printf '%s\n' absent >"$backup_directory/retained-destination.state"
    fi
    printf 'action=28ab\nrole=%s\n' "$role" >"$backup_directory/manifest"
    chmod 0600 "$backup_directory"/*
}
install_atomic() {
    local action28ad_remote_source=$1
    local action28ad_remote_target=$2
    local action28ad_remote_mode=$3
    local action28ad_remote_directory=${action28ad_remote_target%/*}
    local action28ad_remote_stage

    action28ad_remote_stage=$(mktemp "$action28ad_remote_directory/.action28ad.XXXXXX")
    install -o root -g root -m "$action28ad_remote_mode" \
        "$action28ad_remote_source" "$action28ad_remote_stage"
    mv -fT -- "$action28ad_remote_stage" "$action28ad_remote_target"
}
reset_failed_if_needed() {
    local action28ad_remote_unit=$1
    local action28ad_remote_failed_state

    action28ad_remote_failed_state=$(systemctl is-failed "$action28ad_remote_unit" 2>/dev/null || true)
    printf 'unit=%s before=%s\n' "$action28ad_remote_unit" \
        "${action28ad_remote_failed_state:-unknown}"
    if [[ "$action28ad_remote_failed_state" = failed ]]; then
        systemctl reset-failed "$action28ad_remote_unit" || return 1
    fi
    action28ad_remote_failed_state=$(systemctl is-failed "$action28ad_remote_unit" 2>/dev/null || true)
    printf 'unit=%s after=%s\n' "$action28ad_remote_unit" \
        "${action28ad_remote_failed_state:-unknown}"
    [[ "$action28ad_remote_failed_state" != failed ]]
}
reset_synchronization_failures() {
    reset_failed_if_needed caddy-lsyncd.service || return 1
    reset_failed_if_needed caddy-sync-reconcile.service
}
promote_release() {
    local action28ad_remote_revision=$1
    local action28ad_remote_source=/var/lib/caddy-sync/outbound/$action28ad_remote_revision
    local action28ad_remote_destination=/etc/caddy/releases/$action28ad_remote_revision
    local action28ad_remote_stage

    if [[ "$role" = node-b && "$action28ad_remote_revision" = "$retained_revision" ]]; then
        action28ad_remote_source=/var/lib/caddy-sync/incoming/node-a/$action28ad_remote_revision
    fi
    manifest_valid "$action28ad_remote_source" || return 1
    [[ "$(jq -r '.revision // empty' "$action28ad_remote_source/release-manifest.json")" = "$action28ad_remote_revision" ]] || return 1
    action28ad_remote_stage=$(mktemp -d \
        "/etc/caddy/releases/.action28ad-promote.XXXXXX")
    cp -a -- "$action28ad_remote_source/." "$action28ad_remote_stage/" || {
        rm -rf -- "$action28ad_remote_stage"
        return 1
    }
    manifest_valid "$action28ad_remote_stage" || {
        rm -rf -- "$action28ad_remote_stage"
        return 1
    }
    if release_payload_equal "$action28ad_remote_destination" \
        "$action28ad_remote_stage"; then
        rm -rf -- "$action28ad_remote_stage"
    else
        [[ ! -e "$backup_directory/retained-destination.displaced" &&
            ! -L "$backup_directory/retained-destination.displaced" ]] || return 1
        if [[ -e "$action28ad_remote_destination" ||
            -L "$action28ad_remote_destination" ]]; then
            mv -- "$action28ad_remote_destination" \
                "$backup_directory/retained-destination.displaced" || return 1
        fi
        mv -- "$action28ad_remote_stage" "$action28ad_remote_destination" || return 1
    fi
    chown -R root:caddy-tls "$action28ad_remote_destination"
    find "$action28ad_remote_destination" -type d -exec chmod 0550 {} +
    find "$action28ad_remote_destination" -type f -exec chmod 0440 {} +
    set -a
    # shellcheck disable=SC1091
    source /etc/default/caddy-ha
    set +a
    env CADDY_CONFIG_ROOT="$action28ad_remote_destination" \
        caddy validate --config "$action28ad_remote_destination/Caddyfile" \
        --adapter caddyfile >/dev/null
    ln -sfn "$action28ad_remote_destination" /etc/caddy/current.new
    mv -Tf /etc/caddy/current.new /etc/caddy/current
    systemctl reload caddy.service
}
rollback_node() {
    local action28ad_remote_before
    local action28ad_remote_retained_destination=$releases_root/$retained_revision
    local action28ad_remote_retained_state

    if [[ ! -d "$backup_directory" ]]; then
        printf 'rollback_not_required=true\n'
        return 0
    fi
    if [[ "$role" = node-a ]]; then
        systemctl start keepalived.service || return 1
    fi
    action28ad_remote_before=$(<"$backup_directory/current.before")
    ln -sfn "$action28ad_remote_before" /etc/caddy/current.new
    mv -Tf /etc/caddy/current.new /etc/caddy/current
    action28ad_remote_retained_state=$(
        <"$backup_directory/retained-destination.state"
    )
    if [[ -d "$backup_directory/retained-destination.displaced" ]]; then
        if [[ -e "$action28ad_remote_retained_destination" ||
            -L "$action28ad_remote_retained_destination" ]]; then
            [[ ! -e "$backup_directory/retained-destination.failed" &&
                ! -L "$backup_directory/retained-destination.failed" ]] || return 1
            mv -- "$action28ad_remote_retained_destination" \
                "$backup_directory/retained-destination.failed" || return 1
        fi
        mv -- "$backup_directory/retained-destination.displaced" \
            "$action28ad_remote_retained_destination" || return 1
    elif [[ "$action28ad_remote_retained_state" = absent &&
        -d "$action28ad_remote_retained_destination" ]]; then
        mv -- "$action28ad_remote_retained_destination" \
            "$backup_directory/retained-destination.created" || return 1
    fi
    install_atomic "$backup_directory/publisher.before" "$publisher" 0755
    install_atomic "$backup_directory/reconciler.before" "$reconciler" 0755
    install_atomic "$backup_directory/finalizer.before" "$finalizer" 0755
    install_atomic "$backup_directory/reconcile-path.before" "$reconcile_path" 0644
    rm -f -- "$lsyncd_config"
    systemctl disable --now caddy-lsyncd.service caddy-sync-reconcile.path >/dev/null 2>&1 || :
    reset_synchronization_failures || return 1
    systemctl daemon-reload
    systemctl reload caddy.service
    printf 'rollback_complete=true\n' >"$backup_directory/rollback.complete"
}

if [[ "$classifier_self_test" = true ]]; then
    [[ -z "$mode$role$stage$run_id$expected_revision$expected_source" ]]
    run_stream_classifier_self_test
    exit 0
fi
if [[ "$quarantine_self_test" = true ]]; then
    [[ -z "$mode$role$stage$run_id$expected_revision$expected_source" ]]
    run_historical_quarantine_self_test
    exit 0
fi
if [[ "$manifest_boundary_self_test" = true ]]; then
    [[ -z "$mode$role$stage$run_id$expected_revision$expected_source" ]]
    run_manifest_boundary_self_test
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
install -d -o root -g root -m 0700 /tmp/caddy-action28ad "$evidence_directory"
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
        printf '%s_%s_observed_finalizer_sha256=%s\n' "$prefix" "$mode" \
            "$(file_hash "$finalizer")"
        printf '%s_%s_observed_current_revision=%s\n' "$prefix" "$mode" \
            "$(current_revision)"
        check identity_root test "$(id -u)" -eq 0
        check hostname_exact test "$(hostname)" = "$expected_hostname"
        check stage_exact stage_valid
        check keepalived_hash_exact test \
            "$(file_hash /etc/keepalived/keepalived.conf)" = "$expected_keepalived_sha256"
        check publisher_baseline_exact test "$(file_hash "$publisher")" = "$old_publisher_sha256"
        check reconciler_baseline_exact test "$(file_hash "$reconciler")" = "$old_reconciler_sha256"
        check finalizer_baseline_exact test "$(file_hash "$finalizer")" = "$old_finalizer_sha256"
        check lsyncd_config_absent test ! -e "$lsyncd_config"
        check lsyncd_unit_exact test \
            "$(file_hash /etc/systemd/system/caddy-lsyncd.service)" = "$lsyncd_unit_sha256"
        check reconcile_path_exact test \
            "$(file_hash "$reconcile_path")" = "$old_reconcile_path_sha256"
        check reconcile_service_exact test \
            "$(file_hash /etc/systemd/system/caddy-sync-reconcile.service)" = "$reconcile_service_sha256"
        action28ad_remote_lsyncd_baseline_state=$(
            systemctl is-active caddy-lsyncd.service || true
        )
        printf '%s_%s_observed_lsyncd_baseline_state=%s\n' "$prefix" "$mode" \
            "$action28ad_remote_lsyncd_baseline_state"
        check synchronization_baseline_accepted lsyncd_baseline_state_valid \
            "$action28ad_remote_lsyncd_baseline_state"
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
            printf '%s_%s_observed_historical_quarantine_release_manifest_sha256=%s\n' \
                "$prefix" "$mode" \
                "$(file_hash "$historical_quarantine/release-manifest.json")"
            printf '%s_%s_observed_historical_quarantine_payload_manifest_sha256=%s\n' \
                "$prefix" "$mode" \
                "$(file_hash "$historical_quarantine/manifest.sha256")"
            check historical_incoming_absent test ! -e "$historical_incoming"
            check historical_quarantine_exact historical_quarantine_valid \
                "$historical_incoming" "$historical_quarantine" \
                "$historical_release_manifest_sha256" \
                "$historical_payload_manifest_sha256"
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
        run_captured disable_lsyncd_baseline systemctl disable --now \
            caddy-lsyncd.service
        run_captured reset_synchronization_failures reset_synchronization_failures
        check lsyncd_baseline_reset test \
            "$(systemctl is-active caddy-lsyncd.service || true)" = inactive
        check lsyncd_failed_state_cleared test \
            "$(systemctl is-failed caddy-lsyncd.service || true)" != failed
        install -d -o root -g root -m 0755 /etc/lsyncd
        install -d -o caddy-sync -g caddy-sync -m 0750 \
            /var/lib/caddy-sync/outbound /var/lib/caddy-sync/incoming
        install_atomic "$stage/publish-release-v2.sh" "$publisher" 0755
        install_atomic "$stage/reconcile-release-v2.sh" "$reconciler" 0755
        install_atomic "$stage/finalize-incoming-release-v2.sh" "$finalizer" 0755
        install_atomic "$stage/caddy-sync-reconcile.path" "$reconcile_path" 0644
        install_atomic "$stage/caddy.lua" "$lsyncd_config" 0644
        systemctl daemon-reload
        check publisher_installed test "$(file_hash "$publisher")" = "$publisher_sha256"
        check reconciler_installed test "$(file_hash "$reconciler")" = "$reconciler_sha256"
        check finalizer_installed test "$(file_hash "$finalizer")" = "$finalizer_sha256"
        check reconcile_path_installed test \
            "$(file_hash "$reconcile_path")" = "$reconcile_path_sha256"
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
        run_captured lsyncd_journal_cursor journalctl --show-cursor -n 0 --no-pager
        lsyncd_journal_cursor=$(sed -n 's/^-- cursor: //p' \
            "$evidence_directory/lsyncd_journal_cursor.stdout" | tail -n 1)
        check lsyncd_journal_cursor_nonempty test -n "$lsyncd_journal_cursor"
        action28ad_remote_enable_lsyncd_status=0
        run_captured enable_lsyncd systemctl enable --now caddy-lsyncd.service ||
            action28ad_remote_enable_lsyncd_status=$?
        action28ad_remote_lsyncd_stability_status=0
        run_captured lsyncd_stability lsyncd_stability ||
            action28ad_remote_lsyncd_stability_status=$?
        action28ad_remote_lsyncd_show_status=0
        run_captured lsyncd_show systemctl show caddy-lsyncd.service --no-pager \
            --property LoadState --property ActiveState --property SubState \
            --property Result --property ExecMainCode --property ExecMainStatus \
            --property MainPID --property NRestarts ||
            action28ad_remote_lsyncd_show_status=$?
        action28ad_remote_lsyncd_status_status=0
        run_captured lsyncd_status env SYSTEMD_COLORS=0 systemctl status \
            caddy-lsyncd.service --no-pager --full --lines=80 ||
            action28ad_remote_lsyncd_status_status=$?
        action28ad_remote_lsyncd_journal_status=0
        run_captured lsyncd_journal journalctl -u caddy-lsyncd.service \
            --after-cursor "$lsyncd_journal_cursor" --no-pager \
            --output=short-iso || action28ad_remote_lsyncd_journal_status=$?
        printf '%s_%s_lsyncd_enable_observed_status=%s\n' "$prefix" "$mode" \
            "$action28ad_remote_enable_lsyncd_status"
        printf '%s_%s_lsyncd_stability_observed_status=%s\n' "$prefix" "$mode" \
            "$action28ad_remote_lsyncd_stability_status"
        printf '%s_%s_lsyncd_show_observed_status=%s\n' "$prefix" "$mode" \
            "$action28ad_remote_lsyncd_show_status"
        printf '%s_%s_lsyncd_status_observed_status=%s\n' "$prefix" "$mode" \
            "$action28ad_remote_lsyncd_status_status"
        printf '%s_%s_lsyncd_journal_observed_status=%s\n' "$prefix" "$mode" \
            "$action28ad_remote_lsyncd_journal_status"
        check lsyncd_enable_status_zero test \
            "$action28ad_remote_enable_lsyncd_status" -eq 0
        check lsyncd_stability_status_zero test \
            "$action28ad_remote_lsyncd_stability_status" -eq 0
        check lsyncd_show_status_zero test \
            "$action28ad_remote_lsyncd_show_status" -eq 0
        check lsyncd_status_status_zero test \
            "$action28ad_remote_lsyncd_status_status" -eq 0
        check lsyncd_journal_status_zero test \
            "$action28ad_remote_lsyncd_journal_status" -eq 0
        check lsyncd_journal_transport_clean test \
            -z "$(grep -Ei 'rrsync error|rsync error|Retrying startup|connection unexpectedly closed' \
                "$evidence_directory/lsyncd_journal.stdout" || true)"
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
        action28ad_remote_current_release=$(resolve_current_release_path \
            /etc/caddy/current "$releases_root" "$expected_revision" 2>/dev/null || true)
        action28ad_remote_current_source=$(jq -r '.source_node // empty' \
            "$action28ad_remote_current_release/release-manifest.json" \
            2>/dev/null || true)
        check current_release_resolved test -n "$action28ad_remote_current_release"
        check current_revision_exact test "$(current_revision)" = "$expected_revision"
        check current_source_exact test \
            "$action28ad_remote_current_source" = "$expected_source"
        check current_manifest_valid manifest_valid "$action28ad_remote_current_release"
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
        check finalizer_restored test "$(file_hash "$finalizer")" = "$old_finalizer_sha256"
        check reconcile_path_restored test \
            "$(file_hash "$reconcile_path")" = "$old_reconcile_path_sha256"
        check lsyncd_config_removed test ! -e "$lsyncd_config"
        check lsyncd_inactive test \
            "$(systemctl is-active caddy-lsyncd.service || true)" = inactive
        check lsyncd_failed_state_cleared test \
            "$(systemctl is-failed caddy-lsyncd.service || true)" != failed
        check retained_destination_restored retained_destination_restored \
            "$(<"$backup_directory/retained-destination.state")" \
            "$releases_root/$retained_revision"
        ;;
    commit)
        check backup_present test -d "$backup_directory"
        printf 'action28ad_complete=true\n' >"$backup_directory/transaction.complete"
        chmod 0600 "$backup_directory/transaction.complete"
        check transaction_marker test -f "$backup_directory/transaction.complete"
        check transient_stage_absent test \
            -z "$(find /run -maxdepth 1 -name 'caddy-action28ad-bundle.*' \
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
