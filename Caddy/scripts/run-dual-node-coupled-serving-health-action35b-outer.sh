#!/usr/bin/env bash
# shellcheck disable=SC2016 # Remote Bash programs intentionally expand only on the node.

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly action35b_outer_prefix=action_35b_outer
readonly transaction_sha256=1abbd4dba18227a62fdce2ca32bb18290efc272d32306c2438d991320dc37143
readonly action35b_outer_node_a=pi@10.1.0.53
readonly action35b_outer_node_b=pi@10.1.0.54
readonly action35b_outer_remote_root=/tmp/caddy-action35b-upload

action35b_outer_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly action35b_outer_directory
readonly action35b_outer_repository=${action35b_outer_directory%/Caddy/scripts}
readonly action35b_outer_transaction_source=$action35b_outer_directory/apply-coupled-serving-health-action35b.sh
readonly action35b_outer_manifest=$action35b_outer_repository/Caddy/manifests/serving-health-production.tsv
readonly action35b_outer_state=$action35b_outer_repository/Caddy/manifests/current-live-state.tsv
readonly action35b_outer_ssh_command=${ACTION35B_SSH_COMMAND:-ssh}
readonly action35b_outer_scp_command=${ACTION35B_SCP_COMMAND:-scp}
action35b_outer_node_a_mutated=false
action35b_outer_node_b_mutated=false
action35b_outer_recovery_failed=false
action35b_outer_probe_pid=

if [[ "${1:-}" = --production-path-test && $# -eq 1 ]]; then
    exec /bin/bash "$action35b_outer_repository/Caddy/tests/coupled-serving-health-deployment-regression.sh" \
        --entrypoint outer
fi

action35b_outer_test_mode=false
if [[ "${1:-}" = --production-path-test-inner && $# -eq 1 ]]; then
    action35b_outer_test_mode=true
elif (($#)); then
    exit 64
fi
cd -- "$action35b_outer_repository"

if [[ "$action35b_outer_test_mode" = false ]]; then
    /bin/bash Caddy/tests/deployable-successor-policy.sh --authorization-ready >/dev/null
    /bin/bash Caddy/tests/coupled-serving-health-deployment-regression.sh >/dev/null
fi
[[ "$(sha256sum "$action35b_outer_transaction_source" | awk '{ print $1 }')" = "$transaction_sha256" ]] || exit 1

action35b_outer_evidence=/tmp/caddy-ssh-evidence/action35b
if [[ "$action35b_outer_test_mode" = true ]]; then
    [[ "${CADDY_ACTION35B_PRODUCTION_TEST_ROOT:-}" = /tmp/* ]] || exit 64
    action35b_outer_evidence=$CADDY_ACTION35B_PRODUCTION_TEST_ROOT/ssh-evidence
fi
readonly action35b_outer_evidence
[[ ! -e "$action35b_outer_evidence" ]] || exit 1
install -d -m 0700 "$(dirname -- "$action35b_outer_evidence")" "$action35b_outer_evidence"
action35b_outer_payload=$(mktemp -d /tmp/caddy-action35b-payload.XXXXXX)
readonly action35b_outer_payload
trap 'rm -rf -- "$action35b_outer_payload"' EXIT INT TERM

install -d -m 0700 \
    "$action35b_outer_payload/files/homelab-server-configs" \
    "$action35b_outer_payload/files/homelab-dns" \
    "$action35b_outer_payload/remote"
install -m 0600 "$action35b_outer_manifest" \
    "$action35b_outer_payload/serving-health-production.tsv"
install -m 0600 "$action35b_outer_state" "$action35b_outer_payload/current-live-state.tsv"
install -m 0600 "$action35b_outer_repository/Caddy/manifests/production-artifacts.tsv" \
    "$action35b_outer_payload/production-artifacts.tsv"
install -m 0700 "$action35b_outer_transaction_source" "$action35b_outer_payload/transaction.sh"

while IFS=$'\t' read -r action35b_outer_repository_name action35b_outer_source \
    _ _ _ _; do
    [[ -n "$action35b_outer_repository_name" && "$action35b_outer_repository_name" != \#* ]] || continue
    action35b_outer_source_root=$action35b_outer_repository
    [[ "$action35b_outer_repository_name" = homelab-server-configs ]] ||
        action35b_outer_source_root=${action35b_outer_repository%/homelab-server-configs}/homelab-dns
    action35b_outer_destination=$action35b_outer_payload/files/$action35b_outer_repository_name/$action35b_outer_source
    install -d -m 0700 "$(dirname -- "$action35b_outer_destination")"
    install -m 0600 "$action35b_outer_source_root/$action35b_outer_source" \
        "$action35b_outer_destination"
done <"$action35b_outer_manifest"

cat >"$action35b_outer_payload/remote/prepare-upload.sh" <<'REMOTE'
#!/usr/bin/env bash
set -Eeuo pipefail
umask 077
readonly root_prefix=${ACTION35B_ROOT_PREFIX:-}
readonly target=$root_prefix$1
[[ "$1" = /tmp/caddy-action35b-upload && ! -e "$target" && ! -L "$target" ]]
install -d -m 0700 "$target"
REMOTE
cat >"$action35b_outer_payload/remote/accept-upload.sh" <<'REMOTE'
#!/usr/bin/env bash
set -Eeuo pipefail
readonly root_prefix=${ACTION35B_ROOT_PREFIX:-}
readonly target=$root_prefix$1
[[ "$1" = /tmp/caddy-action35b-upload && -d "$target" && ! -L "$target" ]]
[[ -f "$target/payload.tar" && ! -L "$target/payload.tar" ]]
tar -tf "$target/payload.tar" >/dev/null
tar -C "$target" -xf "$target/payload.tar"
REMOTE
cat >"$action35b_outer_payload/remote/remove-tree.sh" <<'REMOTE'
#!/usr/bin/env bash
set -Eeuo pipefail
readonly target=$1
case "$target" in
    /tmp/caddy-action35b-upload | /var/backups/caddy-action35b/node-a | /var/backups/caddy-action35b/node-b) ;;
    *) exit 64 ;;
esac
[[ -d "$target" && ! -L "$target" ]]
find "$target" -xdev -mindepth 1 -delete
rmdir "$target"
REMOTE
cat >"$action35b_outer_payload/remote/ownership.sh" <<'REMOTE'
#!/usr/bin/env bash
set -Eeuo pipefail
cd /
ipv4=$(timeout 2 busctl get-property org.keepalived.Vrrp1 /org/keepalived/Vrrp1/Instance/eth0/100/IPv4 org.keepalived.Vrrp1.Instance State)
ipv6=$(timeout 2 busctl get-property org.keepalived.Vrrp1 /org/keepalived/Vrrp1/Instance/eth0/101/IPv6 org.keepalived.Vrrp1.Instance State)
count=$(ip -o address show dev eth0 | awk '$4 ~ /^(10\.1\.0\.(55|56)\/22|fd36:5aa8:6971:1::(55|56)\/128)$/ { n++ } END { print n + 0 }')
printf 'ipv4=%s ipv6=%s vip_count=%s\n' "$ipv4" "$ipv6" "$count"
REMOTE
cat >"$action35b_outer_payload/remote/health.sh" <<'REMOTE'
#!/usr/bin/env bash
set -Eeuo pipefail
cd /
/usr/local/libexec/check-caddy.sh
/etc/scripts/check-dns.sh
REMOTE
cat >"$action35b_outer_payload/remote/restore-release.sh" <<'REMOTE'
#!/usr/bin/env bash
set -Eeuo pipefail
readonly original=$1
case "$original" in /etc/caddy/releases/*) ;; *) exit 64 ;; esac
[[ -d "$original" && ! -L "$original" ]]
ln -sfn "$original" /etc/caddy/current
systemctl reload caddy.service
REMOTE
cat >"$action35b_outer_payload/remote/publish-release.sh" <<'REMOTE'
#!/usr/bin/env bash
set -Eeuo pipefail
cd /
readonly upload=$1
readonly root_prefix=${ACTION35B_ROOT_PREFIX:-}
readonly candidate=$root_prefix/tmp/caddy-action35b-release
[[ "$upload" = /tmp/caddy-action35b-upload && ! -e "$candidate" && ! -L "$candidate" ]]
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
env CADDY_CONFIG_ROOT="$candidate" caddy validate \
    --config "$candidate/Caddyfile" --adapter caddyfile >/dev/null
"$root_prefix/usr/local/libexec/publish-release-v2.sh" --source "$candidate" --node-role node-a
REMOTE
cat >"$action35b_outer_payload/remote/wait-revision.sh" <<'REMOTE'
#!/usr/bin/env bash
set -Eeuo pipefail
readonly expected=$1
readonly root_prefix=${ACTION35B_ROOT_PREFIX:-}
[[ "$expected" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]
for _ in $(seq 1 60); do
    if [[ "$(jq -r .revision "$root_prefix/etc/caddy/current/release-manifest.json")" = "$expected" ]]; then
        exit 0
    fi
    sleep 1
done
exit 1
REMOTE
cat >"$action35b_outer_payload/remote/promote-release.sh" <<'REMOTE'
#!/usr/bin/env bash
set -Eeuo pipefail
cd /
readonly revision=$1
readonly root_prefix=${ACTION35B_ROOT_PREFIX:-}
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
chmod 0700 "$action35b_outer_payload/remote/"*.sh

tar --sort=name --mtime=@0 --owner=0 --group=0 --numeric-owner \
    -C "$action35b_outer_payload" -cf "$action35b_outer_evidence/payload.tar" .
sha256sum "$action35b_outer_evidence/payload.tar" | awk '{ print $1 }' \
    >"$action35b_outer_evidence/payload.sha256"
printf '%s\n' "$action35b_outer_remote_root" >"$action35b_outer_evidence/remote-path"

action35b_outer_run() {
    local action35b_outer_label=$1

    shift
    local action35b_outer_status=0
    : >"$action35b_outer_evidence/$action35b_outer_label.stdout"
    : >"$action35b_outer_evidence/$action35b_outer_label.stderr"
    "$@" >"$action35b_outer_evidence/$action35b_outer_label.stdout" \
        2>"$action35b_outer_evidence/$action35b_outer_label.stderr" || action35b_outer_status=$?
    printf '%s\n' "$action35b_outer_status" >"$action35b_outer_evidence/$action35b_outer_label.status"
    return "$action35b_outer_status"
}

action35b_outer_stream() {
    local action35b_outer_label=$1
    local action35b_outer_node=$2
    local action35b_outer_privilege=$3
    local action35b_outer_program=$4
    shift 4
    local action35b_outer_remote='cd / && /bin/bash -s --'
    local action35b_outer_argument
    local action35b_outer_status=0

    [[ "$action35b_outer_privilege" = user ]] ||
        action35b_outer_remote='cd / && sudo -n /bin/bash -s --'
    for action35b_outer_argument in "$@"; do
        printf -v action35b_outer_remote '%s %q' "$action35b_outer_remote" \
            "$action35b_outer_argument"
    done
    printf '%s\n' "$action35b_outer_remote" \
        >"$action35b_outer_evidence/$action35b_outer_label.remote-command"
    : >"$action35b_outer_evidence/$action35b_outer_label.stdout"
    : >"$action35b_outer_evidence/$action35b_outer_label.stderr"
    "$action35b_outer_ssh_command" "$action35b_outer_node" \
        "$action35b_outer_remote" <"$action35b_outer_program" \
        >"$action35b_outer_evidence/$action35b_outer_label.stdout" \
        2>"$action35b_outer_evidence/$action35b_outer_label.stderr" ||
        action35b_outer_status=$?
    printf '%s\n' "$action35b_outer_status" \
        >"$action35b_outer_evidence/$action35b_outer_label.status"
    return "$action35b_outer_status"
}

action35b_outer_restore_node() {
    local action35b_outer_node=$1
    local action35b_outer_role=$2
    local action35b_outer_original=$3

    if [[ "$action35b_outer_test_mode" = true ]]; then
        local action35b_outer_test_node=$CADDY_ACTION35B_PRODUCTION_TEST_ROOT/$action35b_outer_role
        if [[ -d "$action35b_outer_test_node/var/backups/caddy-action35b/$action35b_outer_role" ]]; then
            /bin/bash "$action35b_outer_transaction_source" --node-role "$action35b_outer_role" \
                --rollback-existing --production-path-test "$action35b_outer_test_node" || return 1
        fi
        ln -sfn "${action35b_outer_original#"$action35b_outer_test_node/etc/caddy/"}" \
            "$action35b_outer_test_node/etc/caddy/current"
    else
        if ssh "$action35b_outer_node" test -d \
            "/var/backups/caddy-action35b/$action35b_outer_role"; then
            ssh "$action35b_outer_node" sudo /bin/bash \
                "$action35b_outer_remote_root/transaction.sh" --node-role "$action35b_outer_role" \
                --rollback-existing || return 1
        fi
        action35b_outer_stream "$action35b_outer_role-restore-release" \
            "$action35b_outer_node" root \
            "$action35b_outer_payload/remote/restore-release.sh" \
            "$action35b_outer_original" || return 1
    fi
}

action35b_outer_cleanup_trap() {
    local action35b_outer_status=$?

    trap - EXIT INT TERM
    if [[ -n "$action35b_outer_probe_pid" ]]; then
        kill "$action35b_outer_probe_pid" >/dev/null 2>&1 || :
        wait "$action35b_outer_probe_pid" >/dev/null 2>&1 || :
    fi
    if ((action35b_outer_status != 0)); then
        if [[ "$action35b_outer_node_a_mutated" = true ]]; then
            action35b_outer_restore_node "$action35b_outer_node_a" node-a \
                "$(<"$action35b_outer_evidence/node-a-original-release.path")" ||
                action35b_outer_recovery_failed=true
        fi
        if [[ "$action35b_outer_node_b_mutated" = true ]]; then
            action35b_outer_restore_node "$action35b_outer_node_b" node-b \
                "$(<"$action35b_outer_evidence/node-b-original-release.path")" ||
                action35b_outer_recovery_failed=true
        fi
        [[ "$action35b_outer_recovery_failed" = false ]] || exit 125
    fi
    rm -rf -- "$action35b_outer_payload"
    exit "$action35b_outer_status"
}

action35b_outer_start_availability_probe() {
    : >"$action35b_outer_evidence/availability.tsv"
    (
        while :; do
            action35b_outer_probe_status=0
            if [[ "$action35b_outer_test_mode" = true ]]; then
                test -L "$CADDY_ACTION35B_PRODUCTION_TEST_ROOT/node-a/etc/caddy/current" &&
                    test -L "$CADDY_ACTION35B_PRODUCTION_TEST_ROOT/node-b/etc/caddy/current" ||
                    action35b_outer_probe_status=$?
            else
                dig @10.1.0.55 pihole.local.theama.co A +short +time=1 +tries=1 >/dev/null &&
                    dig @fd36:5aa8:6971:1::55 pihole.local.theama.co AAAA +short +time=1 +tries=1 >/dev/null &&
                    curl --fail --silent --show-error --max-time 1 --output /dev/null \
                        --resolve pihole-admin.local.theama.co:443:10.1.0.56 \
                        https://pihole-admin.local.theama.co/admin/login.php &&
                    curl --fail --silent --show-error --max-time 1 --output /dev/null --ipv6 \
                        --resolve 'pihole-admin.local.theama.co:443:[fd36:5aa8:6971:1::56]' \
                        https://pihole-admin.local.theama.co/admin/login.php ||
                    action35b_outer_probe_status=$?
            fi
            printf '%(%s)T\t%s\n' -1 "$action35b_outer_probe_status" \
                >>"$action35b_outer_evidence/availability.tsv"
            sleep 1
        done
    ) &
    action35b_outer_probe_pid=$!
}

action35b_outer_stop_availability_probe() {
    kill "$action35b_outer_probe_pid" >/dev/null 2>&1 || :
    wait "$action35b_outer_probe_pid" >/dev/null 2>&1 || :
    action35b_outer_probe_pid=
    [[ "$(wc -l <"$action35b_outer_evidence/availability.tsv")" -ge 2 ]]
    awk -F '\t' '$2 != 0 { bad = 1 } END { exit bad }' \
        "$action35b_outer_evidence/availability.tsv"
}

action35b_outer_capture_original_release() {
    local action35b_outer_node=$1
    local action35b_outer_role=$2

    if [[ "$action35b_outer_test_mode" = true ]]; then
        readlink -f -- "$CADDY_ACTION35B_PRODUCTION_TEST_ROOT/$action35b_outer_role/etc/caddy/current" \
            >"$action35b_outer_evidence/$action35b_outer_role-original-release.path"
    else
        action35b_outer_run "$action35b_outer_role-original-release" ssh "$action35b_outer_node" \
            readlink -f -- /etc/caddy/current
        install -m 0600 "$action35b_outer_evidence/$action35b_outer_role-original-release.stdout" \
            "$action35b_outer_evidence/$action35b_outer_role-original-release.path"
    fi
}

action35b_outer_upload() {
    local action35b_outer_node=$1
    local action35b_outer_label=$2
    local action35b_outer_test_role=
    local action35b_outer_test_node=
    local action35b_outer_test_upload=

    if [[ "$action35b_outer_test_mode" = true ]]; then
        action35b_outer_test_role=node-a
        [[ "$action35b_outer_node" = "$action35b_outer_node_b" ]] && action35b_outer_test_role=node-b
        action35b_outer_test_node=$CADDY_ACTION35B_PRODUCTION_TEST_ROOT/$action35b_outer_test_role
        ACTION35B_KEEP_TEST_ROOT=0 /bin/bash "$action35b_outer_repository/Caddy/tests/coupled-serving-health-deployment-regression.sh" \
            --prepare-node "$action35b_outer_test_node" "$action35b_outer_test_role"
        action35b_outer_test_upload=$action35b_outer_test_node$action35b_outer_remote_root
    fi

    action35b_outer_stream "$action35b_outer_label-prepare" "$action35b_outer_node" user \
        "$action35b_outer_payload/remote/prepare-upload.sh" \
        "$action35b_outer_remote_root" || return 1
    action35b_outer_run "$action35b_outer_label-upload" "$action35b_outer_scp_command" \
        "$action35b_outer_evidence/payload.tar" \
        "$action35b_outer_node:$action35b_outer_remote_root/payload.tar" || return 1
    action35b_outer_stream "$action35b_outer_label-accept" "$action35b_outer_node" user \
        "$action35b_outer_payload/remote/accept-upload.sh" \
        "$action35b_outer_remote_root" || return 1

    if [[ "$action35b_outer_test_mode" = true ]]; then
        ACTION35B_KEEP_TEST_ROOT=0 /bin/bash \
            "$action35b_outer_repository/Caddy/tests/coupled-serving-health-deployment-regression.sh" \
            --add-baseline-inventory "$action35b_outer_test_upload" \
            "$action35b_outer_test_node" "$action35b_outer_test_role"
    fi
}

action35b_outer_dispatch() {
    local action35b_outer_node=$1
    local action35b_outer_role=$2
    local action35b_outer_label=$3

    local action35b_outer_remote_command
    printf -v action35b_outer_remote_command \
        'sudo -n /bin/bash %q --node-role %q --payload %q' \
        "$action35b_outer_remote_root/transaction.sh" "$action35b_outer_role" \
        "$action35b_outer_remote_root"
    printf '%s\n' "$action35b_outer_remote_command" \
        >"$action35b_outer_evidence/$action35b_outer_label-command.argv"
    action35b_outer_run "$action35b_outer_label-transaction" \
        "$action35b_outer_ssh_command" "$action35b_outer_node" \
        "$action35b_outer_remote_command"
}

action35b_outer_prepare_protocol_release() {
    action35b_outer_stream release-publish "$action35b_outer_node_a" root \
        "$action35b_outer_payload/remote/publish-release.sh" \
        "$action35b_outer_remote_root" || return 1
    sed -n 's/^Published protocol-v2 release \([^ ]*\) for receiver validation\.$/\1/p' \
        "$action35b_outer_evidence/release-publish.stdout" >"$action35b_outer_evidence/revision"
    [[ "$(wc -l <"$action35b_outer_evidence/revision")" -eq 1 ]]
}

action35b_outer_accept_standby_release() {
    local action35b_outer_revision
    action35b_outer_revision=$(<"$action35b_outer_evidence/revision")
    action35b_outer_stream release-node-b-accepted "$action35b_outer_node_b" user \
        "$action35b_outer_payload/remote/wait-revision.sh" \
        "$action35b_outer_revision"
}

action35b_outer_promote_node_a_release() {
    local action35b_outer_revision
    action35b_outer_revision=$(<"$action35b_outer_evidence/revision")
    action35b_outer_stream release-node-a-promote "$action35b_outer_node_a" root \
        "$action35b_outer_payload/remote/promote-release.sh" \
        "$action35b_outer_revision"
}

action35b_outer_capture_ownership() {
    local action35b_outer_sample=$1

    if [[ "$action35b_outer_test_mode" = true ]]; then
        action35b_outer_run "ownership-node-a-$action35b_outer_sample" /bin/bash \
            "$CADDY_ACTION35B_PRODUCTION_TEST_ROOT/node-a/bin/ownership" node-a || return 1
        action35b_outer_run "ownership-node-b-$action35b_outer_sample" /bin/bash \
            "$CADDY_ACTION35B_PRODUCTION_TEST_ROOT/node-b/bin/ownership" node-b || return 1
    else
        for action35b_outer_role in node-a node-b; do
            action35b_outer_node=$action35b_outer_node_a
            [[ "$action35b_outer_role" = node-a ]] || action35b_outer_node=$action35b_outer_node_b
            action35b_outer_stream \
                "ownership-$action35b_outer_role-$action35b_outer_sample" \
                "$action35b_outer_node" user \
                "$action35b_outer_payload/remote/ownership.sh" || return 1
        done
    fi
    grep -Eq '^ipv4=(\(us\) 2 "Master"|Master) ipv6=(\(us\) 2 "Master"|Master) vip_count=4$' \
        "$action35b_outer_evidence/ownership-node-a-$action35b_outer_sample.stdout" || return 1
    grep -Eq '^ipv4=(\(us\) 1 "Backup"|Backup) ipv6=(\(us\) 1 "Backup"|Backup) vip_count=0$' \
        "$action35b_outer_evidence/ownership-node-b-$action35b_outer_sample.stdout" || return 1
}

# Uploading is non-mutating. Construct one Node A release and require Node B to
# accept that exact protocol-v2 revision before any serving-health mutation.
action35b_outer_upload "$action35b_outer_node_a" node-a
action35b_outer_upload "$action35b_outer_node_b" node-b
action35b_outer_capture_original_release "$action35b_outer_node_a" node-a
action35b_outer_capture_original_release "$action35b_outer_node_b" node-b
trap action35b_outer_cleanup_trap EXIT INT TERM
action35b_outer_start_availability_probe
sleep 1
action35b_outer_prepare_protocol_release
action35b_outer_accept_standby_release
action35b_outer_node_b_mutated=true

# Standby first. Node A is not dispatched until Node B has returned accepted.
action35b_outer_dispatch "$action35b_outer_node_b" node-b node-b
if [[ "$action35b_outer_test_mode" = true && "${ACTION35B_TEST_FAIL_AFTER_NODE_B:-0}" = 1 ]]; then
    exit 1
fi
action35b_outer_promote_node_a_release
action35b_outer_node_a_mutated=true
action35b_outer_dispatch "$action35b_outer_node_a" node-a node-a

for action35b_outer_sample in 1 2 3; do
    action35b_outer_capture_ownership "$action35b_outer_sample"
    sleep 1
done

if [[ "$action35b_outer_test_mode" = true ]]; then
    action35b_outer_run cluster-convergence test -f \
        "$CADDY_ACTION35B_PRODUCTION_TEST_ROOT/node-a/tmp/caddy-action35b/node-a/post-caddy-3.status" || exit 1
    action35b_outer_run node-b-postcondition test -f \
        "$CADDY_ACTION35B_PRODUCTION_TEST_ROOT/node-b/tmp/caddy-action35b/node-b/post-caddy-3.status" || exit 1
else
    action35b_outer_stream cluster-convergence "$action35b_outer_node_a" user \
        "$action35b_outer_payload/remote/health.sh" || exit 1
    action35b_outer_stream node-b-postcondition "$action35b_outer_node_b" user \
        "$action35b_outer_payload/remote/health.sh" || exit 1
fi
action35b_outer_stop_availability_probe

# Cluster acceptance is complete. Release rollback authority is no longer
# needed; remove only the exact action-owned backups before upload cleanup.
action35b_outer_node_a_mutated=false
action35b_outer_node_b_mutated=false
for action35b_outer_role in node-a node-b; do
    if [[ "$action35b_outer_test_mode" = true ]]; then
        action35b_outer_run "backup-cleanup-$action35b_outer_role" rm -rf -- \
            "$CADDY_ACTION35B_PRODUCTION_TEST_ROOT/$action35b_outer_role/var/backups/caddy-action35b/$action35b_outer_role" || exit 125
    else
        action35b_outer_node=$action35b_outer_node_a
        [[ "$action35b_outer_role" = node-a ]] || action35b_outer_node=$action35b_outer_node_b
        action35b_outer_stream "backup-cleanup-$action35b_outer_role" \
            "$action35b_outer_node" root \
            "$action35b_outer_payload/remote/remove-tree.sh" \
            "/var/backups/caddy-action35b/$action35b_outer_role" || exit 125
    fi
done

for action35b_outer_node in "$action35b_outer_node_a" "$action35b_outer_node_b"; do
    if [[ "$action35b_outer_test_mode" = true ]]; then
        action35b_outer_test_role=node-a
        [[ "$action35b_outer_node" = "$action35b_outer_node_b" ]] && action35b_outer_test_role=node-b
        action35b_outer_run "cleanup-${action35b_outer_node#*@}" /bin/bash -c \
            'find "$1" -xdev -mindepth 1 -delete && rmdir "$1"' _ \
            "$CADDY_ACTION35B_PRODUCTION_TEST_ROOT/$action35b_outer_test_role$action35b_outer_remote_root" || exit 125
    else
        action35b_outer_stream "cleanup-${action35b_outer_node#*@}" \
            "$action35b_outer_node" root \
            "$action35b_outer_payload/remote/remove-tree.sh" \
            "$action35b_outer_remote_root" || exit 125
    fi
done

if [[ "$action35b_outer_test_mode" = true ]]; then
    readonly action35b_outer_policy_evidence=${CADDY_PRODUCTION_PATH_EVIDENCE_ROOT:-$CADDY_ACTION35B_PRODUCTION_TEST_ROOT/evidence}
    if [[ ! -e "$action35b_outer_policy_evidence" ]]; then
        install -d -m 0700 "$action35b_outer_policy_evidence"
    fi
    [[ -d "$action35b_outer_policy_evidence" && ! -L "$action35b_outer_policy_evidence" ]] || exit 1
    [[ -z "$(find "$action35b_outer_policy_evidence" -mindepth 1 -maxdepth 1 -print -quit)" ]] || exit 1
    chmod 0700 "$action35b_outer_policy_evidence"
    install -m 0600 "$action35b_outer_evidence/payload.sha256" "$action35b_outer_policy_evidence/payload.sha256"
    install -m 0600 "$action35b_outer_evidence/remote-path" "$action35b_outer_policy_evidence/remote-path"
    install -m 0600 "$action35b_outer_evidence/node-b-command.argv" "$action35b_outer_policy_evidence/remote-command.argv"
    printf 'prepare\t%s\naccept\t%s\ndisposition\t%s\n' \
        "$(<"$action35b_outer_evidence/node-b-prepare.status")" \
        "$(<"$action35b_outer_evidence/node-b-accept.status")" \
        "$(<"$action35b_outer_evidence/cleanup-10.1.0.54.status")" \
        >"$action35b_outer_policy_evidence/upload-events.tsv"
    install -m 0600 "$action35b_outer_evidence/node-b-transaction.status" \
        "$action35b_outer_policy_evidence/transaction.status"
    [[ "${ACTION35B_TRANSPORT_EVIDENCE:-}" = /tmp/* &&
        -f "$ACTION35B_TRANSPORT_EVIDENCE" && ! -L "$ACTION35B_TRANSPORT_EVIDENCE" ]] || exit 1
    install -m 0600 "$ACTION35B_TRANSPORT_EVIDENCE" \
        "$action35b_outer_policy_evidence/transport-events.tsv"
    awk '{ total += $1 } END { print total + 0 }' \
        "$CADDY_ACTION35B_PRODUCTION_TEST_ROOT/node-a/tmp/caddy-action35b/node-a/mutation-count" \
        "$CADDY_ACTION35B_PRODUCTION_TEST_ROOT/node-b/tmp/caddy-action35b/node-b/mutation-count" \
        >"$action35b_outer_policy_evidence/mutation-count"
    chmod 0600 "$action35b_outer_policy_evidence/"*
fi

printf '%s_evidence_parent=true\n' "$action35b_outer_prefix"
printf '%s_payload_constructed=true\n' "$action35b_outer_prefix"
printf '%s_remote_path_generated=true\n' "$action35b_outer_prefix"
printf '%s_upload_disposition=true\n' "$action35b_outer_prefix"
printf '%s_standby_first=true\n' "$action35b_outer_prefix"
printf '%s_complete=true\n' "$action35b_outer_prefix"
