#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=deployment_lifecycle_policy
test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
repository_root=${test_directory%/Caddy/tests}

if [[ $# -eq 3 && $1 == --check && $2 == --repository-root ]]; then
    repository_root=$3
    [[ "$repository_root" == /tmp/* && -d "$repository_root" &&
        ! -L "$repository_root" ]] || exit 64
elif [[ $# -ne 1 || $1 != --check ]]; then
    exit 64
fi
readonly repository_root
readonly script_registry=$repository_root/Caddy/manifests/script-lifecycle.tsv
readonly systemd_registry=$repository_root/Caddy/manifests/systemd-lifecycle.tsv
readonly production_inventory=$repository_root/Caddy/manifests/production-artifacts.tsv
readonly synchronization_manifest=$repository_root/Caddy/manifests/synchronization-protocol-v2.yaml
readonly installer=$repository_root/Caddy/scripts/install-caddy-ha.sh
readonly validator=$repository_root/Caddy/scripts/validate-caddy-ha.sh
readonly uninstaller=$repository_root/Caddy/scripts/uninstall-caddy-ha.sh

fail() {
    printf '%s_failure=%s\n' "$prefix" "$1" >&2
    exit 1
}

for required_file in \
    "$script_registry" \
    "$systemd_registry" \
    "$production_inventory" \
    "$synchronization_manifest" \
    "$installer" \
    "$validator" \
    "$uninstaller" \
    "$repository_root/Caddy/scripts/README.md"; do
    [[ -f "$required_file" && ! -L "$required_file" ]] ||
        fail "required_${required_file##*/}"
done

validate_registry() {
    local lifecycle_registry=$1
    local lifecycle_kind=$2

    awk -F '\t' -v kind="$lifecycle_kind" '
        /^[[:space:]]*(#|$)/ { next }
        NF != 6 { exit 1 }
        kind == "script" && $1 !~ /^Caddy\/scripts\/[A-Za-z0-9._@+-]+$/ { exit 1 }
        kind == "systemd" && $1 !~ /^Caddy\/systemd\/[A-Za-z0-9._@+-]+(\/[A-Za-z0-9._@+-]+)?$/ { exit 1 }
        $2 !~ /^(production-current|historical-action|historical-superseded|workstation-only|rejected|deferred)$/ { exit 1 }
        $3 !~ /^(yes|no)$/ { exit 1 }
        $3 == "yes" && $2 != "production-current" { exit 1 }
        $3 == "yes" && $4 !~ /^\/(etc|usr)\// { exit 1 }
        $3 == "yes" && $5 !~ /^0[0-7][0-7][0-7]$/ { exit 1 }
        $3 == "no" && ($4 != "-" || $5 != "-") { exit 1 }
        $6 !~ /^Caddy\/[A-Za-z0-9._@+\/-]+$/ { exit 1 }
        seen_source[$1]++ { exit 1 }
        $3 == "yes" && seen_target[$4]++ { exit 1 }
        END { if (length(seen_source) == 0) exit 1 }
    ' "$lifecycle_registry"
}

validate_registry "$script_registry" script || fail script_registry_contract
validate_registry "$systemd_registry" systemd || fail systemd_registry_contract

diff -u \
    <(find "$repository_root/Caddy/scripts" -maxdepth 1 -type f \
        ! -name README.md -printf 'Caddy/scripts/%f\n' | LC_ALL=C sort) \
    <(awk -F '\t' '!/^[[:space:]]*(#|$)/ { print $1 }' \
        "$script_registry" | LC_ALL=C sort) >/dev/null ||
    fail script_inventory_incomplete

diff -u \
    <(find "$repository_root/Caddy/systemd" -type f \
        -printf 'Caddy/systemd/%P\n' | LC_ALL=C sort) \
    <(awk -F '\t' '!/^[[:space:]]*(#|$)/ { print $1 }' \
        "$systemd_registry" | LC_ALL=C sort) >/dev/null ||
    fail systemd_inventory_incomplete

while IFS=$'\t' read -r lifecycle_source lifecycle_state \
    lifecycle_deployable lifecycle_target lifecycle_mode lifecycle_authority; do
    [[ -n "$lifecycle_source" && "$lifecycle_source" != \#* ]] || continue
    : "$lifecycle_state" "$lifecycle_target" "$lifecycle_mode" "$lifecycle_authority"
    lifecycle_file=$repository_root/$lifecycle_source
    [[ -f "$lifecycle_file" && ! -L "$lifecycle_file" ]] ||
        fail "source_${lifecycle_source##*/}"
    if [[ "$lifecycle_deployable" == yes && "$lifecycle_source" == Caddy/scripts/* ]]; then
        [[ -x "$lifecycle_file" ]] || fail "executable_${lifecycle_source##*/}"
    fi
done < <(sed -e '/^[[:space:]]*#/d' -e '/^[[:space:]]*$/d' \
    "$script_registry" "$systemd_registry")

require_row() {
    local lifecycle_registry=$1
    local lifecycle_row=$2

    grep -Fxq "$lifecycle_row" "$lifecycle_registry" ||
        fail "required_${lifecycle_row%%$'\t'*}"
}

require_row "$script_registry" $'Caddy/scripts/caddy-sync-release-receiver-v2\tproduction-current\tyes\t/usr/local/libexec/caddy-sync-release-receiver-v2\t0755\tCaddy/manifests/synchronization-protocol-v2.yaml'
require_row "$script_registry" $'Caddy/scripts/caddy-apprise-delivery-worker.sh\tproduction-current\tyes\t/usr/local/libexec/caddy-apprise-delivery-worker\t0755\tCaddy/manifests/durable-apprise-action34.tsv'
require_row "$script_registry" $'Caddy/scripts/caddy-apprise-enqueue.sh\tproduction-current\tyes\t/usr/local/libexec/caddy-apprise-enqueue\t0755\tCaddy/manifests/durable-apprise-action34.tsv'
require_row "$script_registry" $'Caddy/scripts/check-caddy-vrrp-action20h.sh\tproduction-current\tyes\t/usr/local/libexec/check-caddy.sh\t0755\tCaddy/manifests/production-artifacts.tsv'
require_row "$script_registry" $'Caddy/scripts/check-certificate-expiry.sh\tproduction-current\tyes\t/usr/local/libexec/check-certificate-expiry.sh\t0755\tCaddy/systemd/caddy-cert-expiry.service'
require_row "$script_registry" $'Caddy/scripts/finalize-incoming-release-v2-stderr-safe-trigger-action28ac.sh\tproduction-current\tyes\t/usr/local/libexec/finalize-incoming-release-v2.sh\t0755\tCaddy/manifests/production-artifacts.tsv'
require_row "$script_registry" $'Caddy/scripts/lsyncd-sync-failure-notify.sh\tproduction-current\tyes\t/usr/local/libexec/lsyncd-sync-failure-notify.sh\t0755\tCaddy/systemd/caddy-sync-failure@.service'
require_row "$script_registry" $'Caddy/scripts/prepare-lighttpd-config.sh\tproduction-current\tyes\t/usr/local/libexec/prepare-lighttpd-config.sh\t0755\tCaddy/configs/lighttpd/desired-state.conf'
require_row "$script_registry" $'Caddy/scripts/publish-release-v2.sh\tproduction-current\tyes\t/usr/local/libexec/publish-release-v2.sh\t0755\tCaddy/manifests/production-artifacts.tsv'
require_row "$script_registry" $'Caddy/scripts/reconcile-release-v2.sh\tproduction-current\tyes\t/usr/local/libexec/reconcile-release.sh\t0755\tCaddy/manifests/production-artifacts.tsv'
require_row "$script_registry" $'Caddy/scripts/validate-sync-health.sh\tproduction-current\tyes\t/usr/local/libexec/validate-sync-health.sh\t0755\tCaddy/manifests/production-artifacts.tsv'
require_row "$systemd_registry" $'Caddy/systemd/caddy-pihole-backend.service\trejected\tno\t-\t-\tCaddy/manifests/pihole-admin-backend-action28k.yaml'

readonly -a expected_installable_scripts=(
    Caddy/scripts/caddy-apprise-delivery-worker.sh
    Caddy/scripts/caddy-apprise-enqueue.sh
    Caddy/scripts/caddy-sync-release-receiver-v2
    Caddy/scripts/check-caddy-vrrp-action20h.sh
    Caddy/scripts/check-certificate-expiry.sh
    Caddy/scripts/finalize-incoming-release-v2-stderr-safe-trigger-action28ac.sh
    Caddy/scripts/lsyncd-sync-failure-notify.sh
    Caddy/scripts/prepare-lighttpd-config.sh
    Caddy/scripts/publish-release-v2.sh
    Caddy/scripts/reconcile-release-v2.sh
    Caddy/scripts/validate-sync-health.sh
)
diff -u \
    <(printf '%s\n' "${expected_installable_scripts[@]}" | LC_ALL=C sort) \
    <(awk -F '\t' '$2 == "production-current" && $3 == "yes" { print $1 }' \
        "$script_registry" | LC_ALL=C sort) >/dev/null ||
    fail unexpected_installable_script

readonly -a expected_installable_systemd=(
    caddy-apprise-worker.path
    caddy-apprise-worker.service
    caddy-apprise-worker.timer
    caddy-cert-expiry.service
    caddy-cert-expiry.timer
    caddy-lsyncd.service
    caddy-sync-failure@.service
    caddy-sync-health.service
    caddy-sync-health.timer
    caddy-sync-reconcile.path
    caddy-sync-reconcile.service
    caddy.service.d/override.conf
    lighttpd.service.d/caddy-ha.conf
)
for lifecycle_systemd_relative in "${expected_installable_systemd[@]}"; do
    lifecycle_systemd_authority=Caddy/manifests/production-artifacts.tsv
    case "$lifecycle_systemd_relative" in
        caddy-apprise-worker.*) lifecycle_systemd_authority=Caddy/manifests/durable-apprise-action34.tsv ;;
    esac
    require_row "$systemd_registry" \
        "Caddy/systemd/$lifecycle_systemd_relative"$'\tproduction-current\tyes\t'"/etc/systemd/system/$lifecycle_systemd_relative"$'\t0644\t'"$lifecycle_systemd_authority"
done
diff -u \
    <(printf 'Caddy/systemd/%s\n' "${expected_installable_systemd[@]}" | LC_ALL=C sort) \
    <(awk -F '\t' '$2 == "production-current" && $3 == "yes" { print $1 }' \
        "$systemd_registry" | LC_ALL=C sort) >/dev/null ||
    fail unexpected_installable_systemd

while IFS= read -r lifecycle_exec; do
    [[ -n "$lifecycle_exec" ]] || continue
    awk -F '\t' -v target="$lifecycle_exec" '
        $2 == "production-current" && $3 == "yes" && $4 == target { found++ }
        END { exit(found == 1 ? 0 : 1) }
    ' "$script_registry" || fail "systemd_exec_${lifecycle_exec##*/}"
done < <(awk -F= '/^ExecStart=\/usr\/local\/libexec\// {
    split($2, part, /[[:space:]]+/); print part[1]
}' "$repository_root"/Caddy/systemd/*.service | LC_ALL=C sort -u)

forced_receiver=$(awk '$1 == "forced_command:" { print $2; exit }' \
    "$synchronization_manifest")
awk -F '\t' -v target="$forced_receiver" '
    $2 == "production-current" && $3 == "yes" && $4 == target { found++ }
    END { exit(found == 1 ? 0 : 1) }
' "$script_registry" || fail forced_receiver_unregistered

while IFS= read -r inventory_source; do
    awk -F '\t' -v source="$inventory_source" '
        $1 == source && $2 == "production-current" { found++ }
        END { exit(found == 1 ? 0 : 1) }
    ' "$script_registry" || fail "production_source_${inventory_source##*/}"
done < <(awk -F '\t' '$2 == "homelab-server-configs" && $3 ~ /^Caddy\/scripts\// { print $3 }' \
    "$production_inventory" | LC_ALL=C sort -u)

validate_node_inventory_pair() {
    local inventory_source=$1
    local inventory_target=$2
    local inventory_authority=$3

    awk -F '\t' -v source="$inventory_source" -v target="$inventory_target" '
        /^[[:space:]]*(#|$)/ { next }
        $2 == "homelab-server-configs" && $3 == source {
            total++
            if ($4 != target || $5 !~ /^node-[ab]$/) bad = 1
            nodes[$5]++
        }
        END {
            exit(bad || total != 2 || nodes["node-a"] != 1 ||
                nodes["node-b"] != 1 ? 1 : 0)
        }
    ' "$production_inventory" && return 0

    [[ "$inventory_authority" = Caddy/manifests/durable-apprise-action34.tsv ]] || return 1
    awk -F '\t' -v source="$inventory_source" -v target="$inventory_target" '
        /^[[:space:]]*(#|$)/ { next }
        $1 == source && $2 == target { found++ }
        END { exit(found == 1 ? 0 : 1) }
    ' "$repository_root/$inventory_authority"
}

while IFS=$'\t' read -r lifecycle_source lifecycle_state \
    lifecycle_deployable lifecycle_target lifecycle_mode lifecycle_authority; do
    [[ -n "$lifecycle_source" && "$lifecycle_source" != \#* ]] || continue
    : "$lifecycle_state" "$lifecycle_mode" "$lifecycle_authority"
    [[ "$lifecycle_deployable" == yes ]] || continue
    validate_node_inventory_pair "$lifecycle_source" "$lifecycle_target" \
        "$lifecycle_authority" ||
        fail "node_inventory_${lifecycle_source##*/}"
done < <(sed -e '/^[[:space:]]*#/d' -e '/^[[:space:]]*$/d' \
    "$script_registry" "$systemd_registry")

readonly installer_script_registry_call="install_registered \"\$script_lifecycle\""
readonly installer_systemd_registry_call="install_registered \"\$systemd_lifecycle\""
readonly installer_systemd_tree_call="install_tree \"\$caddy_root/systemd\""
readonly validator_script_registry_call="validate_registered \"\$script_lifecycle\""
readonly validator_systemd_registry_call="validate_registered \"\$systemd_lifecycle\""
readonly uninstaller_script_registry_call="append_registered_paths \"\$caddy_root/manifests/script-lifecycle.tsv\""
readonly uninstaller_systemd_registry_call="append_registered_paths \"\$caddy_root/manifests/systemd-lifecycle.tsv\""

grep -Fq "$installer_script_registry_call" "$installer" ||
    fail installer_script_registry_missing
grep -Fq "$installer_systemd_registry_call" "$installer" ||
    fail installer_systemd_registry_missing
if grep -Fq "$installer_systemd_tree_call" "$installer"; then
    fail installer_systemd_tree_copy
fi
if grep -Fq 'configs/munin/' "$installer"; then
    fail installer_deferred_munin
fi
grep -Fq "$validator_script_registry_call" "$validator" ||
    fail validator_script_registry_missing
grep -Fq "$validator_systemd_registry_call" "$validator" ||
    fail validator_systemd_registry_missing
grep -Fq "$uninstaller_script_registry_call" \
    "$uninstaller" || fail uninstaller_script_registry_missing
grep -Fq "$uninstaller_systemd_registry_call" \
    "$uninstaller" || fail uninstaller_systemd_registry_missing

if grep -Fq '/etc/keepalived/' "$validator" ||
    grep -Fq '/etc/keepalived/' "$uninstaller"; then
    fail external_keepalived_consumer
fi

printf '%s_check_script_inventory=true\n' "$prefix"
printf '%s_check_systemd_inventory=true\n' "$prefix"
printf '%s_check_runtime_dependencies=true\n' "$prefix"
printf '%s_check_node_inventory_pairs=true\n' "$prefix"
printf '%s_check_installer_allowlist=true\n' "$prefix"
printf '%s_complete=true\n' "$prefix"
