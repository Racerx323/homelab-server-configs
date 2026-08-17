#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH
trap 'printf "regression_failure_line=%s status=%s\n" "$LINENO" "$?" >&2' ERR

readonly action35h_regression_prefix=serving_health_deployment_regression
action35h_regression_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly action35h_regression_directory
readonly action35h_regression_repository=${action35h_regression_directory%/Caddy/tests}
readonly action35h_regression_transaction=$action35h_regression_repository/Caddy/scripts/apply-coupled-serving-health-action35h.sh
readonly action35h_regression_outer=$action35h_regression_repository/Caddy/scripts/run-dual-node-coupled-serving-health-action35h-outer.sh
readonly action35h_regression_manifest=$action35h_regression_repository/Caddy/manifests/serving-health-production.tsv
readonly action35h_regression_protocol_manifest=$action35h_regression_repository/Caddy/manifests/synchronization-protocol-v2.yaml
readonly action35h_regression_successor_registry=$action35h_regression_repository/Caddy/manifests/deployable-successor.tsv
readonly action35h_regression_original_revision=action32g
readonly action35h_regression_revision=action35h-production-path

action35h_regression_final_directory_mode=$(awk '
    $1 == "final_directory_mode:" {
        gsub(/"/, "", $2)
        print $2
        count++
    }
    END { exit(count == 1 ? 0 : 1) }
' "$action35h_regression_protocol_manifest")
readonly action35h_regression_final_directory_mode
[[ "$action35h_regression_final_directory_mode" =~ ^0[0-7]{3}$ ]]
action35h_regression_final_owner=$(awk '
    $1 == "chown" && $2 == "-R" && $4 == "\"$destination\"" {
        print $3
        count++
    }
    END { exit(count == 1 ? 0 : 1) }
' "$action35h_regression_repository/Caddy/scripts/reconcile-release-v2.sh")
readonly action35h_regression_final_owner
[[ "$action35h_regression_final_owner" = root:caddy-tls ]]

awk -F '\t' '
    NR == 2 && $2 == "defined" && $3 == "35h" { found++ }
    END { exit(found == 1 ? 0 : 1) }
' "$action35h_regression_successor_registry"

action35h_regression_mode=all
if [[ "${1:-}" = --entrypoint ]]; then
    action35h_regression_mode=${2:-}
    [[ $# -eq 2 && "$action35h_regression_mode" =~ ^(transaction|outer)$ ]] || exit 64
elif [[ "${1:-}" = --prepare-node ]]; then
    [[ $# -eq 3 && "$3" =~ ^node-[ab]$ && "$2" = /tmp/* ]] || exit 64
    action35h_regression_make_after_parse=true
    action35h_regression_prepare_root=$2
    action35h_regression_prepare_role=$3
elif [[ "${1:-}" = --add-baseline-inventory ]]; then
    [[ $# -eq 4 && "$2" = /tmp/* && "$3" = /tmp/* && "$4" =~ ^node-[ab]$ ]] || exit 64
    action35h_regression_inventory_after_parse=true
    action35h_regression_inventory_payload=$2
    action35h_regression_inventory_root=$3
    action35h_regression_inventory_role=$4
elif (($#)); then
    exit 64
fi

action35h_regression_root=$(mktemp -d /tmp/caddy-action35h-production-path.XXXXXX)
readonly action35h_regression_root
action35h_regression_cleanup() {
    find "$action35h_regression_root" -type d -exec chmod u+rwx {} + 2>/dev/null || true
    rm -rf -- "$action35h_regression_root"
}
if [[ "${ACTION35H_KEEP_TEST_ROOT:-0}" = 1 ]]; then
    printf 'action35h_test_root=%s\n' "$action35h_regression_root" >&2
else
    trap action35h_regression_cleanup EXIT INT TERM
fi

action35h_regression_copy_payload() {
    local action35h_regression_payload=$1
    local action35h_regression_repo action35h_regression_source
    local action35h_regression_source_root action35h_regression_destination

    install -d -m 0700 "$action35h_regression_payload/files/homelab-server-configs" \
        "$action35h_regression_payload/files/homelab-dns"
    install -m 0600 "$action35h_regression_manifest" \
        "$action35h_regression_payload/serving-health-production.tsv"
    install -m 0600 "$action35h_regression_repository/Caddy/manifests/current-live-state.tsv" \
        "$action35h_regression_payload/current-live-state.tsv"
    printf '%s\n' \
        $'# key\trepository\tsource-path\tinstalled-path\tnode\tsource-sha256\tdeployed-sha256\taccepted-action\tlifecycle' \
        >"$action35h_regression_payload/production-artifacts.tsv"
    while IFS=$'\t' read -r action35h_regression_repo action35h_regression_source _ _ _ _; do
        [[ -n "$action35h_regression_repo" && "$action35h_regression_repo" != \#* ]] || continue
        action35h_regression_source_root=$action35h_regression_repository
        [[ "$action35h_regression_repo" = homelab-server-configs ]] ||
            action35h_regression_source_root=${action35h_regression_repository%/homelab-server-configs}/homelab-dns
        action35h_regression_destination=$action35h_regression_payload/files/$action35h_regression_repo/$action35h_regression_source
        install -d -m 0700 "$(dirname -- "$action35h_regression_destination")"
        install -m 0600 "$action35h_regression_source_root/$action35h_regression_source" \
            "$action35h_regression_destination"
    done <"$action35h_regression_manifest"
}

action35h_regression_add_baseline_inventory() {
    local action35h_regression_payload=$1
    local action35h_regression_node_root=$2
    local action35h_regression_role=$3
    local action35h_regression_key action35h_regression_path action35h_regression_hash

    for action35h_regression_key in dns-helper caddy-helper keepalived-config; do
        case "$action35h_regression_key" in
            dns-helper) action35h_regression_path=/etc/scripts/check-dns.sh ;;
            caddy-helper) action35h_regression_path=/usr/local/libexec/check-caddy.sh ;;
            keepalived-config) action35h_regression_path=/etc/keepalived/keepalived.conf ;;
        esac
        action35h_regression_hash=$(sha256sum "$action35h_regression_node_root$action35h_regression_path" | awk '{ print $1 }')
        printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
            "${action35h_regression_role}_${action35h_regression_key}" test test \
            "$action35h_regression_path" "$action35h_regression_role" \
            "$action35h_regression_hash" "$action35h_regression_hash" test production-current \
            >>"$action35h_regression_payload/production-artifacts.tsv"
    done
}

if [[ "${action35h_regression_inventory_after_parse:-false}" = true ]]; then
    printf '%s\n' \
        $'# key\trepository\tsource-path\tinstalled-path\tnode\tsource-sha256\tdeployed-sha256\taccepted-action\tlifecycle' \
        >"$action35h_regression_inventory_payload/production-artifacts.tsv"
    action35h_regression_add_baseline_inventory "$action35h_regression_inventory_payload" \
        "$action35h_regression_inventory_root" "$action35h_regression_inventory_role"
    exit 0
fi

action35h_regression_make_node() {
    local action35h_regression_node_root=$1
    local action35h_regression_role=$2
    local action35h_regression_fqdn=pi${action35h_regression_role#node-}.local.theama.co
    local action35h_regression_ipv4=10.1.0.53
    local action35h_regression_ipv6=fd36:5aa8:6971:1::53

    [[ "$action35h_regression_role" = node-a ]] || {
        action35h_regression_fqdn=pihole00.local.theama.co
        action35h_regression_ipv4=10.1.0.54
        action35h_regression_ipv6=fd36:5aa8:6971:1::54
    }
    install -d -m 0700 \
        "$action35h_regression_node_root/bin" "$action35h_regression_node_root/calls" \
        "$action35h_regression_node_root/etc/caddy/releases/action32g/conf.d" \
        "$action35h_regression_node_root/etc/caddy/releases/action32g/tls" \
        "$action35h_regression_node_root/etc/scripts" \
        "$action35h_regression_node_root/etc/keepalived" \
        "$action35h_regression_node_root/etc/default" \
        "$action35h_regression_node_root/usr/local/libexec" \
        "$action35h_regression_node_root/etc/systemd/system" \
        "$action35h_regression_node_root/var/lib/caddy-sync/incoming/node-a" \
        "$action35h_regression_node_root/var/lib/caddy-sync/incoming/node-b" \
        "$action35h_regression_node_root/var/lib/caddy-sync/outbound" \
        "$action35h_regression_node_root/var/lib/caddy-sync/quarantine" \
        "$action35h_regression_node_root/var/lib/caddy-pihole-web-health" \
        "$action35h_regression_node_root/run/caddy-pihole-web-health"
    cat >"$action35h_regression_node_root/bin/install" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
readonly root=${ACTION35H_ROOT_PREFIX:?}
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
    chmod 0755 "$action35h_regression_node_root/bin/install"
    : >"$action35h_regression_node_root/calls/install.tsv"
    printf '{"revision":"action32g","parent_revision":"action32f","source_node":"node-a"}\n' \
        >"$action35h_regression_node_root/etc/caddy/releases/action32g/release-manifest.json"
    install -m 0640 "$action35h_regression_repository/Caddy/configs/caddy/Caddyfile" \
        "$action35h_regression_node_root/etc/caddy/releases/action32g/Caddyfile"
    install -m 0640 "$action35h_regression_repository/Caddy/configs/caddy/conf.d/00-health.caddy" \
        "$action35h_regression_node_root/etc/caddy/releases/action32g/conf.d/00-health.caddy"
    install -m 0640 "$action35h_regression_repository/Caddy/configs/caddy/conf.d/91-exact-listener-default-deny.caddy" \
        "$action35h_regression_node_root/etc/caddy/releases/action32g/conf.d/91-exact-listener-default-deny.caddy"
    printf 'old-production-route\n' \
        >"$action35h_regression_node_root/etc/caddy/releases/action32g/conf.d/10-pihole-admin.caddy"
    chmod 0640 "$action35h_regression_node_root/etc/caddy/releases/action32g/conf.d/10-pihole-admin.caddy"
    if [[ ! -f "$action35h_regression_root/test-tls/privkey.pem" ]]; then
        install -d -m 0700 "$action35h_regression_root/test-tls"
        openssl req -x509 -newkey rsa:2048 -nodes -days 1 \
            -subj '/CN=pihole-admin.local.theama.co' \
            -keyout "$action35h_regression_root/test-tls/privkey.pem" \
            -out "$action35h_regression_root/test-tls/fullchain.pem" \
            >/dev/null 2>&1
    fi
    install -m 0640 "$action35h_regression_root/test-tls/privkey.pem" \
        "$action35h_regression_node_root/etc/caddy/releases/action32g/tls/privkey.pem"
    install -m 0640 "$action35h_regression_root/test-tls/fullchain.pem" \
        "$action35h_regression_node_root/etc/caddy/releases/action32g/tls/fullchain.pem"
    chmod 0640 "$action35h_regression_node_root/etc/caddy/releases/action32g/tls/"*.pem
    find "$action35h_regression_node_root/etc/caddy/releases/action32g" -type d \
        -exec chmod "$action35h_regression_final_directory_mode" {} +
    if [[ "${CADDY_VALIDATION_CONTAINER:-0}" = 1 ]]; then
        [[ "$EUID" -eq 0 ]]
        getent group caddy-tls >/dev/null || /usr/sbin/groupadd --system caddy-tls
        chown -R root:caddy-tls \
            "$action35h_regression_node_root/etc/caddy/releases/action32g"
    fi
    printf 'NODE_FQDN=%s\nNODE_IPV4=%s\nNODE_IPV6=%s\n' \
        "$action35h_regression_fqdn" "$action35h_regression_ipv4" "$action35h_regression_ipv6" \
        >"$action35h_regression_node_root/etc/default/caddy-ha"
    chmod 0640 "$action35h_regression_node_root/etc/default/caddy-ha"
    printf 'old-dns\n' >"$action35h_regression_node_root/etc/scripts/check-dns.sh"
    printf 'old-caddy\n' >"$action35h_regression_node_root/usr/local/libexec/check-caddy.sh"
    printf 'old-keepalived\n' >"$action35h_regression_node_root/etc/keepalived/keepalived.conf"
    local action35h_regression_protocol_payload
    if [[ "$action35h_regression_role" = node-a ]]; then
        action35h_regression_protocol_payload=$action35h_regression_node_root/var/lib/caddy-sync/outbound/$action35h_regression_revision
    else
        action35h_regression_protocol_payload=$action35h_regression_node_root/etc/caddy/releases/$action35h_regression_revision
    fi
    install -d -m 0750 "$action35h_regression_protocol_payload"
    cp -a -- "$action35h_regression_node_root/etc/caddy/releases/action32g/." \
        "$action35h_regression_protocol_payload/"
    chmod u+w "$action35h_regression_protocol_payload"
    printf '{"revision":"%s","parent_revision":"%s","source_node":"node-a","created_at":"2026-08-17T11:03:28-05:00"}\n' \
        "$action35h_regression_revision" "$action35h_regression_original_revision" \
        >"$action35h_regression_protocol_payload/release-manifest.json"
    (
        cd "$action35h_regression_protocol_payload"
        find . -type f ! -path ./manifest.sha256 ! -path ./.finalize-request \
            ! -path ./.complete ! -path ./.complete.pending -print0 |
            LC_ALL=C sort -z | xargs -0 sha256sum
    ) >"$action35h_regression_protocol_payload/manifest.sha256"
    if [[ "$action35h_regression_role" = node-a ]]; then
        : >"$action35h_regression_protocol_payload/.finalize-request"
        find "$action35h_regression_protocol_payload" -type d -exec chmod 0550 {} +
        find "$action35h_regression_protocol_payload" -type f -exec chmod 0440 {} +
        if [[ "${CADDY_VALIDATION_CONTAINER:-0}" = 1 ]]; then
            getent group caddy-sync >/dev/null || /usr/sbin/groupadd --system caddy-sync
            getent passwd caddy-sync >/dev/null || /usr/sbin/useradd --system \
                --gid caddy-sync --no-create-home --shell /usr/sbin/nologin caddy-sync
            chown -R caddy-sync:caddy-sync "$action35h_regression_protocol_payload"
        fi
        ln -s "releases/$action35h_regression_original_revision" \
            "$action35h_regression_node_root/etc/caddy/current"
    else
        : >"$action35h_regression_protocol_payload/.complete"
        find "$action35h_regression_protocol_payload" -type d -exec chmod 0550 {} +
        find "$action35h_regression_protocol_payload" -type f -exec chmod 0440 {} +
        if [[ "${CADDY_VALIDATION_CONTAINER:-0}" = 1 ]]; then
            chown -R root:caddy-tls "$action35h_regression_protocol_payload"
        fi
        ln -s "releases/$action35h_regression_revision" \
            "$action35h_regression_node_root/etc/caddy/current"
    fi
    : >"$action35h_regression_node_root/calls/systemctl.tsv"
    : >"$action35h_regression_node_root/calls/identities.tsv"
    cat >"$action35h_regression_node_root/bin/systemctl" <<EOF
#!/usr/bin/env bash
printf '%q ' "\$@" >>'$action35h_regression_node_root/calls/systemctl.tsv'
printf '\n' >>'$action35h_regression_node_root/calls/systemctl.tsv'
if [[ -f '$action35h_regression_node_root/fail-once' ]] && grep -Fxq -- "\$*" '$action35h_regression_node_root/fail-once'; then
    rm -f -- '$action35h_regression_node_root/fail-once'
    exit 1
fi
if [[ -f '$action35h_regression_node_root/fail-always' ]] && grep -Fxq -- "\$*" '$action35h_regression_node_root/fail-always'; then
    exit 1
fi
case "\${1:-}" in
    is-active | is-enabled | daemon-reload | reload | enable | disable | start | stop) exit 0 ;;
esac
exit 1
EOF
    cat >"$action35h_regression_node_root/bin/caddy" <<EOF
#!/usr/bin/env bash
printf '%q ' "\$@" >>'$action35h_regression_node_root/calls/caddy.tsv'
printf '\n' >>'$action35h_regression_node_root/calls/caddy.tsv'
[[ "\${1:-}" = validate ]]
EOF
    cat >"$action35h_regression_node_root/bin/keepalived" <<EOF
#!/usr/bin/env bash
printf '%q ' "\$@" >>'$action35h_regression_node_root/calls/keepalived.tsv'
printf '\n' >>'$action35h_regression_node_root/calls/keepalived.tsv'
grep -Fq 'check-caddy' "\${2#--use-file=}"
EOF
    cat >"$action35h_regression_node_root/bin/journalctl" <<'EOF'
#!/usr/bin/env bash
case " $* " in
    *' --show-cursor '*) printf '%s\n' 'cursor: action35h-cursor' ;;
    *' --after-cursor '*) printf '%s\n' 'serving-health transition bounded and healthy' ;;
    *) exit 2 ;;
esac
EOF
    cat >"$action35h_regression_node_root/bin/dig" <<'EOF'
#!/usr/bin/env bash
case " $* " in
    *' A '*) printf '%s\n' 10.1.0.55 ;;
    *' AAAA '*) printf '%s\n' fd36:5aa8:6971:1::55 ;;
    *) exit 2 ;;
esac
EOF
    cat >"$action35h_regression_node_root/bin/curl" <<'EOF'
#!/usr/bin/env bash
case "$*" in
    *'/healthz'*) printf '204\n' ;;
    *'pihole00.local.theama.co'*) printf '200 https://pihole00.local.theama.co/admin/login.php\n' ;;
    *'pihole0.local.theama.co'*) printf '200 https://pihole0.local.theama.co/admin/login.php\n' ;;
    *) exit 2 ;;
esac
EOF
    cat >"$action35h_regression_node_root/bin/probe-dig" <<EOF
#!/usr/bin/env bash
printf '%q ' "\$@" >>'$action35h_regression_node_root/calls/probe-dig.tsv'
printf '\n' >>'$action35h_regression_node_root/calls/probe-dig.tsv'
case " \$* " in
    *' A '*) printf '%s\n' 10.1.0.55 ;;
    *' AAAA '*) printf '%s\n' fd36:5aa8:6971:1::55 ;;
    *) exit 2 ;;
esac
EOF
    cat >"$action35h_regression_node_root/bin/probe-curl" <<EOF
#!/usr/bin/env bash
printf '%q ' "\$@" >>'$action35h_regression_node_root/calls/probe-curl.tsv'
printf '\n' >>'$action35h_regression_node_root/calls/probe-curl.tsv'
[[ " \$* " = *pihole-admin.local.theama.co* ]]
EOF
    cat >"$action35h_regression_node_root/bin/ss" <<EOF
#!/usr/bin/env bash
printf 'LISTEN 0 4096 $action35h_regression_ipv4:443 0.0.0.0:*\n'
printf 'LISTEN 0 4096 [$action35h_regression_ipv6]:443 [::]:*\n'
printf 'UNCONN 0 0 $action35h_regression_ipv4:443 0.0.0.0:*\n'
printf 'UNCONN 0 0 [$action35h_regression_ipv6]:443 [::]:*\n'
EOF
    cat >"$action35h_regression_node_root/bin/enqueue" <<EOF
#!/usr/bin/env bash
printf '%q ' "\$@" >>'$action35h_regression_node_root/calls/enqueue.tsv'
printf '\n' >>'$action35h_regression_node_root/calls/enqueue.tsv'
EOF
    cat >"$action35h_regression_node_root/bin/ownership" <<'EOF'
#!/usr/bin/env bash
case "${1:-}" in
    node-a) printf '%s\n' 'ipv4=Master ipv6=Master vip_count=4' ;;
    node-b) printf '%s\n' 'ipv4=Backup ipv6=Backup vip_count=0' ;;
    *) exit 2 ;;
esac
EOF
    cat >"$action35h_regression_node_root/usr/local/libexec/publish-release-v2.sh" <<'EOF'
#!/usr/bin/env bash
printf 'prohibited publish invocation\n' >&2
exit 99
EOF
    cat >"$action35h_regression_node_root/usr/local/libexec/finalize-incoming-release-v2.sh" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
readonly node_root=$ACTION35H_ROOT_PREFIX
incoming=$(find "$node_root/var/lib/caddy-sync/incoming/node-a" -mindepth 1 -maxdepth 1 -type d -print)
[[ -n "$incoming" && "$(printf '%s\n' "$incoming" | wc -l)" -eq 1 ]]
revision=${incoming##*/}
install -d -m 0700 "$node_root/etc/caddy/releases/$revision"
cp -a -- "$incoming/." "$node_root/etc/caddy/releases/$revision/"
chmod u+w "$node_root/etc/caddy/releases/$revision"
: >"$node_root/etc/caddy/releases/$revision/.complete"
rm -f -- "$node_root/etc/caddy/releases/$revision/.finalize-request"
chmod 0550 "$node_root/etc/caddy/releases/$revision"
ln -sfn "releases/$revision" "$node_root/etc/caddy/current"
if ((EUID != 0)); then
    find "$incoming" -xdev -type d -exec chmod u+rwx {} +
fi
find "$incoming" -xdev -mindepth 1 -delete
rmdir "$incoming"
EOF
    chmod 0755 "$action35h_regression_node_root/usr/local/libexec/"*.sh
    chmod 0755 "$action35h_regression_node_root/bin/"*
}

if [[ "${action35h_regression_make_after_parse:-false}" = true ]]; then
    action35h_regression_make_node "$action35h_regression_prepare_root" \
        "$action35h_regression_prepare_role"
    exit 0
fi

action35h_regression_run_transaction() {
    local action35h_regression_role=$1
    local action35h_regression_node_root=$action35h_regression_root/$action35h_regression_role
    local action35h_regression_payload=$action35h_regression_root/payload-$action35h_regression_role

    action35h_regression_make_node "$action35h_regression_node_root" "$action35h_regression_role"
    action35h_regression_copy_payload "$action35h_regression_payload"
    action35h_regression_add_baseline_inventory "$action35h_regression_payload" \
        "$action35h_regression_node_root" "$action35h_regression_role"
    if ! /bin/bash "$action35h_regression_transaction" --node-role "$action35h_regression_role" \
        --payload "$action35h_regression_payload" --production-path-test "$action35h_regression_node_root" \
        >"$action35h_regression_root/$action35h_regression_role.stdout" \
        2>"$action35h_regression_root/$action35h_regression_role.stderr"; then
        sed -n '1,120p' "$action35h_regression_root/$action35h_regression_role.stderr" >&2
        return 1
    fi
    [[ ! -s "$action35h_regression_root/$action35h_regression_role.stderr" ]]
    grep -Fxq 'action_35h_check_complete=true' "$action35h_regression_root/$action35h_regression_role.stdout"
    grep -Fq 'reload keepalived.service' "$action35h_regression_node_root/calls/systemctl.tsv"
    grep -Fq 'enable --now caddy-pihole-web-health.timer' "$action35h_regression_node_root/calls/systemctl.tsv"
    [[ "$(wc -l <"$action35h_regression_node_root/calls/identities.tsv")" -ge 9 ]]
    [[ -s "$action35h_regression_node_root/tmp/caddy-action35h/$action35h_regression_role/journal-after-cursor.stdout" ]]
    printf '%s_transaction_%s=true\n' "$action35h_regression_prefix" "${action35h_regression_role//-/_}"
}

action35h_regression_rejection_matrix() {
    local action35h_regression_case_root=$action35h_regression_root/reject-residue
    local action35h_regression_case_payload=$action35h_regression_root/reject-residue-payload
    local action35h_regression_status=0

    action35h_regression_make_node "$action35h_regression_case_root" node-b
    action35h_regression_copy_payload "$action35h_regression_case_payload"
    action35h_regression_add_baseline_inventory "$action35h_regression_case_payload" \
        "$action35h_regression_case_root" node-b
    install -d -m 0700 "$action35h_regression_case_root/var/lib/caddy-sync/incoming/action35h-unsafe"
    /bin/bash "$action35h_regression_transaction" --node-role node-b \
        --payload "$action35h_regression_case_payload" --production-path-test "$action35h_regression_case_root" \
        >"$action35h_regression_root/reject-residue.stdout" \
        2>"$action35h_regression_root/reject-residue.stderr" || action35h_regression_status=$?
    [[ "$action35h_regression_status" -eq 1 ]]
    grep -Fxq 0 "$action35h_regression_case_root/tmp/caddy-action35h/node-b/mutation-count"
    [[ "$(<"$action35h_regression_case_root/etc/scripts/check-dns.sh")" = old-dns ]]

    action35h_regression_case_root=$action35h_regression_root/rollback-proven
    action35h_regression_case_payload=$action35h_regression_root/rollback-proven-payload
    action35h_regression_status=0
    action35h_regression_make_node "$action35h_regression_case_root" node-b
    action35h_regression_copy_payload "$action35h_regression_case_payload"
    action35h_regression_add_baseline_inventory "$action35h_regression_case_payload" \
        "$action35h_regression_case_root" node-b
    printf '%s\n' 'reload keepalived.service' \
        >"$action35h_regression_case_root/fail-once"
    /bin/bash "$action35h_regression_transaction" --node-role node-b \
        --payload "$action35h_regression_case_payload" --production-path-test "$action35h_regression_case_root" \
        >"$action35h_regression_root/rollback-proven.stdout" \
        2>"$action35h_regression_root/rollback-proven.stderr" || action35h_regression_status=$?
    [[ "$action35h_regression_status" -eq 1 ]]
    grep -Fxq 'action_35h_check_rollback_complete=true' "$action35h_regression_root/rollback-proven.stdout"
    [[ "$(<"$action35h_regression_case_root/etc/scripts/check-dns.sh")" = old-dns ]]

    action35h_regression_case_root=$action35h_regression_root/rollback-unproven
    action35h_regression_case_payload=$action35h_regression_root/rollback-unproven-payload
    action35h_regression_status=0
    action35h_regression_make_node "$action35h_regression_case_root" node-b
    action35h_regression_copy_payload "$action35h_regression_case_payload"
    action35h_regression_add_baseline_inventory "$action35h_regression_case_payload" \
        "$action35h_regression_case_root" node-b
    printf '%s\n' 'reload keepalived.service' \
        >"$action35h_regression_case_root/fail-once"
    printf '%s\n' 'reload keepalived.service' >"$action35h_regression_case_root/fail-always"
    /bin/bash "$action35h_regression_transaction" --node-role node-b \
        --payload "$action35h_regression_case_payload" --production-path-test "$action35h_regression_case_root" \
        >"$action35h_regression_root/rollback-unproven.stdout" \
        2>"$action35h_regression_root/rollback-unproven.stderr" || action35h_regression_status=$?
    [[ "$action35h_regression_status" -eq 125 ]]
    printf '%s_rejection_and_rollback_matrix=true\n' "$action35h_regression_prefix"
}

action35h_regression_prepare_outer_cluster() {
    local action35h_regression_cluster_root=$1
    local action35h_regression_source
    local action35h_regression_destination

    action35h_regression_make_node "$action35h_regression_cluster_root/node-a" node-a
    action35h_regression_make_node "$action35h_regression_cluster_root/node-b" node-b
    action35h_regression_source=$action35h_regression_cluster_root/node-a/var/lib/caddy-sync/outbound/$action35h_regression_revision
    action35h_regression_destination=$action35h_regression_cluster_root/node-b/etc/caddy/releases/$action35h_regression_revision
    find "$action35h_regression_destination" -xdev -type d -exec chmod u+rwx {} +
    find "$action35h_regression_destination" -xdev -mindepth 1 -delete
    rmdir "$action35h_regression_destination"
    cp -a -- "$action35h_regression_source" "$action35h_regression_destination"
    chmod u+w "$action35h_regression_destination"
    rm -f -- "$action35h_regression_destination/.finalize-request"
    : >"$action35h_regression_destination/.complete"
    chmod 0440 "$action35h_regression_destination/.complete"
    chmod 0550 "$action35h_regression_destination"
    if [[ "${CADDY_VALIDATION_CONTAINER:-0}" = 1 ]]; then
        chown -R root:caddy-tls "$action35h_regression_destination"
    fi
}

action35h_regression_run_outer() {
    local action35h_regression_outer_root=$action35h_regression_root/outer
    local action35h_regression_outer_evidence=$action35h_regression_outer_root/evidence
    local action35h_regression_transport_bin=$action35h_regression_outer_root/transport-bin
    local action35h_regression_transport_log=$action35h_regression_outer_root/transport.tsv
    install -d -m 0700 "$action35h_regression_outer_root" \
        "$action35h_regression_transport_bin"
    action35h_regression_prepare_outer_cluster "$action35h_regression_outer_root"
    local action35h_regression_fixture=$action35h_regression_outer_root/node-a/var/lib/caddy-sync/outbound/$action35h_regression_revision
    local action35h_regression_release_manifest_sha256
    local action35h_regression_payload_manifest_sha256
    action35h_regression_release_manifest_sha256=$(sha256sum \
        "$action35h_regression_fixture/release-manifest.json" | awk '{print $1}')
    action35h_regression_payload_manifest_sha256=$(sha256sum \
        "$action35h_regression_fixture/manifest.sha256" | awk '{print $1}')
    : >"$action35h_regression_transport_log"
    cat >"$action35h_regression_transport_bin/ssh" <<EOF
#!/usr/bin/env bash
set -Eeuo pipefail
node=\$1
remote=\$2
case "\$node" in
    pi@10.1.0.53) node_root=\$CADDY_ACTION35H_PRODUCTION_TEST_ROOT/node-a ;;
    pi@10.1.0.54) node_root=\$CADDY_ACTION35H_PRODUCTION_TEST_ROOT/node-b ;;
    *) exit 64 ;;
esac
printf 'ssh\t%s\t%s\n' "\$node" "\$remote" >>'$action35h_regression_transport_log'
export ACTION35H_ROOT_PREFIX=\$node_root
export ACTION35H_CLUSTER_ROOT=\$CADDY_ACTION35H_PRODUCTION_TEST_ROOT
export PATH=\$node_root/bin:/usr/bin:/bin
remote=\${remote//sudo -n \/bin\/bash/\/bin\/bash}
if [[ "\$remote" = *'/transaction.sh'* ]]; then
    remote=\${remote//\/tmp\/caddy-action35h-upload/\$node_root\/tmp\/caddy-action35h-upload}
    remote="\$remote --production-path-test \$node_root"
fi
/bin/sh -c "\$remote"
EOF
    cat >"$action35h_regression_transport_bin/scp" <<EOF
#!/usr/bin/env bash
set -Eeuo pipefail
source_path=\$1
remote=\$2
case "\$remote" in
    pi@10.1.0.53:*) node_root=\$CADDY_ACTION35H_PRODUCTION_TEST_ROOT/node-a ;;
    pi@10.1.0.54:*) node_root=\$CADDY_ACTION35H_PRODUCTION_TEST_ROOT/node-b ;;
    *) exit 64 ;;
esac
remote_path=\${remote#*:}
printf 'scp\t%s\t%s\n' "\$source_path" "\$remote" >>'$action35h_regression_transport_log'
if [[ "\${ACTION35H_TEST_SCP_FAIL_NODE:-}" = "\$node_root" ]]; then
    exit 70
fi
install -m 0600 "\$source_path" "\$node_root\$remote_path"
EOF
    chmod 0755 "$action35h_regression_transport_bin/ssh" \
        "$action35h_regression_transport_bin/scp"
    if [[ "$action35h_regression_mode" = outer && -n "${CADDY_PRODUCTION_PATH_EVIDENCE_ROOT:-}" ]]; then
        action35h_regression_outer_evidence=$CADDY_PRODUCTION_PATH_EVIDENCE_ROOT
    fi
    if ! ACTION35H_SSH_COMMAND=$action35h_regression_transport_bin/ssh \
        ACTION35H_SCP_COMMAND=$action35h_regression_transport_bin/scp \
        ACTION35H_TRANSPORT_EVIDENCE=$action35h_regression_transport_log \
        ACTION35H_EXPECTED_ORIGINAL_REVISION=$action35h_regression_original_revision \
        ACTION35H_EXPECTED_REVISION=$action35h_regression_revision \
        ACTION35H_EXPECTED_RELEASE_MANIFEST_SHA256=$action35h_regression_release_manifest_sha256 \
        ACTION35H_EXPECTED_PAYLOAD_MANIFEST_SHA256=$action35h_regression_payload_manifest_sha256 \
        ACTION35H_USE_REAL_CADDY=${CADDY_VALIDATION_CONTAINER:-0} \
        CADDY_ACTION35H_PRODUCTION_TEST_ROOT=$action35h_regression_outer_root \
        CADDY_PRODUCTION_PATH_EVIDENCE_ROOT=$action35h_regression_outer_evidence \
        /bin/bash "$action35h_regression_outer" --production-path-test-inner \
        >"$action35h_regression_root/outer.stdout" 2>"$action35h_regression_root/outer.stderr"; then
        sed -n '1,120p' "$action35h_regression_root/outer.stderr" >&2
        return 1
    fi
    [[ ! -s "$action35h_regression_root/outer.stderr" ]]
    grep -Fxq 'action_35h_outer_complete=true' "$action35h_regression_root/outer.stdout"
    grep -Fxq 'action_35h_outer_split_baseline_validated=true' \
        "$action35h_regression_root/outer.stdout"
    grep -Fxq 'action_35h_outer_existing_release_reused=true' \
        "$action35h_regression_root/outer.stdout"
    grep -Fxq 'action_35h_outer_ula_probe_paths=true' \
        "$action35h_regression_root/outer.stdout"
    [[ "$(grep -c '^scp' "$action35h_regression_transport_log")" -eq 2 ]]
    grep -Fq $'ssh\tpi@10.1.0.53\tcd / && /bin/bash -s -- /tmp/caddy-action35h-upload' \
        "$action35h_regression_transport_log"
    grep -Fq $'ssh\tpi@10.1.0.54\tcd / && /bin/bash -s -- /tmp/caddy-action35h-upload' \
        "$action35h_regression_transport_log"
    if grep -Fq '/bin/bash -c' "$action35h_regression_transport_log"; then
        return 1
    fi
    if grep -Eq $'ssh\tpi@[^\t]+\t.*readlink[[:space:]]+-f[[:space:]]+--[[:space:]]+/etc/caddy/current' \
        "$action35h_regression_transport_log"; then
        return 1
    fi
    grep -Fxq '/tmp/caddy-action35h-upload' \
        "$action35h_regression_outer_root/ssh-evidence/remote-path"
    grep -Fq '/bin/bash' "$action35h_regression_outer_root/ssh-evidence/node-b-command.argv"
    grep -Fq '/tmp/caddy-action35h-upload/transaction.sh' \
        "$action35h_regression_outer_root/ssh-evidence/node-b-command.argv"
    grep -Fxq "cd / && sudo -n /bin/bash -s -- $action35h_regression_revision" \
        "$action35h_regression_outer_root/ssh-evidence/release-node-a-promote.remote-command"
    grep -Fxq 'cd / && sudo -n /bin/bash -s --' \
        "$action35h_regression_outer_root/ssh-evidence/node-a-original-release.remote-command"
    grep -Fxq 'cd / && sudo -n /bin/bash -s --' \
        "$action35h_regression_outer_root/ssh-evidence/node-b-original-release.remote-command"
    [[ ! -e "$action35h_regression_outer_root/ssh-evidence/release-publish.remote-command" ]]
    if grep -Fq 'publish-release-v2.sh' "$action35h_regression_transport_log"; then
        return 1
    fi
    for action35h_regression_role in node-a node-b; do
        for action35h_regression_probe in dns-ipv4 dns-ipv6 https-ipv4 https-ipv6; do
            [[ "$(awk -F '\t' -v role="$action35h_regression_role" \
                -v label="$action35h_regression_probe" \
                '$2 == role && $4 == label { count++ } END { print count + 0 }' \
                "$action35h_regression_outer_root/ssh-evidence/availability.tsv")" -ge 2 ]]
            awk -F '\t' -v role="$action35h_regression_role" \
                -v label="$action35h_regression_probe" \
                '$2 == role && $4 == label && $5 != 0 { failed = 1 } END { exit failed }' \
                "$action35h_regression_outer_root/ssh-evidence/availability.tsv"
        done
    done
    grep -Fxq 1 \
        "$action35h_regression_outer_root/node-a/tmp/caddy-action35h/node-a/mutation-count"
    grep -Fxq 1 \
        "$action35h_regression_outer_root/node-b/tmp/caddy-action35h/node-b/mutation-count"
    [[ -s "$action35h_regression_outer_root/node-a/calls/identities.tsv" ]]
    [[ -s "$action35h_regression_outer_root/node-b/calls/identities.tsv" ]]
    [[ "$(readlink -f "$action35h_regression_outer_root/node-a/etc/caddy/current")" = "$action35h_regression_outer_root/node-a/etc/caddy/releases/$action35h_regression_revision" ]]
    [[ "$(readlink -f "$action35h_regression_outer_root/node-b/etc/caddy/current")" = "$action35h_regression_outer_root/node-b/etc/caddy/releases/$action35h_regression_revision" ]]
    [[ ! -e "$action35h_regression_outer_root/node-a/var/lib/caddy-sync/outbound/$action35h_regression_revision" ]]
    [[ ! -e "$action35h_regression_outer_root/node-a/var/lib/caddy-sync/incoming/node-a/$action35h_regression_revision" ]]
    grep -Fxq 'protocol_state=validated' \
        "$action35h_regression_outer_root/ssh-evidence/node-a-protocol-state.stdout"
    grep -Fxq 'protocol_state=validated' \
        "$action35h_regression_outer_root/ssh-evidence/node-b-protocol-state.stdout"
    for action35h_regression_mode_implementation in \
        Caddy/scripts/publish-release-v2.sh \
        Caddy/scripts/reconcile-release-v2.sh \
        Caddy/scripts/finalize-incoming-release-v2.sh; do
        grep -Fq -- "chmod $action35h_regression_final_directory_mode" \
            "$action35h_regression_repository/$action35h_regression_mode_implementation"
    done
    printf '%s_protocol_mode_and_owner_derived=true\n' "$action35h_regression_prefix"

    local action35h_regression_split_case action35h_regression_split_root
    local action35h_regression_split_status action35h_regression_split_outbound
    for action35h_regression_split_case in \
        missing-outbound wrong-hash symlink-outbound incoming-residue \
        quarantine-residue missing-node-b-release; do
        action35h_regression_split_root=$action35h_regression_root/split-$action35h_regression_split_case
        action35h_regression_split_status=0
        install -d -m 0700 "$action35h_regression_split_root"
        action35h_regression_prepare_outer_cluster "$action35h_regression_split_root"
        action35h_regression_split_outbound=$action35h_regression_split_root/node-a/var/lib/caddy-sync/outbound/$action35h_regression_revision
        case "$action35h_regression_split_case" in
            missing-outbound)
                find "$action35h_regression_split_outbound" -type d -exec chmod u+rwx {} +
                find "$action35h_regression_split_outbound" -mindepth 1 -delete
                rmdir "$action35h_regression_split_outbound"
                ;;
            wrong-hash)
                chmod u+w "$action35h_regression_split_outbound/manifest.sha256"
                printf '0%.0s' {1..64} >>"$action35h_regression_split_outbound/manifest.sha256"
                printf '  ./unexpected\n' >>"$action35h_regression_split_outbound/manifest.sha256"
                ;;
            symlink-outbound)
                find "$action35h_regression_split_outbound" -type d -exec chmod u+rwx {} +
                find "$action35h_regression_split_outbound" -mindepth 1 -delete
                rmdir "$action35h_regression_split_outbound"
                ln -s "$action35h_regression_split_root/node-a/etc/caddy/releases/$action35h_regression_original_revision" \
                    "$action35h_regression_split_outbound"
                ;;
            incoming-residue)
                install -d -m 0700 \
                    "$action35h_regression_split_root/node-a/var/lib/caddy-sync/incoming/node-a/$action35h_regression_revision"
                ;;
            quarantine-residue)
                install -d -m 0700 \
                    "$action35h_regression_split_root/node-a/var/lib/caddy-sync/quarantine/quarantined-$action35h_regression_revision"
                ;;
            missing-node-b-release)
                find "$action35h_regression_split_root/node-b/etc/caddy/releases/$action35h_regression_revision" \
                    -type d -exec chmod u+rwx {} +
                find "$action35h_regression_split_root/node-b/etc/caddy/releases/$action35h_regression_revision" \
                    -mindepth 1 -delete
                rmdir "$action35h_regression_split_root/node-b/etc/caddy/releases/$action35h_regression_revision"
                ;;
        esac
        ACTION35H_SSH_COMMAND=$action35h_regression_transport_bin/ssh \
            ACTION35H_SCP_COMMAND=$action35h_regression_transport_bin/scp \
            ACTION35H_TRANSPORT_EVIDENCE=$action35h_regression_transport_log \
            ACTION35H_EXPECTED_ORIGINAL_REVISION=$action35h_regression_original_revision \
            ACTION35H_EXPECTED_REVISION=$action35h_regression_revision \
            ACTION35H_EXPECTED_RELEASE_MANIFEST_SHA256=$action35h_regression_release_manifest_sha256 \
            ACTION35H_EXPECTED_PAYLOAD_MANIFEST_SHA256=$action35h_regression_payload_manifest_sha256 \
            CADDY_ACTION35H_PRODUCTION_TEST_ROOT=$action35h_regression_split_root \
            /bin/bash "$action35h_regression_outer" --production-path-test-inner \
            >"$action35h_regression_root/split-$action35h_regression_split_case.stdout" \
            2>"$action35h_regression_root/split-$action35h_regression_split_case.stderr" ||
            action35h_regression_split_status=$?
        [[ "$action35h_regression_split_status" -eq 1 ]]
        [[ ! -e "$action35h_regression_split_root/ssh-evidence/node-a-prepare.status" ]]
        [[ ! -e "$action35h_regression_split_root/ssh-evidence/node-b-prepare.status" ]]
    done
    printf '%s_split_baseline_rejection_matrix=true\n' "$action35h_regression_prefix"

    local action35h_regression_rollback_root=$action35h_regression_root/outer-rollback
    local action35h_regression_rollback_status=0
    local action35h_regression_rollback_evidence=$action35h_regression_rollback_root/evidence
    install -d -m 0700 "$action35h_regression_rollback_root"
    action35h_regression_prepare_outer_cluster "$action35h_regression_rollback_root"
    ACTION35H_TEST_FAIL_AFTER_NODE_B=1 \
        ACTION35H_SSH_COMMAND=$action35h_regression_transport_bin/ssh \
        ACTION35H_SCP_COMMAND=$action35h_regression_transport_bin/scp \
        ACTION35H_TRANSPORT_EVIDENCE=$action35h_regression_transport_log \
        ACTION35H_EXPECTED_ORIGINAL_REVISION=$action35h_regression_original_revision \
        ACTION35H_EXPECTED_REVISION=$action35h_regression_revision \
        ACTION35H_EXPECTED_RELEASE_MANIFEST_SHA256=$action35h_regression_release_manifest_sha256 \
        ACTION35H_EXPECTED_PAYLOAD_MANIFEST_SHA256=$action35h_regression_payload_manifest_sha256 \
        ACTION35H_USE_REAL_CADDY=${CADDY_VALIDATION_CONTAINER:-0} \
        CADDY_ACTION35H_PRODUCTION_TEST_ROOT=$action35h_regression_rollback_root \
        CADDY_PRODUCTION_PATH_EVIDENCE_ROOT=$action35h_regression_rollback_evidence \
        /bin/bash "$action35h_regression_outer" --production-path-test-inner \
        >"$action35h_regression_root/outer-rollback.stdout" \
        2>"$action35h_regression_root/outer-rollback.stderr" ||
        action35h_regression_rollback_status=$?
    [[ "$action35h_regression_rollback_status" -eq 1 ]]
    [[ "$(<"$action35h_regression_rollback_root/node-b/etc/scripts/check-dns.sh")" = old-dns ]]
    [[ "$(readlink -f "$action35h_regression_rollback_root/node-b/etc/caddy/current")" = "$action35h_regression_rollback_root/node-b/etc/caddy/releases/$action35h_regression_revision" ]]
    [[ "$(readlink -f "$action35h_regression_rollback_root/node-a/etc/caddy/current")" = "$action35h_regression_rollback_root/node-a/etc/caddy/releases/$action35h_regression_original_revision" ]]
    [[ ! -e "$action35h_regression_rollback_root/node-a/etc/caddy/releases/$action35h_regression_revision" ]]
    [[ -d "$action35h_regression_rollback_root/node-a/var/lib/caddy-sync/outbound/$action35h_regression_revision" ]]
    [[ ! -e "$action35h_regression_rollback_root/node-a/tmp/caddy-action35h-upload" ]]
    [[ ! -e "$action35h_regression_rollback_root/node-b/tmp/caddy-action35h-upload" ]]
    [[ ! -e "$action35h_regression_rollback_root/node-a/tmp/caddy-action35h-release" ]]

    local action35h_regression_upload_failure_root=$action35h_regression_root/outer-upload-failure
    local action35h_regression_upload_failure_status=0
    install -d -m 0700 "$action35h_regression_upload_failure_root"
    action35h_regression_prepare_outer_cluster "$action35h_regression_upload_failure_root"
    ACTION35H_TEST_SCP_FAIL_NODE=$action35h_regression_upload_failure_root/node-a \
        ACTION35H_SSH_COMMAND=$action35h_regression_transport_bin/ssh \
        ACTION35H_SCP_COMMAND=$action35h_regression_transport_bin/scp \
        ACTION35H_TRANSPORT_EVIDENCE=$action35h_regression_transport_log \
        ACTION35H_EXPECTED_ORIGINAL_REVISION=$action35h_regression_original_revision \
        ACTION35H_EXPECTED_REVISION=$action35h_regression_revision \
        ACTION35H_EXPECTED_RELEASE_MANIFEST_SHA256=$action35h_regression_release_manifest_sha256 \
        ACTION35H_EXPECTED_PAYLOAD_MANIFEST_SHA256=$action35h_regression_payload_manifest_sha256 \
        CADDY_ACTION35H_PRODUCTION_TEST_ROOT=$action35h_regression_upload_failure_root \
        /bin/bash "$action35h_regression_outer" --production-path-test-inner \
        >"$action35h_regression_root/outer-upload-failure.stdout" \
        2>"$action35h_regression_root/outer-upload-failure.stderr" ||
        action35h_regression_upload_failure_status=$?
    [[ "$action35h_regression_upload_failure_status" -eq 1 ]]
    [[ ! -e "$action35h_regression_upload_failure_root/node-a/tmp/caddy-action35h-upload" ]]
    [[ ! -e "$action35h_regression_upload_failure_root/ssh-evidence/node-a-transaction.status" ]]

    if [[ "${CADDY_VALIDATION_CONTAINER:-0}" = 1 ]]; then
        [[ "$EUID" -eq 0 ]]
        local action35h_regression_identity_root=$action35h_regression_root/identity-boundary
        install -d -o root -g root -m 0750 \
            "$action35h_regression_identity_root/etc/caddy/releases/action32g"
        printf '{}\n' \
            >"$action35h_regression_identity_root/etc/caddy/releases/action32g/release-manifest.json"
        ln -s releases/action32g "$action35h_regression_identity_root/etc/caddy/current"
        if setpriv --reuid=65534 --regid=65534 --clear-groups \
            readlink -f -- "$action35h_regression_identity_root/etc/caddy/current" >/dev/null 2>&1; then
            return 1
        fi
        [[ "$(readlink -f -- "$action35h_regression_identity_root/etc/caddy/current")" = "$action35h_regression_identity_root/etc/caddy/releases/action32g" ]]
        printf '%s_real_identity_permission_boundary=true\n' "$action35h_regression_prefix"
    fi
    printf '%s_marker_only_evidence_rejected=true\n' "$action35h_regression_prefix"
    printf '%s_outer=true\n' "$action35h_regression_prefix"
    printf 'action_35h_outer_split_baseline_validated=true\n'
    printf 'action_35h_outer_standby_first=true\n'
    printf 'action_35h_outer_existing_release_reused=true\n'
    printf 'action_35h_outer_ula_probe_paths=true\n'
    printf 'action_35h_outer_complete=true\n'
}

case "$action35h_regression_mode" in
    transaction)
        action35h_regression_run_transaction node-b
        action35h_regression_rejection_matrix
        printf 'action_35h_check_baseline_complete=true\n'
        printf 'action_35h_check_residue_absent=true\n'
        printf 'action_35h_check_candidate_validation_complete=true\n'
        printf 'action_35h_check_mutation_complete=true\n'
        printf 'action_35h_check_acceptance_complete=true\n'
        printf 'action_35h_check_complete=true\n'
        ;;
    outer) action35h_regression_run_outer ;;
    all)
        action35h_regression_run_transaction node-b
        action35h_regression_run_transaction node-a
        action35h_regression_rejection_matrix
        action35h_regression_run_outer
        ;;
esac
printf '%s_complete=true\n' "$action35h_regression_prefix"
