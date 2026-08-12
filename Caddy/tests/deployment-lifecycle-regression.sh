#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
readonly repository_root=${test_directory%/Caddy/tests}
readonly caddy_root=$repository_root/Caddy
work_directory=$(mktemp -d /tmp/caddy-deployment-lifecycle.XXXXXX)
readonly work_directory
trap 'rm -rf -- "$work_directory"' EXIT

/bin/bash "$test_directory/deployment-lifecycle-policy.sh" --check >/dev/null

/bin/bash "$caddy_root/scripts/reconcile-release-v2.sh" \
    --candidate-selection-self-test >/dev/null

for direct_notifier_consumer in \
    "$caddy_root/scripts/check-certificate-expiry.sh" \
    "$caddy_root/scripts/reconcile-release-v2.sh" \
    "$caddy_root/scripts/validate-sync-health.sh"; do
    if grep -Fq '/usr/local/libexec/lsyncd-sync-failure-notify.sh' \
        "$direct_notifier_consumer"; then
        exit 1
    fi
done
grep -Fxq 'OnFailure=caddy-sync-failure@%n.service' \
    "$caddy_root/systemd/caddy-cert-expiry.service"
grep -Fxq 'OnFailure=caddy-sync-failure@%n.service' \
    "$caddy_root/systemd/caddy-sync-health.service"
grep -Fxq 'OnFailure=caddy-sync-failure@%n.service' \
    "$caddy_root/systemd/caddy-sync-reconcile.service"
grep -Fxq \
    'ExecStart=/usr/local/libexec/lsyncd-sync-failure-notify.sh "systemd unit failed: %i"' \
    "$caddy_root/systemd/caddy-sync-failure@.service"

grep -Fxq 'EnvironmentFile=/etc/default/caddy-ha' \
    "$caddy_root/systemd/caddy.service.d/override.conf"
if grep -Fq 'EnvironmentFile=-/etc/default/caddy-ha' \
    "$caddy_root/systemd/caddy.service.d/override.conf"; then
    exit 1
fi
grep -Fxq 'ReadOnlyPaths=/etc/lsyncd /var/lib/caddy-sync' \
    "$caddy_root/systemd/caddy-lsyncd.service"
grep -Fxq 'ReadWritePaths=/run/caddy-lsyncd' \
    "$caddy_root/systemd/caddy-lsyncd.service"
if grep -Eq '^ReadWritePaths=.*var/lib/caddy-sync' \
    "$caddy_root/systemd/caddy-lsyncd.service"; then
    exit 1
fi
grep -Fxq 'ProtectSystem=strict' "$caddy_root/systemd/caddy-lsyncd.service"
grep -Fxq 'UMask=0077' "$caddy_root/systemd/caddy-lsyncd.service"
if grep -Fxq 'Persistent=true' "$caddy_root/systemd/caddy-sync-health.timer"; then
    exit 1
fi

for rejected_component in keepalived munin; do
    rejected_status=0
    /bin/bash "$caddy_root/scripts/install-caddy-ha.sh" \
        --node node-a --component "$rejected_component" --dry-run \
        >"$work_directory/$rejected_component.stdout" \
        2>"$work_directory/$rejected_component.stderr" || rejected_status=$?
    [[ "$rejected_status" -eq 2 ]]
    [[ ! -s "$work_directory/$rejected_component.stdout" ]]
done
grep -Fxq \
    'Keepalived is externally owned by homelab-dns/Keepalived/configs; installation from Caddy is prohibited.' \
    "$work_directory/keepalived.stderr"
grep -Fxq \
    'Munin integration is deferred and cannot be installed by this script.' \
    "$work_directory/munin.stderr"

negative_root=$work_directory/negative-repository
readonly negative_root
install -d -m 0700 "$negative_root/Caddy/manifests"
cp -a -- \
    "$caddy_root/scripts" \
    "$caddy_root/systemd" \
    "$negative_root/Caddy/"
cp -- \
    "$caddy_root/manifests/script-lifecycle.tsv" \
    "$caddy_root/manifests/systemd-lifecycle.tsv" \
    "$caddy_root/manifests/production-artifacts.tsv" \
    "$caddy_root/manifests/synchronization-protocol-v2.yaml" \
    "$negative_root/Caddy/manifests/"
sed -i \
    's|Caddy/scripts/caddy-sync-rsync-receiver\thistorical-superseded\tno\t-\t-|Caddy/scripts/caddy-sync-rsync-receiver\tproduction-current\tyes\t/usr/local/libexec/caddy-sync-rsync-receiver\t0755|' \
    "$negative_root/Caddy/manifests/script-lifecycle.tsv"
negative_status=0
/bin/bash "$test_directory/deployment-lifecycle-policy.sh" --check \
    --repository-root "$negative_root" >/dev/null 2>&1 || negative_status=$?
[[ "$negative_status" -eq 1 ]]
cp -- "$caddy_root/manifests/script-lifecycle.tsv" \
    "$negative_root/Caddy/manifests/script-lifecycle.tsv"
sed -i \
    's|Caddy/systemd/caddy-pihole-backend.service\trejected\tno\t-\t-|Caddy/systemd/caddy-pihole-backend.service\tproduction-current\tyes\t/etc/systemd/system/caddy-pihole-backend.service\t0644|' \
    "$negative_root/Caddy/manifests/systemd-lifecycle.tsv"
negative_status=0
/bin/bash "$test_directory/deployment-lifecycle-policy.sh" --check \
    --repository-root "$negative_root" >/dev/null 2>&1 || negative_status=$?
[[ "$negative_status" -eq 1 ]]
cp -- "$caddy_root/manifests/systemd-lifecycle.tsv" \
    "$negative_root/Caddy/manifests/systemd-lifecycle.tsv"
sed -i '/^node_b_cert_expiry_service\t/d' \
    "$negative_root/Caddy/manifests/production-artifacts.tsv"
negative_status=0
/bin/bash "$test_directory/deployment-lifecycle-policy.sh" --check \
    --repository-root "$negative_root" >/dev/null 2>&1 || negative_status=$?
[[ "$negative_status" -eq 1 ]]

root=$work_directory/root
certificate_directory=$work_directory/certificates
readonly root certificate_directory
install -d -m 0700 \
    "$certificate_directory" \
    "$root/etc/keepalived/conf.d" \
    "$root/etc/munin/plugin-conf.d"
for certificate_file in \
    leaf.pem intermediates.pem fullchain.pem privkey.pem certificate-manifest.json; do
    printf 'fixture-%s\n' "$certificate_file" >"$certificate_directory/$certificate_file"
done
printf 'externally-owned\n' >"$root/etc/keepalived/conf.d/caddy-ha.conf"
printf 'deferred-owned\n' >"$root/etc/munin/plugin-conf.d/caddy-ha"

/bin/bash "$caddy_root/scripts/install-caddy-ha.sh" \
    --node node-a \
    --root "$root" \
    --certificate-dir "$certificate_directory" \
    --component all >"$work_directory/install.json"
jq -e '.node == "node-a" and .component == "all" and .service_mutations == false' \
    "$work_directory/install.json" >/dev/null

awk -F '\t' '$2 == "production-current" && $3 == "yes" {
    sub("^/usr/local/libexec/", "", $4); print $4
}' "$caddy_root/manifests/script-lifecycle.tsv" | LC_ALL=C sort \
    >"$work_directory/expected-scripts"
find "$root/usr/local/libexec" -maxdepth 1 -type f -printf '%f\n' |
    LC_ALL=C sort >"$work_directory/observed-scripts"
cmp --silent "$work_directory/expected-scripts" \
    "$work_directory/observed-scripts"

awk -F '\t' '$2 == "production-current" && $3 == "yes" {
    sub("^/etc/systemd/system/", "", $4); print $4
}' "$caddy_root/manifests/systemd-lifecycle.tsv" | LC_ALL=C sort \
    >"$work_directory/expected-systemd"
find "$root/etc/systemd/system" -type f -printf '%P\n' | LC_ALL=C sort \
    >"$work_directory/observed-systemd"
cmp --silent "$work_directory/expected-systemd" \
    "$work_directory/observed-systemd"

[[ ! -e "$root/etc/systemd/system/caddy-pihole-backend.service" ]]
[[ ! -e "$root/usr/local/libexec/caddy-sync-rsync-receiver" ]]
[[ ! -e "$root/usr/local/libexec/lsyncd-ha-failover-notify.sh" ]]
[[ ! -e "$root/usr/local/libexec/publish-release.sh" ]]
grep -Fxq externally-owned "$root/etc/keepalived/conf.d/caddy-ha.conf"
grep -Fxq deferred-owned "$root/etc/munin/plugin-conf.d/caddy-ha"

/bin/bash "$caddy_root/scripts/validate-caddy-ha.sh" \
    --node node-a --root "$root" >/dev/null

install -m 0755 "$caddy_root/scripts/caddy-sync-rsync-receiver" \
    "$root/usr/local/libexec/caddy-sync-rsync-receiver"
if /bin/bash "$caddy_root/scripts/validate-caddy-ha.sh" \
    --node node-a --root "$root" >/dev/null 2>&1; then
    printf 'Validator accepted a superseded receiver.\n' >&2
    exit 1
fi
rm -- "$root/usr/local/libexec/caddy-sync-rsync-receiver"

printf 'drift\n' >>"$root/usr/local/libexec/caddy-sync-release-receiver-v2"
if /bin/bash "$caddy_root/scripts/validate-caddy-ha.sh" \
    --node node-a --root "$root" >/dev/null 2>&1; then
    printf 'Validator accepted current-artifact drift.\n' >&2
    exit 1
fi
install -m 0755 "$caddy_root/scripts/caddy-sync-release-receiver-v2" \
    "$root/usr/local/libexec/caddy-sync-release-receiver-v2"

/bin/bash "$caddy_root/scripts/uninstall-caddy-ha.sh" \
    --node node-a --root "$root" >"$work_directory/uninstall.json"
jq -e '.node == "node-a" and .service_mutations == false' \
    "$work_directory/uninstall.json" >/dev/null
grep -Fxq externally-owned "$root/etc/keepalived/conf.d/caddy-ha.conf"
grep -Fxq deferred-owned "$root/etc/munin/plugin-conf.d/caddy-ha"

while IFS=$'\t' read -r lifecycle_source lifecycle_state \
    lifecycle_deployable lifecycle_target lifecycle_mode lifecycle_authority; do
    [[ -n "$lifecycle_source" && "$lifecycle_source" != \#* ]] || continue
    : "$lifecycle_mode" "$lifecycle_authority"
    [[ "$lifecycle_state" == production-current &&
        "$lifecycle_deployable" == yes ]] || continue
    [[ ! -e "$root$lifecycle_target" && ! -L "$root$lifecycle_target" ]]
done < <(sed -e '/^[[:space:]]*#/d' -e '/^[[:space:]]*$/d' \
    "$caddy_root/manifests/script-lifecycle.tsv" \
    "$caddy_root/manifests/systemd-lifecycle.tsv")

printf 'deployment_lifecycle_regression_complete=true\n'
