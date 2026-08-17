#!/usr/bin/env bash
# shellcheck disable=SC2016 # Remote Bash programs intentionally expand only on the node.

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly action35f_outer_prefix=action_35f_outer
readonly transaction_sha256=0040150451305ffa43d72eb834d0228f376404123a0eb0cd05721af1e1b3819e
readonly action35f_outer_node_a=pi@10.1.0.53
readonly action35f_outer_node_b=pi@10.1.0.54
readonly action35f_outer_remote_root=/tmp/caddy-action35f-upload
readonly action35f_outer_retained_candidate=/tmp/caddy-action35c-release
readonly action35f_outer_candidate_route_sha256=93df2e2d056052b92505f70f3d79e826d5c7c6c69baaededd2c5c1b9bb410512

action35f_outer_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly action35f_outer_directory
readonly action35f_outer_repository=${action35f_outer_directory%/Caddy/scripts}
readonly action35f_outer_transaction_source=$action35f_outer_directory/apply-coupled-serving-health-action35f.sh
readonly action35f_outer_manifest=$action35f_outer_repository/Caddy/manifests/serving-health-production.tsv
readonly action35f_outer_state=$action35f_outer_repository/Caddy/manifests/current-live-state.tsv
readonly action35f_outer_protocol_manifest=$action35f_outer_repository/Caddy/manifests/synchronization-protocol-v2.yaml
readonly action35f_outer_ssh_command=${ACTION35F_SSH_COMMAND:-ssh}
readonly action35f_outer_scp_command=${ACTION35F_SCP_COMMAND:-scp}
action35f_outer_node_a_mutated=false
action35f_outer_node_b_mutated=false
action35f_outer_node_a_upload_present=false
action35f_outer_node_b_upload_present=false
action35f_outer_candidate_present=false
action35f_outer_recovery_failed=false
action35f_outer_probe_pid=

if [[ "${1:-}" = --production-path-test && $# -eq 1 ]]; then
    exec /bin/bash "$action35f_outer_repository/Caddy/tests/coupled-serving-health-deployment-regression.sh" \
        --entrypoint outer
fi

action35f_outer_test_mode=false
if [[ "${1:-}" = --production-path-test-inner && $# -eq 1 ]]; then
    action35f_outer_test_mode=true
elif (($#)); then
    exit 64
fi
cd -- "$action35f_outer_repository"

action35f_outer_final_directory_mode=$(awk '
    $1 == "final_directory_mode:" {
        gsub(/"/, "", $2)
        print $2
        count++
    }
    END { exit(count == 1 ? 0 : 1) }
' "$action35f_outer_protocol_manifest")
readonly action35f_outer_final_directory_mode
[[ "$action35f_outer_final_directory_mode" =~ ^0[0-7]{3}$ ]]
for action35f_outer_mode_implementation in \
    Caddy/scripts/publish-release-v2.sh \
    Caddy/scripts/reconcile-release-v2.sh \
    Caddy/scripts/finalize-incoming-release-v2.sh; do
    grep -Fq -- "chmod $action35f_outer_final_directory_mode" \
        "$action35f_outer_mode_implementation"
done

if [[ "$action35f_outer_test_mode" = false ]]; then
    /bin/bash Caddy/tests/deployable-successor-policy.sh --authorization-ready >/dev/null
    /bin/bash Caddy/tests/coupled-serving-health-deployment-regression.sh >/dev/null
fi
[[ "$(sha256sum "$action35f_outer_transaction_source" | awk '{ print $1 }')" = "$transaction_sha256" ]] || exit 1

action35f_outer_evidence=/tmp/caddy-ssh-evidence/action35f
if [[ "$action35f_outer_test_mode" = true ]]; then
    [[ "${CADDY_ACTION35F_PRODUCTION_TEST_ROOT:-}" = /tmp/* ]] || exit 64
    action35f_outer_evidence=$CADDY_ACTION35F_PRODUCTION_TEST_ROOT/ssh-evidence
fi
readonly action35f_outer_evidence
[[ ! -e "$action35f_outer_evidence" ]] || exit 1
install -d -m 0700 "$(dirname -- "$action35f_outer_evidence")" "$action35f_outer_evidence"
action35f_outer_payload=$(mktemp -d /tmp/caddy-action35f-payload.XXXXXX)
readonly action35f_outer_payload
trap 'rm -rf -- "$action35f_outer_payload"' EXIT INT TERM

install -d -m 0700 \
    "$action35f_outer_payload/files/homelab-server-configs" \
    "$action35f_outer_payload/files/homelab-dns" \
    "$action35f_outer_payload/remote"
install -m 0600 "$action35f_outer_manifest" \
    "$action35f_outer_payload/serving-health-production.tsv"
install -m 0600 "$action35f_outer_state" "$action35f_outer_payload/current-live-state.tsv"
install -m 0600 "$action35f_outer_protocol_manifest" \
    "$action35f_outer_payload/synchronization-protocol-v2.yaml"
install -m 0600 "$action35f_outer_repository/Caddy/manifests/production-artifacts.tsv" \
    "$action35f_outer_payload/production-artifacts.tsv"
install -m 0700 "$action35f_outer_transaction_source" "$action35f_outer_payload/transaction.sh"

while IFS=$'\t' read -r action35f_outer_repository_name action35f_outer_source \
    _ _ _ _; do
    [[ -n "$action35f_outer_repository_name" && "$action35f_outer_repository_name" != \#* ]] || continue
    action35f_outer_source_root=$action35f_outer_repository
    [[ "$action35f_outer_repository_name" = homelab-server-configs ]] ||
        action35f_outer_source_root=${action35f_outer_repository%/homelab-server-configs}/homelab-dns
    action35f_outer_destination=$action35f_outer_payload/files/$action35f_outer_repository_name/$action35f_outer_source
    install -d -m 0700 "$(dirname -- "$action35f_outer_destination")"
    install -m 0600 "$action35f_outer_source_root/$action35f_outer_source" \
        "$action35f_outer_destination"
done <"$action35f_outer_manifest"

cat >"$action35f_outer_payload/remote/dispose-retained-candidate.sh" <<'REMOTE'
#!/usr/bin/env bash
set -Eeuo pipefail
umask 077
readonly root_prefix=${ACTION35F_ROOT_PREFIX:-}
readonly relative=$1
readonly original_relative=$2
readonly expected_route_sha256=$3
readonly expected_root_mode=$4
readonly target=$root_prefix$relative
[[ "$relative" = /tmp/caddy-action35c-release ]]
if [[ -n "$root_prefix" ]]; then
    [[ "$original_relative" = "$root_prefix"/etc/caddy/releases/* ]]
    readonly original=$original_relative
else
    [[ "$original_relative" = /etc/caddy/releases/* ]]
    readonly original=$original_relative
fi
[[ "$expected_route_sha256" =~ ^[0-9a-f]{64}$ ]]
[[ "$expected_root_mode" =~ ^0[0-7]{3}$ ]]
if [[ ! -e "$target" && ! -L "$target" ]]; then
    printf 'retained_candidate_state=absent\n'
    exit 0
fi
[[ -d "$target" && ! -L "$target" ]]
readonly observed_root_mode=$(stat -c '%a' "$target")
printf 'retained_candidate_expected_root_mode=%s\n' "$expected_root_mode"
printf 'retained_candidate_observed_root_mode=0%s\n' "$observed_root_mode"
[[ "$observed_root_mode" = "${expected_root_mode#0}" ]]
[[ -d "$original" && ! -L "$original" ]]
if [[ -z "$root_prefix" ]]; then
    readonly observed_owner=$(stat -c '%U:%G' "$target")
    printf 'retained_candidate_expected_owner=root:root\n'
    printf 'retained_candidate_observed_owner=%s\n' "$observed_owner"
    [[ "$observed_owner" = root:root ]]
fi
readonly route=$target/conf.d/10-pihole-admin.caddy
[[ -f "$route" && ! -L "$route" && "$(stat -c '%a' "$route")" = 640 ]]
readonly observed_route_sha256=$(sha256sum "$route" | awk '{ print $1 }')
printf 'retained_candidate_expected_route_sha256=%s\n' "$expected_route_sha256"
printf 'retained_candidate_observed_route_sha256=%s\n' "$observed_route_sha256"
[[ "$observed_route_sha256" = "$expected_route_sha256" ]]
diff -qr --exclude=10-pihole-admin.caddy "$original" "$target" >/dev/null
diff -u \
    <(find "$original" -xdev -mindepth 1 -printf '%y\t%P\n' | LC_ALL=C sort) \
    <(find "$target" -xdev -mindepth 1 -printf '%y\t%P\n' | LC_ALL=C sort) >/dev/null
if [[ -n "$root_prefix" && $EUID -ne 0 ]]; then
    find "$target" -xdev -type d -exec chmod u+rwx {} +
fi
find "$target" -xdev -mindepth 1 -delete
rmdir "$target"
printf 'retained_candidate_state=validated-and-removed\n'
REMOTE
cat >"$action35f_outer_payload/remote/resolve-current.sh" <<'REMOTE'
#!/usr/bin/env bash
set -Eeuo pipefail
readonly root_prefix=${ACTION35F_ROOT_PREFIX:-}
readonly current=$root_prefix/etc/caddy/current
[[ -L "$current" ]]
resolved=$(readlink -f -- "$current")
[[ "$resolved" = "$root_prefix"/etc/caddy/releases/* ]]
[[ -d "$resolved" && ! -L "$resolved" ]]
[[ -f "$resolved/release-manifest.json" && ! -L "$resolved/release-manifest.json" ]]
printf '%s\n' "$resolved"
REMOTE
cat >"$action35f_outer_payload/remote/prepare-upload.sh" <<'REMOTE'
#!/usr/bin/env bash
set -Eeuo pipefail
umask 077
readonly root_prefix=${ACTION35F_ROOT_PREFIX:-}
readonly target=$root_prefix$1
[[ "$1" = /tmp/caddy-action35f-upload && ! -e "$target" && ! -L "$target" ]]
install -d -m 0700 "$target"
REMOTE
cat >"$action35f_outer_payload/remote/accept-upload.sh" <<'REMOTE'
#!/usr/bin/env bash
set -Eeuo pipefail
readonly root_prefix=${ACTION35F_ROOT_PREFIX:-}
readonly target=$root_prefix$1
[[ "$1" = /tmp/caddy-action35f-upload && -d "$target" && ! -L "$target" ]]
[[ -f "$target/payload.tar" && ! -L "$target/payload.tar" ]]
tar -tf "$target/payload.tar" >/dev/null
tar -C "$target" -xf "$target/payload.tar"
REMOTE
cat >"$action35f_outer_payload/remote/remove-tree.sh" <<'REMOTE'
#!/usr/bin/env bash
set -Eeuo pipefail
readonly target=$1
case "$target" in
    /tmp/caddy-action35f-upload | /tmp/caddy-action35f-release | /var/backups/caddy-action35f/node-a | /var/backups/caddy-action35f/node-b) ;;
    *) exit 64 ;;
esac
[[ -d "$target" && ! -L "$target" ]]
if [[ -n "${ACTION35F_ROOT_PREFIX:-}" && $EUID -ne 0 ]]; then
    find "$target" -xdev -type d -exec chmod u+rwx {} +
fi
find "$target" -xdev -mindepth 1 -delete
rmdir "$target"
REMOTE
cat >"$action35f_outer_payload/remote/remove-candidate.sh" <<'REMOTE'
#!/usr/bin/env bash
set -Eeuo pipefail
readonly target=${ACTION35F_ROOT_PREFIX:-}/tmp/caddy-action35f-release
if [[ ! -e "$target" && ! -L "$target" ]]; then
    exit 0
fi
[[ -d "$target" && ! -L "$target" ]]
if [[ -n "${ACTION35F_ROOT_PREFIX:-}" && $EUID -ne 0 ]]; then
    find "$target" -xdev -type d -exec chmod u+rwx {} +
fi
find "$target" -xdev -mindepth 1 -delete
rmdir "$target"
REMOTE
cat >"$action35f_outer_payload/remote/ownership.sh" <<'REMOTE'
#!/usr/bin/env bash
set -Eeuo pipefail
cd /
ipv4=$(timeout 2 busctl get-property org.keepalived.Vrrp1 /org/keepalived/Vrrp1/Instance/eth0/100/IPv4 org.keepalived.Vrrp1.Instance State)
ipv6=$(timeout 2 busctl get-property org.keepalived.Vrrp1 /org/keepalived/Vrrp1/Instance/eth0/101/IPv6 org.keepalived.Vrrp1.Instance State)
count=$(ip -o address show dev eth0 | awk '$4 ~ /^(10\.1\.0\.(55|56)\/22|fd36:5aa8:6971:1::(55|56)\/128)$/ { n++ } END { print n + 0 }')
printf 'ipv4=%s ipv6=%s vip_count=%s\n' "$ipv4" "$ipv6" "$count"
REMOTE
cat >"$action35f_outer_payload/remote/health.sh" <<'REMOTE'
#!/usr/bin/env bash
set -Eeuo pipefail
cd /
/usr/local/libexec/check-caddy.sh
/etc/scripts/check-dns.sh
REMOTE
cat >"$action35f_outer_payload/remote/restore-release.sh" <<'REMOTE'
#!/usr/bin/env bash
set -Eeuo pipefail
readonly original=$1
case "$original" in /etc/caddy/releases/*) ;; *) exit 64 ;; esac
[[ -d "$original" && ! -L "$original" ]]
ln -sfn "$original" /etc/caddy/current
systemctl reload caddy.service
REMOTE
cat >"$action35f_outer_payload/remote/publish-release.sh" <<'REMOTE'
#!/usr/bin/env bash
set -Eeuo pipefail
cd /
readonly upload=$1
readonly root_prefix=${ACTION35F_ROOT_PREFIX:-}
readonly candidate=$root_prefix/tmp/caddy-action35f-release
readonly environment_file=$root_prefix/etc/default/caddy-ha
[[ "$upload" = /tmp/caddy-action35f-upload && ! -e "$candidate" && ! -L "$candidate" ]]
[[ -f "$environment_file" && ! -L "$environment_file" ]]
[[ "$(stat -c '%a' "$environment_file")" = 640 ]]
if [[ -z "$root_prefix" ]]; then
    [[ "$(stat -c '%U:%G' "$environment_file")" = root:caddy-tls ]]
fi
[[ "$(wc -l <"$environment_file")" -eq 3 ]]
[[ "$(grep -Ec '^(NODE_FQDN|NODE_IPV4|NODE_IPV6)=[A-Za-z0-9:.~-]+$' "$environment_file")" -eq 3 ]]
for required_key in NODE_FQDN NODE_IPV4 NODE_IPV6; do
    [[ "$(grep -c "^$required_key=" "$environment_file")" -eq 1 ]]
done
set -a
# The file has been constrained to three exact assignment-only records.
# shellcheck disable=SC1090
source "$environment_file"
set +a
[[ "$NODE_FQDN" =~ ^[a-z0-9][a-z0-9.-]*[a-z0-9]$ ]]
[[ "$NODE_IPV4" =~ ^[0-9]+(\.[0-9]+){3}$ ]]
[[ "$NODE_IPV6" =~ ^[0-9a-f:]+$ ]]
if [[ -n "$root_prefix" ]]; then
    install -d -m 0700 "$candidate"
else
    install -d -o root -g root -m 0700 "$candidate"
fi
cp -a -- "$root_prefix/etc/caddy/current/." "$candidate/"
if [[ -n "$root_prefix" ]]; then
    install -m 0640 \
        "$root_prefix$upload/files/homelab-server-configs/Caddy/configs/caddy/conf.d/10-pihole-admin.caddy" \
        "$candidate/conf.d/10-pihole-admin.caddy"
else
    install -o root -g caddy-tls -m 0640 \
        "$upload/files/homelab-server-configs/Caddy/configs/caddy/conf.d/10-pihole-admin.caddy" \
        "$candidate/conf.d/10-pihole-admin.caddy"
fi
readonly caddy_validate_command=$(
    if [[ -n "$root_prefix" && "${ACTION35F_USE_REAL_CADDY:-0}" = 1 ]]; then
        printf '/usr/bin/caddy'
    else
        command -v caddy
    fi
)
env CADDY_CONFIG_ROOT="$candidate" \
    NODE_FQDN="$NODE_FQDN" NODE_IPV4="$NODE_IPV4" NODE_IPV6="$NODE_IPV6" \
    "$caddy_validate_command" validate \
    --config "$candidate/Caddyfile" --adapter caddyfile >/dev/null
printf 'candidate_parser=%s\n' "$caddy_validate_command"
"$root_prefix/usr/local/libexec/publish-release-v2.sh" --source "$candidate" --node-role node-a
REMOTE
cat >"$action35f_outer_payload/remote/wait-revision.sh" <<'REMOTE'
#!/usr/bin/env bash
set -Eeuo pipefail
readonly expected=$1
readonly root_prefix=${ACTION35F_ROOT_PREFIX:-}
[[ "$expected" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]
for _ in $(seq 1 60); do
    if [[ "$(jq -r .revision "$root_prefix/etc/caddy/current/release-manifest.json")" = "$expected" ]]; then
        exit 0
    fi
    sleep 1
done
exit 1
REMOTE
cat >"$action35f_outer_payload/remote/promote-release.sh" <<'REMOTE'
#!/usr/bin/env bash
set -Eeuo pipefail
cd /
readonly revision=$1
readonly root_prefix=${ACTION35F_ROOT_PREFIX:-}
[[ "$revision" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]
readonly outgoing=$root_prefix/var/lib/caddy-sync/outbound/$revision
readonly incoming=$root_prefix/var/lib/caddy-sync/incoming/$revision
[[ -d "$outgoing" && ! -L "$outgoing" && ! -e "$incoming" && ! -L "$incoming" ]]
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
chmod 0700 "$action35f_outer_payload/remote/"*.sh

tar --sort=name --mtime=@0 --owner=0 --group=0 --numeric-owner \
    -C "$action35f_outer_payload" -cf "$action35f_outer_evidence/payload.tar" .
sha256sum "$action35f_outer_evidence/payload.tar" | awk '{ print $1 }' \
    >"$action35f_outer_evidence/payload.sha256"
printf '%s\n' "$action35f_outer_remote_root" >"$action35f_outer_evidence/remote-path"

action35f_outer_run() {
    local action35f_outer_label=$1

    shift
    local action35f_outer_status=0
    : >"$action35f_outer_evidence/$action35f_outer_label.stdout"
    : >"$action35f_outer_evidence/$action35f_outer_label.stderr"
    "$@" >"$action35f_outer_evidence/$action35f_outer_label.stdout" \
        2>"$action35f_outer_evidence/$action35f_outer_label.stderr" || action35f_outer_status=$?
    printf '%s\n' "$action35f_outer_status" >"$action35f_outer_evidence/$action35f_outer_label.status"
    return "$action35f_outer_status"
}

action35f_outer_stream() {
    local action35f_outer_label=$1
    local action35f_outer_node=$2
    local action35f_outer_privilege=$3
    local action35f_outer_program=$4
    shift 4
    local action35f_outer_remote='cd / && /bin/bash -s --'
    local action35f_outer_argument
    local action35f_outer_status=0

    [[ "$action35f_outer_privilege" = user ]] ||
        action35f_outer_remote='cd / && sudo -n /bin/bash -s --'
    for action35f_outer_argument in "$@"; do
        printf -v action35f_outer_remote '%s %q' "$action35f_outer_remote" \
            "$action35f_outer_argument"
    done
    printf '%s\n' "$action35f_outer_remote" \
        >"$action35f_outer_evidence/$action35f_outer_label.remote-command"
    : >"$action35f_outer_evidence/$action35f_outer_label.stdout"
    : >"$action35f_outer_evidence/$action35f_outer_label.stderr"
    "$action35f_outer_ssh_command" "$action35f_outer_node" \
        "$action35f_outer_remote" <"$action35f_outer_program" \
        >"$action35f_outer_evidence/$action35f_outer_label.stdout" \
        2>"$action35f_outer_evidence/$action35f_outer_label.stderr" ||
        action35f_outer_status=$?
    printf '%s\n' "$action35f_outer_status" \
        >"$action35f_outer_evidence/$action35f_outer_label.status"
    return "$action35f_outer_status"
}

action35f_outer_restore_node() {
    local action35f_outer_node=$1
    local action35f_outer_role=$2
    local action35f_outer_original=$3

    if [[ "$action35f_outer_test_mode" = true ]]; then
        local action35f_outer_test_node=$CADDY_ACTION35F_PRODUCTION_TEST_ROOT/$action35f_outer_role
        if [[ -d "$action35f_outer_test_node/var/backups/caddy-action35f/$action35f_outer_role" ]]; then
            /bin/bash "$action35f_outer_transaction_source" --node-role "$action35f_outer_role" \
                --rollback-existing --production-path-test "$action35f_outer_test_node" || return 1
        fi
        ln -sfn "${action35f_outer_original#"$action35f_outer_test_node/etc/caddy/"}" \
            "$action35f_outer_test_node/etc/caddy/current"
    else
        if ssh "$action35f_outer_node" test -d \
            "/var/backups/caddy-action35f/$action35f_outer_role"; then
            ssh "$action35f_outer_node" sudo /bin/bash \
                "$action35f_outer_remote_root/transaction.sh" --node-role "$action35f_outer_role" \
                --rollback-existing || return 1
        fi
        action35f_outer_stream "$action35f_outer_role-restore-release" \
            "$action35f_outer_node" root \
            "$action35f_outer_payload/remote/restore-release.sh" \
            "$action35f_outer_original" || return 1
    fi
}

action35f_outer_remove_upload() {
    local action35f_outer_node=$1
    local action35f_outer_role=$2

    if [[ "$action35f_outer_test_mode" = true ]]; then
        local action35f_outer_test_upload=$CADDY_ACTION35F_PRODUCTION_TEST_ROOT/$action35f_outer_role$action35f_outer_remote_root
        [[ ! -e "$action35f_outer_test_upload" && ! -L "$action35f_outer_test_upload" ]] ||
            action35f_outer_run "failure-cleanup-$action35f_outer_role" /bin/bash -c \
                '[[ -d "$1" && ! -L "$1" ]] && find "$1" -xdev -mindepth 1 -delete && rmdir "$1"' \
                _ "$action35f_outer_test_upload"
    else
        action35f_outer_stream "failure-cleanup-$action35f_outer_role" \
            "$action35f_outer_node" root \
            "$action35f_outer_payload/remote/remove-tree.sh" \
            "$action35f_outer_remote_root"
    fi
}

action35f_outer_remove_candidate() {
    action35f_outer_stream failure-cleanup-candidate \
        "$action35f_outer_node_a" root \
        "$action35f_outer_payload/remote/remove-candidate.sh"
}

action35f_outer_cleanup_trap() {
    local action35f_outer_status=$?

    trap - EXIT INT TERM
    if [[ -n "$action35f_outer_probe_pid" ]]; then
        kill "$action35f_outer_probe_pid" >/dev/null 2>&1 || :
        wait "$action35f_outer_probe_pid" >/dev/null 2>&1 || :
    fi
    if ((action35f_outer_status != 0)); then
        if [[ "$action35f_outer_node_a_mutated" = true ]]; then
            action35f_outer_restore_node "$action35f_outer_node_a" node-a \
                "$(<"$action35f_outer_evidence/node-a-original-release.path")" ||
                action35f_outer_recovery_failed=true
        fi
        if [[ "$action35f_outer_node_b_mutated" = true ]]; then
            action35f_outer_restore_node "$action35f_outer_node_b" node-b \
                "$(<"$action35f_outer_evidence/node-b-original-release.path")" ||
                action35f_outer_recovery_failed=true
        fi
        if [[ "$action35f_outer_node_a_upload_present" = true ]]; then
            action35f_outer_remove_upload "$action35f_outer_node_a" node-a || {
                [[ "$action35f_outer_node_a_mutated" = false &&
                    "$action35f_outer_node_b_mutated" = false ]] ||
                    action35f_outer_recovery_failed=true
            }
        fi
        if [[ "$action35f_outer_node_b_upload_present" = true ]]; then
            action35f_outer_remove_upload "$action35f_outer_node_b" node-b || {
                [[ "$action35f_outer_node_a_mutated" = false &&
                    "$action35f_outer_node_b_mutated" = false ]] ||
                    action35f_outer_recovery_failed=true
            }
        fi
        if [[ "$action35f_outer_candidate_present" = true ]]; then
            action35f_outer_remove_candidate || {
                [[ "$action35f_outer_node_a_mutated" = false &&
                    "$action35f_outer_node_b_mutated" = false ]] ||
                    action35f_outer_recovery_failed=true
            }
        fi
        [[ "$action35f_outer_recovery_failed" = false ]] || exit 125
    fi
    rm -rf -- "$action35f_outer_payload"
    exit "$action35f_outer_status"
}

action35f_outer_start_availability_probe() {
    : >"$action35f_outer_evidence/availability.tsv"
    (
        action35f_outer_probe_dig=dig
        action35f_outer_probe_curl=curl
        if [[ "$action35f_outer_test_mode" = true ]]; then
            action35f_outer_probe_dig=$CADDY_ACTION35F_PRODUCTION_TEST_ROOT/node-a/bin/probe-dig
            action35f_outer_probe_curl=$CADDY_ACTION35F_PRODUCTION_TEST_ROOT/node-a/bin/probe-curl
        fi
        action35f_outer_probe_sample=0
        while :; do
            action35f_outer_probe_sample=$((action35f_outer_probe_sample + 1))
            action35f_outer_probe_capture "$action35f_outer_probe_sample" dns-ipv4 \
                10.1.0.55 "$action35f_outer_probe_dig" @10.1.0.55 \
                pihole.local.theama.co A +short +time=1 +tries=1
            action35f_outer_probe_capture "$action35f_outer_probe_sample" dns-ipv6 \
                fd36:5aa8:6971:1::55 "$action35f_outer_probe_dig" \
                @fd36:5aa8:6971:1::55 pihole.local.theama.co AAAA \
                +short +time=1 +tries=1
            action35f_outer_probe_capture "$action35f_outer_probe_sample" https-ipv4 \
                empty "$action35f_outer_probe_curl" --fail --silent --show-error \
                --max-time 1 --output /dev/null \
                --resolve pihole-admin.local.theama.co:443:10.1.0.56 \
                https://pihole-admin.local.theama.co/admin/login.php
            action35f_outer_probe_capture "$action35f_outer_probe_sample" https-ipv6 \
                empty "$action35f_outer_probe_curl" --fail --silent --show-error \
                --max-time 1 --output /dev/null --ipv6 \
                --resolve 'pihole-admin.local.theama.co:443:[fd36:5aa8:6971:1::56]' \
                https://pihole-admin.local.theama.co/admin/login.php
            sleep 1
        done
    ) &
    action35f_outer_probe_pid=$!
}

action35f_outer_probe_capture() {
    local action35f_outer_probe_sample=$1
    local action35f_outer_probe_label=$2
    local action35f_outer_probe_expected=$3
    shift 3
    local action35f_outer_probe_base=$action35f_outer_evidence/availability-$action35f_outer_probe_sample-$action35f_outer_probe_label
    local action35f_outer_probe_status=0

    "$@" >"$action35f_outer_probe_base.stdout" \
        2>"$action35f_outer_probe_base.stderr" || action35f_outer_probe_status=$?
    [[ "$(stat -c '%s' "$action35f_outer_probe_base.stdout")" -le 4096 &&
    "$(stat -c '%s' "$action35f_outer_probe_base.stderr")" -le 4096 ]] ||
        action35f_outer_probe_status=70
    iconv -f UTF-8 -t UTF-8 "$action35f_outer_probe_base.stdout" >/dev/null 2>&1 &&
        iconv -f UTF-8 -t UTF-8 "$action35f_outer_probe_base.stderr" >/dev/null 2>&1 ||
        action35f_outer_probe_status=70
    [[ -z "$(LC_ALL=C tr -d '\11\12\15\40-\176\200-\377' \
        <"$action35f_outer_probe_base.stdout")" &&
    -z "$(LC_ALL=C tr -d '\11\12\15\40-\176\200-\377' \
        <"$action35f_outer_probe_base.stderr")" ]] ||
        action35f_outer_probe_status=70
    if [[ "$action35f_outer_probe_expected" = empty ]]; then
        [[ ! -s "$action35f_outer_probe_base.stdout" && ! -s "$action35f_outer_probe_base.stderr" ]] ||
            action35f_outer_probe_status=1
    else
        [[ "$(<"$action35f_outer_probe_base.stdout")" = "$action35f_outer_probe_expected" &&
        ! -s "$action35f_outer_probe_base.stderr" ]] ||
            action35f_outer_probe_status=1
    fi
    printf '%s\n' "$action35f_outer_probe_status" >"$action35f_outer_probe_base.status"
    printf '%(%s)T\t%s\t%s\t%s\n' -1 "$action35f_outer_probe_sample" \
        "$action35f_outer_probe_label" "$action35f_outer_probe_status" \
        >>"$action35f_outer_evidence/availability.tsv"
}

action35f_outer_stop_availability_probe() {
    kill "$action35f_outer_probe_pid" >/dev/null 2>&1 || :
    wait "$action35f_outer_probe_pid" >/dev/null 2>&1 || :
    action35f_outer_probe_pid=
    for action35f_outer_probe_label in dns-ipv4 dns-ipv6 https-ipv4 https-ipv6; do
        [[ "$(awk -F '\t' -v label="$action35f_outer_probe_label" \
            '$3 == label { count++ } END { print count + 0 }' \
            "$action35f_outer_evidence/availability.tsv")" -ge 2 ]] || return 1
    done
    awk -F '\t' '$4 != 0 { bad = 1 } END { exit bad }' \
        "$action35f_outer_evidence/availability.tsv"
}

action35f_outer_capture_original_release() {
    local action35f_outer_node=$1
    local action35f_outer_role=$2

    if [[ "$action35f_outer_test_mode" = true &&
        ! -d "$CADDY_ACTION35F_PRODUCTION_TEST_ROOT/$action35f_outer_role/etc" ]]; then
        ACTION35F_KEEP_TEST_ROOT=0 /bin/bash \
            "$action35f_outer_repository/Caddy/tests/coupled-serving-health-deployment-regression.sh" \
            --prepare-node "$CADDY_ACTION35F_PRODUCTION_TEST_ROOT/$action35f_outer_role" \
            "$action35f_outer_role"
    fi
    action35f_outer_stream "$action35f_outer_role-original-release" \
        "$action35f_outer_node" root \
        "$action35f_outer_payload/remote/resolve-current.sh" || return 1
    install -m 0600 "$action35f_outer_evidence/$action35f_outer_role-original-release.stdout" \
        "$action35f_outer_evidence/$action35f_outer_role-original-release.path"
}

action35f_outer_dispose_retained_candidate() {
    local action35f_outer_node=$1
    local action35f_outer_role=$2

    action35f_outer_stream "$action35f_outer_role-retained-candidate" \
        "$action35f_outer_node" root \
        "$action35f_outer_payload/remote/dispose-retained-candidate.sh" \
        "$action35f_outer_retained_candidate" \
        "$(<"$action35f_outer_evidence/$action35f_outer_role-original-release.path")" \
        "$action35f_outer_candidate_route_sha256" \
        "$action35f_outer_final_directory_mode"
}

action35f_outer_upload() {
    local action35f_outer_node=$1
    local action35f_outer_label=$2
    local action35f_outer_test_role=
    local action35f_outer_test_node=
    local action35f_outer_test_upload=

    if [[ "$action35f_outer_test_mode" = true ]]; then
        action35f_outer_test_role=node-a
        [[ "$action35f_outer_node" = "$action35f_outer_node_b" ]] && action35f_outer_test_role=node-b
        action35f_outer_test_node=$CADDY_ACTION35F_PRODUCTION_TEST_ROOT/$action35f_outer_test_role
        if [[ ! -d "$action35f_outer_test_node/etc" ]]; then
            ACTION35F_KEEP_TEST_ROOT=0 /bin/bash "$action35f_outer_repository/Caddy/tests/coupled-serving-health-deployment-regression.sh" \
                --prepare-node "$action35f_outer_test_node" "$action35f_outer_test_role"
        fi
        action35f_outer_test_upload=$action35f_outer_test_node$action35f_outer_remote_root
    fi

    action35f_outer_stream "$action35f_outer_label-prepare" "$action35f_outer_node" user \
        "$action35f_outer_payload/remote/prepare-upload.sh" \
        "$action35f_outer_remote_root" || return 1
    if [[ "$action35f_outer_node" = "$action35f_outer_node_a" ]]; then
        action35f_outer_node_a_upload_present=true
    else
        action35f_outer_node_b_upload_present=true
    fi
    action35f_outer_run "$action35f_outer_label-upload" "$action35f_outer_scp_command" \
        "$action35f_outer_evidence/payload.tar" \
        "$action35f_outer_node:$action35f_outer_remote_root/payload.tar" || return 1
    action35f_outer_stream "$action35f_outer_label-accept" "$action35f_outer_node" user \
        "$action35f_outer_payload/remote/accept-upload.sh" \
        "$action35f_outer_remote_root" || return 1

    if [[ "$action35f_outer_test_mode" = true ]]; then
        ACTION35F_KEEP_TEST_ROOT=0 /bin/bash \
            "$action35f_outer_repository/Caddy/tests/coupled-serving-health-deployment-regression.sh" \
            --add-baseline-inventory "$action35f_outer_test_upload" \
            "$action35f_outer_test_node" "$action35f_outer_test_role"
    fi
}

action35f_outer_dispatch() {
    local action35f_outer_node=$1
    local action35f_outer_role=$2
    local action35f_outer_label=$3

    local action35f_outer_remote_command
    printf -v action35f_outer_remote_command \
        'sudo -n /bin/bash %q --node-role %q --payload %q' \
        "$action35f_outer_remote_root/transaction.sh" "$action35f_outer_role" \
        "$action35f_outer_remote_root"
    printf '%s\n' "$action35f_outer_remote_command" \
        >"$action35f_outer_evidence/$action35f_outer_label-command.argv"
    action35f_outer_run "$action35f_outer_label-transaction" \
        "$action35f_outer_ssh_command" "$action35f_outer_node" \
        "$action35f_outer_remote_command"
}

action35f_outer_prepare_protocol_release() {
    action35f_outer_candidate_present=true
    action35f_outer_stream release-publish "$action35f_outer_node_a" root \
        "$action35f_outer_payload/remote/publish-release.sh" \
        "$action35f_outer_remote_root" || return 1
    sed -n 's/^Published protocol-v2 release \([^ ]*\) for receiver validation\.$/\1/p' \
        "$action35f_outer_evidence/release-publish.stdout" >"$action35f_outer_evidence/revision"
    [[ "$(wc -l <"$action35f_outer_evidence/revision")" -eq 1 ]]
}

action35f_outer_accept_standby_release() {
    local action35f_outer_revision
    action35f_outer_revision=$(<"$action35f_outer_evidence/revision")
    action35f_outer_stream release-node-b-accepted "$action35f_outer_node_b" user \
        "$action35f_outer_payload/remote/wait-revision.sh" \
        "$action35f_outer_revision"
}

action35f_outer_promote_node_a_release() {
    local action35f_outer_revision
    action35f_outer_revision=$(<"$action35f_outer_evidence/revision")
    action35f_outer_stream release-node-a-promote "$action35f_outer_node_a" root \
        "$action35f_outer_payload/remote/promote-release.sh" \
        "$action35f_outer_revision"
}

action35f_outer_capture_ownership() {
    local action35f_outer_sample=$1

    if [[ "$action35f_outer_test_mode" = true ]]; then
        action35f_outer_run "ownership-node-a-$action35f_outer_sample" /bin/bash \
            "$CADDY_ACTION35F_PRODUCTION_TEST_ROOT/node-a/bin/ownership" node-a || return 1
        action35f_outer_run "ownership-node-b-$action35f_outer_sample" /bin/bash \
            "$CADDY_ACTION35F_PRODUCTION_TEST_ROOT/node-b/bin/ownership" node-b || return 1
    else
        for action35f_outer_role in node-a node-b; do
            action35f_outer_node=$action35f_outer_node_a
            [[ "$action35f_outer_role" = node-a ]] || action35f_outer_node=$action35f_outer_node_b
            action35f_outer_stream \
                "ownership-$action35f_outer_role-$action35f_outer_sample" \
                "$action35f_outer_node" user \
                "$action35f_outer_payload/remote/ownership.sh" || return 1
        done
    fi
    grep -Eq '^ipv4=(\(us\) 2 "Master"|Master) ipv6=(\(us\) 2 "Master"|Master) vip_count=4$' \
        "$action35f_outer_evidence/ownership-node-a-$action35f_outer_sample.stdout" || return 1
    grep -Eq '^ipv4=(\(us\) 1 "Backup"|Backup) ipv6=(\(us\) 1 "Backup"|Backup) vip_count=0$' \
        "$action35f_outer_evidence/ownership-node-b-$action35f_outer_sample.stdout" || return 1
}

# Uploading is non-mutating, but the recovery trap must already own exact
# cleanup before the first remote upload directory can be created.
trap action35f_outer_cleanup_trap EXIT INT TERM
action35f_outer_capture_original_release "$action35f_outer_node_a" node-a
action35f_outer_capture_original_release "$action35f_outer_node_b" node-b
action35f_outer_dispose_retained_candidate "$action35f_outer_node_a" node-a
action35f_outer_dispose_retained_candidate "$action35f_outer_node_b" node-b
action35f_outer_upload "$action35f_outer_node_a" node-a
action35f_outer_upload "$action35f_outer_node_b" node-b

# Construct one Node A release and require Node B to accept that exact
# protocol-v2 revision before any serving-health mutation.
action35f_outer_start_availability_probe
sleep 1
action35f_outer_prepare_protocol_release
action35f_outer_accept_standby_release
action35f_outer_node_b_mutated=true

# Standby first. Node A is not dispatched until Node B has returned accepted.
action35f_outer_dispatch "$action35f_outer_node_b" node-b node-b
if [[ "$action35f_outer_test_mode" = true && "${ACTION35F_TEST_FAIL_AFTER_NODE_B:-0}" = 1 ]]; then
    exit 1
fi
action35f_outer_promote_node_a_release
action35f_outer_node_a_mutated=true
action35f_outer_dispatch "$action35f_outer_node_a" node-a node-a

for action35f_outer_sample in 1 2 3; do
    action35f_outer_capture_ownership "$action35f_outer_sample"
    sleep 1
done

if [[ "$action35f_outer_test_mode" = true ]]; then
    action35f_outer_run cluster-convergence test -f \
        "$CADDY_ACTION35F_PRODUCTION_TEST_ROOT/node-a/tmp/caddy-action35f/node-a/post-caddy-3.status" || exit 1
    action35f_outer_run node-b-postcondition test -f \
        "$CADDY_ACTION35F_PRODUCTION_TEST_ROOT/node-b/tmp/caddy-action35f/node-b/post-caddy-3.status" || exit 1
else
    action35f_outer_stream cluster-convergence "$action35f_outer_node_a" user \
        "$action35f_outer_payload/remote/health.sh" || exit 1
    action35f_outer_stream node-b-postcondition "$action35f_outer_node_b" user \
        "$action35f_outer_payload/remote/health.sh" || exit 1
fi
action35f_outer_stop_availability_probe

action35f_outer_remove_candidate || exit 125
action35f_outer_candidate_present=false

# Cluster acceptance is complete. Release rollback authority is no longer
# needed; remove only the exact action-owned backups before upload cleanup.
action35f_outer_node_a_mutated=false
action35f_outer_node_b_mutated=false
for action35f_outer_role in node-a node-b; do
    if [[ "$action35f_outer_test_mode" = true ]]; then
        action35f_outer_run "backup-cleanup-$action35f_outer_role" rm -rf -- \
            "$CADDY_ACTION35F_PRODUCTION_TEST_ROOT/$action35f_outer_role/var/backups/caddy-action35f/$action35f_outer_role" || exit 125
    else
        action35f_outer_node=$action35f_outer_node_a
        [[ "$action35f_outer_role" = node-a ]] || action35f_outer_node=$action35f_outer_node_b
        action35f_outer_stream "backup-cleanup-$action35f_outer_role" \
            "$action35f_outer_node" root \
            "$action35f_outer_payload/remote/remove-tree.sh" \
            "/var/backups/caddy-action35f/$action35f_outer_role" || exit 125
    fi
done

for action35f_outer_node in "$action35f_outer_node_a" "$action35f_outer_node_b"; do
    if [[ "$action35f_outer_test_mode" = true ]]; then
        action35f_outer_test_role=node-a
        [[ "$action35f_outer_node" = "$action35f_outer_node_b" ]] && action35f_outer_test_role=node-b
        action35f_outer_run "cleanup-${action35f_outer_node#*@}" /bin/bash -c \
            'find "$1" -xdev -mindepth 1 -delete && rmdir "$1"' _ \
            "$CADDY_ACTION35F_PRODUCTION_TEST_ROOT/$action35f_outer_test_role$action35f_outer_remote_root" || exit 125
    else
        action35f_outer_stream "cleanup-${action35f_outer_node#*@}" \
            "$action35f_outer_node" root \
            "$action35f_outer_payload/remote/remove-tree.sh" \
            "$action35f_outer_remote_root" || exit 125
    fi
    if [[ "$action35f_outer_node" = "$action35f_outer_node_a" ]]; then
        action35f_outer_node_a_upload_present=false
    else
        action35f_outer_node_b_upload_present=false
    fi
done

if [[ "$action35f_outer_test_mode" = true ]]; then
    readonly action35f_outer_policy_evidence=${CADDY_PRODUCTION_PATH_EVIDENCE_ROOT:-$CADDY_ACTION35F_PRODUCTION_TEST_ROOT/evidence}
    if [[ ! -e "$action35f_outer_policy_evidence" ]]; then
        install -d -m 0700 "$action35f_outer_policy_evidence"
    fi
    [[ -d "$action35f_outer_policy_evidence" && ! -L "$action35f_outer_policy_evidence" ]] || exit 1
    [[ -z "$(find "$action35f_outer_policy_evidence" -mindepth 1 -maxdepth 1 -print -quit)" ]] || exit 1
    chmod 0700 "$action35f_outer_policy_evidence"
    install -m 0600 "$action35f_outer_evidence/payload.sha256" "$action35f_outer_policy_evidence/payload.sha256"
    install -m 0600 "$action35f_outer_evidence/remote-path" "$action35f_outer_policy_evidence/remote-path"
    install -m 0600 "$action35f_outer_evidence/node-b-command.argv" "$action35f_outer_policy_evidence/remote-command.argv"
    printf 'prepare\t%s\naccept\t%s\ndisposition\t%s\n' \
        "$(<"$action35f_outer_evidence/node-b-prepare.status")" \
        "$(<"$action35f_outer_evidence/node-b-accept.status")" \
        "$(<"$action35f_outer_evidence/cleanup-10.1.0.54.status")" \
        >"$action35f_outer_policy_evidence/upload-events.tsv"
    install -m 0600 "$action35f_outer_evidence/node-b-transaction.status" \
        "$action35f_outer_policy_evidence/transaction.status"
    [[ "${ACTION35F_TRANSPORT_EVIDENCE:-}" = /tmp/* &&
        -f "$ACTION35F_TRANSPORT_EVIDENCE" && ! -L "$ACTION35F_TRANSPORT_EVIDENCE" ]] || exit 1
    install -m 0600 "$ACTION35F_TRANSPORT_EVIDENCE" \
        "$action35f_outer_policy_evidence/transport-events.tsv"
    awk '{ total += $1 } END { print total + 0 }' \
        "$CADDY_ACTION35F_PRODUCTION_TEST_ROOT/node-a/tmp/caddy-action35f/node-a/mutation-count" \
        "$CADDY_ACTION35F_PRODUCTION_TEST_ROOT/node-b/tmp/caddy-action35f/node-b/mutation-count" \
        >"$action35f_outer_policy_evidence/mutation-count"
    chmod 0600 "$action35f_outer_policy_evidence/"*
fi

printf '%s_evidence_parent=true\n' "$action35f_outer_prefix"
printf '%s_payload_constructed=true\n' "$action35f_outer_prefix"
printf '%s_remote_path_generated=true\n' "$action35f_outer_prefix"
printf '%s_upload_disposition=true\n' "$action35f_outer_prefix"
printf '%s_standby_first=true\n' "$action35f_outer_prefix"
printf '%s_complete=true\n' "$action35f_outer_prefix"
