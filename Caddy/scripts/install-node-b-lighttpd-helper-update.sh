#!/usr/bin/env bash
set -euo pipefail

readonly stage=/var/tmp/caddy-ha-lighttpd-node-b-action15-retry
readonly candidate=/etc/.lighttpd-caddy-action15-retry
readonly backup=/var/backups/caddy-ha/action15-lighttpd-helper-update-node-b
readonly source_renderer="$stage/scripts/prepare-lighttpd-config.sh"
readonly source_desired="$stage/configs/lighttpd/desired-state.conf"
readonly target_renderer=/usr/local/libexec/prepare-lighttpd-config.sh
readonly target_desired=/usr/local/share/caddy-ha/lighttpd-desired-state.conf
readonly renderer_sha256=ce9a78aa487ce55c6fbba553b238160687852361d81c9b37179e4def8f83166f
readonly desired_sha256=8299970d5bb3793859071cd82f794dbae84955a6af931cf35d1509141f689027
readonly candidate_main_sha256=b712ee21f71a9102ef90d53d07d0a783a1fd848c1fa307d20166029dc14dd248

backup_complete=false
success=false
renderer_preexisting=false
desired_preexisting=false
desired_parent_created=false
old_renderer_sha256=absent
old_desired_sha256=absent

cleanup() {
    local status=$?

    if [[ "$success" != true && "$backup_complete" == true ]]; then
        if [[ "$renderer_preexisting" == true ]]; then
            cp -a -- "$backup/prepare-lighttpd-config.sh" "$target_renderer"
            [[ "$(sha256sum "$target_renderer" | awk '{print $1}')" == "$old_renderer_sha256" ]]
        else
            rm -f -- "$target_renderer"
            [[ ! -e "$target_renderer" ]]
        fi
        if [[ "$desired_preexisting" == true ]]; then
            cp -a -- "$backup/lighttpd-desired-state.conf" "$target_desired"
            [[ "$(sha256sum "$target_desired" | awk '{print $1}')" == "$old_desired_sha256" ]]
        else
            rm -f -- "$target_desired"
            [[ ! -e "$target_desired" ]]
        fi
        if [[ "$desired_parent_created" == true ]]; then
            rmdir -- "${target_desired%/*}"
        fi
        printf 'action_15_helper_update_rollback_complete=true\n' >&2
    fi
    exit "$status"
}
trap cleanup EXIT

tree_hash() {
    local root=$1

    (
        cd "$root"
        find . -type f -print0 |
            sort -z |
            xargs -0 sha256sum
    ) | sha256sum | awk '{print $1}'
}

listener_snapshot() {
    ss -H -lntup |
        awk '$5 ~ /:(80|443|8080|2019)$/ {print}' |
        sort
}

service_snapshot() {
    local unit

    for unit in lighttpd caddy caddy-api lsyncd caddy-lsyncd keepalived; do
        printf '%s=%s/%s\n' \
            "$unit" \
            "$(systemctl is-active "$unit" 2>/dev/null || true)" \
            "$(systemctl is-enabled "$unit" 2>/dev/null || true)"
    done
}

[[ $EUID -eq 0 ]]
[[ ! -e "$backup" ]]
for path in "$source_renderer" "$source_desired"; do
    [[ -f "$path" && ! -L "$path" ]]
done
[[ -d "$candidate" && ! -L "$candidate" ]]
[[ -d "${target_renderer%/*}" && ! -L "${target_renderer%/*}" ]]
[[ -d "${target_desired%/*/*}" && ! -L "${target_desired%/*/*}" ]]
[[ "$(sha256sum "$source_renderer" | awk '{print $1}')" == "$renderer_sha256" ]]
[[ "$(sha256sum "$source_desired" | awk '{print $1}')" == "$desired_sha256" ]]
[[ "$(sha256sum "$candidate/lighttpd.conf" | awk '{print $1}')" == "$candidate_main_sha256" ]]

if [[ -e "$target_renderer" || -L "$target_renderer" ]]; then
    [[ -f "$target_renderer" && ! -L "$target_renderer" ]]
    renderer_preexisting=true
    old_renderer_sha256=$(sha256sum "$target_renderer" | awk '{print $1}')
fi
if [[ -e "$target_desired" || -L "$target_desired" ]]; then
    [[ -f "$target_desired" && ! -L "$target_desired" ]]
    desired_preexisting=true
    old_desired_sha256=$(sha256sum "$target_desired" | awk '{print $1}')
fi
live_tree_before=$(tree_hash /etc/lighttpd)
candidate_tree_before=$(tree_hash "$candidate")
failed_tree_before=$(tree_hash /etc/.lighttpd-caddy-action15.failed)
keepalived_tree_before=$(tree_hash /etc/keepalived)
listeners_before=$(listener_snapshot)
services_before=$(service_snapshot)

[[ "$(systemctl is-active lighttpd)" == active ]]
[[ "$(systemctl is-enabled lighttpd)" == enabled ]]
[[ "$(systemctl is-active caddy 2>/dev/null || true)" == inactive ]]
[[ "$(systemctl is-enabled caddy 2>/dev/null || true)" == masked ]]
[[ "$(systemctl is-active lsyncd 2>/dev/null || true)" == inactive ]]
[[ "$(systemctl is-enabled lsyncd 2>/dev/null || true)" == masked ]]
[[ "$(systemctl is-active keepalived)" == active ]]
[[ "$(systemctl is-enabled keepalived)" == enabled ]]

install -d -o root -g root -m 0750 "$backup"
if [[ "$renderer_preexisting" == true ]]; then
    cp -a -- "$target_renderer" "$backup/prepare-lighttpd-config.sh"
fi
if [[ "$desired_preexisting" == true ]]; then
    cp -a -- "$target_desired" "$backup/lighttpd-desired-state.conf"
fi
printf '%s\n' \
    "renderer_preexisting=$renderer_preexisting" \
    "renderer_sha256=$old_renderer_sha256" \
    "desired_preexisting=$desired_preexisting" \
    "desired_sha256=$old_desired_sha256" \
    >"$backup/PRESTATE"
chmod 0640 "$backup/PRESTATE"
backup_complete=true

if [[ ! -d "${target_desired%/*}" ]]; then
    install -d -o root -g root -m 0755 "${target_desired%/*}"
    desired_parent_created=true
fi
install -o root -g root -m 0755 "$source_renderer" "$target_renderer"
install -o root -g root -m 0644 "$source_desired" "$target_desired"

[[ "$(stat -c '%U:%G:%a' "$target_renderer")" == root:root:755 ]]
[[ "$(stat -c '%U:%G:%a' "$target_desired")" == root:root:644 ]]
[[ "$(sha256sum "$target_renderer" | awk '{print $1}')" == "$renderer_sha256" ]]
[[ "$(sha256sum "$target_desired" | awk '{print $1}')" == "$desired_sha256" ]]
bash -n "$target_renderer"
grep -Fxq 'server.errorlog-use-syslog = "enable"' "$target_desired"
grep -Fxq 'accesslog.use-syslog = "enable"' "$target_desired"

[[ "$(tree_hash /etc/lighttpd)" == "$live_tree_before" ]]
[[ "$(tree_hash "$candidate")" == "$candidate_tree_before" ]]
[[ "$(tree_hash /etc/.lighttpd-caddy-action15.failed)" == "$failed_tree_before" ]]
[[ "$(tree_hash /etc/keepalived)" == "$keepalived_tree_before" ]]
[[ "$(listener_snapshot)" == "$listeners_before" ]]
[[ "$(service_snapshot)" == "$services_before" ]]

printf 'old_renderer_sha256=%s\n' "$old_renderer_sha256"
printf 'old_desired_state_sha256=%s\n' "$old_desired_sha256"
printf 'installed_renderer_sha256=%s\n' "$renderer_sha256"
printf 'installed_desired_state_sha256=%s\n' "$desired_sha256"
printf 'backup_path=%s\n' "$backup"
printf 'action_15_helper_update_complete=true\n'
success=true
