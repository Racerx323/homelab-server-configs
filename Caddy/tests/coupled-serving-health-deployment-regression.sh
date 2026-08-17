#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly action35b_regression_prefix=serving_health_deployment_regression
action35b_regression_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly action35b_regression_directory
readonly action35b_regression_repository=${action35b_regression_directory%/Caddy/tests}
readonly action35b_regression_transaction=$action35b_regression_repository/Caddy/scripts/apply-coupled-serving-health-action35b.sh
readonly action35b_regression_outer=$action35b_regression_repository/Caddy/scripts/run-dual-node-coupled-serving-health-action35b-outer.sh
readonly action35b_regression_manifest=$action35b_regression_repository/Caddy/manifests/serving-health-production.tsv
readonly action35b_regression_successor_registry=$action35b_regression_repository/Caddy/manifests/deployable-successor.tsv

awk -F '\t' '
    NR == 2 && $2 == "defined" && $3 == "35b" { found++ }
    END { exit(found == 1 ? 0 : 1) }
' "$action35b_regression_successor_registry"

action35b_regression_mode=all
if [[ "${1:-}" = --entrypoint ]]; then
    action35b_regression_mode=${2:-}
    [[ $# -eq 2 && "$action35b_regression_mode" =~ ^(transaction|outer)$ ]] || exit 64
elif [[ "${1:-}" = --prepare-node ]]; then
    [[ $# -eq 3 && "$3" =~ ^node-[ab]$ && "$2" = /tmp/* ]] || exit 64
    action35b_regression_make_after_parse=true
    action35b_regression_prepare_root=$2
    action35b_regression_prepare_role=$3
elif [[ "${1:-}" = --add-baseline-inventory ]]; then
    [[ $# -eq 4 && "$2" = /tmp/* && "$3" = /tmp/* && "$4" =~ ^node-[ab]$ ]] || exit 64
    action35b_regression_inventory_after_parse=true
    action35b_regression_inventory_payload=$2
    action35b_regression_inventory_root=$3
    action35b_regression_inventory_role=$4
elif (($#)); then
    exit 64
fi

action35b_regression_root=$(mktemp -d /tmp/caddy-action35b-production-path.XXXXXX)
readonly action35b_regression_root
if [[ "${ACTION35B_KEEP_TEST_ROOT:-0}" = 1 ]]; then
    printf 'action35b_test_root=%s\n' "$action35b_regression_root" >&2
else
    trap 'rm -rf -- "$action35b_regression_root"' EXIT INT TERM
fi

action35b_regression_copy_payload() {
    local action35b_regression_payload=$1
    local action35b_regression_repo action35b_regression_source
    local action35b_regression_source_root action35b_regression_destination

    install -d -m 0700 "$action35b_regression_payload/files/homelab-server-configs" \
        "$action35b_regression_payload/files/homelab-dns"
    install -m 0600 "$action35b_regression_manifest" \
        "$action35b_regression_payload/serving-health-production.tsv"
    install -m 0600 "$action35b_regression_repository/Caddy/manifests/current-live-state.tsv" \
        "$action35b_regression_payload/current-live-state.tsv"
    printf '%s\n' \
        $'# key\trepository\tsource-path\tinstalled-path\tnode\tsource-sha256\tdeployed-sha256\taccepted-action\tlifecycle' \
        >"$action35b_regression_payload/production-artifacts.tsv"
    while IFS=$'\t' read -r action35b_regression_repo action35b_regression_source _ _ _ _; do
        [[ -n "$action35b_regression_repo" && "$action35b_regression_repo" != \#* ]] || continue
        action35b_regression_source_root=$action35b_regression_repository
        [[ "$action35b_regression_repo" = homelab-server-configs ]] ||
            action35b_regression_source_root=${action35b_regression_repository%/homelab-server-configs}/homelab-dns
        action35b_regression_destination=$action35b_regression_payload/files/$action35b_regression_repo/$action35b_regression_source
        install -d -m 0700 "$(dirname -- "$action35b_regression_destination")"
        install -m 0600 "$action35b_regression_source_root/$action35b_regression_source" \
            "$action35b_regression_destination"
    done <"$action35b_regression_manifest"
}

action35b_regression_add_baseline_inventory() {
    local action35b_regression_payload=$1
    local action35b_regression_node_root=$2
    local action35b_regression_role=$3
    local action35b_regression_key action35b_regression_path action35b_regression_hash

    for action35b_regression_key in dns-helper caddy-helper keepalived-config; do
        case "$action35b_regression_key" in
            dns-helper) action35b_regression_path=/etc/scripts/check-dns.sh ;;
            caddy-helper) action35b_regression_path=/usr/local/libexec/check-caddy.sh ;;
            keepalived-config) action35b_regression_path=/etc/keepalived/keepalived.conf ;;
        esac
        action35b_regression_hash=$(sha256sum "$action35b_regression_node_root$action35b_regression_path" | awk '{ print $1 }')
        printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
            "${action35b_regression_role}_${action35b_regression_key}" test test \
            "$action35b_regression_path" "$action35b_regression_role" \
            "$action35b_regression_hash" "$action35b_regression_hash" test production-current \
            >>"$action35b_regression_payload/production-artifacts.tsv"
    done
}

if [[ "${action35b_regression_inventory_after_parse:-false}" = true ]]; then
    printf '%s\n' \
        $'# key\trepository\tsource-path\tinstalled-path\tnode\tsource-sha256\tdeployed-sha256\taccepted-action\tlifecycle' \
        >"$action35b_regression_inventory_payload/production-artifacts.tsv"
    action35b_regression_add_baseline_inventory "$action35b_regression_inventory_payload" \
        "$action35b_regression_inventory_root" "$action35b_regression_inventory_role"
    exit 0
fi

action35b_regression_make_node() {
    local action35b_regression_node_root=$1
    local action35b_regression_role=$2
    local action35b_regression_fqdn=pi${action35b_regression_role#node-}.local.theama.co
    local action35b_regression_ipv4=10.1.0.53
    local action35b_regression_ipv6=fd36:5aa8:6971:1::53

    [[ "$action35b_regression_role" = node-a ]] || {
        action35b_regression_fqdn=pihole00.local.theama.co
        action35b_regression_ipv4=10.1.0.54
        action35b_regression_ipv6=fd36:5aa8:6971:1::54
    }
    install -d -m 0700 \
        "$action35b_regression_node_root/bin" "$action35b_regression_node_root/calls" \
        "$action35b_regression_node_root/etc/caddy/releases/action32g/conf.d" \
        "$action35b_regression_node_root/etc/scripts" \
        "$action35b_regression_node_root/etc/keepalived" \
        "$action35b_regression_node_root/etc/default" \
        "$action35b_regression_node_root/usr/local/libexec" \
        "$action35b_regression_node_root/etc/systemd/system" \
        "$action35b_regression_node_root/var/lib/caddy-sync/incoming" \
        "$action35b_regression_node_root/var/lib/caddy-sync/outbound" \
        "$action35b_regression_node_root/var/lib/caddy-pihole-web-health" \
        "$action35b_regression_node_root/run/caddy-pihole-web-health"
    ln -s releases/action32g "$action35b_regression_node_root/etc/caddy/current"
    printf '{"revision":"action32g","parent_revision":"action32f","source_node":"node-a"}\n' \
        >"$action35b_regression_node_root/etc/caddy/releases/action32g/release-manifest.json"
    printf 'NODE_FQDN=%s\nNODE_IPV4=%s\nNODE_IPV6=%s\n' \
        "$action35b_regression_fqdn" "$action35b_regression_ipv4" "$action35b_regression_ipv6" \
        >"$action35b_regression_node_root/etc/default/caddy-ha"
    printf 'old-dns\n' >"$action35b_regression_node_root/etc/scripts/check-dns.sh"
    printf 'old-caddy\n' >"$action35b_regression_node_root/usr/local/libexec/check-caddy.sh"
    printf 'old-keepalived\n' >"$action35b_regression_node_root/etc/keepalived/keepalived.conf"
    : >"$action35b_regression_node_root/calls/systemctl.tsv"
    : >"$action35b_regression_node_root/calls/identities.tsv"
    cat >"$action35b_regression_node_root/bin/systemctl" <<EOF
#!/usr/bin/env bash
printf '%q ' "\$@" >>'$action35b_regression_node_root/calls/systemctl.tsv'
printf '\n' >>'$action35b_regression_node_root/calls/systemctl.tsv'
if [[ -f '$action35b_regression_node_root/fail-once' ]] && grep -Fxq -- "\$*" '$action35b_regression_node_root/fail-once'; then
    rm -f -- '$action35b_regression_node_root/fail-once'
    exit 1
fi
if [[ -f '$action35b_regression_node_root/fail-always' ]] && grep -Fxq -- "\$*" '$action35b_regression_node_root/fail-always'; then
    exit 1
fi
case "\${1:-}" in
    is-active | is-enabled | daemon-reload | reload | enable | disable | start) exit 0 ;;
esac
exit 1
EOF
    cat >"$action35b_regression_node_root/bin/caddy" <<EOF
#!/usr/bin/env bash
printf '%q ' "\$@" >>'$action35b_regression_node_root/calls/caddy.tsv'
printf '\n' >>'$action35b_regression_node_root/calls/caddy.tsv'
[[ "\${1:-}" = validate ]]
EOF
    cat >"$action35b_regression_node_root/bin/keepalived" <<EOF
#!/usr/bin/env bash
printf '%q ' "\$@" >>'$action35b_regression_node_root/calls/keepalived.tsv'
printf '\n' >>'$action35b_regression_node_root/calls/keepalived.tsv'
grep -Fq 'check-caddy' "\${2#--use-file=}"
EOF
    cat >"$action35b_regression_node_root/bin/journalctl" <<'EOF'
#!/usr/bin/env bash
case " $* " in
    *' --show-cursor '*) printf '%s\n' 'cursor: action35b-cursor' ;;
    *' --after-cursor '*) printf '%s\n' 'serving-health transition bounded and healthy' ;;
    *) exit 2 ;;
esac
EOF
    cat >"$action35b_regression_node_root/bin/dig" <<'EOF'
#!/usr/bin/env bash
case " $* " in
    *' A '*) printf '%s\n' 10.1.0.55 ;;
    *' AAAA '*) printf '%s\n' fd36:5aa8:6971:1::55 ;;
    *) exit 2 ;;
esac
EOF
    cat >"$action35b_regression_node_root/bin/curl" <<'EOF'
#!/usr/bin/env bash
case "$*" in
    *'/healthz'*) printf '204\n' ;;
    *'pihole00.local.theama.co'*) printf '200 https://pihole00.local.theama.co/admin/login.php\n' ;;
    *'pihole0.local.theama.co'*) printf '200 https://pihole0.local.theama.co/admin/login.php\n' ;;
    *) exit 2 ;;
esac
EOF
    cat >"$action35b_regression_node_root/bin/ss" <<EOF
#!/usr/bin/env bash
printf 'LISTEN 0 4096 $action35b_regression_ipv4:443 0.0.0.0:*\n'
printf 'LISTEN 0 4096 [$action35b_regression_ipv6]:443 [::]:*\n'
printf 'UNCONN 0 0 $action35b_regression_ipv4:443 0.0.0.0:*\n'
printf 'UNCONN 0 0 [$action35b_regression_ipv6]:443 [::]:*\n'
EOF
    cat >"$action35b_regression_node_root/bin/enqueue" <<EOF
#!/usr/bin/env bash
printf '%q ' "\$@" >>'$action35b_regression_node_root/calls/enqueue.tsv'
printf '\n' >>'$action35b_regression_node_root/calls/enqueue.tsv'
EOF
    cat >"$action35b_regression_node_root/bin/ownership" <<'EOF'
#!/usr/bin/env bash
case "${1:-}" in
    node-a) printf '%s\n' 'ipv4=Master ipv6=Master vip_count=4' ;;
    node-b) printf '%s\n' 'ipv4=Backup ipv6=Backup vip_count=0' ;;
    *) exit 2 ;;
esac
EOF
    cat >"$action35b_regression_node_root/usr/local/libexec/publish-release-v2.sh" <<'EOF'
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
readonly revision=action35b-production-path
readonly node_a=$ACTION35B_CLUSTER_ROOT/node-a
readonly node_b=$ACTION35B_CLUSTER_ROOT/node-b
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
    cat >"$action35b_regression_node_root/usr/local/libexec/finalize-incoming-release-v2.sh" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
readonly node_root=$ACTION35B_ROOT_PREFIX
incoming=$(find "$node_root/var/lib/caddy-sync/incoming" -mindepth 1 -maxdepth 1 -type d -print)
[[ -n "$incoming" && "$(printf '%s\n' "$incoming" | wc -l)" -eq 1 ]]
revision=${incoming##*/}
install -d -m 0700 "$node_root/etc/caddy/releases/$revision"
cp -a -- "$incoming/." "$node_root/etc/caddy/releases/$revision/"
ln -sfn "releases/$revision" "$node_root/etc/caddy/current"
find "$incoming" -xdev -mindepth 1 -delete
rmdir "$incoming"
EOF
    chmod 0755 "$action35b_regression_node_root/usr/local/libexec/"*.sh
    chmod 0755 "$action35b_regression_node_root/bin/"*
}

if [[ "${action35b_regression_make_after_parse:-false}" = true ]]; then
    action35b_regression_make_node "$action35b_regression_prepare_root" \
        "$action35b_regression_prepare_role"
    exit 0
fi

action35b_regression_run_transaction() {
    local action35b_regression_role=$1
    local action35b_regression_node_root=$action35b_regression_root/$action35b_regression_role
    local action35b_regression_payload=$action35b_regression_root/payload-$action35b_regression_role

    action35b_regression_make_node "$action35b_regression_node_root" "$action35b_regression_role"
    action35b_regression_copy_payload "$action35b_regression_payload"
    action35b_regression_add_baseline_inventory "$action35b_regression_payload" \
        "$action35b_regression_node_root" "$action35b_regression_role"
    if ! /bin/bash "$action35b_regression_transaction" --node-role "$action35b_regression_role" \
        --payload "$action35b_regression_payload" --production-path-test "$action35b_regression_node_root" \
        >"$action35b_regression_root/$action35b_regression_role.stdout" \
        2>"$action35b_regression_root/$action35b_regression_role.stderr"; then
        sed -n '1,120p' "$action35b_regression_root/$action35b_regression_role.stderr" >&2
        return 1
    fi
    [[ ! -s "$action35b_regression_root/$action35b_regression_role.stderr" ]]
    grep -Fxq 'action_35b_check_complete=true' "$action35b_regression_root/$action35b_regression_role.stdout"
    grep -Fq 'reload keepalived.service' "$action35b_regression_node_root/calls/systemctl.tsv"
    grep -Fq 'enable --now caddy-pihole-web-health.timer' "$action35b_regression_node_root/calls/systemctl.tsv"
    [[ "$(wc -l <"$action35b_regression_node_root/calls/identities.tsv")" -ge 9 ]]
    [[ -s "$action35b_regression_node_root/tmp/caddy-action35b/$action35b_regression_role/journal-after-cursor.stdout" ]]
    printf '%s_transaction_%s=true\n' "$action35b_regression_prefix" "${action35b_regression_role//-/_}"
}

action35b_regression_rejection_matrix() {
    local action35b_regression_case_root=$action35b_regression_root/reject-residue
    local action35b_regression_case_payload=$action35b_regression_root/reject-residue-payload
    local action35b_regression_status=0

    action35b_regression_make_node "$action35b_regression_case_root" node-b
    action35b_regression_copy_payload "$action35b_regression_case_payload"
    action35b_regression_add_baseline_inventory "$action35b_regression_case_payload" \
        "$action35b_regression_case_root" node-b
    install -d -m 0700 "$action35b_regression_case_root/var/lib/caddy-sync/incoming/action35b-unsafe"
    /bin/bash "$action35b_regression_transaction" --node-role node-b \
        --payload "$action35b_regression_case_payload" --production-path-test "$action35b_regression_case_root" \
        >"$action35b_regression_root/reject-residue.stdout" \
        2>"$action35b_regression_root/reject-residue.stderr" || action35b_regression_status=$?
    [[ "$action35b_regression_status" -eq 1 ]]
    grep -Fxq 0 "$action35b_regression_case_root/tmp/caddy-action35b/node-b/mutation-count"
    [[ "$(<"$action35b_regression_case_root/etc/scripts/check-dns.sh")" = old-dns ]]

    action35b_regression_case_root=$action35b_regression_root/rollback-proven
    action35b_regression_case_payload=$action35b_regression_root/rollback-proven-payload
    action35b_regression_status=0
    action35b_regression_make_node "$action35b_regression_case_root" node-b
    action35b_regression_copy_payload "$action35b_regression_case_payload"
    action35b_regression_add_baseline_inventory "$action35b_regression_case_payload" \
        "$action35b_regression_case_root" node-b
    printf '%s\n' 'reload keepalived.service' \
        >"$action35b_regression_case_root/fail-once"
    /bin/bash "$action35b_regression_transaction" --node-role node-b \
        --payload "$action35b_regression_case_payload" --production-path-test "$action35b_regression_case_root" \
        >"$action35b_regression_root/rollback-proven.stdout" \
        2>"$action35b_regression_root/rollback-proven.stderr" || action35b_regression_status=$?
    [[ "$action35b_regression_status" -eq 1 ]]
    grep -Fxq 'action_35b_check_rollback_complete=true' "$action35b_regression_root/rollback-proven.stdout"
    [[ "$(<"$action35b_regression_case_root/etc/scripts/check-dns.sh")" = old-dns ]]

    action35b_regression_case_root=$action35b_regression_root/rollback-unproven
    action35b_regression_case_payload=$action35b_regression_root/rollback-unproven-payload
    action35b_regression_status=0
    action35b_regression_make_node "$action35b_regression_case_root" node-b
    action35b_regression_copy_payload "$action35b_regression_case_payload"
    action35b_regression_add_baseline_inventory "$action35b_regression_case_payload" \
        "$action35b_regression_case_root" node-b
    printf '%s\n' 'reload keepalived.service' \
        >"$action35b_regression_case_root/fail-once"
    printf '%s\n' 'reload keepalived.service' >"$action35b_regression_case_root/fail-always"
    /bin/bash "$action35b_regression_transaction" --node-role node-b \
        --payload "$action35b_regression_case_payload" --production-path-test "$action35b_regression_case_root" \
        >"$action35b_regression_root/rollback-unproven.stdout" \
        2>"$action35b_regression_root/rollback-unproven.stderr" || action35b_regression_status=$?
    [[ "$action35b_regression_status" -eq 125 ]]
    printf '%s_rejection_and_rollback_matrix=true\n' "$action35b_regression_prefix"
}

action35b_regression_run_outer() {
    local action35b_regression_outer_root=$action35b_regression_root/outer
    local action35b_regression_outer_evidence=$action35b_regression_outer_root/evidence
    local action35b_regression_transport_bin=$action35b_regression_outer_root/transport-bin
    local action35b_regression_transport_log=$action35b_regression_outer_root/transport.tsv
    install -d -m 0700 "$action35b_regression_outer_root" \
        "$action35b_regression_transport_bin"
    : >"$action35b_regression_transport_log"
    cat >"$action35b_regression_transport_bin/ssh" <<EOF
#!/usr/bin/env bash
set -Eeuo pipefail
node=\$1
remote=\$2
case "\$node" in
    pi@10.1.0.53) node_root=\$CADDY_ACTION35B_PRODUCTION_TEST_ROOT/node-a ;;
    pi@10.1.0.54) node_root=\$CADDY_ACTION35B_PRODUCTION_TEST_ROOT/node-b ;;
    *) exit 64 ;;
esac
printf 'ssh\t%s\t%s\n' "\$node" "\$remote" >>'$action35b_regression_transport_log'
export ACTION35B_ROOT_PREFIX=\$node_root
export ACTION35B_CLUSTER_ROOT=\$CADDY_ACTION35B_PRODUCTION_TEST_ROOT
export PATH=\$node_root/bin:/usr/bin:/bin
remote=\${remote//sudo -n \/bin\/bash/\/bin\/bash}
if [[ "\$remote" = *'/transaction.sh'* ]]; then
    remote=\${remote//\/tmp\/caddy-action35b-upload/\$node_root\/tmp\/caddy-action35b-upload}
    remote="\$remote --production-path-test \$node_root"
fi
/bin/sh -c "\$remote"
EOF
    cat >"$action35b_regression_transport_bin/scp" <<EOF
#!/usr/bin/env bash
set -Eeuo pipefail
source_path=\$1
remote=\$2
case "\$remote" in
    pi@10.1.0.53:*) node_root=\$CADDY_ACTION35B_PRODUCTION_TEST_ROOT/node-a ;;
    pi@10.1.0.54:*) node_root=\$CADDY_ACTION35B_PRODUCTION_TEST_ROOT/node-b ;;
    *) exit 64 ;;
esac
remote_path=\${remote#*:}
printf 'scp\t%s\t%s\n' "\$source_path" "\$remote" >>'$action35b_regression_transport_log'
install -m 0600 "\$source_path" "\$node_root\$remote_path"
EOF
    chmod 0755 "$action35b_regression_transport_bin/ssh" \
        "$action35b_regression_transport_bin/scp"
    if [[ "$action35b_regression_mode" = outer && -n "${CADDY_PRODUCTION_PATH_EVIDENCE_ROOT:-}" ]]; then
        action35b_regression_outer_evidence=$CADDY_PRODUCTION_PATH_EVIDENCE_ROOT
    fi
    if ! ACTION35B_SSH_COMMAND=$action35b_regression_transport_bin/ssh \
        ACTION35B_SCP_COMMAND=$action35b_regression_transport_bin/scp \
        ACTION35B_TRANSPORT_EVIDENCE=$action35b_regression_transport_log \
        CADDY_ACTION35B_PRODUCTION_TEST_ROOT=$action35b_regression_outer_root \
        CADDY_PRODUCTION_PATH_EVIDENCE_ROOT=$action35b_regression_outer_evidence \
        /bin/bash "$action35b_regression_outer" --production-path-test-inner \
        >"$action35b_regression_root/outer.stdout" 2>"$action35b_regression_root/outer.stderr"; then
        sed -n '1,120p' "$action35b_regression_root/outer.stderr" >&2
        return 1
    fi
    [[ ! -s "$action35b_regression_root/outer.stderr" ]]
    grep -Fxq 'action_35b_outer_complete=true' "$action35b_regression_root/outer.stdout"
    [[ "$(grep -c '^ssh' "$action35b_regression_transport_log")" -eq 9 ]]
    [[ "$(grep -c '^scp' "$action35b_regression_transport_log")" -eq 2 ]]
    grep -Fq $'ssh\tpi@10.1.0.53\tcd / && /bin/bash -s -- /tmp/caddy-action35b-upload' \
        "$action35b_regression_transport_log"
    grep -Fq $'ssh\tpi@10.1.0.54\tcd / && /bin/bash -s -- /tmp/caddy-action35b-upload' \
        "$action35b_regression_transport_log"
    if grep -Fq '/bin/bash -c' "$action35b_regression_transport_log"; then
        return 1
    fi
    grep -Fxq '/tmp/caddy-action35b-upload' \
        "$action35b_regression_outer_root/ssh-evidence/remote-path"
    grep -Fq '/bin/bash' "$action35b_regression_outer_root/ssh-evidence/node-b-command.argv"
    grep -Fq '/tmp/caddy-action35b-upload/transaction.sh' \
        "$action35b_regression_outer_root/ssh-evidence/node-b-command.argv"
    grep -Fq $'ssh\tpi@10.1.0.53\tcd / && sudo -n /bin/bash -s -- /tmp/caddy-action35b-upload' \
        "$action35b_regression_transport_log"
    grep -Fq 'release-publish.remote-command' < <(
        find "$action35b_regression_outer_root/ssh-evidence" -maxdepth 1 -printf '%f\n'
    )
    [[ "$(wc -l <"$action35b_regression_outer_root/ssh-evidence/availability.tsv")" -ge 2 ]]
    grep -Fxq 1 \
        "$action35b_regression_outer_root/node-a/tmp/caddy-action35b/node-a/mutation-count"
    grep -Fxq 1 \
        "$action35b_regression_outer_root/node-b/tmp/caddy-action35b/node-b/mutation-count"
    [[ -s "$action35b_regression_outer_root/node-a/calls/identities.tsv" ]]
    [[ -s "$action35b_regression_outer_root/node-b/calls/identities.tsv" ]]

    local action35b_regression_rollback_root=$action35b_regression_root/outer-rollback
    local action35b_regression_rollback_status=0
    local action35b_regression_rollback_evidence=$action35b_regression_rollback_root/evidence
    install -d -m 0700 "$action35b_regression_rollback_root"
    ACTION35B_TEST_FAIL_AFTER_NODE_B=1 \
        ACTION35B_SSH_COMMAND=$action35b_regression_transport_bin/ssh \
        ACTION35B_SCP_COMMAND=$action35b_regression_transport_bin/scp \
        ACTION35B_TRANSPORT_EVIDENCE=$action35b_regression_transport_log \
        CADDY_ACTION35B_PRODUCTION_TEST_ROOT=$action35b_regression_rollback_root \
        CADDY_PRODUCTION_PATH_EVIDENCE_ROOT=$action35b_regression_rollback_evidence \
        /bin/bash "$action35b_regression_outer" --production-path-test-inner \
        >"$action35b_regression_root/outer-rollback.stdout" \
        2>"$action35b_regression_root/outer-rollback.stderr" ||
        action35b_regression_rollback_status=$?
    [[ "$action35b_regression_rollback_status" -eq 1 ]]
    [[ "$(<"$action35b_regression_rollback_root/node-b/etc/scripts/check-dns.sh")" = old-dns ]]
    [[ "$(readlink -f "$action35b_regression_rollback_root/node-b/etc/caddy/current")" = "$action35b_regression_rollback_root/node-b/etc/caddy/releases/action32g" ]]
    printf '%s_marker_only_evidence_rejected=true\n' "$action35b_regression_prefix"
    printf '%s_outer=true\n' "$action35b_regression_prefix"
}

case "$action35b_regression_mode" in
    transaction)
        action35b_regression_run_transaction node-b
        action35b_regression_rejection_matrix
        printf 'action_35b_check_baseline_complete=true\n'
        printf 'action_35b_check_candidate_validation_complete=true\n'
        printf 'action_35b_check_mutation_complete=true\n'
        printf 'action_35b_check_acceptance_complete=true\n'
        printf 'action_35b_check_complete=true\n'
        ;;
    outer) action35b_regression_run_outer ;;
    all)
        action35b_regression_run_transaction node-b
        action35b_regression_run_transaction node-a
        action35b_regression_rejection_matrix
        action35b_regression_run_outer
        ;;
esac
printf '%s_complete=true\n' "$action35b_regression_prefix"
