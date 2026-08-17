#!/usr/bin/env bash
# shellcheck disable=SC2016 # Remote Bash programs intentionally expand only on the node.

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly action35h_outer_prefix=action_35h_outer
readonly transaction_sha256=f77dc10659ec610fb88a5ac1371e083ce3ac5e442ce2a334e17dabc75441986a
readonly action35h_outer_node_a=pi@10.1.0.53
readonly action35h_outer_node_b=pi@10.1.0.54
readonly action35h_outer_remote_root=/tmp/caddy-action35h-upload
readonly action35h_outer_original_revision=${ACTION35H_EXPECTED_ORIGINAL_REVISION:-20260811T180754Z-d7816a72-48c7-461c-a86f-451027f5de04}
readonly action35h_outer_revision=${ACTION35H_EXPECTED_REVISION:-20260817T160328Z-472d68b9-2bfb-40f1-8563-0754067182ca}
readonly action35h_outer_release_manifest_sha256=${ACTION35H_EXPECTED_RELEASE_MANIFEST_SHA256:-6049da00c0e7318c3fce98bc6cc78348ded5286998a346f00657df8c1d2a046d}
readonly action35h_outer_payload_manifest_sha256=${ACTION35H_EXPECTED_PAYLOAD_MANIFEST_SHA256:-ecb1a00827899bffc47d9e180b4f0a19a6daf0fc4beee9cb52898a9608102962}

action35h_outer_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly action35h_outer_directory
readonly action35h_outer_repository=${action35h_outer_directory%/Caddy/scripts}
readonly action35h_outer_transaction_source=$action35h_outer_directory/apply-coupled-serving-health-action35h.sh
readonly action35h_outer_manifest=$action35h_outer_repository/Caddy/manifests/serving-health-production.tsv
readonly action35h_outer_state=$action35h_outer_repository/Caddy/manifests/current-live-state.tsv
readonly action35h_outer_protocol_manifest=$action35h_outer_repository/Caddy/manifests/synchronization-protocol-v2.yaml
readonly action35h_outer_ssh_command=${ACTION35H_SSH_COMMAND:-ssh}
readonly action35h_outer_scp_command=${ACTION35H_SCP_COMMAND:-scp}
action35h_outer_node_a_mutated=false
action35h_outer_node_b_mutated=false
action35h_outer_node_a_upload_present=false
action35h_outer_node_b_upload_present=false
action35h_outer_recovery_failed=false
action35h_outer_probe_pid=

if [[ "${1:-}" = --production-path-test && $# -eq 1 ]]; then
    exec /bin/bash "$action35h_outer_repository/Caddy/tests/coupled-serving-health-deployment-regression.sh" \
        --entrypoint outer
fi

action35h_outer_test_mode=false
if [[ "${1:-}" = --production-path-test-inner && $# -eq 1 ]]; then
    action35h_outer_test_mode=true
elif (($#)); then
    exit 64
fi
if [[ "$action35h_outer_test_mode" = false ]]; then
    [[ -z "${ACTION35H_EXPECTED_ORIGINAL_REVISION:-}" ]]
    [[ -z "${ACTION35H_EXPECTED_REVISION:-}" ]]
    [[ -z "${ACTION35H_EXPECTED_RELEASE_MANIFEST_SHA256:-}" ]]
    [[ -z "${ACTION35H_EXPECTED_PAYLOAD_MANIFEST_SHA256:-}" ]]
fi
[[ "$action35h_outer_original_revision" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]
[[ "$action35h_outer_revision" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]
[[ "$action35h_outer_release_manifest_sha256" =~ ^[0-9a-f]{64}$ ]]
[[ "$action35h_outer_payload_manifest_sha256" =~ ^[0-9a-f]{64}$ ]]
cd -- "$action35h_outer_repository"

action35h_outer_final_directory_mode=$(awk '
    $1 == "final_directory_mode:" {
        gsub(/"/, "", $2)
        print $2
        count++
    }
    END { exit(count == 1 ? 0 : 1) }
' "$action35h_outer_protocol_manifest")
readonly action35h_outer_final_directory_mode
[[ "$action35h_outer_final_directory_mode" =~ ^0[0-7]{3}$ ]]
for action35h_outer_mode_implementation in \
    Caddy/scripts/publish-release-v2.sh \
    Caddy/scripts/reconcile-release-v2.sh \
    Caddy/scripts/finalize-incoming-release-v2.sh; do
    grep -Fq -- "chmod $action35h_outer_final_directory_mode" \
        "$action35h_outer_mode_implementation"
done
action35h_outer_final_owner=$(awk '
    $1 == "chown" && $2 == "-R" && $4 == "\"$destination\"" {
        print $3
        count++
    }
    END { exit(count == 1 ? 0 : 1) }
' Caddy/scripts/reconcile-release-v2.sh)
readonly action35h_outer_final_owner
[[ "$action35h_outer_final_owner" = root:caddy-tls ]]

if [[ "$action35h_outer_test_mode" = false ]]; then
    /bin/bash Caddy/tests/deployable-successor-policy.sh --authorization-ready >/dev/null
    /bin/bash Caddy/tests/coupled-serving-health-deployment-regression.sh >/dev/null
fi
[[ "$(sha256sum "$action35h_outer_transaction_source" | awk '{ print $1 }')" = "$transaction_sha256" ]] || exit 1

action35h_outer_evidence=/tmp/caddy-ssh-evidence/action35h
if [[ "$action35h_outer_test_mode" = true ]]; then
    [[ "${CADDY_ACTION35H_PRODUCTION_TEST_ROOT:-}" = /tmp/* ]] || exit 64
    action35h_outer_evidence=$CADDY_ACTION35H_PRODUCTION_TEST_ROOT/ssh-evidence
fi
readonly action35h_outer_evidence
[[ ! -e "$action35h_outer_evidence" ]] || exit 1
install -d -m 0700 "$(dirname -- "$action35h_outer_evidence")" "$action35h_outer_evidence"
action35h_outer_payload=$(mktemp -d /tmp/caddy-action35h-payload.XXXXXX)
readonly action35h_outer_payload
trap 'rm -rf -- "$action35h_outer_payload"' EXIT INT TERM

install -d -m 0700 \
    "$action35h_outer_payload/files/homelab-server-configs" \
    "$action35h_outer_payload/files/homelab-dns" \
    "$action35h_outer_payload/remote"
install -m 0600 "$action35h_outer_manifest" \
    "$action35h_outer_payload/serving-health-production.tsv"
install -m 0600 "$action35h_outer_state" "$action35h_outer_payload/current-live-state.tsv"
install -m 0600 "$action35h_outer_protocol_manifest" \
    "$action35h_outer_payload/synchronization-protocol-v2.yaml"
install -m 0600 "$action35h_outer_repository/Caddy/manifests/production-artifacts.tsv" \
    "$action35h_outer_payload/production-artifacts.tsv"
install -m 0700 "$action35h_outer_transaction_source" "$action35h_outer_payload/transaction.sh"

while IFS=$'\t' read -r action35h_outer_repository_name action35h_outer_source \
    _ _ _ _; do
    [[ -n "$action35h_outer_repository_name" && "$action35h_outer_repository_name" != \#* ]] || continue
    action35h_outer_source_root=$action35h_outer_repository
    [[ "$action35h_outer_repository_name" = homelab-server-configs ]] ||
        action35h_outer_source_root=${action35h_outer_repository%/homelab-server-configs}/homelab-dns
    action35h_outer_destination=$action35h_outer_payload/files/$action35h_outer_repository_name/$action35h_outer_source
    install -d -m 0700 "$(dirname -- "$action35h_outer_destination")"
    install -m 0600 "$action35h_outer_source_root/$action35h_outer_source" \
        "$action35h_outer_destination"
done <"$action35h_outer_manifest"

cat >"$action35h_outer_payload/remote/validate-protocol-state.sh" <<'REMOTE'
#!/usr/bin/env bash
set -Eeuo pipefail
umask 077
readonly root_prefix=${ACTION35H_ROOT_PREFIX:-}
readonly role=$1
readonly original_revision=$2
readonly revision=$3
readonly expected_release_manifest_sha256=$4
readonly expected_payload_manifest_sha256=$5
[[ "$role" =~ ^node-[ab]$ ]]
[[ "$original_revision" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]
[[ "$revision" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]
[[ "$expected_release_manifest_sha256" =~ ^[0-9a-f]{64}$ ]]
[[ "$expected_payload_manifest_sha256" =~ ^[0-9a-f]{64}$ ]]
readonly current=$root_prefix/etc/caddy/current
readonly outbound=$root_prefix/var/lib/caddy-sync/outbound/$revision
readonly incoming_a=$root_prefix/var/lib/caddy-sync/incoming/node-a/$revision
readonly incoming_b=$root_prefix/var/lib/caddy-sync/incoming/node-b/$revision
readonly release=$root_prefix/etc/caddy/releases/$revision
readonly quarantine=$root_prefix/var/lib/caddy-sync/quarantine
readonly current_path=$(readlink -f -- "$current")
readonly expected_current=$(
    if [[ "$role" = node-a ]]; then
        printf '%s/etc/caddy/releases/%s' "$root_prefix" "$original_revision"
    else
        printf '%s/etc/caddy/releases/%s' "$root_prefix" "$revision"
    fi
)
[[ "$current_path" = "$expected_current" ]]
[[ ! -e "$incoming_a" && ! -L "$incoming_a" ]]
[[ ! -e "$incoming_b" && ! -L "$incoming_b" ]]
[[ -z "$(find "$quarantine" -mindepth 1 -maxdepth 1 -name "*$revision*" -print -quit 2>/dev/null)" ]]
if [[ "$role" = node-a ]]; then
    [[ -d "$outbound" && ! -L "$outbound" ]]
    if [[ -z "$root_prefix" || "${CADDY_VALIDATION_CONTAINER:-0}" = 1 ]]; then
        [[ "$(stat -c '%U:%G:%a' "$outbound")" = caddy-sync:caddy-sync:550 ]]
    else
        [[ "$(stat -c '%a' "$outbound")" = 550 ]]
    fi
    [[ ! -e "$release" && ! -L "$release" ]]
    readonly payload=$outbound
    [[ -f "$payload/.finalize-request" && ! -s "$payload/.finalize-request" ]]
    [[ ! -e "$payload/.complete" && ! -L "$payload/.complete" ]]
else
    [[ ! -e "$outbound" && ! -L "$outbound" ]]
    [[ -d "$release" && ! -L "$release" ]]
    if [[ -z "$root_prefix" || "${CADDY_VALIDATION_CONTAINER:-0}" = 1 ]]; then
        [[ "$(stat -c '%U:%G:%a' "$release")" = root:caddy-tls:550 ]]
    else
        [[ "$(stat -c '%a' "$release")" = 550 ]]
    fi
    readonly payload=$release
    [[ -f "$payload/.complete" && ! -s "$payload/.complete" ]]
fi
[[ -f "$payload/release-manifest.json" && ! -L "$payload/release-manifest.json" ]]
[[ -f "$payload/manifest.sha256" && ! -L "$payload/manifest.sha256" ]]
[[ "$(sha256sum "$payload/release-manifest.json" | awk '{print $1}')" = "$expected_release_manifest_sha256" ]]
[[ "$(sha256sum "$payload/manifest.sha256" | awk '{print $1}')" = "$expected_payload_manifest_sha256" ]]
[[ "$(jq -er '.revision' "$payload/release-manifest.json")" = "$revision" ]]
[[ "$(jq -er '.parent_revision' "$payload/release-manifest.json")" = "$original_revision" ]]
[[ "$(jq -er '.source_node' "$payload/release-manifest.json")" = node-a ]]
(cd "$payload" && sha256sum --strict --check manifest.sha256 >/dev/null)
[[ -z "$(find "$payload" -type l -print -quit)" ]]
[[ -z "$(find "$payload" ! -type d ! -type f -print -quit)" ]]
printf 'protocol_role=%s\n' "$role"
printf 'protocol_current=%s\n' "$current_path"
printf 'protocol_payload=%s\n' "$payload"
printf 'protocol_revision=%s\n' "$revision"
printf 'protocol_parent=%s\n' "$original_revision"
printf 'protocol_source=node-a\n'
printf 'protocol_release_manifest_sha256=%s\n' "$expected_release_manifest_sha256"
printf 'protocol_payload_manifest_sha256=%s\n' "$expected_payload_manifest_sha256"
printf 'protocol_state=validated\n'
REMOTE
cat >"$action35h_outer_payload/remote/resolve-current.sh" <<'REMOTE'
#!/usr/bin/env bash
set -Eeuo pipefail
readonly root_prefix=${ACTION35H_ROOT_PREFIX:-}
readonly current=$root_prefix/etc/caddy/current
[[ -L "$current" ]]
resolved=$(readlink -f -- "$current")
[[ "$resolved" = "$root_prefix"/etc/caddy/releases/* ]]
[[ -d "$resolved" && ! -L "$resolved" ]]
[[ -f "$resolved/release-manifest.json" && ! -L "$resolved/release-manifest.json" ]]
printf '%s\n' "$resolved"
REMOTE
cat >"$action35h_outer_payload/remote/prepare-upload.sh" <<'REMOTE'
#!/usr/bin/env bash
set -Eeuo pipefail
umask 077
readonly root_prefix=${ACTION35H_ROOT_PREFIX:-}
readonly target=$root_prefix$1
[[ "$1" = /tmp/caddy-action35h-upload && ! -e "$target" && ! -L "$target" ]]
install -d -m 0700 "$target"
REMOTE
cat >"$action35h_outer_payload/remote/accept-upload.sh" <<'REMOTE'
#!/usr/bin/env bash
set -Eeuo pipefail
readonly root_prefix=${ACTION35H_ROOT_PREFIX:-}
readonly target=$root_prefix$1
[[ "$1" = /tmp/caddy-action35h-upload && -d "$target" && ! -L "$target" ]]
[[ -f "$target/payload.tar" && ! -L "$target/payload.tar" ]]
tar -tf "$target/payload.tar" >/dev/null
tar -C "$target" -xf "$target/payload.tar"
REMOTE
cat >"$action35h_outer_payload/remote/remove-tree.sh" <<'REMOTE'
#!/usr/bin/env bash
set -Eeuo pipefail
readonly target=$1
case "$target" in
    /tmp/caddy-action35h-upload | /var/backups/caddy-action35h/node-a | /var/backups/caddy-action35h/node-b) ;;
    *) exit 64 ;;
esac
[[ -d "$target" && ! -L "$target" ]]
if [[ -n "${ACTION35H_ROOT_PREFIX:-}" && $EUID -ne 0 ]]; then
    find "$target" -xdev -type d -exec chmod u+rwx {} +
fi
find "$target" -xdev -mindepth 1 -delete
rmdir "$target"
REMOTE
cat >"$action35h_outer_payload/remote/ownership.sh" <<'REMOTE'
#!/usr/bin/env bash
set -Eeuo pipefail
cd /
ipv4=$(timeout 2 busctl get-property org.keepalived.Vrrp1 /org/keepalived/Vrrp1/Instance/eth0/100/IPv4 org.keepalived.Vrrp1.Instance State)
ipv6=$(timeout 2 busctl get-property org.keepalived.Vrrp1 /org/keepalived/Vrrp1/Instance/eth0/101/IPv6 org.keepalived.Vrrp1.Instance State)
count=$(ip -o address show dev eth0 | awk '$4 ~ /^(10\.1\.0\.(55|56)\/22|fd36:5aa8:6971:1::(55|56)\/128)$/ { n++ } END { print n + 0 }')
printf 'ipv4=%s ipv6=%s vip_count=%s\n' "$ipv4" "$ipv6" "$count"
REMOTE
cat >"$action35h_outer_payload/remote/health.sh" <<'REMOTE'
#!/usr/bin/env bash
set -Eeuo pipefail
cd /
/usr/local/libexec/check-caddy.sh
/etc/scripts/check-dns.sh
REMOTE
cat >"$action35h_outer_payload/remote/restore-release.sh" <<'REMOTE'
#!/usr/bin/env bash
set -Eeuo pipefail
readonly original=$1
readonly revision=$2
readonly role=$3
readonly root_prefix=${ACTION35H_ROOT_PREFIX:-}
case "$original" in "$root_prefix"/etc/caddy/releases/*) ;; *) exit 64 ;; esac
[[ "$revision" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]
[[ "$role" =~ ^node-[ab]$ ]]
[[ -d "$original" && ! -L "$original" ]]
ln -sfn "${original#"$root_prefix/etc/caddy/"}" "$root_prefix/etc/caddy/current"
systemctl reload caddy.service
if [[ "$role" = node-a ]]; then
    readonly release=$root_prefix/etc/caddy/releases/$revision
    readonly outbound=$root_prefix/var/lib/caddy-sync/outbound/$revision
    readonly incoming=$root_prefix/var/lib/caddy-sync/incoming/node-a/$revision
    if [[ -e "$release" || -L "$release" ]]; then
        [[ -d "$release" && ! -L "$release" ]]
        [[ -d "$outbound" && ! -L "$outbound" ]]
        cmp -s "$release/manifest.sha256" "$outbound/manifest.sha256"
        if [[ -n "$root_prefix" && $EUID -ne 0 ]]; then
            find "$release" -xdev -type d -exec chmod u+rwx {} +
        fi
        find "$release" -xdev -mindepth 1 -delete
        rmdir "$release"
    fi
    if [[ -e "$incoming" || -L "$incoming" ]]; then
        [[ -d "$incoming" && ! -L "$incoming" ]]
        [[ -d "$outbound" && ! -L "$outbound" ]]
        cmp -s "$incoming/manifest.sha256" "$outbound/manifest.sha256"
        if [[ -n "$root_prefix" && $EUID -ne 0 ]]; then
            find "$incoming" -xdev -type d -exec chmod u+rwx {} +
        fi
        find "$incoming" -xdev -mindepth 1 -delete
        rmdir "$incoming"
    fi
fi
REMOTE
cat >"$action35h_outer_payload/remote/wait-revision.sh" <<'REMOTE'
#!/usr/bin/env bash
set -Eeuo pipefail
readonly expected_revision=$1
readonly root_prefix=${ACTION35H_ROOT_PREFIX:-}
[[ "$expected_revision" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]
for _ in $(seq 1 60); do
    if [[ "$(jq -r .revision "$root_prefix/etc/caddy/current/release-manifest.json")" = "$expected_revision" ]]; then
        exit 0
    fi
    sleep 1
done
exit 1
REMOTE
cat >"$action35h_outer_payload/remote/promote-release.sh" <<'REMOTE'
#!/usr/bin/env bash
set -Eeuo pipefail
cd /
readonly revision=$1
readonly root_prefix=${ACTION35H_ROOT_PREFIX:-}
[[ "$revision" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]
readonly outgoing=$root_prefix/var/lib/caddy-sync/outbound/$revision
readonly incoming=$root_prefix/var/lib/caddy-sync/incoming/node-a/$revision
[[ -d "$outgoing" && ! -L "$outgoing" && ! -e "$incoming" && ! -L "$incoming" ]]
[[ -f "$outgoing/.finalize-request" && ! -s "$outgoing/.finalize-request" ]]
[[ -f "$outgoing/manifest.sha256" && ! -L "$outgoing/manifest.sha256" ]]
(cd "$outgoing" && sha256sum --strict --check manifest.sha256 >/dev/null)
cp -a -- "$outgoing" "$incoming"
if [[ -z "$root_prefix" ]]; then
    chown -R caddy-sync:caddy-sync "$incoming"
fi
"$root_prefix/usr/local/libexec/finalize-incoming-release-v2.sh" --source-role node-a
systemctl start caddy-sync-reconcile.service
for _ in $(seq 1 60); do
    if [[ "$(jq -r .revision "$root_prefix/etc/caddy/current/release-manifest.json")" = "$revision" ]]; then
        exit 0
    fi
    sleep 1
done
exit 1
REMOTE
cat >"$action35h_outer_payload/remote/probe-availability.sh" <<'REMOTE'
#!/usr/bin/env bash
set -Eeuo pipefail
umask 077
readonly role=$1
readonly sample=$2
readonly root_prefix=${ACTION35H_ROOT_PREFIX:-}
[[ "$role" =~ ^node-[ab]$ ]]
[[ "$sample" =~ ^[1-9][0-9]*$ ]]
readonly evidence=$root_prefix/tmp/caddy-action35h-availability/$role/$sample
[[ ! -e "$evidence" && ! -L "$evidence" ]]
install -d -m 0700 "$evidence"
dig_command=dig
curl_command=curl
if [[ -n "$root_prefix" ]]; then
    dig_command=$root_prefix/bin/probe-dig
    curl_command=$root_prefix/bin/probe-curl
fi
capture() {
    local label=$1
    local probe_expected=$2
    shift 2
    local status=0
    "$@" >"$evidence/$label.stdout" 2>"$evidence/$label.stderr" || status=$?
    [[ "$(stat -c '%s' "$evidence/$label.stdout")" -le 4096 ]]
    [[ "$(stat -c '%s' "$evidence/$label.stderr")" -le 4096 ]]
    iconv -f UTF-8 -t UTF-8 "$evidence/$label.stdout" >/dev/null
    iconv -f UTF-8 -t UTF-8 "$evidence/$label.stderr" >/dev/null
    [[ -z "$(LC_ALL=C tr -d '\11\12\15\40-\176\200-\377' <"$evidence/$label.stdout")" ]]
    [[ -z "$(LC_ALL=C tr -d '\11\12\15\40-\176\200-\377' <"$evidence/$label.stderr")" ]]
    [[ ! -s "$evidence/$label.stderr" ]]
    if [[ "$probe_expected" = empty ]]; then
        [[ ! -s "$evidence/$label.stdout" ]]
    else
        [[ "$(<"$evidence/$label.stdout")" = "$probe_expected" ]]
    fi
    [[ "$status" -eq 0 ]]
    printf '%s\n' "$status" >"$evidence/$label.status"
    printf '%(%s)T\t%s\t%s\t%s\t%s\n' -1 "$role" "$sample" "$label" "$status"
}
capture dns-ipv4 10.1.0.55 "$dig_command" @10.1.0.55 \
    pihole.local.theama.co A +short +time=1 +tries=1
capture dns-ipv6 fd36:5aa8:6971:1::55 "$dig_command" \
    @fd36:5aa8:6971:1::55 pihole.local.theama.co AAAA +short +time=1 +tries=1
capture https-ipv4 empty "$curl_command" --fail --silent --show-error \
    --max-time 1 --output /dev/null \
    --resolve pihole-admin.local.theama.co:443:10.1.0.56 \
    https://pihole-admin.local.theama.co/admin/login.php
capture https-ipv6 empty "$curl_command" --fail --silent --show-error \
    --max-time 1 --output /dev/null --ipv6 \
    --resolve 'pihole-admin.local.theama.co:443:[fd36:5aa8:6971:1::56]' \
    https://pihole-admin.local.theama.co/admin/login.php
REMOTE
cat >"$action35h_outer_payload/remote/finalize-protocol-residue.sh" <<'REMOTE'
#!/usr/bin/env bash
set -Eeuo pipefail
readonly role=$1
readonly revision=$2
readonly expected_payload_manifest_sha256=$3
readonly root_prefix=${ACTION35H_ROOT_PREFIX:-}
[[ "$role" =~ ^node-[ab]$ ]]
[[ "$revision" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]
[[ "$expected_payload_manifest_sha256" =~ ^[0-9a-f]{64}$ ]]
readonly release=$root_prefix/etc/caddy/releases/$revision
readonly outbound=$root_prefix/var/lib/caddy-sync/outbound/$revision
readonly incoming_a=$root_prefix/var/lib/caddy-sync/incoming/node-a/$revision
readonly incoming_b=$root_prefix/var/lib/caddy-sync/incoming/node-b/$revision
[[ -d "$release" && ! -L "$release" ]]
[[ "$(readlink -f "$root_prefix/etc/caddy/current")" = "$release" ]]
[[ "$(sha256sum "$release/manifest.sha256" | awk '{print $1}')" = "$expected_payload_manifest_sha256" ]]
(cd "$release" && sha256sum --strict --check manifest.sha256 >/dev/null)
if [[ "$role" = node-a ]]; then
    [[ -d "$outbound" && ! -L "$outbound" ]]
    if [[ -z "$root_prefix" || "${CADDY_VALIDATION_CONTAINER:-0}" = 1 ]]; then
        [[ "$(stat -c '%U:%G:%a' "$outbound")" = caddy-sync:caddy-sync:550 ]]
    else
        [[ "$(stat -c '%a' "$outbound")" = 550 ]]
    fi
    [[ "$(sha256sum "$outbound/manifest.sha256" | awk '{print $1}')" = "$expected_payload_manifest_sha256" ]]
    cmp -s "$outbound/manifest.sha256" "$release/manifest.sha256"
    systemctl stop caddy-lsyncd.service
    if [[ -n "$root_prefix" && $EUID -ne 0 ]]; then
        find "$outbound" -xdev -type d -exec chmod u+rwx {} +
    fi
    find "$outbound" -xdev -mindepth 1 -delete
    rmdir "$outbound"
    systemctl start caddy-lsyncd.service
    systemctl is-active --quiet caddy-lsyncd.service
else
    [[ ! -e "$outbound" && ! -L "$outbound" ]]
fi
systemctl start caddy-sync-reconcile.service
stable=0
for _ in $(seq 1 60); do
    if [[ ! -e "$incoming_a" && ! -L "$incoming_a" && ! -e "$incoming_b" && ! -L "$incoming_b" ]] &&
        { [[ "$role" = node-b ]] || [[ ! -e "$outbound" && ! -L "$outbound" ]]; }; then
        stable=$((stable + 1))
        if ((stable >= 3)); then
            printf 'protocol_residue_%s=absent\n' "$role"
            exit 0
        fi
    else
        stable=0
    fi
    sleep 1
done
exit 1
REMOTE
cat >"$action35h_outer_payload/remote/rollback-transaction.sh" <<'REMOTE'
#!/usr/bin/env bash
set -Eeuo pipefail
readonly role=$1
readonly upload=/tmp/caddy-action35h-upload
readonly backup=/var/backups/caddy-action35h/$role
[[ "$role" =~ ^node-[ab]$ ]]
if [[ -d "$backup" && ! -L "$backup" ]]; then
    [[ -f "$upload/transaction.sh" && ! -L "$upload/transaction.sh" ]]
    /bin/bash "$upload/transaction.sh" --node-role "$role" --rollback-existing
fi
REMOTE
chmod 0700 "$action35h_outer_payload/remote/"*.sh

tar --sort=name --mtime=@0 --owner=0 --group=0 --numeric-owner \
    -C "$action35h_outer_payload" -cf "$action35h_outer_evidence/payload.tar" .
sha256sum "$action35h_outer_evidence/payload.tar" | awk '{ print $1 }' \
    >"$action35h_outer_evidence/payload.sha256"
printf '%s\n' "$action35h_outer_remote_root" >"$action35h_outer_evidence/remote-path"

action35h_outer_run() {
    local action35h_outer_label=$1

    shift
    local action35h_outer_status=0
    : >"$action35h_outer_evidence/$action35h_outer_label.stdout"
    : >"$action35h_outer_evidence/$action35h_outer_label.stderr"
    "$@" >"$action35h_outer_evidence/$action35h_outer_label.stdout" \
        2>"$action35h_outer_evidence/$action35h_outer_label.stderr" || action35h_outer_status=$?
    printf '%s\n' "$action35h_outer_status" >"$action35h_outer_evidence/$action35h_outer_label.status"
    return "$action35h_outer_status"
}

action35h_outer_stream() {
    local action35h_outer_label=$1
    local action35h_outer_node=$2
    local action35h_outer_privilege=$3
    local action35h_outer_program=$4
    shift 4
    local action35h_outer_remote='cd / && /bin/bash -s --'
    local action35h_outer_argument
    local action35h_outer_status=0

    [[ "$action35h_outer_privilege" = user ]] ||
        action35h_outer_remote='cd / && sudo -n /bin/bash -s --'
    for action35h_outer_argument in "$@"; do
        printf -v action35h_outer_remote '%s %q' "$action35h_outer_remote" \
            "$action35h_outer_argument"
    done
    printf '%s\n' "$action35h_outer_remote" \
        >"$action35h_outer_evidence/$action35h_outer_label.remote-command"
    : >"$action35h_outer_evidence/$action35h_outer_label.stdout"
    : >"$action35h_outer_evidence/$action35h_outer_label.stderr"
    "$action35h_outer_ssh_command" "$action35h_outer_node" \
        "$action35h_outer_remote" <"$action35h_outer_program" \
        >"$action35h_outer_evidence/$action35h_outer_label.stdout" \
        2>"$action35h_outer_evidence/$action35h_outer_label.stderr" ||
        action35h_outer_status=$?
    printf '%s\n' "$action35h_outer_status" \
        >"$action35h_outer_evidence/$action35h_outer_label.status"
    return "$action35h_outer_status"
}

action35h_outer_restore_node() {
    local action35h_outer_node=$1
    local action35h_outer_role=$2
    local action35h_outer_original=$3

    if [[ "$action35h_outer_test_mode" = true ]]; then
        local action35h_outer_test_node=$CADDY_ACTION35H_PRODUCTION_TEST_ROOT/$action35h_outer_role
        if [[ -d "$action35h_outer_test_node/var/backups/caddy-action35h/$action35h_outer_role" ]]; then
            /bin/bash "$action35h_outer_transaction_source" --node-role "$action35h_outer_role" \
                --rollback-existing --production-path-test "$action35h_outer_test_node" || return 1
        fi
    else
        action35h_outer_stream "$action35h_outer_role-rollback-transaction" \
            "$action35h_outer_node" root \
            "$action35h_outer_payload/remote/rollback-transaction.sh" \
            "$action35h_outer_role" || return 1
    fi
    action35h_outer_stream "$action35h_outer_role-restore-release" \
        "$action35h_outer_node" root \
        "$action35h_outer_payload/remote/restore-release.sh" \
        "$action35h_outer_original" "$action35h_outer_revision" \
        "$action35h_outer_role" || return 1
}

action35h_outer_remove_upload() {
    local action35h_outer_node=$1
    local action35h_outer_role=$2

    if [[ "$action35h_outer_test_mode" = true ]]; then
        local action35h_outer_test_upload=$CADDY_ACTION35H_PRODUCTION_TEST_ROOT/$action35h_outer_role$action35h_outer_remote_root
        [[ ! -e "$action35h_outer_test_upload" && ! -L "$action35h_outer_test_upload" ]] ||
            action35h_outer_run "failure-cleanup-$action35h_outer_role" /bin/bash -c \
                '[[ -d "$1" && ! -L "$1" ]] && find "$1" -xdev -mindepth 1 -delete && rmdir "$1"' \
                _ "$action35h_outer_test_upload"
    else
        action35h_outer_stream "failure-cleanup-$action35h_outer_role" \
            "$action35h_outer_node" root \
            "$action35h_outer_payload/remote/remove-tree.sh" \
            "$action35h_outer_remote_root"
    fi
}

action35h_outer_cleanup_trap() {
    local action35h_outer_status=$?

    trap - EXIT INT TERM
    if [[ -n "$action35h_outer_probe_pid" ]]; then
        kill "$action35h_outer_probe_pid" >/dev/null 2>&1 || :
        wait "$action35h_outer_probe_pid" >/dev/null 2>&1 || :
    fi
    if ((action35h_outer_status != 0)); then
        if [[ "$action35h_outer_node_a_mutated" = true ]]; then
            action35h_outer_restore_node "$action35h_outer_node_a" node-a \
                "$(<"$action35h_outer_evidence/node-a-original-release.path")" ||
                action35h_outer_recovery_failed=true
        fi
        if [[ "$action35h_outer_node_b_mutated" = true ]]; then
            action35h_outer_restore_node "$action35h_outer_node_b" node-b \
                "$(<"$action35h_outer_evidence/node-b-original-release.path")" ||
                action35h_outer_recovery_failed=true
        fi
        if [[ "$action35h_outer_node_a_upload_present" = true ]]; then
            action35h_outer_remove_upload "$action35h_outer_node_a" node-a || {
                [[ "$action35h_outer_node_a_mutated" = false &&
                    "$action35h_outer_node_b_mutated" = false ]] ||
                    action35h_outer_recovery_failed=true
            }
        fi
        if [[ "$action35h_outer_node_b_upload_present" = true ]]; then
            action35h_outer_remove_upload "$action35h_outer_node_b" node-b || {
                [[ "$action35h_outer_node_a_mutated" = false &&
                    "$action35h_outer_node_b_mutated" = false ]] ||
                    action35h_outer_recovery_failed=true
            }
        fi
        [[ "$action35h_outer_recovery_failed" = false ]] || exit 125
    fi
    rm -rf -- "$action35h_outer_payload"
    exit "$action35h_outer_status"
}

action35h_outer_start_availability_probe() {
    : >"$action35h_outer_evidence/availability.tsv"
    (
        action35h_outer_probe_sample=0
        while :; do
            action35h_outer_probe_sample=$((action35h_outer_probe_sample + 1))
            for action35h_outer_probe_role in node-a node-b; do
                action35h_outer_probe_node=$action35h_outer_node_a
                [[ "$action35h_outer_probe_role" = node-a ]] ||
                    action35h_outer_probe_node=$action35h_outer_node_b
                action35h_outer_probe_label=availability-$action35h_outer_probe_role-$action35h_outer_probe_sample
                if action35h_outer_stream "$action35h_outer_probe_label" \
                    "$action35h_outer_probe_node" root \
                    "$action35h_outer_payload/remote/probe-availability.sh" \
                    "$action35h_outer_probe_role" "$action35h_outer_probe_sample"; then
                    cat "$action35h_outer_evidence/$action35h_outer_probe_label.stdout" \
                        >>"$action35h_outer_evidence/availability.tsv"
                else
                    printf '%(%s)T\t%s\t%s\ttransport\t1\n' -1 \
                        "$action35h_outer_probe_role" "$action35h_outer_probe_sample" \
                        >>"$action35h_outer_evidence/availability.tsv"
                fi
            done
            sleep 1
        done
    ) &
    action35h_outer_probe_pid=$!
}

action35h_outer_stop_availability_probe() {
    kill "$action35h_outer_probe_pid" >/dev/null 2>&1 || :
    wait "$action35h_outer_probe_pid" >/dev/null 2>&1 || :
    action35h_outer_probe_pid=
    for action35h_outer_probe_role in node-a node-b; do
        for action35h_outer_probe_label in dns-ipv4 dns-ipv6 https-ipv4 https-ipv6; do
            [[ "$(awk -F '\t' -v role="$action35h_outer_probe_role" \
                -v label="$action35h_outer_probe_label" \
                '$2 == role && $4 == label { count++ } END { print count + 0 }' \
                "$action35h_outer_evidence/availability.tsv")" -ge 2 ]] || return 1
        done
    done
    awk -F '\t' '$5 != 0 { bad = 1 } END { exit bad }' \
        "$action35h_outer_evidence/availability.tsv"
}

action35h_outer_capture_original_release() {
    local action35h_outer_node=$1
    local action35h_outer_role=$2

    if [[ "$action35h_outer_test_mode" = true &&
        ! -d "$CADDY_ACTION35H_PRODUCTION_TEST_ROOT/$action35h_outer_role/etc" ]]; then
        ACTION35H_KEEP_TEST_ROOT=0 /bin/bash \
            "$action35h_outer_repository/Caddy/tests/coupled-serving-health-deployment-regression.sh" \
            --prepare-node "$CADDY_ACTION35H_PRODUCTION_TEST_ROOT/$action35h_outer_role" \
            "$action35h_outer_role"
    fi
    action35h_outer_stream "$action35h_outer_role-original-release" \
        "$action35h_outer_node" root \
        "$action35h_outer_payload/remote/resolve-current.sh" || return 1
    install -m 0600 "$action35h_outer_evidence/$action35h_outer_role-original-release.stdout" \
        "$action35h_outer_evidence/$action35h_outer_role-original-release.path"
}

action35h_outer_validate_protocol_state() {
    local action35h_outer_node=$1
    local action35h_outer_role=$2

    action35h_outer_stream "$action35h_outer_role-protocol-state" \
        "$action35h_outer_node" root \
        "$action35h_outer_payload/remote/validate-protocol-state.sh" \
        "$action35h_outer_role" "$action35h_outer_original_revision" \
        "$action35h_outer_revision" "$action35h_outer_release_manifest_sha256" \
        "$action35h_outer_payload_manifest_sha256"
}

action35h_outer_upload() {
    local action35h_outer_node=$1
    local action35h_outer_label=$2
    local action35h_outer_test_role=
    local action35h_outer_test_node=
    local action35h_outer_test_upload=

    if [[ "$action35h_outer_test_mode" = true ]]; then
        action35h_outer_test_role=node-a
        [[ "$action35h_outer_node" = "$action35h_outer_node_b" ]] && action35h_outer_test_role=node-b
        action35h_outer_test_node=$CADDY_ACTION35H_PRODUCTION_TEST_ROOT/$action35h_outer_test_role
        if [[ ! -d "$action35h_outer_test_node/etc" ]]; then
            ACTION35H_KEEP_TEST_ROOT=0 /bin/bash "$action35h_outer_repository/Caddy/tests/coupled-serving-health-deployment-regression.sh" \
                --prepare-node "$action35h_outer_test_node" "$action35h_outer_test_role"
        fi
        action35h_outer_test_upload=$action35h_outer_test_node$action35h_outer_remote_root
    fi

    action35h_outer_stream "$action35h_outer_label-prepare" "$action35h_outer_node" user \
        "$action35h_outer_payload/remote/prepare-upload.sh" \
        "$action35h_outer_remote_root" || return 1
    if [[ "$action35h_outer_node" = "$action35h_outer_node_a" ]]; then
        action35h_outer_node_a_upload_present=true
    else
        action35h_outer_node_b_upload_present=true
    fi
    action35h_outer_run "$action35h_outer_label-upload" "$action35h_outer_scp_command" \
        "$action35h_outer_evidence/payload.tar" \
        "$action35h_outer_node:$action35h_outer_remote_root/payload.tar" || return 1
    action35h_outer_stream "$action35h_outer_label-accept" "$action35h_outer_node" user \
        "$action35h_outer_payload/remote/accept-upload.sh" \
        "$action35h_outer_remote_root" || return 1

    if [[ "$action35h_outer_test_mode" = true ]]; then
        ACTION35H_KEEP_TEST_ROOT=0 /bin/bash \
            "$action35h_outer_repository/Caddy/tests/coupled-serving-health-deployment-regression.sh" \
            --add-baseline-inventory "$action35h_outer_test_upload" \
            "$action35h_outer_test_node" "$action35h_outer_test_role"
    fi
}

action35h_outer_dispatch() {
    local action35h_outer_node=$1
    local action35h_outer_role=$2
    local action35h_outer_label=$3

    local action35h_outer_remote_command
    printf -v action35h_outer_remote_command \
        'sudo -n /bin/bash %q --node-role %q --payload %q' \
        "$action35h_outer_remote_root/transaction.sh" "$action35h_outer_role" \
        "$action35h_outer_remote_root"
    printf '%s\n' "$action35h_outer_remote_command" \
        >"$action35h_outer_evidence/$action35h_outer_label-command.argv"
    action35h_outer_run "$action35h_outer_label-transaction" \
        "$action35h_outer_ssh_command" "$action35h_outer_node" \
        "$action35h_outer_remote_command"
}

action35h_outer_accept_standby_release() {
    action35h_outer_stream release-node-b-accepted "$action35h_outer_node_b" root \
        "$action35h_outer_payload/remote/wait-revision.sh" \
        "$action35h_outer_revision"
}

action35h_outer_promote_node_a_release() {
    action35h_outer_stream release-node-a-promote "$action35h_outer_node_a" root \
        "$action35h_outer_payload/remote/promote-release.sh" \
        "$action35h_outer_revision"
}

action35h_outer_finalize_protocol_residue() {
    local action35h_outer_node=$1
    local action35h_outer_role=$2

    action35h_outer_stream "$action35h_outer_role-protocol-residue" \
        "$action35h_outer_node" root \
        "$action35h_outer_payload/remote/finalize-protocol-residue.sh" \
        "$action35h_outer_role" "$action35h_outer_revision" \
        "$action35h_outer_payload_manifest_sha256"
}

action35h_outer_capture_ownership() {
    local action35h_outer_sample=$1

    if [[ "$action35h_outer_test_mode" = true ]]; then
        action35h_outer_run "ownership-node-a-$action35h_outer_sample" /bin/bash \
            "$CADDY_ACTION35H_PRODUCTION_TEST_ROOT/node-a/bin/ownership" node-a || return 1
        action35h_outer_run "ownership-node-b-$action35h_outer_sample" /bin/bash \
            "$CADDY_ACTION35H_PRODUCTION_TEST_ROOT/node-b/bin/ownership" node-b || return 1
    else
        for action35h_outer_role in node-a node-b; do
            action35h_outer_node=$action35h_outer_node_a
            [[ "$action35h_outer_role" = node-a ]] || action35h_outer_node=$action35h_outer_node_b
            action35h_outer_stream \
                "ownership-$action35h_outer_role-$action35h_outer_sample" \
                "$action35h_outer_node" user \
                "$action35h_outer_payload/remote/ownership.sh" || return 1
        done
    fi
    grep -Eq '^ipv4=(\(us\) 2 "Master"|Master) ipv6=(\(us\) 2 "Master"|Master) vip_count=4$' \
        "$action35h_outer_evidence/ownership-node-a-$action35h_outer_sample.stdout" || return 1
    grep -Eq '^ipv4=(\(us\) 1 "Backup"|Backup) ipv6=(\(us\) 1 "Backup"|Backup) vip_count=0$' \
        "$action35h_outer_evidence/ownership-node-b-$action35h_outer_sample.stdout" || return 1
}

# Uploading is non-mutating, but the recovery trap must already own exact
# cleanup before the first remote upload directory can be created.
trap action35h_outer_cleanup_trap EXIT INT TERM
action35h_outer_capture_original_release "$action35h_outer_node_a" node-a
action35h_outer_capture_original_release "$action35h_outer_node_b" node-b
[[ "$(<"$action35h_outer_evidence/node-a-original-release.path")" = *"/etc/caddy/releases/$action35h_outer_original_revision" ]]
[[ "$(<"$action35h_outer_evidence/node-b-original-release.path")" = *"/etc/caddy/releases/$action35h_outer_revision" ]]
action35h_outer_validate_protocol_state "$action35h_outer_node_a" node-a
action35h_outer_validate_protocol_state "$action35h_outer_node_b" node-b
for action35h_outer_identity in revision parent source release_manifest_sha256 payload_manifest_sha256; do
    action35h_outer_expected=
    case "$action35h_outer_identity" in
        revision) action35h_outer_expected=$action35h_outer_revision ;;
        parent) action35h_outer_expected=$action35h_outer_original_revision ;;
        source) action35h_outer_expected=node-a ;;
        release_manifest_sha256) action35h_outer_expected=$action35h_outer_release_manifest_sha256 ;;
        payload_manifest_sha256) action35h_outer_expected=$action35h_outer_payload_manifest_sha256 ;;
    esac
    for action35h_outer_role in node-a node-b; do
        grep -Fxq "protocol_${action35h_outer_identity}=$action35h_outer_expected" \
            "$action35h_outer_evidence/$action35h_outer_role-protocol-state.stdout"
    done
done
action35h_outer_upload "$action35h_outer_node_a" node-a
action35h_outer_upload "$action35h_outer_node_b" node-b

# Node B already holds the exact retained Node A revision. Accept it through a
# privileged streamed program, then mutate the standby before Node A.
action35h_outer_start_availability_probe
sleep 1
action35h_outer_accept_standby_release
action35h_outer_node_b_mutated=true

# Standby first. Node A is not dispatched until Node B has returned accepted.
action35h_outer_dispatch "$action35h_outer_node_b" node-b node-b
if [[ "$action35h_outer_test_mode" = true && "${ACTION35H_TEST_FAIL_AFTER_NODE_B:-0}" = 1 ]]; then
    exit 1
fi
action35h_outer_node_a_mutated=true
action35h_outer_promote_node_a_release
action35h_outer_dispatch "$action35h_outer_node_a" node-a node-a

for action35h_outer_sample in 1 2 3; do
    action35h_outer_capture_ownership "$action35h_outer_sample"
    sleep 1
done

if [[ "$action35h_outer_test_mode" = true ]]; then
    action35h_outer_run cluster-convergence test -f \
        "$CADDY_ACTION35H_PRODUCTION_TEST_ROOT/node-a/tmp/caddy-action35h/node-a/post-caddy-3.status" || exit 1
    action35h_outer_run node-b-postcondition test -f \
        "$CADDY_ACTION35H_PRODUCTION_TEST_ROOT/node-b/tmp/caddy-action35h/node-b/post-caddy-3.status" || exit 1
else
    action35h_outer_stream cluster-convergence "$action35h_outer_node_a" user \
        "$action35h_outer_payload/remote/health.sh" || exit 1
    action35h_outer_stream node-b-postcondition "$action35h_outer_node_b" user \
        "$action35h_outer_payload/remote/health.sh" || exit 1
fi
action35h_outer_stop_availability_probe

action35h_outer_finalize_protocol_residue "$action35h_outer_node_b" node-b || exit 125
action35h_outer_finalize_protocol_residue "$action35h_outer_node_a" node-a || exit 125

# Cluster acceptance is complete. Release rollback authority is no longer
# needed; remove only the exact action-owned backups before upload cleanup.
action35h_outer_node_a_mutated=false
action35h_outer_node_b_mutated=false
for action35h_outer_role in node-a node-b; do
    if [[ "$action35h_outer_test_mode" = true ]]; then
        action35h_outer_run "backup-cleanup-$action35h_outer_role" rm -rf -- \
            "$CADDY_ACTION35H_PRODUCTION_TEST_ROOT/$action35h_outer_role/var/backups/caddy-action35h/$action35h_outer_role" || exit 125
    else
        action35h_outer_node=$action35h_outer_node_a
        [[ "$action35h_outer_role" = node-a ]] || action35h_outer_node=$action35h_outer_node_b
        action35h_outer_stream "backup-cleanup-$action35h_outer_role" \
            "$action35h_outer_node" root \
            "$action35h_outer_payload/remote/remove-tree.sh" \
            "/var/backups/caddy-action35h/$action35h_outer_role" || exit 125
    fi
done

for action35h_outer_node in "$action35h_outer_node_a" "$action35h_outer_node_b"; do
    if [[ "$action35h_outer_test_mode" = true ]]; then
        action35h_outer_test_role=node-a
        [[ "$action35h_outer_node" = "$action35h_outer_node_b" ]] && action35h_outer_test_role=node-b
        action35h_outer_run "cleanup-${action35h_outer_node#*@}" /bin/bash -c \
            'find "$1" -xdev -mindepth 1 -delete && rmdir "$1"' _ \
            "$CADDY_ACTION35H_PRODUCTION_TEST_ROOT/$action35h_outer_test_role$action35h_outer_remote_root" || exit 125
    else
        action35h_outer_stream "cleanup-${action35h_outer_node#*@}" \
            "$action35h_outer_node" root \
            "$action35h_outer_payload/remote/remove-tree.sh" \
            "$action35h_outer_remote_root" || exit 125
    fi
    if [[ "$action35h_outer_node" = "$action35h_outer_node_a" ]]; then
        action35h_outer_node_a_upload_present=false
    else
        action35h_outer_node_b_upload_present=false
    fi
done

if [[ "$action35h_outer_test_mode" = true ]]; then
    readonly action35h_outer_policy_evidence=${CADDY_PRODUCTION_PATH_EVIDENCE_ROOT:-$CADDY_ACTION35H_PRODUCTION_TEST_ROOT/evidence}
    if [[ ! -e "$action35h_outer_policy_evidence" ]]; then
        install -d -m 0700 "$action35h_outer_policy_evidence"
    fi
    [[ -d "$action35h_outer_policy_evidence" && ! -L "$action35h_outer_policy_evidence" ]] || exit 1
    [[ -z "$(find "$action35h_outer_policy_evidence" -mindepth 1 -maxdepth 1 -print -quit)" ]] || exit 1
    chmod 0700 "$action35h_outer_policy_evidence"
    install -m 0600 "$action35h_outer_evidence/payload.sha256" "$action35h_outer_policy_evidence/payload.sha256"
    install -m 0600 "$action35h_outer_evidence/remote-path" "$action35h_outer_policy_evidence/remote-path"
    install -m 0600 "$action35h_outer_evidence/node-b-command.argv" "$action35h_outer_policy_evidence/remote-command.argv"
    printf 'prepare\t%s\naccept\t%s\ndisposition\t%s\n' \
        "$(<"$action35h_outer_evidence/node-b-prepare.status")" \
        "$(<"$action35h_outer_evidence/node-b-accept.status")" \
        "$(<"$action35h_outer_evidence/cleanup-10.1.0.54.status")" \
        >"$action35h_outer_policy_evidence/upload-events.tsv"
    install -m 0600 "$action35h_outer_evidence/node-b-transaction.status" \
        "$action35h_outer_policy_evidence/transaction.status"
    [[ "${ACTION35H_TRANSPORT_EVIDENCE:-}" = /tmp/* &&
        -f "$ACTION35H_TRANSPORT_EVIDENCE" && ! -L "$ACTION35H_TRANSPORT_EVIDENCE" ]] || exit 1
    install -m 0600 "$ACTION35H_TRANSPORT_EVIDENCE" \
        "$action35h_outer_policy_evidence/transport-events.tsv"
    awk '{ total += $1 } END { print total + 0 }' \
        "$CADDY_ACTION35H_PRODUCTION_TEST_ROOT/node-a/tmp/caddy-action35h/node-a/mutation-count" \
        "$CADDY_ACTION35H_PRODUCTION_TEST_ROOT/node-b/tmp/caddy-action35h/node-b/mutation-count" \
        >"$action35h_outer_policy_evidence/mutation-count"
    chmod 0600 "$action35h_outer_policy_evidence/"*
fi

printf '%s_evidence_parent=true\n' "$action35h_outer_prefix"
printf '%s_payload_constructed=true\n' "$action35h_outer_prefix"
printf '%s_remote_path_generated=true\n' "$action35h_outer_prefix"
printf '%s_upload_disposition=true\n' "$action35h_outer_prefix"
printf '%s_split_baseline_validated=true\n' "$action35h_outer_prefix"
printf '%s_existing_release_reused=true\n' "$action35h_outer_prefix"
printf '%s_ula_probe_paths=true\n' "$action35h_outer_prefix"
printf '%s_standby_first=true\n' "$action35h_outer_prefix"
printf '%s_complete=true\n' "$action35h_outer_prefix"
