#!/usr/bin/env bash

set -euo pipefail
set +x
umask 077
PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH
readonly PATH

readonly source_stage=/var/tmp/caddy-source-node-a-action16af
readonly certificate_stage=/var/tmp/caddy-cert-node-a-action16ae
readonly baseline=/var/backups/caddy-ha/predeploy-node-a-20260728T184626Z
readonly lighttpd_live=/etc/lighttpd
readonly lighttpd_candidate=/var/tmp/caddy-ha-lighttpd-node-a-action16ab
readonly sysctl_target=/etc/sysctl.d/70-caddy-ha.conf
readonly installer="$source_stage/Caddy/scripts/install-caddy-ha.sh"
readonly manifest="$source_stage/Caddy/manifests/deployment.yaml"

readonly live_tree_sha256=b15ff54d2e91bbecd1d21b762818599d732f01b66ee5d1ef7c24147c72e2cb92
readonly candidate_tree_sha256=6e178911d34a783e16fca001f7c91dc29098598043bd4c4c4c19af59e81a6c13
readonly keepalived_main_sha256=cf4858888ae80772f1a50dda7c0ea120ff083eafae33a0ad4ca291d44755c1e2
readonly sysctl_target_sha256=d7036eaead2f5ef20afa8bdf20a7a353ee700532a095822320a1b9efad4846e8

readonly expected_source_checksums=(
    'a41c7816e927c16278fab018675a3f2db5b2aae89dd5b181f1ecb06ec9beb86e  Caddy/configs/caddy/Caddyfile'
    '05fa1d2875ee0639601447ccd31284d3df55fc8d5e8cedef4a291c61d44f4b27  Caddy/configs/caddy/conf.d/00-health.caddy'
    '5621134920da9dde97122fe9968a2debdd0c980ac0e432323fb46e0c1139798c  Caddy/configs/caddy/conf.d/10-pihole-admin.caddy'
    '9ce8430d11882f4e2008ff27f4f4a2fcad568f81081629289f64ad2450316b27  Caddy/configs/caddy/conf.d/90-default-deny.caddy'
    '0a9c6632171c7490b030f9e4ebc2a122342c0eb8c08f95db0becf09a3f965696  Caddy/manifests/dependencies.yaml'
    'ee58ae3d2af19c6b5fd45b8c87d9c4866450d1a2d737c277c26442db36ebcfd0  Caddy/manifests/deployment.yaml'
    '809c3734dccafc743ced9db81c03db94d1bf9f6918de68b6cc38383a204ebf22  Caddy/manifests/dns-records.yaml'
    '851e93e7b32b907374dfedab8c91867b74fda50243b10f9859128c24f6149ab7  Caddy/scripts/install-caddy-ha.sh'
    'd7fa1c57a4d74edd966b78cf66d79e534f49c09a7265c2ad326f00018fa4c1c2  Caddy/scripts/render-node-config.sh'
    'bbd5ff898e49b70e4d3dbac247c5ea11b762035404f5b58e2928d3dd5dc03679  Caddy/templates/caddy-ha.env.in'
    'ebc60650edd4cb384000604b402ce1e99153b50d505c7e13289b6b33d7abdd09  Caddy/templates/keepalived-caddy-ha.conf.in'
    '5091566ae9f8165d502305ce08dad75cf1c78b417eca3dbd1dca8efa7eff105a  Caddy/templates/lsyncd-caddy.lua.in'
)

readonly expected_log_lines=(
    'ENSURE directory /etc/caddy/releases/bootstrap owner root:caddy-tls mode 0750'
    'ENSURE directory /etc/caddy/releases/bootstrap/conf.d owner root:caddy-tls mode 0750'
    'ENSURE directory /etc/caddy/releases/bootstrap/tls owner root:caddy-tls mode 0750'
    'INSTALL <render>/caddy-ha.env -> /etc/default/caddy-ha owner root:caddy-tls mode 0640'
    'INSTALL /var/tmp/caddy-cert-node-a-action16ae/certificate-manifest.json -> /etc/caddy/releases/bootstrap/tls/certificate-manifest.json owner root:root mode 0644'
    'INSTALL /var/tmp/caddy-cert-node-a-action16ae/fullchain.pem -> /etc/caddy/releases/bootstrap/tls/fullchain.pem owner root:root mode 0644'
    'INSTALL /var/tmp/caddy-cert-node-a-action16ae/intermediates.pem -> /etc/caddy/releases/bootstrap/tls/intermediates.pem owner root:root mode 0644'
    'INSTALL /var/tmp/caddy-cert-node-a-action16ae/leaf.pem -> /etc/caddy/releases/bootstrap/tls/leaf.pem owner root:root mode 0644'
    'INSTALL /var/tmp/caddy-cert-node-a-action16ae/privkey.pem -> /etc/caddy/releases/bootstrap/tls/privkey.pem owner root:caddy-tls mode 0640'
    'INSTALL /var/tmp/caddy-source-node-a-action16af/Caddy/configs/caddy/Caddyfile -> /etc/caddy/releases/bootstrap/Caddyfile owner root:root mode 0644'
    'INSTALL /var/tmp/caddy-source-node-a-action16af/Caddy/configs/caddy/conf.d/00-health.caddy -> /etc/caddy/releases/bootstrap/conf.d/00-health.caddy owner root:root mode 0644'
    'INSTALL /var/tmp/caddy-source-node-a-action16af/Caddy/configs/caddy/conf.d/10-pihole-admin.caddy -> /etc/caddy/releases/bootstrap/conf.d/10-pihole-admin.caddy owner root:root mode 0644'
    'INSTALL /var/tmp/caddy-source-node-a-action16af/Caddy/configs/caddy/conf.d/90-default-deny.caddy -> /etc/caddy/releases/bootstrap/conf.d/90-default-deny.caddy owner root:root mode 0644'
    'SYMLINK /etc/caddy/current -> /etc/caddy/releases/bootstrap'
)

package_inventory() {
    dpkg-query -W \
        -f='${binary:Package}\t${db:Status-Abbrev}\t${Version}\n' |
        sort
}

protected_service_state() {
    local service

    for service in \
        lighttpd.service keepalived.service ssh.service unbound.service \
        pihole-FTL.service munin-node.service caddy.service \
        caddy-api.service lsyncd.service uuidd.service uuidd.socket; do
        printf '### %s\n' "$service"
        systemctl show "$service" --no-pager \
            -p ActiveState -p SubState -p MainPID -p NRestarts
        printf 'unit_file_state=%s\n' \
            "$(systemctl is-enabled "$service" 2>/dev/null || true)"
    done
}

group_names() {
    id -nG "$1" |
        tr ' ' '\n' |
        sed '/^$/d' |
        sort
}

group_members() {
    getent group "$1" |
        cut -d: -f4 |
        tr ',' '\n' |
        sed '/^$/d' |
        sort
}

identity_state() {
    id caddy
    id caddy-sync
    id keepalived_script
    passwd --status caddy-sync
    passwd --status keepalived_script
    getent group caddy-tls
    stat -c '%n %U:%G:%a' \
        /etc/caddy/releases \
        /var/lib/caddy-sync \
        /var/lib/caddy-sync/outbound \
        /var/lib/caddy-sync/incoming \
        /var/lib/caddy-sync/quarantine \
        /var/lib/caddy-sync/.ssh
}

tree_hash() {
    local root=$1

    (
        cd "$root"
        find . -type f -print0 |
            sort -z |
            xargs -0 sha256sum
    ) | sha256sum | awk '{ print $1 }'
}

listener_snapshot() {
    ss -H -lntup | sort
}

stage_state() {
    local stage=$1

    find "$stage" -printf '%P|%y|%U:%G:%m:%s:%T@:%i\n' | sort
    find "$stage" -type f -print0 |
        sort -z |
        xargs -0 sha256sum
}

temporary_paths() {
    find /tmp -mindepth 1 -maxdepth 1 \
        \( -name 'caddy-render.*' -o -name 'caddy-action16ag.*' \) \
        -printf '%f\n' |
        sort
}

protected_state() {
    package_inventory
    identity_state
    protected_service_state
    listener_snapshot
    stage_state "$source_stage"
    stage_state "$certificate_stage"
    tree_hash "$lighttpd_live"
    tree_hash "$lighttpd_candidate"
    sha256sum -- \
        "$lighttpd_live/lighttpd.conf" \
        "$lighttpd_live/conf-enabled/external.conf" \
        "$lighttpd_candidate/lighttpd.conf" \
        /etc/keepalived/keepalived.conf \
        "$sysctl_target"
    /usr/sbin/sysctl -n net.ipv4.ip_nonlocal_bind
    /usr/sbin/sysctl -n net.ipv6.ip_nonlocal_bind
    dpkg --audit
    temporary_paths
}

validate_source_stage() {
    local checksum expected_hash relative_path
    local -a actual_files=()
    local -a expected_files=()

    [[ -d "$source_stage" && ! -L "$source_stage" ]]
    [[ "$(stat -c '%U:%G:%a' "$source_stage")" == root:root:750 ]]
    if find "$source_stage" -type l -print -quit | grep -q .; then
        return 1
    fi

    for checksum in "${expected_source_checksums[@]}"; do
        expected_hash=${checksum%% *}
        relative_path=${checksum#*  }
        expected_files+=("$relative_path")
        [[ -f "$source_stage/$relative_path" &&
            ! -L "$source_stage/$relative_path" ]]
        [[ "$(sha256sum "$source_stage/$relative_path" |
            awk '{ print $1 }')" == "$expected_hash" ]]
        case "$relative_path" in
            Caddy/scripts/install-caddy-ha.sh | \
                Caddy/scripts/render-node-config.sh)
                [[ "$(stat -c '%U:%G:%a' "$source_stage/$relative_path")" == root:root:750 ]]
                ;;
            *)
                [[ "$(stat -c '%U:%G:%a' "$source_stage/$relative_path")" == root:root:640 ]]
                ;;
        esac
    done

    mapfile -t actual_files < <(
        find "$source_stage" -type f -printf '%P\n' | sort
    )
    [[ "${actual_files[*]}" == "${expected_files[*]}" ]]
}

validate_certificate_stage() {
    local public_file
    local -a actual_files=()
    local -r expected_certificate_files='certificate-manifest.json fullchain.pem intermediates.pem leaf.pem privkey.pem'

    [[ -d "$certificate_stage" && ! -L "$certificate_stage" ]]
    [[ "$(stat -c '%U:%G:%a' "$certificate_stage")" == root:caddy-tls:750 ]]
    if find "$certificate_stage" -type l -print -quit | grep -q .; then
        return 1
    fi
    mapfile -t actual_files < <(
        find "$certificate_stage" -mindepth 1 -maxdepth 1 -type f \
            -printf '%f\n' | sort
    )
    [[ "${actual_files[*]}" == "$expected_certificate_files" ]]
    for public_file in \
        certificate-manifest.json fullchain.pem intermediates.pem leaf.pem; do
        [[ "$(stat -c '%U:%G:%a' "$certificate_stage/$public_file")" == root:caddy-tls:644 ]]
    done
    [[ "$(stat -c '%U:%G:%a' "$certificate_stage/privkey.pem")" == root:caddy-tls:640 ]]
    [[ "$(sha256sum "$certificate_stage/leaf.pem" |
        awk '{ print $1 }')" == 4d0eb710b9920f2017ff2ac84f80ae5784deaad4ace7b4f4dafb9537347ef319 ]]
    [[ "$(sha256sum "$certificate_stage/intermediates.pem" |
        awk '{ print $1 }')" == 6802a694f52e6c9c9f6ea7f960a815e50b600a1592bbd325bcaf42dee8e6e50d ]]
    [[ "$(sha256sum "$certificate_stage/fullchain.pem" |
        awk '{ print $1 }')" == d8d850a9e8ce026939ce4505fda50ab2578d3b0fe55580fbcf24f6004ec7aa83 ]]
    [[ "$(sha256sum "$certificate_stage/certificate-manifest.json" |
        awk '{ print $1 }')" == 0a910e43586e42110247d13bd148272a61717699379019b22ef25ed60d7e39df ]]
}

validate_node_state() {
    [[ "$(hostname)" == j1-svpihole0 ]]
    grep -Fq '10.1.0.53/22' < <(ip -o -4 address show dev eth0)
    [[ "$(dpkg --print-architecture)" == arm64 ]]
    [[ -d "$baseline" && ! -L "$baseline" ]]
    (
        cd "$baseline"
        sha256sum --check --status configuration.tar.sha256
        grep -Fxq 'backup_complete=true' backup-manifest.txt
    )

    [[ "$(dpkg-query -W -f='${db:Status-Abbrev}:${Version}:${Architecture}' caddy)" == 'ii :2.11.4:arm64' ]]
    [[ "$(id -u caddy)" -eq 995 ]]
    [[ "$(id -g caddy)" -eq 992 ]]
    [[ "$(group_names caddy)" == $'caddy\ncaddy-tls\nwww-data' ]]
    [[ "$(id -u caddy-sync)" -eq 994 ]]
    [[ "$(id -g caddy-sync)" -eq 990 ]]
    [[ "$(group_names caddy-sync)" == $'caddy-sync\ncaddy-tls' ]]
    [[ "$(id -u keepalived_script)" -eq 993 ]]
    [[ "$(id -g keepalived_script)" -eq 989 ]]
    [[ "$(group_names keepalived_script)" == $'caddy-tls\nkeepalived_script' ]]
    [[ "$(getent group caddy-tls | cut -d: -f3)" -eq 991 ]]
    [[ "$(group_members caddy-tls)" == $'caddy\ncaddy-sync\nkeepalived_script' ]]

    for unit in \
        caddy.service caddy-api.service lsyncd.service uuidd.service uuidd.socket; do
        [[ "$(systemctl is-active "$unit" 2>/dev/null || true)" == inactive ]]
        [[ "$(systemctl is-enabled "$unit" 2>/dev/null || true)" == masked ]]
    done
    for service in lighttpd keepalived ssh unbound pihole-FTL munin-node; do
        systemctl is-active --quiet "$service"
    done
    if pgrep -x caddy >/dev/null ||
        pgrep -x lsyncd >/dev/null ||
        pgrep -x uuidd >/dev/null; then
        return 1
    fi

    [[ "$(tree_hash "$lighttpd_live")" == "$live_tree_sha256" ]]
    [[ "$(tree_hash "$lighttpd_candidate")" == "$candidate_tree_sha256" ]]
    [[ "$(sha256sum /etc/keepalived/keepalived.conf |
        awk '{ print $1 }')" == "$keepalived_main_sha256" ]]
    [[ "$(sha256sum "$sysctl_target" |
        awk '{ print $1 }')" == "$sysctl_target_sha256" ]]
    [[ "$(/usr/sbin/sysctl -n net.ipv4.ip_nonlocal_bind)" == 1 ]]
    [[ "$(/usr/sbin/sysctl -n net.ipv6.ip_nonlocal_bind)" == 1 ]]
    [[ ! -e /etc/caddy/releases/bootstrap &&
        ! -L /etc/caddy/releases/bootstrap ]]
    [[ ! -e /etc/caddy/current && ! -L /etc/caddy/current ]]
    [[ ! -e /etc/default/caddy-ha && ! -L /etc/default/caddy-ha ]]
    [[ ! -e /usr/sbin/policy-rc.d && ! -L /usr/sbin/policy-rc.d ]]
    [[ -z "$(dpkg --audit)" ]]
    [[ -z "$(temporary_paths)" ]]

    validate_source_stage
    validate_certificate_stage
}

validate_dry_run_log() {
    local input_log=$1
    local normalized_output=$2
    local expected_output=$3

    sed -E \
        's#/tmp/caddy-action16ag\.[A-Za-z0-9]+/caddy-render\.[A-Za-z0-9]+#<render>#g' \
        "$input_log" |
        sort >"$normalized_output"
    printf '%s\n' "${expected_log_lines[@]}" |
        sort >"$expected_output"
    cmp --silent "$expected_output" "$normalized_output"
    [[ "$(wc -l <"$normalized_output")" -eq 14 ]]
}

capture_dir=
state_before=
action_complete=false
cleanup() {
    local original_rc=$?
    local cleanup_failed=false

    trap - EXIT
    set +e
    if [[ -n "$capture_dir" ]]; then
        case "$capture_dir" in
            /tmp/caddy-action16ag.*)
                rm -rf --one-file-system -- "$capture_dir" ||
                    cleanup_failed=true
                ;;
            *)
                cleanup_failed=true
                ;;
        esac
    fi
    [[ -z "$(temporary_paths)" ]] || cleanup_failed=true
    if [[ -n "$state_before" ]]; then
        [[ "$(protected_state)" == "$state_before" ]] ||
            cleanup_failed=true
    fi

    if [[ "$cleanup_failed" == true ]]; then
        printf 'action_16ag_transient_cleanup_complete=false\n' >&2
        printf 'manual_intervention_required=true\n' >&2
        exit 97
    fi
    if [[ "$action_complete" != true ]]; then
        printf 'action_16ag_transient_cleanup_complete=true\n' >&2
    fi
    exit "$original_rc"
}

if [[ "${1:-}" == --self-test ]]; then
    [[ "${#expected_source_checksums[@]}" -eq 12 ]]
    [[ "${#expected_log_lines[@]}" -eq 14 ]]
    [[ "$installer" == /var/tmp/caddy-source-node-a-action16af/Caddy/scripts/install-caddy-ha.sh ]]
    [[ "$manifest" == /var/tmp/caddy-source-node-a-action16af/Caddy/manifests/deployment.yaml ]]
    self_test_dir=$(mktemp -d /tmp/caddy-action16ag-selftest.XXXXXX)
    trap 'rm -rf --one-file-system -- "$self_test_dir"' EXIT
    printf '%s\n' "${expected_log_lines[@]}" |
        sed \
            's#<render>#/tmp/caddy-action16ag.A1b2C3/caddy-render.D4e5F6#g' \
            >"$self_test_dir/input.log"
    validate_dry_run_log \
        "$self_test_dir/input.log" \
        "$self_test_dir/normalized.log" \
        "$self_test_dir/expected.log"
    rm -rf --one-file-system -- "$self_test_dir"
    trap - EXIT
    printf 'action_16ag_installer_dry_run_self_test_complete=true\n'
    exit 0
elif (($#)); then
    printf 'Usage: %s [--self-test]\n' "${0##*/}" >&2
    exit 2
fi

[[ "$(id -u)" -eq 0 ]]
validate_node_state
state_before=$(protected_state)

trap cleanup EXIT
capture_dir=$(mktemp -d /tmp/caddy-action16ag.XXXXXX)
readonly dry_run_stdout="$capture_dir/stdout.json"
readonly dry_run_stderr="$capture_dir/stderr.log"
readonly normalized_log="$capture_dir/stderr.normalized"
readonly expected_log="$capture_dir/stderr.expected"

TMPDIR="$capture_dir" "$installer" \
    --node node-a \
    --component caddy \
    --manifest "$manifest" \
    --certificate-dir "$certificate_stage" \
    --dry-run \
    >"$dry_run_stdout" \
    2>"$dry_run_stderr"

jq -e '
    keys == [
        "changes",
        "component",
        "dry_run",
        "node",
        "root",
        "service_mutations"
    ] and
    .node == "node-a" and
    .component == "caddy" and
    .root == "/" and
    .dry_run == true and
    .changes == 14 and
    .service_mutations == false
' "$dry_run_stdout" >/dev/null
validate_dry_run_log \
    "$dry_run_stderr" \
    "$normalized_log" \
    "$expected_log"

rm -rf --one-file-system -- "$capture_dir"
capture_dir=
[[ -z "$(temporary_paths)" ]]
validate_node_state
[[ "$(protected_state)" == "$state_before" ]]

action_complete=true
trap - EXIT
printf 'installer_node=node-a\n'
printf 'installer_component=caddy\n'
printf 'installer_root=/\n'
printf 'installer_dry_run=true\n'
printf 'installer_changes=14\n'
printf 'installer_service_mutations=false\n'
printf 'source_stage_unchanged=true\n'
printf 'certificate_stage_unchanged=true\n'
printf 'protected_state_unchanged=true\n'
printf 'action_16ag_installer_dry_run_complete=true\n'
