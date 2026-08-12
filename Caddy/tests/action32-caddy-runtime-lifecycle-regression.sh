#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_32_regression
test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
readonly repository_root=${test_directory%/Caddy/tests}
readonly transaction=$repository_root/Caddy/scripts/apply-caddy-runtime-lifecycle-action32.sh
readonly outer=$repository_root/Caddy/scripts/run-dual-node-caddy-runtime-lifecycle-action32-outer.sh
readonly artifact_manifest=$repository_root/Caddy/manifests/caddy-runtime-lifecycle-action32.tsv
fixture_root=

file_hash() { sha256sum -- "$1" | awk '{ print $1 }'; }
fail() {
    printf '%s_failure=%s\n' "$prefix" "$1" >&2
    exit 1
}
cleanup() {
    [[ -z "$fixture_root" || ! -d "$fixture_root" ]] || rm -rf -- "$fixture_root"
}
trap cleanup EXIT INT TERM

for action32_regression_file in "$transaction" "$outer" "$artifact_manifest"; do
    [[ -f "$action32_regression_file" && ! -L "$action32_regression_file" ]] ||
        fail "required_${action32_regression_file##*/}"
done

awk -F '\t' '
    /^[[:space:]]*(#|$)/ { next }
    NF != 5 { exit 1 }
    $1 !~ /^Caddy\/(scripts|systemd)\// { exit 1 }
    $2 !~ /^\/(usr\/local\/libexec|etc\/systemd\/system)\// { exit 1 }
    $3 !~ /^0(644|755)$/ { exit 1 }
    length($4) != 64 || $4 !~ /^[0-9a-f]+$/ { exit 1 }
    length($5) != 64 || $5 !~ /^[0-9a-f]+$/ { exit 1 }
    source[$1]++ || target[$2]++ { exit 1 }
    { count++ }
    END { exit(count == 10 ? 0 : 1) }
' "$artifact_manifest" || fail manifest_contract

while IFS=$'\t' read -r action32_regression_source action32_regression_target \
    action32_regression_mode action32_regression_baseline action32_regression_candidate; do
    [[ -n "$action32_regression_source" && "$action32_regression_source" != \#* ]] || continue
    : "$action32_regression_target" "$action32_regression_mode" "$action32_regression_baseline"
    [[ "$(file_hash "$repository_root/$action32_regression_source")" = "$action32_regression_candidate" ]] || fail "source_${action32_regression_source##*/}"
done <"$artifact_manifest"

for action32_regression_required in \
    'systemctl stop caddy-sync-reconcile.path caddy-lsyncd.service' \
    'systemctl daemon-reload' \
    'systemctl start caddy-lsyncd.service' \
    'systemctl start caddy-sync-reconcile.path' \
    'systemctl restart caddy-cert-expiry.timer' \
    'systemctl restart caddy-sync-health.timer' \
    'systemctl start caddy-cert-expiry.service' \
    'systemctl start caddy-sync-health.service' \
    'systemctl start caddy-sync-reconcile.service' \
    'ReadWritePaths=/run/caddy-lsyncd' \
    'EnvironmentFile=/etc/default/caddy-ha' \
    'post_cursor_clean' \
    'manual_intervention_required=true'; do
    grep -Fq "$action32_regression_required" "$transaction" ||
        fail "transaction_${action32_regression_required//[^a-zA-Z0-9]/_}"
done

if grep -Eq 'systemctl (reload|restart) (caddy|keepalived)\.service' "$transaction"; then
    fail prohibited_runtime_reload
fi
grep -Fq 'node_b_mutated=true' "$outer" || fail standby_first_node_b
grep -Fq 'node_a_mutated=true' "$outer" || fail standby_first_node_a
node_b_line=$(grep -nF 'node_b_mutated=true' "$outer" | cut -d: -f1)
node_a_line=$(grep -nF 'node_a_mutated=true' "$outer" | cut -d: -f1)
[[ "$node_b_line" -lt "$node_a_line" ]] || fail standby_order
grep -Fq 'tar --sort=name --mtime=' "$outer" || fail deterministic_archive
grep -Fq 'cd / && sudo -n /bin/bash -s --' "$outer" || fail remote_cwd
grep -Fq '/tmp/caddy-action32-payload-' "$outer" || fail remote_payload_path
grep -Fq 'prepare_capture' "$outer" || fail capture_precreation

fixture_root=$(mktemp -d /tmp/action32-regression.XXXXXX) || fail fixture_root
install -d -m 0700 "$fixture_root/payload/Caddy/manifests" || fail fixture_manifest_directory
install -m 0600 "$artifact_manifest" \
    "$fixture_root/payload/Caddy/manifests/${artifact_manifest##*/}" || fail fixture_manifest
while IFS=$'\t' read -r action32_regression_source action32_regression_target \
    action32_regression_mode action32_regression_baseline action32_regression_candidate; do
    [[ -n "$action32_regression_source" && "$action32_regression_source" != \#* ]] || continue
    : "$action32_regression_target" "$action32_regression_mode" \
        "$action32_regression_baseline" "$action32_regression_candidate"
    install -d -m 0700 "$fixture_root/payload/${action32_regression_source%/*}" ||
        fail fixture_source_directory
    install -m 0600 "$repository_root/$action32_regression_source" \
        "$fixture_root/payload/$action32_regression_source" || fail fixture_source
done <"$artifact_manifest"
tar --sort=name --mtime='@0' --owner=0 --group=0 --numeric-owner \
    --format=ustar -cf "$fixture_root/payload.tar" -C "$fixture_root/payload" . ||
    fail fixture_archive
fixture_hash=$(file_hash "$fixture_root/payload.tar") || fail fixture_hash
/bin/bash "$transaction" --validate-payload node-a "$fixture_root/payload.tar" \
    "$fixture_hash" >/dev/null || fail real_payload_validation

cp "$fixture_root/payload.tar" "$fixture_root/tampered.tar" || fail tampered_copy
printf 'x' >>"$fixture_root/tampered.tar" || fail tampered_write
if /bin/bash "$transaction" --validate-payload node-a "$fixture_root/tampered.tar" \
    "$fixture_hash" >/dev/null 2>&1; then
    fail tampered_archive_accepted
fi

/bin/bash "$repository_root/Caddy/scripts/reconcile-release-v2.sh" \
    --candidate-selection-self-test >/dev/null || fail candidate_drain_self_test

printf '%s_artifact_count=10\n' "$prefix"
printf '%s_real_payload_validated=true\n' "$prefix"
printf '%s_complete=true\n' "$prefix"
