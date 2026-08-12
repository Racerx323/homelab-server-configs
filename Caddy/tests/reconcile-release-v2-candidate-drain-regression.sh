#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export PATH
readonly PATH

test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
readonly caddy_root=${test_directory%/tests}
readonly reconciler=$caddy_root/scripts/reconcile-release-v2.sh

if [[ "${CADDY_VALIDATION_CONTAINER:-}" != 1 ]]; then
    printf 'reconcile_release_v2_candidate_drain_host_deferred_to_debian=true\n'
    exit 0
fi

[[ "$(id -u)" -eq 0 ]]
getent group caddy-tls >/dev/null || groupadd --system caddy-tls
rm -rf -- /etc/caddy/current /etc/caddy/releases \
    /var/lib/caddy-sync/incoming /var/lib/caddy-sync/quarantine
install -d -m 0755 /etc/default /etc/caddy/releases \
    /var/lib/caddy-sync/incoming/node-a
install -d -m 0750 /var/lib/caddy-sync/quarantine
printf 'NODE_FQDN=fixture.local\nNODE_IPV4=192.0.2.1\nNODE_IPV6=2001:db8::1\n' \
    >/etc/default/caddy-ha

fake_state=/tmp/reconcile-release-v2-candidate-drain-systemctl
readonly fake_state
printf '0\n' >"$fake_state"
cat >/usr/bin/caddy <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
[[ "$1" = validate ]]
EOF
cat >/usr/bin/systemctl <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
[[ "$1" = reload && "$2" = caddy.service ]]
count=$(<"$CANDIDATE_DRAIN_SYSTEMCTL_STATE")
printf '%s\n' "$((count + 1))" >"$CANDIDATE_DRAIN_SYSTEMCTL_STATE"
EOF
chmod 0755 /usr/bin/caddy /usr/bin/systemctl
export CANDIDATE_DRAIN_SYSTEMCTL_STATE=$fake_state

make_release() {
    local drain_revision=$1
    local drain_parent=$2
    local drain_payload=$3
    local drain_destination=$4

    install -d -m 0750 "$drain_destination"
    printf '%s\n' "$drain_payload" >"$drain_destination/Caddyfile"
    jq -n --arg revision "$drain_revision" --arg parent "$drain_parent" \
        '{revision: $revision, parent_revision: $parent, source_node: "node-a"}' \
        >"$drain_destination/release-manifest.json"
    (
        cd "$drain_destination"
        sha256sum ./Caddyfile ./release-manifest.json >manifest.sha256
    )
    : >"$drain_destination/.finalize-request"
    : >"$drain_destination/.complete"
    find "$drain_destination" -type d -exec chmod 0550 {} +
    find "$drain_destination" -type f -exec chmod 0440 {} +
}

make_release base previous base /etc/caddy/releases/base
ln -s /etc/caddy/releases/base /etc/caddy/current
cp -a -- /etc/caddy/releases/base \
    /var/lib/caddy-sync/incoming/node-a/base
make_release child base child /var/lib/caddy-sync/incoming/node-a/child

/bin/bash "$reconciler" >/tmp/reconcile-release-v2-drain.stdout \
    2>/tmp/reconcile-release-v2-drain.stderr
[[ ! -s /tmp/reconcile-release-v2-drain.stderr ]]
[[ "$(readlink -f -- /etc/caddy/current)" = /etc/caddy/releases/child ]]
[[ "$(<"$fake_state")" = 1 ]]
[[ -z "$(find /var/lib/caddy-sync/incoming -mindepth 2 -maxdepth 2 \
    -type d -print -quit)" ]]
grep -Fxq 'Protocol-v2 release base is already active.' \
    /tmp/reconcile-release-v2-drain.stdout
grep -Fxq 'Activated protocol-v2 release child' \
    /tmp/reconcile-release-v2-drain.stdout

make_release child-a child first \
    /var/lib/caddy-sync/incoming/node-a/child-a
make_release child-b child second \
    /var/lib/caddy-sync/incoming/node-a/child-b
ambiguous_status=0
/bin/bash "$reconciler" >/tmp/reconcile-release-v2-ambiguous.stdout \
    2>/tmp/reconcile-release-v2-ambiguous.stderr || ambiguous_status=$?
[[ "$ambiguous_status" -ne 0 ]]
[[ ! -s /tmp/reconcile-release-v2-ambiguous.stdout ]]
grep -Fxq 'Multiple finalized candidates claim the active parent.' \
    /tmp/reconcile-release-v2-ambiguous.stderr
[[ -d /var/lib/caddy-sync/incoming/node-a/child-a ]]
[[ -d /var/lib/caddy-sync/incoming/node-a/child-b ]]
[[ "$(<"$fake_state")" = 1 ]]

printf 'reconcile_release_v2_candidate_drain_replay_consumed=true\n'
printf 'reconcile_release_v2_candidate_drain_child_activated=true\n'
printf 'reconcile_release_v2_candidate_drain_ambiguity_rejected=true\n'
printf 'reconcile_release_v2_candidate_drain_regression_complete=true\n'
