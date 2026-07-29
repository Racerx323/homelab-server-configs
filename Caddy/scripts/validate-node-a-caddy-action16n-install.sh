#!/usr/bin/env bash

set -euo pipefail

expected_version=2.11.4
expected_binary_version='v2.11.4 h1:XKxkMTgNSizEvKG6QHue6cAsFOteU2qA61w2tKkCWi0='
expected_source_sha=b27d8e3f353b8e77214793ab7dfa5111cd502978461c43b4e54e0833ba49e199
expected_keyring_sha=c17cd5298a0bab02fda439fff278d9a55df2120cf9dac790c6ce71930db90b37
expected_package_sha=aeab2e38bf77a0162611a1703a5e16c09475b000d41f7edaa9337734d16642fd
expected_caddy_service_sha=6c271e030644bd36a0c8956885934f16c928f88202bc126f12cde519ef9693ff
expected_caddy_api_service_sha=a794bbf7d890eb9e1231bbad251890f87870815a96e3820b28a71819ba9f9c14
source_target=/etc/apt/sources.list.d/caddy-stable.list
key_target=/usr/share/keyrings/caddy-stable-archive-keyring.gpg
baseline=/var/backups/caddy-ha/predeploy-node-a-20260728T184626Z

[[ "$(hostname)" == j1-svpihole0 ]]
ip -o -4 address show dev eth0 |
    grep -Fq '10.1.0.53/22'
[[ "$(dpkg --print-architecture)" == arm64 ]]
[[ -d "$baseline" && ! -L "$baseline" ]]
(
    cd "$baseline"
    sha256sum --check --status configuration.tar.sha256
    grep -Fxq 'backup_complete=true' backup-manifest.txt
)

[[ -f "$source_target" && ! -L "$source_target" ]]
[[ -f "$key_target" && ! -L "$key_target" ]]
printf '%s  %s\n' "$expected_source_sha" "$source_target" |
    sha256sum --check --status
printf '%s  %s\n' "$expected_keyring_sha" "$key_target" |
    sha256sum --check --status

policy=$(apt-cache policy caddy)
candidate=$(
    awk '/^[[:space:]]*Candidate:/ { print $2; exit }' <<<"$policy"
)
installed=$(
    awk '/^[[:space:]]*Installed:/ { print $2; exit }' <<<"$policy"
)
[[ "$candidate" == "$expected_version" ]]
[[ "$installed" == "$expected_version" ]]
grep -Fq 'https://dl.cloudsmith.io/public/caddy/stable/deb/debian' \
    <<<"$policy"
grep -Fxq 'Architecture: arm64' \
    < <(apt-cache show "caddy=$expected_version")

simulation=$(
    LC_ALL=C apt-get -s install --no-install-recommends \
        "caddy=$expected_version" 2>&1
)
printf '%s\n' "$simulation"
[[ "$(
    awk '$1 == "Inst" { count++ } END { print count + 0 }' <<<"$simulation"
)" -eq 0 ]]
[[ "$(
    awk '$1 == "Conf" { count++ } END { print count + 0 }' <<<"$simulation"
)" -eq 0 ]]
[[ "$(
    awk '$1 == "Remv" { count++ } END { print count + 0 }' <<<"$simulation"
)" -eq 0 ]]
grep -Fxq \
    '0 upgraded, 0 newly installed, 0 to remove and 0 not upgraded.' \
    <<<"$simulation"

[[ "$(dpkg-query -W -f='${db:Status-Abbrev}' caddy)" == 'ii ' ]]
[[ "$(dpkg-query -W -f='${Version}' caddy)" == "$expected_version" ]]
[[ "$(dpkg-query -W -f='${Architecture}' caddy)" == arm64 ]]
manual_packages=$(apt-mark showmanual)
grep -Fxq caddy <<<"$manual_packages"
[[ "$(/usr/bin/caddy version)" == "$expected_binary_version" ]]
[[ -z "$(dpkg --verify caddy)" ]]
[[ -z "$(dpkg --audit)" ]]

printf '%s  %s\n' \
    "$expected_caddy_service_sha" \
    /lib/systemd/system/caddy.service |
    sha256sum --check --status
printf '%s  %s\n' \
    "$expected_caddy_api_service_sha" \
    /lib/systemd/system/caddy-api.service |
    sha256sum --check --status
[[ "$(stat -c '%U:%G:%a' /lib/systemd/system/caddy.service)" == root:root:644 ]]
[[ "$(stat -c '%U:%G:%a' /lib/systemd/system/caddy-api.service)" == root:root:644 ]]

[[ "$(getent passwd caddy | cut -d: -f6)" == /var/lib/caddy ]]
[[ "$(getent passwd caddy | cut -d: -f7)" == /usr/sbin/nologin ]]
getent group caddy >/dev/null
id -nG caddy | tr ' ' '\n' | grep -Fxq www-data
printf 'caddy_identity=%s\n' "$(id caddy)"
[[ "$(stat -c '%U:%G:%a' /etc/caddy)" == root:root:755 ]]
[[ "$(stat -c '%U:%G:%a' /etc/caddy/Caddyfile)" == root:root:644 ]]
[[ "$(stat -c '%U:%G:%a' /var/lib/caddy)" == caddy:caddy:755 ]]
[[ "$(stat -c '%U:%G:%a' /var/log/caddy)" == caddy:caddy:755 ]]

for unit in caddy.service caddy-api.service; do
    [[ -L "/etc/systemd/system/$unit" ]]
    [[ "$(readlink "/etc/systemd/system/$unit")" == /dev/null ]]
    [[ "$(systemctl is-active "$unit" 2>/dev/null || true)" == inactive ]]
    [[ "$(systemctl is-enabled "$unit" 2>/dev/null || true)" == masked ]]
    printf 'caddy_unit_state=%s:inactive:masked\n' "$unit"
done
if pgrep -x caddy >/dev/null; then
    printf 'Unexpected Caddy process after inhibited installation.\n' >&2
    exit 1
fi
[[ ! -e /usr/sbin/policy-rc.d && ! -L /usr/sbin/policy-rc.d ]]

printf '%s  %s\n' \
    568507d5604cb2794106de3de29d1603c3f12c9045bf7fc1ad4342592a1395c1 \
    /etc/lighttpd/lighttpd.conf |
    sha256sum --check --status
printf '%s  %s\n' \
    6da587363054a4db69fb742d23bddde06aec866e11fb7a91bff1a8d75a713f7a \
    /etc/lighttpd/conf-enabled/external.conf |
    sha256sum --check --status
printf '%s  %s\n' \
    cf4858888ae80772f1a50dda7c0ea120ff083eafae33a0ad4ca291d44755c1e2 \
    /etc/keepalived/keepalived.conf |
    sha256sum --check --status

for service in lighttpd keepalived ssh unbound pihole-FTL munin-node; do
    systemctl is-active --quiet "$service"
    printf 'protected_service_active=%s\n' "$service"
done

lighttpd_pid=$(systemctl show --property=MainPID --value lighttpd.service)
[[ "$lighttpd_pid" =~ ^[1-9][0-9]*$ ]]
tcp_frontend=$(
    ss -H -ltnp |
        awk '$4 ~ /:80$|:443$/ { print }' |
        sort
)
printf '%s\n' '--- TCP 80/443 listeners ---'
printf '%s\n' "$tcp_frontend"
[[ -n "$tcp_frontend" ]]
if grep -Fv 'users:(("lighttpd"' <<<"$tcp_frontend"; then
    printf 'A non-lighttpd process owns TCP 80 or 443.\n' >&2
    exit 1
fi
grep -Fq "pid=$lighttpd_pid" <<<"$tcp_frontend"
grep -Eq '[[:space:]][^[:space:]]*:80[[:space:]]' <<<"$tcp_frontend"
grep -Eq '[[:space:]][^[:space:]]*:443[[:space:]]' <<<"$tcp_frontend"
[[ -z "$(
    ss -H -lunp |
        awk '$4 ~ /:443$/ { print }' |
        sort
)" ]]

mapfile -t stage_matches < <(
    find /tmp -mindepth 1 -maxdepth 1 \
        \( -name 'caddy-package-audit-node-a.*' \
        -o -name 'caddy-repo-audit-node-a.*' \
        -o -name 'caddy-repo-install-node-a.*' \
        -o -name 'caddy-metadata-refresh-node-a.*' \
        -o -name 'caddy-inhibited-install-node-a.*' \
        -o -name 'caddy-inhibited-install-retry-node-a.*' \) -print |
        sort
)
if ((${#stage_matches[@]} != 0)); then
    printf 'Unexpected Caddy staging path: %s\n' "${stage_matches[@]}" >&2
    exit 1
fi

cached_package=/var/cache/apt/archives/caddy_2.11.4_arm64.deb
if [[ -e "$cached_package" || -L "$cached_package" ]]; then
    [[ -f "$cached_package" && ! -L "$cached_package" ]]
    [[ "$(stat -c '%U:%G:%a' "$cached_package")" == root:root:644 ]]
    printf '%s  %s\n' "$expected_package_sha" "$cached_package" |
        sha256sum --check --status
    printf 'accepted_caddy_apt_cache_present=true\n'
else
    printf 'accepted_caddy_apt_cache_present=false\n'
fi

printf 'caddy_version=%s\n' "$(/usr/bin/caddy version)"
printf 'caddy_package_convergence_valid=true\n'
