#!/usr/bin/env bash
# shellcheck disable=SC2016

set -Eeuo pipefail
set +x
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=systemd_boot_persistence_policy
test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
readonly caddy_root=${test_directory%/tests}
readonly agents_file=$caddy_root/../AGENTS.md
readonly systemd_registry=$caddy_root/manifests/systemd-lifecycle.tsv
readonly health_worker=$caddy_root/scripts/validate-sync-health.sh
readonly lsyncd_unit=$caddy_root/systemd/caddy-lsyncd.service

check() {
    local systemd_policy_label=$1

    shift
    if "$@"; then
        printf '%s_check_%s=true\n' "$prefix" "$systemd_policy_label"
        return 0
    fi
    printf '%s_check_%s=false\n' "$prefix" "$systemd_policy_label" >&2
    return 1
}
run_checks() {
    local systemd_policy_unit
    local systemd_policy_source
    local systemd_policy_installed

    # conditional-validator-explicit-failures-begin
    check obsolete_path_source_absent test ! -e "$caddy_root/systemd/caddy-validate-reload.path" || return 1
    check obsolete_service_source_absent test ! -e "$caddy_root/systemd/caddy-validate-reload.service" || return 1
    for systemd_policy_unit in \
        caddy.service caddy-lsyncd.service caddy-sync-reconcile.path \
        caddy-cert-expiry.timer caddy-sync-health.timer \
        caddy-pihole-web-health.timer; do
        if [[ "$systemd_policy_unit" = caddy.service ]]; then
            continue
        fi
        systemd_policy_source=$caddy_root/systemd/$systemd_policy_unit
        systemd_policy_installed=/etc/systemd/system/$systemd_policy_unit
        check "${systemd_policy_unit//[^a-zA-Z0-9]/_}_registered" awk -F '\t' \
            -v source="Caddy/systemd/$systemd_policy_unit" -v installed="$systemd_policy_installed" '
                $1 == source && $2 == "production-current" && $3 == "yes" &&
                    $4 == installed { found++ }
                END { exit(found == 1 ? 0 : 1) }
            ' "$systemd_registry" || return 1
        check "${systemd_policy_unit//[^a-zA-Z0-9]/_}_source" test -f "$systemd_policy_source" || return 1
    done
    check backend_worker_static awk -F '\t' '
        $1 == "Caddy/systemd/caddy-pihole-web-health.service" &&
            $2 == "production-current" && $3 == "yes" { found++ }
        END { exit(found == 1 ? 0 : 1) }
    ' "$systemd_registry" || return 1
    check rejected_backend_noninstallable awk -F '\t' '
        $1 == "Caddy/systemd/caddy-pihole-backend.service" &&
            $2 == "rejected" && $3 == "no" { found++ }
        END { exit(found == 1 ? 0 : 1) }
    ' "$systemd_registry" || return 1
    check status_age_contract_absent test -z \
        "$(grep -E 'maximum_lsyncd_status_age|lsyncd_status_(age|fresh)|status.*mtime|wait_for_lsyncd_status_advance' \
            "$health_worker" || true)" || return 1
    check health_worker_service_state grep -Fq \
        '[[ "$(service_property SubState)" = running ]]' "$health_worker" || return 1
    check health_worker_main_pid grep -Fq \
        '[[ "$sync_health_main_pid" =~ ^[1-9][0-9]*$ ]]' "$health_worker" || return 1
    check health_worker_restart_count grep -Fq \
        '[[ "$sync_health_restarts" =~ ^[0-9]+$ ]]' "$health_worker" || return 1
    check health_worker_parseable_snapshot grep -Fq \
        "grep -Eq '^Lsyncd status report at .+\$'" "$health_worker" || return 1
    check lsyncd_success_exit_exact test "$(grep -Fxc 'SuccessExitStatus=143' "$lsyncd_unit")" -eq 1 || return 1
    check repository_rule grep -Fq 'Production service acceptance must validate boot persistence' "$agents_file" || return 1
    # conditional-validator-explicit-failures-end
    printf '%s_complete=true\n' "$prefix"
}

case "${1:-}" in
    --check) run_checks ;;
    *) exit 64 ;;
esac
