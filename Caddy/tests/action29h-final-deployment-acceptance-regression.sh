#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_29h_regression
test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
readonly caddy_root=${test_directory%/tests}
readonly inspector=$caddy_root/scripts/inspect-final-deployment-action29h.sh
readonly outer=$caddy_root/scripts/run-final-deployment-acceptance-action29h-outer.sh
readonly dns_probe=$caddy_root/scripts/run-dual-node-dns-record-families-action24-retry3-outer.sh
fixture_root=

check() {
    local action29_regression_label=$1

    shift
    if "$@" >/dev/null 2>&1; then
        printf '%s_check_%s=true\n' "$prefix" "$action29_regression_label"
        return 0
    fi
    printf '%s_check_%s=false\n' "$prefix" "$action29_regression_label" >&2
    return 1
}
accept_node() {
    local action29_regression_role=$1
    local action29_regression_stdout=$2

    /bin/bash "$outer" --validate-node-transcript "$action29_regression_role" \
        "$action29_regression_stdout" 0 "$fixture_root/empty"
}
reject_node() {
    local action29_regression_role=$1
    local action29_regression_stdout=$2

    if accept_node "$action29_regression_role" "$action29_regression_stdout"; then
        return 1
    fi
}
accept_component() {
    local action29_regression_label=$1
    local action29_regression_stdout=$2

    /bin/bash "$outer" --validate-component-transcript "$action29_regression_label" \
        "$action29_regression_stdout" 0 "$fixture_root/empty"
}
reject_component() {
    local action29_regression_label=$1
    local action29_regression_stdout=$2

    if accept_component "$action29_regression_label" "$action29_regression_stdout"; then
        return 1
    fi
}
reject_command() {
    if "$@"; then
        return 1
    fi
}
run_regression() {
    local action29_regression_role
    local action29_regression_token
    local action29_regression_valid
    local action29_regression_altered
    local action29_regression_marker
    local action29_regression_component
    local action29_regression_cleanup
    local action29h_regression_backup
    local action29h_regression_owner
    local action29h_regression_group
    local action29h_regression_before_ftl
    local action29h_regression_before_domain
    local action29h_regression_release
    local action29h_regression_manifest_output
    local action29h_regression_expected_labels
    local action29h_regression_dns_render

    fixture_root=$(mktemp -d /tmp/action29-regression.XXXXXX) || return 1
    trap 'rm -rf -- "$fixture_root"' EXIT INT TERM
    install -m 0600 /dev/null "$fixture_root/empty" || return 1
    action29h_regression_dns_render=$fixture_root/dns-render
    install -d -m 0700 "$action29h_regression_dns_render" || return 1
    /bin/bash "$dns_probe" --render-to "$action29h_regression_dns_render" || return 1
    check dns_production_ftl_hash grep -Fqx \
        'readonly accepted_pihole_ftl_sha256=a1dc88b1f696a6870e38025be113ff8664750fca6265c79a2aee12f80898cfa3' \
        "$action29h_regression_dns_render/inspector" || return 1
    check dns_production_domain_hash grep -Fqx \
        'readonly accepted_pihole_domain_sha256=39fa219a7d1c81c7fb36d89bc17ba1caae26f3472eb861a750a8ba03ae55b026' \
        "$action29h_regression_dns_render/inspector" || return 1
    check dns_stale_ftl_hash_absent reject_command grep -Fq \
        c77de6654c575e12fa1661f8ec901de67d9a623c3e9b965d4e32b550c132a7aa \
        "$action29h_regression_dns_render/inspector" || return 1
    check dns_stale_domain_hash_absent reject_command grep -Fq \
        a8305acbc27a9133d6e68e8b1a0fe9a462a975919233d71866d54b2e98810f96 \
        "$action29h_regression_dns_render/inspector" || return 1
    action29h_regression_expected_labels=$fixture_root/expected-labels
    /bin/bash "$inspector" --expected-checks node-a \
        >"$action29h_regression_expected_labels" || return 1
    check production_pihole_service_label grep -Fqx pihole_FTL_active \
        "$action29h_regression_expected_labels" || return 1
    check production_lsyncd_service_label grep -Fqx caddy_lsyncd_active \
        "$action29h_regression_expected_labels" || return 1
    check stale_pihole_service_label_absent reject_command grep -Fqx pihole_ftl_active \
        "$action29h_regression_expected_labels" || return 1
    check stale_lsyncd_service_label_absent reject_command grep -Fqx lsyncd_active \
        "$action29h_regression_expected_labels" || return 1
    # shellcheck disable=SC2016
    check production_service_label_transform grep -Fq \
        'check "${action29_remote_service//-/_}_active" service_active' \
        "$inspector" || return 1

    # conditional-validator-explicit-failures-begin
    for action29_regression_role in node-a node-b; do
        action29_regression_token=${action29_regression_role//-/_}
        action29_regression_valid=$fixture_root/$action29_regression_token.valid
        /bin/bash "$inspector" --self-test-node "$action29_regression_role" \
            >"$action29_regression_valid" || return 1
        check "${action29_regression_token}_real_producer_accepted" accept_node \
            "$action29_regression_role" "$action29_regression_valid" || return 1

        action29_regression_altered=$fixture_root/$action29_regression_token.false
        sed '0,/=true$/s//=false/' "$action29_regression_valid" >"$action29_regression_altered" || return 1
        check "${action29_regression_token}_false_rejected" reject_node \
            "$action29_regression_role" "$action29_regression_altered" || return 1

        action29_regression_altered=$fixture_root/$action29_regression_token.missing
        sed '1d' "$action29_regression_valid" >"$action29_regression_altered" || return 1
        check "${action29_regression_token}_missing_rejected" reject_node \
            "$action29_regression_role" "$action29_regression_altered" || return 1

        action29_regression_altered=$fixture_root/$action29_regression_token.duplicate
        cp -- "$action29_regression_valid" "$action29_regression_altered" || return 1
        sed -n '1p' "$action29_regression_valid" >>"$action29_regression_altered" || return 1
        check "${action29_regression_token}_duplicate_rejected" reject_node \
            "$action29_regression_role" "$action29_regression_altered" || return 1

        action29_regression_altered=$fixture_root/$action29_regression_token.identity
        sed 's/^action_29h_remote_\(.*\)_observed_pihole_ftl_sha256=.*/action_29h_remote_\1_observed_pihole_ftl_sha256=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/' \
            "$action29_regression_valid" >"$action29_regression_altered" || return 1
        check "${action29_regression_token}_altered_observed_identity_rejected" reject_node \
            "$action29_regression_role" "$action29_regression_altered" || return 1

        action29_regression_altered=$fixture_root/$action29_regression_token.manifest-path-status
        sed 's/_observed_manifest_paths_status=0$/_observed_manifest_paths_status=1/' \
            "$action29_regression_valid" >"$action29_regression_altered" || return 1
        check "${action29_regression_token}_manifest_path_status_rejected" reject_node \
            "$action29_regression_role" "$action29_regression_altered" || return 1

        action29_regression_altered=$fixture_root/$action29_regression_token.manifest-file-set-status
        sed 's/_observed_manifest_file_set_status=0$/_observed_manifest_file_set_status=1/' \
            "$action29_regression_valid" >"$action29_regression_altered" || return 1
        check "${action29_regression_token}_manifest_file_set_status_rejected" reject_node \
            "$action29_regression_role" "$action29_regression_altered" || return 1
    done

    for action29_regression_component in dns protocol tls; do
        case "$action29_regression_component" in
            dns) action29_regression_marker=action_24_retry_outer_complete=true ;;
            protocol) action29_regression_marker=action_26_h3_retry_complete=true ;;
            tls) action29_regression_marker=action_27_retry3_outer_complete=true ;;
            *) return 64 ;;
        esac
        printf '%s\n' "$action29_regression_marker" >"$fixture_root/$action29_regression_component.valid"
        check "${action29_regression_component}_component_accepted" accept_component \
            "$action29_regression_component" "$fixture_root/$action29_regression_component.valid" || return 1
        install -m 0600 /dev/null "$fixture_root/$action29_regression_component.missing" || return 1
        check "${action29_regression_component}_missing_rejected" reject_component \
            "$action29_regression_component" "$fixture_root/$action29_regression_component.missing" || return 1
        {
            printf '%s\n' "$action29_regression_marker"
            printf 'fixture_check_injected=false\n'
        } >"$fixture_root/$action29_regression_component.false"
        check "${action29_regression_component}_false_rejected" reject_component \
            "$action29_regression_component" "$fixture_root/$action29_regression_component.false" || return 1
    done
    # shellcheck disable=SC2016
    check production_remote_cwd grep -Fq \
        '"cd / && sudo -n /bin/bash -s -- --node $action29_outer_role"' "$outer" || return 1
    # shellcheck disable=SC2016
    check production_inspector_stream grep -Fq '<"$inspector"' "$outer" || return 1
    # shellcheck disable=SC2016
    check production_capture_before_ssh grep -Fq \
        'prepare_capture "$action29_outer_stdout" "$action29_outer_stderr" "$action29_outer_status_file"' \
        "$outer" || return 1
    check no_mutation_commands test -z \
        "$(grep -E 'systemctl (start|stop|restart|reload|enable|disable)|install -[A-Za-z]*m [^0].* /etc/' \
            "$inspector" || true)" || return 1
    printf '%s\n' PRIVACYLEVEL=0 RATE_LIMIT=1000/60 RESOLVE_IPV6=YES PIHOLE_PTR=NONE \
        >"$fixture_root/pihole-FTL.conf" || return 1
    check pihole_ftl_v5_directives /bin/bash "$inspector" --validate-ftl-v5 \
        "$fixture_root/pihole-FTL.conf" || return 1
    sed 's/RESOLVE_IPV6=YES/RESOLVE_IPV6=NO/' "$fixture_root/pihole-FTL.conf" \
        >"$fixture_root/pihole-FTL.invalid" || return 1
    check pihole_ftl_v5_negative reject_command /bin/bash "$inspector" --validate-ftl-v5 \
        "$fixture_root/pihole-FTL.invalid" || return 1
    cat >"$fixture_root/local.theama.co.conf" <<'EOF'
domain=local.theama.co
server=/local.theama.co/127.0.0.1#5335
server=/local.theama.co/::1#5335
server=/0.1.10.in-addr.arpa/127.0.0.1#5335
server=/0.1.10.in-addr.arpa/::1#5335
server=/1.1.10.in-addr.arpa/127.0.0.1#5335
server=/1.1.10.in-addr.arpa/::1#5335
server=/2.1.10.in-addr.arpa/127.0.0.1#5335
server=/2.1.10.in-addr.arpa/::1#5335
server=/3.1.10.in-addr.arpa/127.0.0.1#5335
server=/3.1.10.in-addr.arpa/::1#5335
server=/1.0.0.0.1.7.9.6.8.a.a.5.6.3.d.f.ip6.arpa/127.0.0.1#5335
server=/1.0.0.0.1.7.9.6.8.a.a.5.6.3.d.f.ip6.arpa/::1#5335
EOF
    check pihole_domain_v5_forwarding /bin/bash "$inspector" --validate-domain-v5 \
        "$fixture_root/local.theama.co.conf" || return 1
    sed '/3.1.10.in-addr.arpa\/::1#5335/d' "$fixture_root/local.theama.co.conf" \
        >"$fixture_root/local.theama.co.invalid" || return 1
    check pihole_domain_v5_negative reject_command /bin/bash "$inspector" --validate-domain-v5 \
        "$fixture_root/local.theama.co.invalid" || return 1
    # shellcheck disable=SC2016
    check pihole_ftl_metadata_production grep -Fq \
        'check pihole_ftl_metadata_exact metadata_owner_exact "$pihole_ftl" pihole root 664' \
        "$inspector" || return 1
    # shellcheck disable=SC2016
    check pihole_domain_metadata_production grep -Fq \
        'check pihole_domain_metadata_exact metadata_owner_exact "$pihole_domain" root root 644' \
        "$inspector" || return 1
    # shellcheck disable=SC2016
    check action29b_backup_production grep -Fq \
        'check action29b_backup_valid action29b_backup_valid' "$inspector" || return 1
    action29h_regression_backup=$fixture_root/action29b-backup
    action29h_regression_owner=$(id -un) || return 1
    action29h_regression_group=$(id -gn) || return 1
    install -d -m 0700 "$action29h_regression_backup" || return 1
    printf '%s\n' before-ftl >"$action29h_regression_backup/pihole-FTL.conf.before" || return 1
    printf '%s\n' before-domain >"$action29h_regression_backup/local.theama.co.conf.before" || return 1
    printf '%s\n' committed >"$action29h_regression_backup/transaction.complete" || return 1
    chmod 0600 "$action29h_regression_backup/pihole-FTL.conf.before" \
        "$action29h_regression_backup/local.theama.co.conf.before" \
        "$action29h_regression_backup/transaction.complete" || return 1
    action29h_regression_before_ftl=$(sha256sum \
        "$action29h_regression_backup/pihole-FTL.conf.before" | awk '{ print $1 }') || return 1
    action29h_regression_before_domain=$(sha256sum \
        "$action29h_regression_backup/local.theama.co.conf.before" | awk '{ print $1 }') || return 1
    printf '%s\n' \
        'action=29b' 'role=node-a' \
        "before_ftl_sha256=$action29h_regression_before_ftl" \
        "before_domain_sha256=$action29h_regression_before_domain" \
        'target_ftl_sha256=a1dc88b1f696a6870e38025be113ff8664750fca6265c79a2aee12f80898cfa3' \
        'target_domain_sha256=39fa219a7d1c81c7fb36d89bc17ba1caae26f3472eb861a750a8ba03ae55b026' \
        >"$action29h_regression_backup/manifest" || return 1
    chmod 0600 "$action29h_regression_backup/manifest" || return 1
    check action29b_backup_real_validator /bin/bash "$inspector" --validate-action29b-backup \
        node-a "$action29h_regression_backup" "$action29h_regression_owner" \
        "$action29h_regression_group" "$action29h_regression_before_ftl" \
        "$action29h_regression_before_domain" || return 1
    sed 's/^action=29b$/action=wrong/' "$action29h_regression_backup/manifest" \
        >"$fixture_root/altered-manifest" || return 1
    mv -fT "$fixture_root/altered-manifest" "$action29h_regression_backup/manifest" || return 1
    chmod 0600 "$action29h_regression_backup/manifest" || return 1
    check action29b_backup_altered_rejected reject_command /bin/bash "$inspector" \
        --validate-action29b-backup node-a "$action29h_regression_backup" \
        "$action29h_regression_owner" "$action29h_regression_group" \
        "$action29h_regression_before_ftl" "$action29h_regression_before_domain" || return 1
    action29h_regression_release=$fixture_root/release
    install -d -m 0700 "$action29h_regression_release" || return 1
    printf 'fixture\n' >"$action29h_regression_release/Caddyfile" || return 1
    (
        cd -- "$action29h_regression_release" || exit 1
        sha256sum ./Caddyfile >manifest.sha256
    ) || return 1
    check manifest_paths_real_producer /bin/bash "$inspector" --validate-manifest-paths \
        "$action29h_regression_release/manifest.sha256" || return 1
    check manifest_file_set_real_producer /bin/bash "$inspector" --validate-manifest-file-set \
        "$action29h_regression_release" || return 1
    action29h_regression_manifest_output=$fixture_root/manifest-valid.out
    /bin/bash "$inspector" --capture-manifest-fixture node-a \
        "$action29h_regression_release" >"$action29h_regression_manifest_output" || return 1
    check manifest_hash_real_producer_status grep -Fqx \
        'action_29h_remote_node_a_manifest_hash_check_status=0' \
        "$action29h_regression_manifest_output" || return 1
    check manifest_hash_real_producer_content grep -Fqx './Caddyfile: OK' \
        "$action29h_regression_manifest_output" || return 1
    printf 'drift\n' >>"$action29h_regression_release/Caddyfile" || return 1
    action29h_regression_manifest_output=$fixture_root/manifest-invalid.out
    /bin/bash "$inspector" --capture-manifest-fixture node-a \
        "$action29h_regression_release" >"$action29h_regression_manifest_output" || return 1
    check manifest_hash_drift_status grep -Fqx \
        'action_29h_remote_node_a_manifest_hash_check_status=1' \
        "$action29h_regression_manifest_output" || return 1
    check manifest_hash_drift_content grep -Fqx './Caddyfile: FAILED' \
        "$action29h_regression_manifest_output" || return 1
    printf '%064d  ../escape\n' 0 >"$action29h_regression_release/manifest.sha256" || return 1
    check manifest_unsafe_path_rejected reject_command /bin/bash "$inspector" \
        --validate-manifest-paths "$action29h_regression_release/manifest.sha256" || return 1
    check manifest_file_set_drift_rejected reject_command /bin/bash "$inspector" \
        --validate-manifest-file-set "$action29h_regression_release" || return 1
    # shellcheck disable=SC2016
    check production_manifest_identity_observed grep -Fq \
        'observed_manifest_sha256=$(file_hash "$action29_remote_release/manifest.sha256")' \
        "$inspector" || return 1
    # shellcheck disable=SC2016
    check production_manifest_path_gate grep -Fq \
        'check current_manifest_paths_safe test "$action29h_remote_manifest_paths_status" -eq 0' \
        "$inspector" || return 1
    # shellcheck disable=SC2016
    check production_manifest_file_set_gate grep -Fq \
        'check current_manifest_file_set_exact test "$action29h_remote_manifest_file_set_status" -eq 0' \
        "$inspector" || return 1
    # shellcheck disable=SC2016
    check production_manifest_hash_capture grep -Fq \
        'capture_manifest_hash_check "$action29_remote_release"' "$inspector" || return 1
    check production_manifest_evidence_before_decision awk '
        /capture_manifest_hash_check "[$]action29_remote_release"/ && !capture { capture = NR }
        /observed_manifest_paths_status/ && !path_status { path_status = NR }
        /observed_manifest_file_set_status/ && !file_set_status { file_set_status = NR }
        /check current_manifest_identity_exact/ && !decision { decision = NR }
        END {
            exit !(capture > 0 && path_status > 0 && file_set_status > 0 &&
                decision > capture && decision > path_status && decision > file_set_status)
        }
    ' "$inspector" || return 1
    action29_regression_cleanup=$fixture_root/cleanup
    /bin/bash "$inspector" --cleanup-self-test >"$action29_regression_cleanup" || return 1
    check cleanup_unset_safe grep -Fqx \
        'action_29h_remote_cleanup_unset_safe=true' "$action29_regression_cleanup" || return 1
    # conditional-validator-explicit-failures-end

    printf '%s_real_producer_coverage=true\n' "$prefix"
    printf '%s_negative_coverage=true\n' "$prefix"
    printf '%s_complete=true\n' "$prefix"
}

run_regression
