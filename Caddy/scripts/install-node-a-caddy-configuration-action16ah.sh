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
readonly release_parent=/etc/caddy/releases
readonly release=/etc/caddy/releases/bootstrap
readonly current_link=/etc/caddy/current
readonly environment_file=/etc/default/caddy-ha

readonly live_tree_sha256=b15ff54d2e91bbecd1d21b762818599d732f01b66ee5d1ef7c24147c72e2cb92
readonly candidate_tree_sha256=6e178911d34a783e16fca001f7c91dc29098598043bd4c4c4c19af59e81a6c13
readonly keepalived_main_sha256=cf4858888ae80772f1a50dda7c0ea120ff083eafae33a0ad4ca291d44755c1e2
readonly sysctl_target_sha256=d7036eaead2f5ef20afa8bdf20a7a353ee700532a095822320a1b9efad4846e8
readonly environment_sha256=2e439dd4c868736fd7a9dceff7ba3627a1d9fe8780ba7dcef2ce5d0e5e62a2b8

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

readonly expected_release_files=(
    Caddyfile
    conf.d/00-health.caddy
    conf.d/10-pihole-admin.caddy
    conf.d/90-default-deny.caddy
    tls/certificate-manifest.json
    tls/fullchain.pem
    tls/intermediates.pem
    tls/leaf.pem
    tls/privkey.pem
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
        "$release_parent" \
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
            xargs -0 -r sha256sum
    ) | sha256sum | awk '{ print $1 }'
}

tree_state() {
    local root=$1

    find "$root" -printf '%P|%y|%U:%G:%m:%s:%T@:%i\n' | sort
    find "$root" -type f -print0 |
        sort -z |
        xargs -0 -r sha256sum
}

listener_snapshot() {
    ss -H -lntup | sort
}

stage_state() {
    local stage=$1

    tree_state "$stage"
}

backup_state() {
    find /var/backups/caddy-ha -mindepth 1 -maxdepth 1 \
        -printf '%f|%y|%U:%G:%m:%s:%T@:%i\n' |
        sort
    sha256sum \
        "$baseline/configuration.tar.sha256" \
        "$baseline/backup-manifest.txt"
}

temporary_paths() {
    find /tmp -mindepth 1 -maxdepth 1 \
        \( -name 'caddy-render.*' -o -name 'caddy-action16ah.*' \) \
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
    tree_state /var/lib/caddy
    tree_state /var/log/caddy
    backup_state
    tree_hash "$lighttpd_live"
    tree_hash "$lighttpd_candidate"
    sha256sum -- \
        "$lighttpd_live/lighttpd.conf" \
        "$lighttpd_live/conf-enabled/external.conf" \
        "$lighttpd_candidate/lighttpd.conf" \
        /etc/caddy/Caddyfile \
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

validate_common_state() {
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
    [[ "$(/usr/bin/caddy version)" == 'v2.11.4 h1:XKxkMTgNSizEvKG6QHue6cAsFOteU2qA61w2tKkCWi0=' ]]
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
    [[ "$(stat -c '%U:%G:%a' "$release_parent")" == root:caddy-tls:750 ]]

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
    [[ ! -e /usr/sbin/policy-rc.d && ! -L /usr/sbin/policy-rc.d ]]
    [[ -z "$(dpkg --audit)" ]]

    validate_source_stage
    validate_certificate_stage
}

validate_targets_absent() {
    [[ ! -e "$release" && ! -L "$release" ]]
    [[ ! -e "$current_link" && ! -L "$current_link" ]]
    [[ ! -e "$environment_file" && ! -L "$environment_file" ]]
}

validate_installer_json() {
    local json_file=$1
    local expected_changes=$2
    local expected_dry_run=$3

    jq -e \
        --argjson changes "$expected_changes" \
        --argjson dry_run "$expected_dry_run" '
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
        .dry_run == $dry_run and
        .changes == $changes and
        .service_mutations == false
    ' "$json_file" >/dev/null
}

validate_installed_targets() {
    local relative_path
    local -a actual_files=()

    [[ -d "$release" && ! -L "$release" ]]
    [[ "$(stat -c '%U:%G:%a' "$release")" == root:caddy-tls:750 ]]
    [[ "$(stat -c '%U:%G:%a' "$release/conf.d")" == root:caddy-tls:750 ]]
    [[ "$(stat -c '%U:%G:%a' "$release/tls")" == root:caddy-tls:750 ]]
    if find "$release" -type l -print -quit | grep -q .; then
        return 1
    fi
    mapfile -t actual_files < <(
        find "$release" -type f -printf '%P\n' | sort
    )
    [[ "${actual_files[*]}" == "${expected_release_files[*]}" ]]

    for relative_path in \
        Caddyfile \
        conf.d/00-health.caddy \
        conf.d/10-pihole-admin.caddy \
        conf.d/90-default-deny.caddy \
        tls/certificate-manifest.json \
        tls/fullchain.pem \
        tls/intermediates.pem \
        tls/leaf.pem; do
        [[ "$(stat -c '%U:%G:%a' "$release/$relative_path")" == root:root:644 ]]
    done
    [[ "$(stat -c '%U:%G:%a' "$release/tls/privkey.pem")" == root:caddy-tls:640 ]]
    [[ "$(stat -c '%U:%G:%a' "$environment_file")" == root:caddy-tls:640 ]]
    [[ -L "$current_link" ]]
    [[ "$(stat -c '%U:%G:%a' "$current_link")" == root:root:777 ]]
    [[ "$(readlink "$current_link")" == "$release" ]]
    [[ "$(readlink -e "$current_link")" == "$release" ]]

    [[ "$(sha256sum "$release/Caddyfile" |
        awk '{ print $1 }')" == a41c7816e927c16278fab018675a3f2db5b2aae89dd5b181f1ecb06ec9beb86e ]]
    [[ "$(sha256sum "$release/conf.d/00-health.caddy" |
        awk '{ print $1 }')" == 05fa1d2875ee0639601447ccd31284d3df55fc8d5e8cedef4a291c61d44f4b27 ]]
    [[ "$(sha256sum "$release/conf.d/10-pihole-admin.caddy" |
        awk '{ print $1 }')" == 5621134920da9dde97122fe9968a2debdd0c980ac0e432323fb46e0c1139798c ]]
    [[ "$(sha256sum "$release/conf.d/90-default-deny.caddy" |
        awk '{ print $1 }')" == 9ce8430d11882f4e2008ff27f4f4a2fcad568f81081629289f64ad2450316b27 ]]
    [[ "$(sha256sum "$environment_file" |
        awk '{ print $1 }')" == "$environment_sha256" ]]

    cmp --silent \
        "$certificate_stage/leaf.pem" \
        "$release/tls/leaf.pem"
    cmp --silent \
        "$certificate_stage/intermediates.pem" \
        "$release/tls/intermediates.pem"
    cmp --silent \
        "$certificate_stage/fullchain.pem" \
        "$release/tls/fullchain.pem"
    cmp --silent \
        "$certificate_stage/privkey.pem" \
        "$release/tls/privkey.pem"
    cmp --silent \
        "$certificate_stage/certificate-manifest.json" \
        "$release/tls/certificate-manifest.json"

    grep -Fxq 'NODE_ROLE=node-a' "$environment_file"
    grep -Fxq 'NODE_FQDN=pihole0.local.theama.co' "$environment_file"
    grep -Fxq 'NODE_IPV4=10.1.0.53' "$environment_file"
    grep -Fxq 'NODE_IPV6=fd36:5aa8:6971:1::53' "$environment_file"
    grep -Fxq 'PEER_ROLE=node-b' "$environment_file"
    grep -Fxq 'PEER_IPV4=10.1.0.54' "$environment_file"
    grep -Fxq 'PEER_IPV6=fd36:5aa8:6971:1::54' "$environment_file"
    grep -Fxq 'CADDY_PRIORITY=140' "$environment_file"
    grep -Fxq 'NETWORK_INTERFACE=eth0' "$environment_file"
    grep -Fxq 'SYNC_TARGET=pihole00.local.theama.co' "$environment_file"
    [[ "$(wc -l <"$environment_file")" -eq 10 ]]
}

capture_dir=
state_before=
mutation_started=false
transaction_complete=false
rollback() {
    local original_rc=$?
    local rollback_failed=false

    trap - EXIT
    if [[ "$transaction_complete" == true ]]; then
        exit "$original_rc"
    fi
    set +e
    printf 'action_16ah_rollback_started=true\n' >&2

    if [[ "$mutation_started" == true ]]; then
        if [[ -e "$current_link" || -L "$current_link" ]]; then
            if [[ -L "$current_link" || -f "$current_link" ]]; then
                rm -f -- "$current_link" || rollback_failed=true
            else
                rollback_failed=true
            fi
        fi
        if [[ -e "$environment_file" || -L "$environment_file" ]]; then
            if [[ -f "$environment_file" || -L "$environment_file" ]]; then
                rm -f -- "$environment_file" || rollback_failed=true
            else
                rollback_failed=true
            fi
        fi
        if [[ -e "$release" || -L "$release" ]]; then
            rm -rf --one-file-system -- "$release" ||
                rollback_failed=true
        fi
    fi

    if [[ -n "$capture_dir" ]]; then
        case "$capture_dir" in
            /tmp/caddy-action16ah.*)
                rm -rf --one-file-system -- "$capture_dir" ||
                    rollback_failed=true
                ;;
            *)
                rollback_failed=true
                ;;
        esac
    fi

    validate_targets_absent || rollback_failed=true
    [[ -z "$(temporary_paths)" ]] || rollback_failed=true
    if [[ -n "$state_before" ]]; then
        validate_common_state || rollback_failed=true
        [[ "$(protected_state)" == "$state_before" ]] ||
            rollback_failed=true
    fi

    if [[ "$rollback_failed" == true ]]; then
        printf 'action_16ah_rollback_complete=false\n' >&2
        printf 'manual_intervention_required=true\n' >&2
        exit 97
    fi
    printf 'action_16ah_rollback_complete=true\n' >&2
    exit "$original_rc"
}

if [[ "${1:-}" == --self-test ]]; then
    [[ "${#expected_source_checksums[@]}" -eq 12 ]]
    [[ "${#expected_release_files[@]}" -eq 9 ]]
    [[ "$release" == /etc/caddy/releases/bootstrap ]]
    [[ "$current_link" == /etc/caddy/current ]]
    [[ "$environment_file" == /etc/default/caddy-ha ]]
    self_test_dir=$(mktemp -d /tmp/caddy-action16ah-selftest.XXXXXX)
    trap 'rm -rf --one-file-system -- "$self_test_dir"' EXIT
    printf '%s\n' \
        '{"node":"node-a","component":"caddy","root":"/","dry_run":false,"changes":14,"service_mutations":false}' \
        >"$self_test_dir/install.json"
    printf '%s\n' \
        '{"node":"node-a","component":"caddy","root":"/","dry_run":true,"changes":0,"service_mutations":false}' \
        >"$self_test_dir/idempotent.json"
    validate_installer_json "$self_test_dir/install.json" 14 false
    validate_installer_json "$self_test_dir/idempotent.json" 0 true
    rm -rf --one-file-system -- "$self_test_dir"
    trap - EXIT
    printf 'action_16ah_caddy_install_self_test_complete=true\n'
    exit 0
elif (($#)); then
    printf 'Usage: %s [--self-test]\n' "${0##*/}" >&2
    exit 2
fi

[[ "$(id -u)" -eq 0 ]]
validate_common_state
validate_targets_absent
[[ -z "$(temporary_paths)" ]]
state_before=$(protected_state)

trap rollback EXIT
capture_dir=$(mktemp -d /tmp/caddy-action16ah.XXXXXX)
chown root:caddy "$capture_dir"
chmod 0710 "$capture_dir"
install -d -o caddy -g caddy -m 0700 \
    "$capture_dir/caddy-home" \
    "$capture_dir/caddy-config" \
    "$capture_dir/caddy-data"
install -d -o root -g root -m 0700 \
    "$capture_dir/installer-tmp" \
    "$capture_dir/idempotency-tmp"
readonly install_stdout="$capture_dir/install.json"
readonly install_stderr="$capture_dir/install.stderr"
readonly idempotent_stdout="$capture_dir/idempotent.json"
readonly idempotent_stderr="$capture_dir/idempotent.stderr"
readonly formatted_caddyfile="$capture_dir/Caddyfile.formatted"
readonly adapted_json="$capture_dir/caddy-adapted.json"
readonly adapt_stderr="$capture_dir/caddy-adapt.stderr"
readonly validate_stdout="$capture_dir/caddy-validate.stdout"
readonly validate_stderr="$capture_dir/caddy-validate.stderr"

mutation_started=true
TMPDIR="$capture_dir/installer-tmp" "$installer" \
    --node node-a \
    --component caddy \
    --manifest "$manifest" \
    --certificate-dir "$certificate_stage" \
    >"$install_stdout" \
    2>"$install_stderr"

validate_installer_json "$install_stdout" 14 false
[[ ! -s "$install_stderr" ]]
validate_installed_targets

runuser -u caddy -- \
    env \
    HOME="$capture_dir/caddy-home" \
    XDG_CONFIG_HOME="$capture_dir/caddy-config" \
    XDG_DATA_HOME="$capture_dir/caddy-data" \
    CADDY_CONFIG_ROOT="$release" \
    NODE_FQDN=pihole0.local.theama.co \
    NODE_IPV4=10.1.0.53 \
    NODE_IPV6=fd36:5aa8:6971:1::53 \
    /usr/bin/caddy fmt "$release/Caddyfile" \
    >"$formatted_caddyfile"
cmp --silent "$release/Caddyfile" "$formatted_caddyfile"

runuser -u caddy -- \
    env \
    HOME="$capture_dir/caddy-home" \
    XDG_CONFIG_HOME="$capture_dir/caddy-config" \
    XDG_DATA_HOME="$capture_dir/caddy-data" \
    CADDY_CONFIG_ROOT="$release" \
    NODE_FQDN=pihole0.local.theama.co \
    NODE_IPV4=10.1.0.53 \
    NODE_IPV6=fd36:5aa8:6971:1::53 \
    /usr/bin/caddy adapt \
    --config "$release/Caddyfile" \
    --adapter caddyfile \
    >"$adapted_json" \
    2>"$adapt_stderr"
jq empty "$adapted_json"

runuser -u caddy -- \
    env \
    HOME="$capture_dir/caddy-home" \
    XDG_CONFIG_HOME="$capture_dir/caddy-config" \
    XDG_DATA_HOME="$capture_dir/caddy-data" \
    CADDY_CONFIG_ROOT="$release" \
    NODE_FQDN=pihole0.local.theama.co \
    NODE_IPV4=10.1.0.53 \
    NODE_IPV6=fd36:5aa8:6971:1::53 \
    /usr/bin/caddy validate \
    --config "$release/Caddyfile" \
    --adapter caddyfile \
    >"$validate_stdout" \
    2>"$validate_stderr"

TMPDIR="$capture_dir/idempotency-tmp" "$installer" \
    --node node-a \
    --component caddy \
    --manifest "$manifest" \
    --certificate-dir "$certificate_stage" \
    --dry-run \
    >"$idempotent_stdout" \
    2>"$idempotent_stderr"
validate_installer_json "$idempotent_stdout" 0 true
[[ ! -s "$idempotent_stderr" ]]
validate_installed_targets

rm -rf --one-file-system -- "$capture_dir"
capture_dir=
[[ -z "$(temporary_paths)" ]]
validate_common_state
[[ "$(protected_state)" == "$state_before" ]]

printf 'installer_node=node-a\n'
printf 'installer_component=caddy\n'
printf 'installer_initial_changes=14\n'
printf 'installer_idempotent_changes=0\n'
printf 'installer_service_mutations=false\n'
printf 'caddy_format_valid=true\n'
printf 'caddy_adapt_valid=true\n'
printf 'caddy_validate_as_user=caddy\n'
printf 'installed_certificate_matches_stage=true\n'
printf 'source_stage_unchanged=true\n'
printf 'certificate_stage_unchanged=true\n'
printf 'protected_state_unchanged=true\n'
printf 'action_16ah_caddy_install_complete=true\n'
transaction_complete=true
