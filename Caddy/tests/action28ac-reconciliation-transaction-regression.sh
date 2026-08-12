#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export PATH
readonly PATH

script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
readonly caddy_root=${script_directory%/tests}
readonly reconciler=$caddy_root/scripts/reconcile-release-v2.sh

if [[ "${CADDY_VALIDATION_CONTAINER:-}" != 1 ]]; then
    printf 'action_28ac_reconciliation_transaction_host_deferred_to_debian=true\n'
    exit 0
fi

[[ "$(id -u)" -eq 0 ]]
trap 'printf "action_28ac_reconciliation_transaction_failure_line=%s\n" "$LINENO" >&2' ERR
getent group caddy-tls >/dev/null || groupadd --system caddy-tls
rm -rf -- /etc/caddy/current /etc/caddy/releases \
    /var/lib/caddy-sync/incoming /var/lib/caddy-sync/quarantine
install -d -m 0755 /etc/default /etc/caddy/releases /var/lib/caddy-sync/incoming/node-a
install -d -m 0750 /var/lib/caddy-sync/quarantine
printf 'CADDY_TEST_VALUE=fixture\n' >/etc/default/caddy-ha

fake_state=/tmp/action28ac-reconcile-systemctl
readonly fake_state
install -m 0600 /dev/null "$fake_state"
cat >/usr/bin/caddy <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
[[ "$1" = validate ]]
EOF
cat >/usr/bin/systemctl <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
if [[ "$1" = reload && "$2" = caddy.service ]]; then
    count=$(<"$ACTION28AB_SYSTEMCTL_STATE")
    count=$((count + 1))
    printf '%s\n' "$count" >"$ACTION28AB_SYSTEMCTL_STATE"
    if [[ -e /tmp/action28ac-reconcile-fail-next ]]; then
        rm -f /tmp/action28ac-reconcile-fail-next
        exit 1
    fi
    exit 0
fi
exit 64
EOF
chmod 0755 /usr/bin/caddy /usr/bin/systemctl
printf '0\n' >"$fake_state"
export ACTION28AB_SYSTEMCTL_STATE=$fake_state

make_release() {
    local action28ac_reconcile_revision=$1
    local action28ac_reconcile_parent=$2
    local action28ac_reconcile_payload=$3
    local action28ac_reconcile_destination=$4

    install -d -m 0750 "$action28ac_reconcile_destination"
    printf '%s\n' "$action28ac_reconcile_payload" \
        >"$action28ac_reconcile_destination/Caddyfile"
    jq -n --arg revision "$action28ac_reconcile_revision" \
        --arg parent "$action28ac_reconcile_parent" \
        '{revision: $revision, parent_revision: $parent, source_node: "node-a"}' \
        >"$action28ac_reconcile_destination/release-manifest.json"
    (
        cd "$action28ac_reconcile_destination"
        sha256sum ./Caddyfile ./release-manifest.json >manifest.sha256
    )
    : >"$action28ac_reconcile_destination/.finalize-request"
    : >"$action28ac_reconcile_destination/.complete"
    find "$action28ac_reconcile_destination" -type d -exec chmod 0550 {} +
    find "$action28ac_reconcile_destination" -type f -exec chmod 0440 {} +
}

make_release base '' base /etc/caddy/releases/base
ln -s /etc/caddy/releases/base /etc/caddy/current

make_release v1 base first /var/lib/caddy-sync/incoming/node-a/v1
v1_status=0
"$reconciler" >/tmp/action28ac-reconcile-v1.stdout \
    2>/tmp/action28ac-reconcile-v1.stderr || v1_status=$?
if [[ "$v1_status" -ne 0 ]]; then
    printf 'action_28ac_reconciliation_v1_status=%s\n' "$v1_status" >&2
    sed 's/^/action_28ac_reconciliation_v1_stderr=/' \
        /tmp/action28ac-reconcile-v1.stderr >&2
    exit "$v1_status"
fi
[[ "$(readlink -f /etc/caddy/current)" = /etc/caddy/releases/v1 ]]
[[ "$(<"$fake_state")" = 1 ]]
[[ -z "$(find /etc/caddy/releases -maxdepth 1 -name '.reconcile-*' -print -quit)" ]]

make_release v2 v1 second /var/lib/caddy-sync/incoming/node-a/v2
touch /tmp/action28ac-reconcile-fail-next
reload_status=0
"$reconciler" >/tmp/action28ac-reconcile-v2.stdout \
    2>/tmp/action28ac-reconcile-v2.stderr || reload_status=$?
[[ "$reload_status" -eq 1 ]]
[[ "$(readlink -f /etc/caddy/current)" = /etc/caddy/releases/v1 ]]
[[ "$(<"$fake_state")" = 3 ]]
grep -Fxq 'Caddy reload rejected protocol-v2 release v2; previous release restored.' \
    /tmp/action28ac-reconcile-v2.stderr
[[ -z "$(find /etc/caddy/releases -maxdepth 1 -name '.reconcile-*' -print -quit)" ]]

make_release v3 v1 incoming /var/lib/caddy-sync/incoming/node-a/v3
make_release v3 v1 divergent /etc/caddy/releases/v3
divergent_status=0
"$reconciler" >/tmp/action28ac-reconcile-v3.stdout \
    2>/tmp/action28ac-reconcile-v3.stderr || divergent_status=$?
[[ "$divergent_status" -ne 0 ]]
[[ "$(readlink -f /etc/caddy/current)" = /etc/caddy/releases/v1 ]]
[[ "$(<"$fake_state")" = 3 ]]
grep -Fxq 'caddy_sync_reconcile_v2_check_destination_payload_exact=false' \
    /tmp/action28ac-reconcile-v3.stderr

printf 'action_28ac_reconciliation_atomic_promotion=true\n'
printf 'action_28ac_reconciliation_reload_rollback=true\n'
printf 'action_28ac_reconciliation_divergent_destination_rejected=true\n'
printf 'action_28ac_reconciliation_transaction_regression_complete=true\n'
