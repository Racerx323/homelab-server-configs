#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly action35g_regression_prefix=serving_health_deployment_regression
action35g_regression_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly action35g_regression_directory
readonly action35g_regression_repository=${action35g_regression_directory%/Caddy/tests}
readonly action35g_regression_transaction=$action35g_regression_repository/Caddy/scripts/apply-coupled-serving-health-action35g.sh
readonly action35g_regression_outer=$action35g_regression_repository/Caddy/scripts/run-dual-node-coupled-serving-health-action35g-outer.sh
readonly action35g_regression_manifest=$action35g_regression_repository/Caddy/manifests/serving-health-production.tsv
readonly action35g_regression_protocol_manifest=$action35g_regression_repository/Caddy/manifests/synchronization-protocol-v2.yaml
readonly action35g_regression_successor_registry=$action35g_regression_repository/Caddy/manifests/deployable-successor.tsv

action35g_regression_final_directory_mode=$(awk '
    $1 == "final_directory_mode:" {
        gsub(/"/, "", $2)
        print $2
        count++
    }
    END { exit(count == 1 ? 0 : 1) }
' "$action35g_regression_protocol_manifest")
readonly action35g_regression_final_directory_mode
[[ "$action35g_regression_final_directory_mode" =~ ^0[0-7]{3}$ ]]
action35g_regression_final_owner=$(awk '
    $1 == "chown" && $2 == "-R" && $4 == "\"$destination\"" {
        print $3
        count++
    }
    END { exit(count == 1 ? 0 : 1) }
' "$action35g_regression_repository/Caddy/scripts/reconcile-release-v2.sh")
readonly action35g_regression_final_owner
[[ "$action35g_regression_final_owner" = root:caddy-tls ]]

awk -F '\t' '
    NR == 2 && $2 == "defined" && $3 == "35g" { found++ }
    END { exit(found == 1 ? 0 : 1) }
' "$action35g_regression_successor_registry"

action35g_regression_mode=all
if [[ "${1:-}" = --entrypoint ]]; then
    action35g_regression_mode=${2:-}
    [[ $# -eq 2 && "$action35g_regression_mode" =~ ^(transaction|outer)$ ]] || exit 64
elif [[ "${1:-}" = --prepare-node ]]; then
    [[ $# -eq 3 && "$3" =~ ^node-[ab]$ && "$2" = /tmp/* ]] || exit 64
    action35g_regression_make_after_parse=true
    action35g_regression_prepare_root=$2
    action35g_regression_prepare_role=$3
elif [[ "${1:-}" = --add-baseline-inventory ]]; then
    [[ $# -eq 4 && "$2" = /tmp/* && "$3" = /tmp/* && "$4" =~ ^node-[ab]$ ]] || exit 64
    action35g_regression_inventory_after_parse=true
    action35g_regression_inventory_payload=$2
    action35g_regression_inventory_root=$3
    action35g_regression_inventory_role=$4
elif (($#)); then
    exit 64
fi

action35g_regression_root=$(mktemp -d /tmp/caddy-action35g-production-path.XXXXXX)
readonly action35g_regression_root
action35g_regression_cleanup() {
    find "$action35g_regression_root" -type d -exec chmod u+rwx {} + 2>/dev/null || true
    rm -rf -- "$action35g_regression_root"
}
if [[ "${ACTION35G_KEEP_TEST_ROOT:-0}" = 1 ]]; then
    printf 'action35g_test_root=%s\n' "$action35g_regression_root" >&2
else
    trap action35g_regression_cleanup EXIT INT TERM
fi

action35g_regression_copy_payload() {
    local action35g_regression_payload=$1
    local action35g_regression_repo action35g_regression_source
    local action35g_regression_source_root action35g_regression_destination

    install -d -m 0700 "$action35g_regression_payload/files/homelab-server-configs" \
        "$action35g_regression_payload/files/homelab-dns"
    install -m 0600 "$action35g_regression_manifest" \
        "$action35g_regression_payload/serving-health-production.tsv"
    install -m 0600 "$action35g_regression_repository/Caddy/manifests/current-live-state.tsv" \
        "$action35g_regression_payload/current-live-state.tsv"
    printf '%s\n' \
        $'# key\trepository\tsource-path\tinstalled-path\tnode\tsource-sha256\tdeployed-sha256\taccepted-action\tlifecycle' \
        >"$action35g_regression_payload/production-artifacts.tsv"
    while IFS=$'\t' read -r action35g_regression_repo action35g_regression_source _ _ _ _; do
        [[ -n "$action35g_regression_repo" && "$action35g_regression_repo" != \#* ]] || continue
        action35g_regression_source_root=$action35g_regression_repository
        [[ "$action35g_regression_repo" = homelab-server-configs ]] ||
            action35g_regression_source_root=${action35g_regression_repository%/homelab-server-configs}/homelab-dns
        action35g_regression_destination=$action35g_regression_payload/files/$action35g_regression_repo/$action35g_regression_source
        install -d -m 0700 "$(dirname -- "$action35g_regression_destination")"
        install -m 0600 "$action35g_regression_source_root/$action35g_regression_source" \
            "$action35g_regression_destination"
    done <"$action35g_regression_manifest"
}

action35g_regression_add_baseline_inventory() {
    local action35g_regression_payload=$1
    local action35g_regression_node_root=$2
    local action35g_regression_role=$3
    local action35g_regression_key action35g_regression_path action35g_regression_hash

    for action35g_regression_key in dns-helper caddy-helper keepalived-config; do
        case "$action35g_regression_key" in
            dns-helper) action35g_regression_path=/etc/scripts/check-dns.sh ;;
            caddy-helper) action35g_regression_path=/usr/local/libexec/check-caddy.sh ;;
            keepalived-config) action35g_regression_path=/etc/keepalived/keepalived.conf ;;
        esac
        action35g_regression_hash=$(sha256sum "$action35g_regression_node_root$action35g_regression_path" | awk '{ print $1 }')
        printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
            "${action35g_regression_role}_${action35g_regression_key}" test test \
            "$action35g_regression_path" "$action35g_regression_role" \
            "$action35g_regression_hash" "$action35g_regression_hash" test production-current \
            >>"$action35g_regression_payload/production-artifacts.tsv"
    done
}

if [[ "${action35g_regression_inventory_after_parse:-false}" = true ]]; then
    printf '%s\n' \
        $'# key\trepository\tsource-path\tinstalled-path\tnode\tsource-sha256\tdeployed-sha256\taccepted-action\tlifecycle' \
        >"$action35g_regression_inventory_payload/production-artifacts.tsv"
    action35g_regression_add_baseline_inventory "$action35g_regression_inventory_payload" \
        "$action35g_regression_inventory_root" "$action35g_regression_inventory_role"
    exit 0
fi

action35g_regression_make_node() {
    local action35g_regression_node_root=$1
    local action35g_regression_role=$2
    local action35g_regression_fqdn=pi${action35g_regression_role#node-}.local.theama.co
    local action35g_regression_ipv4=10.1.0.53
    local action35g_regression_ipv6=fd36:5aa8:6971:1::53

    [[ "$action35g_regression_role" = node-a ]] || {
        action35g_regression_fqdn=pihole00.local.theama.co
        action35g_regression_ipv4=10.1.0.54
        action35g_regression_ipv6=fd36:5aa8:6971:1::54
    }
    install -d -m 0700 \
        "$action35g_regression_node_root/bin" "$action35g_regression_node_root/calls" \
        "$action35g_regression_node_root/etc/caddy/releases/action32g/conf.d" \
        "$action35g_regression_node_root/etc/caddy/releases/action32g/tls" \
        "$action35g_regression_node_root/etc/scripts" \
        "$action35g_regression_node_root/etc/keepalived" \
        "$action35g_regression_node_root/etc/default" \
        "$action35g_regression_node_root/usr/local/libexec" \
        "$action35g_regression_node_root/etc/systemd/system" \
        "$action35g_regression_node_root/var/lib/caddy-sync/incoming" \
        "$action35g_regression_node_root/var/lib/caddy-sync/outbound" \
        "$action35g_regression_node_root/var/lib/caddy-pihole-web-health" \
        "$action35g_regression_node_root/run/caddy-pihole-web-health"
    cat >"$action35g_regression_node_root/bin/install" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
readonly root=${ACTION35G_ROOT_PREFIX:?}
readonly target=${!#}
readonly parent=${target%/*}
restore_mode=
case "$target" in
    "$root"/tmp/caddy-action*-release/*)
        if [[ -d "$parent" && ! -w "$parent" ]]; then
            restore_mode=$(stat -c '%a' "$parent")
            chmod u+w "$parent"
        fi
        ;;
esac
printf 'install' >>"$root/calls/install.tsv"
printf '\t%q' "$@" >>"$root/calls/install.tsv"
printf '\n' >>"$root/calls/install.tsv"
status=0
/usr/bin/install "$@" || status=$?
if [[ -n "$restore_mode" ]]; then
    chmod "$restore_mode" "$parent"
fi
exit "$status"
EOF
    chmod 0755 "$action35g_regression_node_root/bin/install"
    : >"$action35g_regression_node_root/calls/install.tsv"
    ln -s releases/action32g "$action35g_regression_node_root/etc/caddy/current"
    printf '{"revision":"action32g","parent_revision":"action32f","source_node":"node-a"}\n' \
        >"$action35g_regression_node_root/etc/caddy/releases/action32g/release-manifest.json"
    install -m 0640 "$action35g_regression_repository/Caddy/configs/caddy/Caddyfile" \
        "$action35g_regression_node_root/etc/caddy/releases/action32g/Caddyfile"
    install -m 0640 "$action35g_regression_repository/Caddy/configs/caddy/conf.d/00-health.caddy" \
        "$action35g_regression_node_root/etc/caddy/releases/action32g/conf.d/00-health.caddy"
    install -m 0640 "$action35g_regression_repository/Caddy/configs/caddy/conf.d/91-exact-listener-default-deny.caddy" \
        "$action35g_regression_node_root/etc/caddy/releases/action32g/conf.d/91-exact-listener-default-deny.caddy"
    printf 'old-production-route\n' \
        >"$action35g_regression_node_root/etc/caddy/releases/action32g/conf.d/10-pihole-admin.caddy"
    chmod 0640 "$action35g_regression_node_root/etc/caddy/releases/action32g/conf.d/10-pihole-admin.caddy"
    openssl req -x509 -newkey rsa:2048 -nodes -days 1 \
        -subj '/CN=pihole-admin.local.theama.co' \
        -keyout "$action35g_regression_node_root/etc/caddy/releases/action32g/tls/privkey.pem" \
        -out "$action35g_regression_node_root/etc/caddy/releases/action32g/tls/fullchain.pem" \
        >/dev/null 2>&1
    chmod 0640 "$action35g_regression_node_root/etc/caddy/releases/action32g/tls/"*.pem
    find "$action35g_regression_node_root/etc/caddy/releases/action32g" -type d \
        -exec chmod "$action35g_regression_final_directory_mode" {} +
    if [[ "${CADDY_VALIDATION_CONTAINER:-0}" = 1 ]]; then
        [[ "$EUID" -eq 0 ]]
        getent group caddy-tls >/dev/null || /usr/sbin/groupadd --system caddy-tls
        chown -R root:caddy-tls \
            "$action35g_regression_node_root/etc/caddy/releases/action32g"
    fi
    printf 'NODE_FQDN=%s\nNODE_IPV4=%s\nNODE_IPV6=%s\n' \
        "$action35g_regression_fqdn" "$action35g_regression_ipv4" "$action35g_regression_ipv6" \
        >"$action35g_regression_node_root/etc/default/caddy-ha"
    chmod 0640 "$action35g_regression_node_root/etc/default/caddy-ha"
    printf 'old-dns\n' >"$action35g_regression_node_root/etc/scripts/check-dns.sh"
    printf 'old-caddy\n' >"$action35g_regression_node_root/usr/local/libexec/check-caddy.sh"
    printf 'old-keepalived\n' >"$action35g_regression_node_root/etc/keepalived/keepalived.conf"
    if [[ "$action35g_regression_role" = node-a &&
        "${ACTION35G_TEST_RETAINED_MODE:-exact}" != absent ]]; then
        install -d -m 0700 "$action35g_regression_node_root/tmp/caddy-action35c-release"
        cp -a -- "$action35g_regression_node_root/etc/caddy/releases/action32g/." \
            "$action35g_regression_node_root/tmp/caddy-action35c-release/"
        [[ "$(stat -c '%a' "$action35g_regression_node_root/tmp/caddy-action35c-release")" = "${action35g_regression_final_directory_mode#0}" ]]
        env ACTION35G_ROOT_PREFIX="$action35g_regression_node_root" \
            PATH="$action35g_regression_node_root/bin:/usr/bin:/bin" install -m 0640 \
            "$action35g_regression_repository/Caddy/configs/caddy/conf.d/10-pihole-admin.caddy" \
            "$action35g_regression_node_root/tmp/caddy-action35c-release/conf.d/10-pihole-admin.caddy"
        case "${ACTION35G_TEST_RETAINED_MODE:-exact}" in
            exact) ;;
            partial)
                rm -f -- "$action35g_regression_node_root/tmp/caddy-action35c-release/Caddyfile"
                ;;
            extra)
                printf 'unexpected\n' \
                    >"$action35g_regression_node_root/tmp/caddy-action35c-release/extra"
                ;;
            symlink)
                ln -s Caddyfile \
                    "$action35g_regression_node_root/tmp/caddy-action35c-release/unsafe-link"
                ;;
            malformed)
                printf 'wrong-route\n' \
                    >"$action35g_regression_node_root/tmp/caddy-action35c-release/conf.d/10-pihole-admin.caddy"
                ;;
            unsafe-metadata)
                chmod 0755 "$action35g_regression_node_root/tmp/caddy-action35c-release"
                ;;
            *) return 64 ;;
        esac
    fi
    : >"$action35g_regression_node_root/calls/systemctl.tsv"
    : >"$action35g_regression_node_root/calls/identities.tsv"
    cat >"$action35g_regression_node_root/bin/systemctl" <<EOF
#!/usr/bin/env bash
printf '%q ' "\$@" >>'$action35g_regression_node_root/calls/systemctl.tsv'
printf '\n' >>'$action35g_regression_node_root/calls/systemctl.tsv'
if [[ -f '$action35g_regression_node_root/fail-once' ]] && grep -Fxq -- "\$*" '$action35g_regression_node_root/fail-once'; then
    rm -f -- '$action35g_regression_node_root/fail-once'
    exit 1
fi
if [[ -f '$action35g_regression_node_root/fail-always' ]] && grep -Fxq -- "\$*" '$action35g_regression_node_root/fail-always'; then
    exit 1
fi
case "\${1:-}" in
    is-active | is-enabled | daemon-reload | reload | enable | disable | start) exit 0 ;;
esac
exit 1
EOF
    cat >"$action35g_regression_node_root/bin/caddy" <<EOF
#!/usr/bin/env bash
printf '%q ' "\$@" >>'$action35g_regression_node_root/calls/caddy.tsv'
printf '\n' >>'$action35g_regression_node_root/calls/caddy.tsv'
[[ "\${1:-}" = validate ]]
EOF
    cat >"$action35g_regression_node_root/bin/keepalived" <<EOF
#!/usr/bin/env bash
printf '%q ' "\$@" >>'$action35g_regression_node_root/calls/keepalived.tsv'
printf '\n' >>'$action35g_regression_node_root/calls/keepalived.tsv'
grep -Fq 'check-caddy' "\${2#--use-file=}"
EOF
    cat >"$action35g_regression_node_root/bin/journalctl" <<'EOF'
#!/usr/bin/env bash
case " $* " in
    *' --show-cursor '*) printf '%s\n' 'cursor: action35g-cursor' ;;
    *' --after-cursor '*) printf '%s\n' 'serving-health transition bounded and healthy' ;;
    *) exit 2 ;;
esac
EOF
    cat >"$action35g_regression_node_root/bin/dig" <<'EOF'
#!/usr/bin/env bash
case " $* " in
    *' A '*) printf '%s\n' 10.1.0.55 ;;
    *' AAAA '*) printf '%s\n' fd36:5aa8:6971:1::55 ;;
    *) exit 2 ;;
esac
EOF
    cat >"$action35g_regression_node_root/bin/curl" <<'EOF'
#!/usr/bin/env bash
case "$*" in
    *'/healthz'*) printf '204\n' ;;
    *'pihole00.local.theama.co'*) printf '200 https://pihole00.local.theama.co/admin/login.php\n' ;;
    *'pihole0.local.theama.co'*) printf '200 https://pihole0.local.theama.co/admin/login.php\n' ;;
    *) exit 2 ;;
esac
EOF
    cat >"$action35g_regression_node_root/bin/probe-dig" <<EOF
#!/usr/bin/env bash
printf '%q ' "\$@" >>'$action35g_regression_node_root/calls/probe-dig.tsv'
printf '\n' >>'$action35g_regression_node_root/calls/probe-dig.tsv'
case " \$* " in
    *' A '*) printf '%s\n' 10.1.0.55 ;;
    *' AAAA '*) printf '%s\n' fd36:5aa8:6971:1::55 ;;
    *) exit 2 ;;
esac
EOF
    cat >"$action35g_regression_node_root/bin/probe-curl" <<EOF
#!/usr/bin/env bash
printf '%q ' "\$@" >>'$action35g_regression_node_root/calls/probe-curl.tsv'
printf '\n' >>'$action35g_regression_node_root/calls/probe-curl.tsv'
[[ " \$* " = *pihole-admin.local.theama.co* ]]
EOF
    cat >"$action35g_regression_node_root/bin/ss" <<EOF
#!/usr/bin/env bash
printf 'LISTEN 0 4096 $action35g_regression_ipv4:443 0.0.0.0:*\n'
printf 'LISTEN 0 4096 [$action35g_regression_ipv6]:443 [::]:*\n'
printf 'UNCONN 0 0 $action35g_regression_ipv4:443 0.0.0.0:*\n'
printf 'UNCONN 0 0 [$action35g_regression_ipv6]:443 [::]:*\n'
EOF
    cat >"$action35g_regression_node_root/bin/enqueue" <<EOF
#!/usr/bin/env bash
printf '%q ' "\$@" >>'$action35g_regression_node_root/calls/enqueue.tsv'
printf '\n' >>'$action35g_regression_node_root/calls/enqueue.tsv'
EOF
    cat >"$action35g_regression_node_root/bin/ownership" <<'EOF'
#!/usr/bin/env bash
case "${1:-}" in
    node-a) printf '%s\n' 'ipv4=Master ipv6=Master vip_count=4' ;;
    node-b) printf '%s\n' 'ipv4=Backup ipv6=Backup vip_count=0' ;;
    *) exit 2 ;;
esac
EOF
    cat >"$action35g_regression_node_root/usr/local/libexec/publish-release-v2.sh" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
source_path=
node_role=
while (($#)); do
    case "$1" in
        --source) source_path=$2; shift 2 ;;
        --node-role) node_role=$2; shift 2 ;;
        *) exit 64 ;;
    esac
done
[[ "$node_role" = node-a && -n "$source_path" ]]
readonly revision=action35g-production-path
readonly node_a=$ACTION35G_CLUSTER_ROOT/node-a
readonly node_b=$ACTION35G_CLUSTER_ROOT/node-b
install -d -m 0700 "$node_a/var/lib/caddy-sync/outbound/$revision"
cp -a -- "$source_path/." "$node_a/var/lib/caddy-sync/outbound/$revision/"
printf '{"revision":"%s","parent_revision":"action32g","source_node":"node-a"}\n' "$revision" \
    >"$node_a/var/lib/caddy-sync/outbound/$revision/release-manifest.json"
install -d -m 0700 "$node_b/etc/caddy/releases/$revision"
cp -a -- "$node_a/var/lib/caddy-sync/outbound/$revision/." \
    "$node_b/etc/caddy/releases/$revision/"
ln -sfn "releases/$revision" "$node_b/etc/caddy/current"
printf 'Published protocol-v2 release %s for receiver validation.\n' "$revision"
EOF
    cat >"$action35g_regression_node_root/usr/local/libexec/finalize-incoming-release-v2.sh" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
readonly node_root=$ACTION35G_ROOT_PREFIX
incoming=$(find "$node_root/var/lib/caddy-sync/incoming" -mindepth 1 -maxdepth 1 -type d -print)
[[ -n "$incoming" && "$(printf '%s\n' "$incoming" | wc -l)" -eq 1 ]]
revision=${incoming##*/}
install -d -m 0700 "$node_root/etc/caddy/releases/$revision"
cp -a -- "$incoming/." "$node_root/etc/caddy/releases/$revision/"
ln -sfn "releases/$revision" "$node_root/etc/caddy/current"
if ((EUID != 0)); then
    find "$incoming" -xdev -type d -exec chmod u+rwx {} +
fi
find "$incoming" -xdev -mindepth 1 -delete
rmdir "$incoming"
EOF
    chmod 0755 "$action35g_regression_node_root/usr/local/libexec/"*.sh
    chmod 0755 "$action35g_regression_node_root/bin/"*
}

if [[ "${action35g_regression_make_after_parse:-false}" = true ]]; then
    action35g_regression_make_node "$action35g_regression_prepare_root" \
        "$action35g_regression_prepare_role"
    exit 0
fi

action35g_regression_run_transaction() {
    local action35g_regression_role=$1
    local action35g_regression_node_root=$action35g_regression_root/$action35g_regression_role
    local action35g_regression_payload=$action35g_regression_root/payload-$action35g_regression_role

    action35g_regression_make_node "$action35g_regression_node_root" "$action35g_regression_role"
    action35g_regression_copy_payload "$action35g_regression_payload"
    action35g_regression_add_baseline_inventory "$action35g_regression_payload" \
        "$action35g_regression_node_root" "$action35g_regression_role"
    if ! /bin/bash "$action35g_regression_transaction" --node-role "$action35g_regression_role" \
        --payload "$action35g_regression_payload" --production-path-test "$action35g_regression_node_root" \
        >"$action35g_regression_root/$action35g_regression_role.stdout" \
        2>"$action35g_regression_root/$action35g_regression_role.stderr"; then
        sed -n '1,120p' "$action35g_regression_root/$action35g_regression_role.stderr" >&2
        return 1
    fi
    [[ ! -s "$action35g_regression_root/$action35g_regression_role.stderr" ]]
    grep -Fxq 'action_35g_check_complete=true' "$action35g_regression_root/$action35g_regression_role.stdout"
    grep -Fq 'reload keepalived.service' "$action35g_regression_node_root/calls/systemctl.tsv"
    grep -Fq 'enable --now caddy-pihole-web-health.timer' "$action35g_regression_node_root/calls/systemctl.tsv"
    [[ "$(wc -l <"$action35g_regression_node_root/calls/identities.tsv")" -ge 9 ]]
    [[ -s "$action35g_regression_node_root/tmp/caddy-action35g/$action35g_regression_role/journal-after-cursor.stdout" ]]
    printf '%s_transaction_%s=true\n' "$action35g_regression_prefix" "${action35g_regression_role//-/_}"
}

action35g_regression_rejection_matrix() {
    local action35g_regression_case_root=$action35g_regression_root/reject-residue
    local action35g_regression_case_payload=$action35g_regression_root/reject-residue-payload
    local action35g_regression_status=0

    action35g_regression_make_node "$action35g_regression_case_root" node-b
    action35g_regression_copy_payload "$action35g_regression_case_payload"
    action35g_regression_add_baseline_inventory "$action35g_regression_case_payload" \
        "$action35g_regression_case_root" node-b
    install -d -m 0700 "$action35g_regression_case_root/var/lib/caddy-sync/incoming/action35g-unsafe"
    /bin/bash "$action35g_regression_transaction" --node-role node-b \
        --payload "$action35g_regression_case_payload" --production-path-test "$action35g_regression_case_root" \
        >"$action35g_regression_root/reject-residue.stdout" \
        2>"$action35g_regression_root/reject-residue.stderr" || action35g_regression_status=$?
    [[ "$action35g_regression_status" -eq 1 ]]
    grep -Fxq 0 "$action35g_regression_case_root/tmp/caddy-action35g/node-b/mutation-count"
    [[ "$(<"$action35g_regression_case_root/etc/scripts/check-dns.sh")" = old-dns ]]

    action35g_regression_case_root=$action35g_regression_root/rollback-proven
    action35g_regression_case_payload=$action35g_regression_root/rollback-proven-payload
    action35g_regression_status=0
    action35g_regression_make_node "$action35g_regression_case_root" node-b
    action35g_regression_copy_payload "$action35g_regression_case_payload"
    action35g_regression_add_baseline_inventory "$action35g_regression_case_payload" \
        "$action35g_regression_case_root" node-b
    printf '%s\n' 'reload keepalived.service' \
        >"$action35g_regression_case_root/fail-once"
    /bin/bash "$action35g_regression_transaction" --node-role node-b \
        --payload "$action35g_regression_case_payload" --production-path-test "$action35g_regression_case_root" \
        >"$action35g_regression_root/rollback-proven.stdout" \
        2>"$action35g_regression_root/rollback-proven.stderr" || action35g_regression_status=$?
    [[ "$action35g_regression_status" -eq 1 ]]
    grep -Fxq 'action_35g_check_rollback_complete=true' "$action35g_regression_root/rollback-proven.stdout"
    [[ "$(<"$action35g_regression_case_root/etc/scripts/check-dns.sh")" = old-dns ]]

    action35g_regression_case_root=$action35g_regression_root/rollback-unproven
    action35g_regression_case_payload=$action35g_regression_root/rollback-unproven-payload
    action35g_regression_status=0
    action35g_regression_make_node "$action35g_regression_case_root" node-b
    action35g_regression_copy_payload "$action35g_regression_case_payload"
    action35g_regression_add_baseline_inventory "$action35g_regression_case_payload" \
        "$action35g_regression_case_root" node-b
    printf '%s\n' 'reload keepalived.service' \
        >"$action35g_regression_case_root/fail-once"
    printf '%s\n' 'reload keepalived.service' >"$action35g_regression_case_root/fail-always"
    /bin/bash "$action35g_regression_transaction" --node-role node-b \
        --payload "$action35g_regression_case_payload" --production-path-test "$action35g_regression_case_root" \
        >"$action35g_regression_root/rollback-unproven.stdout" \
        2>"$action35g_regression_root/rollback-unproven.stderr" || action35g_regression_status=$?
    [[ "$action35g_regression_status" -eq 125 ]]
    printf '%s_rejection_and_rollback_matrix=true\n' "$action35g_regression_prefix"
}

action35g_regression_run_outer() {
    local action35g_regression_outer_root=$action35g_regression_root/outer
    local action35g_regression_outer_evidence=$action35g_regression_outer_root/evidence
    local action35g_regression_transport_bin=$action35g_regression_outer_root/transport-bin
    local action35g_regression_transport_log=$action35g_regression_outer_root/transport.tsv
    install -d -m 0700 "$action35g_regression_outer_root" \
        "$action35g_regression_transport_bin"
    : >"$action35g_regression_transport_log"
    cat >"$action35g_regression_transport_bin/ssh" <<EOF
#!/usr/bin/env bash
set -Eeuo pipefail
node=\$1
remote=\$2
case "\$node" in
    pi@10.1.0.53) node_root=\$CADDY_ACTION35G_PRODUCTION_TEST_ROOT/node-a ;;
    pi@10.1.0.54) node_root=\$CADDY_ACTION35G_PRODUCTION_TEST_ROOT/node-b ;;
    *) exit 64 ;;
esac
printf 'ssh\t%s\t%s\n' "\$node" "\$remote" >>'$action35g_regression_transport_log'
export ACTION35G_ROOT_PREFIX=\$node_root
export ACTION35G_CLUSTER_ROOT=\$CADDY_ACTION35G_PRODUCTION_TEST_ROOT
export PATH=\$node_root/bin:/usr/bin:/bin
remote=\${remote//sudo -n \/bin\/bash/\/bin\/bash}
if [[ "\$remote" = *'/transaction.sh'* ]]; then
    remote=\${remote//\/tmp\/caddy-action35g-upload/\$node_root\/tmp\/caddy-action35g-upload}
    remote="\$remote --production-path-test \$node_root"
fi
/bin/sh -c "\$remote"
EOF
    cat >"$action35g_regression_transport_bin/scp" <<EOF
#!/usr/bin/env bash
set -Eeuo pipefail
source_path=\$1
remote=\$2
case "\$remote" in
    pi@10.1.0.53:*) node_root=\$CADDY_ACTION35G_PRODUCTION_TEST_ROOT/node-a ;;
    pi@10.1.0.54:*) node_root=\$CADDY_ACTION35G_PRODUCTION_TEST_ROOT/node-b ;;
    *) exit 64 ;;
esac
remote_path=\${remote#*:}
printf 'scp\t%s\t%s\n' "\$source_path" "\$remote" >>'$action35g_regression_transport_log'
if [[ "\${ACTION35G_TEST_SCP_FAIL_NODE:-}" = "\$node_root" ]]; then
    exit 70
fi
install -m 0600 "\$source_path" "\$node_root\$remote_path"
EOF
    chmod 0755 "$action35g_regression_transport_bin/ssh" \
        "$action35g_regression_transport_bin/scp"
    if [[ "$action35g_regression_mode" = outer && -n "${CADDY_PRODUCTION_PATH_EVIDENCE_ROOT:-}" ]]; then
        action35g_regression_outer_evidence=$CADDY_PRODUCTION_PATH_EVIDENCE_ROOT
    fi
    if ! ACTION35G_SSH_COMMAND=$action35g_regression_transport_bin/ssh \
        ACTION35G_SCP_COMMAND=$action35g_regression_transport_bin/scp \
        ACTION35G_TRANSPORT_EVIDENCE=$action35g_regression_transport_log \
        ACTION35G_USE_REAL_CADDY=${CADDY_VALIDATION_CONTAINER:-0} \
        CADDY_ACTION35G_PRODUCTION_TEST_ROOT=$action35g_regression_outer_root \
        CADDY_PRODUCTION_PATH_EVIDENCE_ROOT=$action35g_regression_outer_evidence \
        /bin/bash "$action35g_regression_outer" --production-path-test-inner \
        >"$action35g_regression_root/outer.stdout" 2>"$action35g_regression_root/outer.stderr"; then
        sed -n '1,120p' "$action35g_regression_root/outer.stderr" >&2
        return 1
    fi
    [[ ! -s "$action35g_regression_root/outer.stderr" ]]
    grep -Fxq 'action_35g_outer_complete=true' "$action35g_regression_root/outer.stdout"
    [[ "$(grep -c '^ssh' "$action35g_regression_transport_log")" -eq 14 ]]
    [[ "$(grep -c '^scp' "$action35g_regression_transport_log")" -eq 2 ]]
    grep -Fq $'ssh\tpi@10.1.0.53\tcd / && /bin/bash -s -- /tmp/caddy-action35g-upload' \
        "$action35g_regression_transport_log"
    grep -Fq $'ssh\tpi@10.1.0.54\tcd / && /bin/bash -s -- /tmp/caddy-action35g-upload' \
        "$action35g_regression_transport_log"
    if grep -Fq '/bin/bash -c' "$action35g_regression_transport_log"; then
        return 1
    fi
    if grep -Eq $'ssh\tpi@[^\t]+\t.*readlink[[:space:]]+-f[[:space:]]+--[[:space:]]+/etc/caddy/current' \
        "$action35g_regression_transport_log"; then
        return 1
    fi
    grep -Fxq '/tmp/caddy-action35g-upload' \
        "$action35g_regression_outer_root/ssh-evidence/remote-path"
    grep -Fq '/bin/bash' "$action35g_regression_outer_root/ssh-evidence/node-b-command.argv"
    grep -Fq '/tmp/caddy-action35g-upload/transaction.sh' \
        "$action35g_regression_outer_root/ssh-evidence/node-b-command.argv"
    grep -Fq $'ssh\tpi@10.1.0.53\tcd / && sudo -n /bin/bash -s -- /tmp/caddy-action35g-upload' \
        "$action35g_regression_transport_log"
    grep -Fxq 'cd / && sudo -n /bin/bash -s --' \
        "$action35g_regression_outer_root/ssh-evidence/node-a-original-release.remote-command"
    grep -Fxq 'cd / && sudo -n /bin/bash -s --' \
        "$action35g_regression_outer_root/ssh-evidence/node-b-original-release.remote-command"
    grep -Fq 'release-publish.remote-command' < <(
        find "$action35g_regression_outer_root/ssh-evidence" -maxdepth 1 -printf '%f\n'
    )
    if [[ "${CADDY_VALIDATION_CONTAINER:-0}" = 1 ]]; then
        grep -Fxq 'candidate_parser=/usr/bin/caddy' \
            "$action35g_regression_outer_root/ssh-evidence/release-publish.stdout"
    else
        grep -Fxq \
            "candidate_parser=$action35g_regression_outer_root/node-a/bin/caddy" \
            "$action35g_regression_outer_root/ssh-evidence/release-publish.stdout"
    fi
    printf '%s_real_caddy_parser=true\n' "$action35g_regression_prefix"
    for action35g_regression_probe in dns-ipv4 dns-ipv6 https-ipv4 https-ipv6; do
        [[ "$(awk -F '\t' -v label="$action35g_regression_probe" \
            '$3 == label { count++ } END { print count + 0 }' \
            "$action35g_regression_outer_root/ssh-evidence/availability.tsv")" -ge 2 ]]
        awk -F '\t' -v label="$action35g_regression_probe" \
            '$3 == label && $4 != 0 { failed = 1 } END { exit failed }' \
            "$action35g_regression_outer_root/ssh-evidence/availability.tsv"
    done
    grep -Fxq 1 \
        "$action35g_regression_outer_root/node-a/tmp/caddy-action35g/node-a/mutation-count"
    grep -Fxq 1 \
        "$action35g_regression_outer_root/node-b/tmp/caddy-action35g/node-b/mutation-count"
    [[ -s "$action35g_regression_outer_root/node-a/calls/identities.tsv" ]]
    [[ -s "$action35g_regression_outer_root/node-b/calls/identities.tsv" ]]
    [[ ! -e "$action35g_regression_outer_root/node-a/tmp/caddy-action35c-release" ]]
    [[ ! -e "$action35g_regression_outer_root/node-b/tmp/caddy-action35c-release" ]]
    [[ ! -e "$action35g_regression_outer_root/node-a/tmp/caddy-action35g-release" ]]
    grep -Fxq 'retained_candidate_state=validated-and-removed' \
        "$action35g_regression_outer_root/ssh-evidence/node-a-retained-candidate.stdout"
    grep -Fxq \
        "retained_candidate_expected_root_mode=$action35g_regression_final_directory_mode" \
        "$action35g_regression_outer_root/ssh-evidence/node-a-retained-candidate.stdout"
    grep -Fxq \
        "retained_candidate_observed_root_mode=$action35g_regression_final_directory_mode" \
        "$action35g_regression_outer_root/ssh-evidence/node-a-retained-candidate.stdout"
    grep -Fxq \
        "retained_candidate_expected_owner=$action35g_regression_final_owner" \
        "$action35g_regression_outer_root/ssh-evidence/node-a-retained-candidate.stdout"
    local action35g_regression_source_owner action35g_regression_candidate_owner
    action35g_regression_source_owner=$(stat -c '%U:%G' \
        "$action35g_regression_outer_root/node-a/etc/caddy/releases/action32g")
    action35g_regression_candidate_owner=$(sed -n \
        's/^retained_candidate_observed_owner=//p' \
        "$action35g_regression_outer_root/ssh-evidence/node-a-retained-candidate.stdout")
    [[ "$action35g_regression_candidate_owner" = "$action35g_regression_source_owner" ]]
    if [[ "${CADDY_VALIDATION_CONTAINER:-0}" = 1 ]]; then
        [[ "$action35g_regression_candidate_owner" = "$action35g_regression_final_owner" ]]
    fi
    for action35g_regression_mode_implementation in \
        Caddy/scripts/publish-release-v2.sh \
        Caddy/scripts/reconcile-release-v2.sh \
        Caddy/scripts/finalize-incoming-release-v2.sh; do
        grep -Fq -- "chmod $action35g_regression_final_directory_mode" \
            "$action35g_regression_repository/$action35g_regression_mode_implementation"
    done
    printf '%s_protocol_mode_and_owner_derived=true\n' "$action35g_regression_prefix"
    grep -Fq -- \
        "$action35g_regression_outer_root/node-a/tmp/caddy-action35g-release/conf.d/10-pihole-admin.caddy" \
        "$action35g_regression_outer_root/node-a/calls/install.tsv"
    grep -Fxq 'retained_candidate_state=absent' \
        "$action35g_regression_outer_root/ssh-evidence/node-b-retained-candidate.stdout"

    local action35g_regression_rollback_root=$action35g_regression_root/outer-rollback
    local action35g_regression_rollback_status=0
    local action35g_regression_rollback_evidence=$action35g_regression_rollback_root/evidence
    install -d -m 0700 "$action35g_regression_rollback_root"
    ACTION35G_TEST_FAIL_AFTER_NODE_B=1 \
        ACTION35G_SSH_COMMAND=$action35g_regression_transport_bin/ssh \
        ACTION35G_SCP_COMMAND=$action35g_regression_transport_bin/scp \
        ACTION35G_TRANSPORT_EVIDENCE=$action35g_regression_transport_log \
        ACTION35G_USE_REAL_CADDY=${CADDY_VALIDATION_CONTAINER:-0} \
        CADDY_ACTION35G_PRODUCTION_TEST_ROOT=$action35g_regression_rollback_root \
        CADDY_PRODUCTION_PATH_EVIDENCE_ROOT=$action35g_regression_rollback_evidence \
        /bin/bash "$action35g_regression_outer" --production-path-test-inner \
        >"$action35g_regression_root/outer-rollback.stdout" \
        2>"$action35g_regression_root/outer-rollback.stderr" ||
        action35g_regression_rollback_status=$?
    [[ "$action35g_regression_rollback_status" -eq 1 ]]
    [[ "$(<"$action35g_regression_rollback_root/node-b/etc/scripts/check-dns.sh")" = old-dns ]]
    [[ "$(readlink -f "$action35g_regression_rollback_root/node-b/etc/caddy/current")" = "$action35g_regression_rollback_root/node-b/etc/caddy/releases/action32g" ]]
    [[ ! -e "$action35g_regression_rollback_root/node-a/tmp/caddy-action35g-upload" ]]
    [[ ! -e "$action35g_regression_rollback_root/node-b/tmp/caddy-action35g-upload" ]]
    [[ ! -e "$action35g_regression_rollback_root/node-a/tmp/caddy-action35g-release" ]]

    local action35g_regression_upload_failure_root=$action35g_regression_root/outer-upload-failure
    local action35g_regression_upload_failure_status=0
    install -d -m 0700 "$action35g_regression_upload_failure_root"
    ACTION35G_TEST_SCP_FAIL_NODE=$action35g_regression_upload_failure_root/node-a \
        ACTION35G_SSH_COMMAND=$action35g_regression_transport_bin/ssh \
        ACTION35G_SCP_COMMAND=$action35g_regression_transport_bin/scp \
        ACTION35G_TRANSPORT_EVIDENCE=$action35g_regression_transport_log \
        CADDY_ACTION35G_PRODUCTION_TEST_ROOT=$action35g_regression_upload_failure_root \
        /bin/bash "$action35g_regression_outer" --production-path-test-inner \
        >"$action35g_regression_root/outer-upload-failure.stdout" \
        2>"$action35g_regression_root/outer-upload-failure.stderr" ||
        action35g_regression_upload_failure_status=$?
    [[ "$action35g_regression_upload_failure_status" -eq 1 ]]
    [[ ! -e "$action35g_regression_upload_failure_root/node-a/tmp/caddy-action35g-upload" ]]
    [[ ! -e "$action35g_regression_upload_failure_root/ssh-evidence/node-a-transaction.status" ]]

    local action35g_regression_absent_root=$action35g_regression_root/outer-absent
    install -d -m 0700 "$action35g_regression_absent_root"
    ACTION35G_TEST_RETAINED_MODE=absent \
        ACTION35G_SSH_COMMAND=$action35g_regression_transport_bin/ssh \
        ACTION35G_SCP_COMMAND=$action35g_regression_transport_bin/scp \
        ACTION35G_TRANSPORT_EVIDENCE=$action35g_regression_transport_log \
        ACTION35G_USE_REAL_CADDY=${CADDY_VALIDATION_CONTAINER:-0} \
        CADDY_ACTION35G_PRODUCTION_TEST_ROOT=$action35g_regression_absent_root \
        CADDY_PRODUCTION_PATH_EVIDENCE_ROOT=$action35g_regression_absent_root/evidence \
        /bin/bash "$action35g_regression_outer" --production-path-test-inner \
        >"$action35g_regression_root/outer-absent.stdout" \
        2>"$action35g_regression_root/outer-absent.stderr"
    [[ ! -s "$action35g_regression_root/outer-absent.stderr" ]]
    grep -Fxq 'retained_candidate_state=absent' \
        "$action35g_regression_absent_root/ssh-evidence/node-a-retained-candidate.stdout"
    grep -Fxq 'retained_candidate_state=absent' \
        "$action35g_regression_absent_root/ssh-evidence/node-b-retained-candidate.stdout"

    local action35g_regression_reject_mode action35g_regression_reject_root
    local action35g_regression_reject_status
    for action35g_regression_reject_mode in partial extra symlink malformed unsafe-metadata; do
        action35g_regression_reject_root=$action35g_regression_root/outer-reject-$action35g_regression_reject_mode
        action35g_regression_reject_status=0
        install -d -m 0700 "$action35g_regression_reject_root"
        ACTION35G_TEST_RETAINED_MODE=$action35g_regression_reject_mode \
            ACTION35G_SSH_COMMAND=$action35g_regression_transport_bin/ssh \
            ACTION35G_SCP_COMMAND=$action35g_regression_transport_bin/scp \
            ACTION35G_TRANSPORT_EVIDENCE=$action35g_regression_transport_log \
            CADDY_ACTION35G_PRODUCTION_TEST_ROOT=$action35g_regression_reject_root \
            /bin/bash "$action35g_regression_outer" --production-path-test-inner \
            >"$action35g_regression_root/outer-reject-$action35g_regression_reject_mode.stdout" \
            2>"$action35g_regression_root/outer-reject-$action35g_regression_reject_mode.stderr" ||
            action35g_regression_reject_status=$?
        [[ "$action35g_regression_reject_status" -eq 1 ]]
        [[ -d "$action35g_regression_reject_root/node-a/tmp/caddy-action35c-release" ]]
        [[ ! -e "$action35g_regression_reject_root/ssh-evidence/node-a-transaction.status" ]]
    done
    printf '%s_retained_candidate_matrix=true\n' "$action35g_regression_prefix"
    if [[ "${CADDY_VALIDATION_CONTAINER:-0}" = 1 ]]; then
        [[ "$EUID" -eq 0 ]]
        local action35g_regression_identity_root=$action35g_regression_root/identity-boundary
        install -d -o root -g root -m 0750 \
            "$action35g_regression_identity_root/etc/caddy/releases/action32g"
        printf '{}\n' \
            >"$action35g_regression_identity_root/etc/caddy/releases/action32g/release-manifest.json"
        ln -s releases/action32g "$action35g_regression_identity_root/etc/caddy/current"
        if setpriv --reuid=65534 --regid=65534 --clear-groups \
            readlink -f -- "$action35g_regression_identity_root/etc/caddy/current" >/dev/null 2>&1; then
            return 1
        fi
        [[ "$(readlink -f -- "$action35g_regression_identity_root/etc/caddy/current")" = "$action35g_regression_identity_root/etc/caddy/releases/action32g" ]]
        printf '%s_real_identity_permission_boundary=true\n' "$action35g_regression_prefix"
    fi
    printf '%s_marker_only_evidence_rejected=true\n' "$action35g_regression_prefix"
    printf '%s_outer=true\n' "$action35g_regression_prefix"
}

case "$action35g_regression_mode" in
    transaction)
        action35g_regression_run_transaction node-b
        action35g_regression_rejection_matrix
        printf 'action_35g_check_baseline_complete=true\n'
        printf 'action_35g_check_candidate_validation_complete=true\n'
        printf 'action_35g_check_mutation_complete=true\n'
        printf 'action_35g_check_acceptance_complete=true\n'
        printf 'action_35g_check_complete=true\n'
        ;;
    outer) action35g_regression_run_outer ;;
    all)
        action35g_regression_run_transaction node-b
        action35g_regression_run_transaction node-a
        action35g_regression_rejection_matrix
        action35g_regression_run_outer
        ;;
esac
printf '%s_complete=true\n' "$action35g_regression_prefix"
