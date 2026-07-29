#!/usr/bin/env bash

set -euo pipefail

packages=(
    bash
    coreutils
    findutils
    iproute2
    iputils-arping
    jq
    ndisc6
    openssl
    procps
    tcpdump
    util-linux
    uuid-runtime
)

package_inventory() {
    dpkg-query -W \
        -f='${binary:Package}\t${db:Status-Abbrev}\t${Version}\n' |
        sort
}

protected_service_state() {
    for service in \
        lighttpd.service keepalived.service ssh.service unbound.service \
        pihole-FTL.service munin-node.service; do
        printf '### %s\n' "$service"
        systemctl show "$service" --no-pager \
            -p ActiveState -p SubState -p MainPID -p NRestarts
    done
}

classify_verification_output() {
    local verify_output=$1
    local line

    verification_conffile_lines=()
    verification_payload_lines=()
    while IFS= read -r line; do
        [[ -n "$line" ]] || continue
        if [[ "$line" =~ ^.{9}[[:space:]]c[[:space:]] ]]; then
            verification_conffile_lines+=("$line")
        else
            verification_payload_lines+=("$line")
        fi
    done <<<"$verify_output"

    verification_conffile_output=
    if ((${#verification_conffile_lines[@]})); then
        printf -v verification_conffile_output '%s\n' \
            "${verification_conffile_lines[@]}"
        verification_conffile_output=${verification_conffile_output%$'\n'}
    fi

    verification_payload_output=
    if ((${#verification_payload_lines[@]})); then
        printf -v verification_payload_output '%s\n' \
            "${verification_payload_lines[@]}"
        verification_payload_output=${verification_payload_output%$'\n'}
    fi
}

expected_conffile_output_for_package() {
    local package=$1

    case "$package" in
        bash)
            printf '%s' '??5?????? c /etc/skel/.bashrc'
            ;;
        procps)
            printf '%s' '??5?????? c /etc/sysctl.conf'
            ;;
        *)
            printf '%s' ''
            ;;
    esac
}

verification_output_allowed() {
    local package=$1
    local verify_output=$2
    local expected_conffile_output

    expected_conffile_output=$(
        expected_conffile_output_for_package "$package"
    )
    classify_verification_output "$verify_output"

    [[ -z "$verification_payload_output" &&
        "$verification_conffile_output" == "$expected_conffile_output" ]]
}

assert_package() {
    local package=$1
    local expected_version=$2
    local status
    local status_rc
    local version
    local version_rc
    local architecture
    local architecture_rc
    local verify_output
    local verify_rc
    local status_match=false
    local version_match=false
    local architecture_match=false
    local verification_match=false
    local verification_policy=clean

    set +e
    status=$(dpkg-query -W -f='${db:Status-Abbrev}' "$package" 2>&1)
    status_rc=$?
    version=$(dpkg-query -W -f='${Version}' "$package" 2>&1)
    version_rc=$?
    architecture=$(dpkg-query -W -f='${Architecture}' "$package" 2>&1)
    architecture_rc=$?
    verify_output=$(dpkg --verify "$package" 2>&1)
    verify_rc=$?
    set -e

    if [[ "$status_rc" -eq 0 && "$status" == 'ii ' ]]; then
        status_match=true
    fi
    if [[ "$version_rc" -eq 0 && "$version" == "$expected_version" ]]; then
        version_match=true
    fi
    if [[ "$architecture_rc" -eq 0 && "$architecture" == arm64 ]]; then
        architecture_match=true
    fi
    if [[ "$package" == bash || "$package" == procps ]]; then
        verification_policy=pinned-conffile-difference
    fi
    if [[ "$verify_rc" -eq 0 ]] &&
        verification_output_allowed "$package" "$verify_output"; then
        verification_match=true
    else
        classify_verification_output "$verify_output"
    fi

    printf '%s\n' "--- package validation: $package ---"
    printf 'expected_status=%q\n' 'ii '
    printf 'observed_status=%q\n' "$status"
    printf 'status_query_rc=%s\n' "$status_rc"
    printf 'status_match=%s\n' "$status_match"
    printf 'expected_version=%s\n' "$expected_version"
    printf 'observed_version=%q\n' "$version"
    printf 'version_query_rc=%s\n' "$version_rc"
    printf 'version_match=%s\n' "$version_match"
    printf 'expected_architecture=arm64\n'
    printf 'observed_architecture=%q\n' "$architecture"
    printf 'architecture_query_rc=%s\n' "$architecture_rc"
    printf 'architecture_match=%s\n' "$architecture_match"
    printf 'dpkg_verify_rc=%s\n' "$verify_rc"
    printf 'verification_policy=%s\n' "$verification_policy"
    printf 'verification_match=%s\n' "$verification_match"
    printf 'conffile_verification_output=%q\n' \
        "$verification_conffile_output"
    printf 'payload_verification_output=%q\n' \
        "$verification_payload_output"

    [[ "$status_match" == true ]]
    [[ "$version_match" == true ]]
    [[ "$architecture_match" == true ]]
    [[ "$verification_match" == true ]]
}

assert_conffile() {
    local path=$1
    local expected_state=$2
    local expected_sha=$3
    local observed_state
    local observed_sha

    [[ -f "$path" && ! -L "$path" ]]
    observed_state=$(stat -c '%F %U:%G %a %s' -- "$path")
    observed_sha=$(sha256sum -- "$path" | awk '{ print $1 }')
    printf '%s\n' "--- pinned conffile: $path ---"
    printf 'expected_state=%q\n' "$expected_state"
    printf 'observed_state=%q\n' "$observed_state"
    printf 'expected_sha256=%s\n' "$expected_sha"
    printf 'observed_sha256=%s\n' "$observed_sha"
    [[ "$observed_state" == "$expected_state" ]]
    [[ "$observed_sha" == "$expected_sha" ]]
}

conffile_state() {
    local path=$1

    stat -c '%F %U:%G %a %s' -- "$path"
    sha256sum -- "$path"
}

ip_file_list_entries() {
    local package_files=$1

    awk '$0 ~ /(^|\/)ip$/ { print }' <<<"$package_files"
}

ip_command_chain_state() {
    local package_binary_name
    local package_control_anchor
    local package_info_dir
    local package_list_path
    local package_files

    package_binary_name=$(dpkg-query -W -f='${binary:Package}' iproute2)
    package_control_anchor=$(
        dpkg-query --control-path iproute2 md5sums
    )
    package_info_dir=$(dirname -- "$package_control_anchor")
    package_list_path="$package_info_dir/$package_binary_name.list"
    package_files=$(dpkg-query -L iproute2)

    printf 'front_link=%s\n' "$(readlink -- /usr/sbin/ip)"
    printf 'canonical_target=%s\n' "$(readlink -e -- /bin/ip)"
    printf 'front_lstat=%s\n' \
        "$(stat -c '%F %U:%G %a %s' -- /usr/sbin/ip)"
    printf 'raw_state=%s\n' \
        "$(stat -L -c '%F %U:%G %a %s %d:%i' -- /bin/ip)"
    printf 'canonical_state=%s\n' \
        "$(stat -c '%F %U:%G %a %s %d:%i' -- /usr/bin/ip)"
    printf 'raw_sha256=%s\n' \
        "$(sha256sum -- /bin/ip | awk '{ print $1 }')"
    printf 'canonical_sha256=%s\n' \
        "$(sha256sum -- /usr/bin/ip | awk '{ print $1 }')"
    printf 'raw_owner=%s\n' "$(dpkg-query --search /bin/ip)"
    printf 'package_binary_name=%s\n' "$package_binary_name"
    printf 'package_control_anchor=%s\n' "$package_control_anchor"
    printf 'package_list_path=%s\n' "$package_list_path"
    printf 'package_list_state=%s\n' \
        "$(stat -c '%F %U:%G %a %s' -- "$package_list_path")"
    printf 'package_list_sha256=%s\n' \
        "$(sha256sum -- "$package_list_path" | awk '{ print $1 }')"
    printf 'relevant_file_entries=%q\n' \
        "$(ip_file_list_entries "$package_files")"
}

ip_command_chain_allowed() {
    local observed_state=$1
    local relevant_entries=$2

    grep -Fxq 'front_link=/bin/ip' <<<"$observed_state" &&
        grep -Fxq 'canonical_target=/usr/bin/ip' <<<"$observed_state" &&
        grep -Fxq \
            'front_lstat=symbolic link root:root 777 7' \
            <<<"$observed_state" &&
        grep -Fxq \
            'raw_state=regular file root:root 755 746760 66306:1995' \
            <<<"$observed_state" &&
        grep -Fxq \
            'canonical_state=regular file root:root 755 746760 66306:1995' \
            <<<"$observed_state" &&
        grep -Fxq \
            'raw_sha256=2c9d712b497ee2d6c436da1dd09fb88f3a7ff535bbece9bab0e9a03c5e6cb835' \
            <<<"$observed_state" &&
        grep -Fxq \
            'canonical_sha256=2c9d712b497ee2d6c436da1dd09fb88f3a7ff535bbece9bab0e9a03c5e6cb835' \
            <<<"$observed_state" &&
        grep -Fxq 'raw_owner=iproute2: /bin/ip' <<<"$observed_state" &&
        grep -Fxq 'package_binary_name=iproute2' <<<"$observed_state" &&
        grep -Fxq \
            'package_control_anchor=/var/lib/dpkg/info/iproute2.md5sums' \
            <<<"$observed_state" &&
        grep -Fxq \
            'package_list_path=/var/lib/dpkg/info/iproute2.list' \
            <<<"$observed_state" &&
        grep -Fxq \
            'package_list_state=regular file root:root 644 6170' \
            <<<"$observed_state" &&
        grep -Fxq \
            'package_list_sha256=72b1b6ce7f4f4ee3b27897116329ea119de664a71a2f642fd326e889cfac471b' \
            <<<"$observed_state" &&
        [[ "$relevant_entries" == $'/bin/ip\n/sbin/ip' ]]
}

assert_ip_command_chain() {
    local observed_state
    local relevant_entries

    observed_state=$(ip_command_chain_state)
    relevant_entries=$(
        ip_file_list_entries "$(dpkg-query -L iproute2)"
    )
    printf '%s\n' '--- pinned ip command chain ---'
    printf '%s\n' "$observed_state"
    ip_command_chain_allowed "$observed_state" "$relevant_entries"
}

assert_masked_inactive() {
    local unit=$1

    [[ "$(systemctl is-active "$unit" 2>/dev/null || true)" == inactive ]]
    [[ "$(systemctl is-enabled "$unit" 2>/dev/null || true)" == masked ]]
}

self_test() {
    local candidate
    local found
    local package
    local valid_ip_state

    verification_output_allowed \
        bash '??5?????? c /etc/skel/.bashrc'
    [[ "$verification_conffile_output" == '??5?????? c /etc/skel/.bashrc' ]]
    [[ -z "$verification_payload_output" ]]

    verification_output_allowed \
        procps '??5?????? c /etc/sysctl.conf'
    [[ "$verification_conffile_output" == '??5?????? c /etc/sysctl.conf' ]]
    [[ -z "$verification_payload_output" ]]

    for package in iputils-arping util-linux uuid-runtime; do
        found=false
        for candidate in "${packages[@]}"; do
            if [[ "$candidate" == "$package" ]]; then
                found=true
            fi
        done
        [[ "$found" == true ]]
        verification_output_allowed "$package" ''
        [[ -z "$verification_conffile_output" ]]
        [[ -z "$verification_payload_output" ]]
    done

    if verification_output_allowed \
        bash $'??5?????? c /etc/skel/.bashrc\n??5?????? c /etc/extra'; then
        printf 'Additional conffile difference was accepted.\n' >&2
        return 1
    fi
    if verification_output_allowed \
        procps '??5?????? c /etc/unexpected'; then
        printf 'Unexpected procps conffile difference was accepted.\n' >&2
        return 1
    fi
    if verification_output_allowed \
        jq '??5??????   /usr/bin/jq'; then
        printf 'Package payload difference was accepted.\n' >&2
        return 1
    fi

    sample_files=$'/bin/ip\n/sbin/ip\n/usr/share/doc/iproute2'
    [[ "$(ip_file_list_entries "$sample_files")" == $'/bin/ip\n/sbin/ip' ]]
    valid_ip_state=$(
        printf '%s\n' \
            'front_link=/bin/ip' \
            'canonical_target=/usr/bin/ip' \
            'front_lstat=symbolic link root:root 777 7' \
            'raw_state=regular file root:root 755 746760 66306:1995' \
            'canonical_state=regular file root:root 755 746760 66306:1995' \
            'raw_sha256=2c9d712b497ee2d6c436da1dd09fb88f3a7ff535bbece9bab0e9a03c5e6cb835' \
            'canonical_sha256=2c9d712b497ee2d6c436da1dd09fb88f3a7ff535bbece9bab0e9a03c5e6cb835' \
            'raw_owner=iproute2: /bin/ip' \
            'package_binary_name=iproute2' \
            'package_control_anchor=/var/lib/dpkg/info/iproute2.md5sums' \
            'package_list_path=/var/lib/dpkg/info/iproute2.list' \
            'package_list_state=regular file root:root 644 6170' \
            'package_list_sha256=72b1b6ce7f4f4ee3b27897116329ea119de664a71a2f642fd326e889cfac471b'
    )
    ip_command_chain_allowed "$valid_ip_state" $'/bin/ip\n/sbin/ip'
    if ip_command_chain_allowed \
        "${valid_ip_state/front_link=\/bin\/ip/front_link=\/tmp\/ip}" \
        $'/bin/ip\n/sbin/ip'; then
        printf 'Unexpected ip link target was accepted.\n' >&2
        return 1
    fi
    if ip_command_chain_allowed \
        "${valid_ip_state/raw_owner=iproute2: /raw_owner=other: }" \
        $'/bin/ip\n/sbin/ip'; then
        printf 'Unexpected ip package owner was accepted.\n' >&2
        return 1
    fi
    if ip_command_chain_allowed "$valid_ip_state" '/usr/bin/ip'; then
        printf 'Unexpected iproute2 file list was accepted.\n' >&2
        return 1
    fi
    printf 'action_16x_retry3_self_test_complete=true\n'
}

if [[ "${1:-}" == --self-test ]]; then
    [[ "$#" -eq 1 ]]
    self_test
    exit 0
elif (($#)); then
    printf 'Usage: %s [--self-test]\n' "${0##*/}" >&2
    exit 2
fi

[[ "$(hostname)" == j1-svpihole0 ]]
ipv4_state=$(ip -o -4 address show dev eth0)
grep -Fq '10.1.0.53/22' <<<"$ipv4_state"
[[ "$(dpkg --print-architecture)" == arm64 ]]

inventory_before=$(package_inventory)
services_before=$(protected_service_state)
listeners_before=$(ss -H -lntup | sort)
[[ -z "$(dpkg --audit)" ]]

assert_conffile \
    /etc/skel/.bashrc \
    'regular file root:root 644 3523' \
    16d4851cb36ab8003eb45e2a8ab12ef971db898e42513f8bb826482ccd97c77d
assert_conffile \
    /etc/sysctl.conf \
    'regular file root:root 644 2348' \
    f5f0f57fffcca760b5aa56b008c44c0ac8f3cc2a868e9831777e92a5614aa08d
bashrc_state_before=$(conffile_state /etc/skel/.bashrc)
sysctl_state_before=$(conffile_state /etc/sysctl.conf)
ip_chain_state_before=$(ip_command_chain_state)
assert_ip_command_chain

simulation=$(
    LC_ALL=C apt-get -s install --no-install-recommends \
        "${packages[@]}" 2>&1
)
printf '%s\n' '--- validation/scripting convergence simulation ---'
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

assert_package bash '5.2.15-2+b13'
assert_package coreutils '9.1-1'
assert_package findutils '4.9.0-4'
assert_package iproute2 '6.1.0-3'
assert_package iputils-arping '3:20221126-1+deb12u1'
assert_package jq '1.6-2.1+deb12u2'
assert_package ndisc6 '1.0.5-1+b2'
assert_package openssl '3.0.20-1~deb12u2+rpt1'
assert_package procps '2:4.0.2-3'
assert_package tcpdump '4.99.3-1'
assert_package util-linux '2.38.1-5+deb12u3'
assert_package uuid-runtime '2.38.1-5+deb12u3'

bash_version=$(/usr/bin/bash --version)
sha256sum_version=$(/usr/bin/sha256sum --version)
# shellcheck disable=SC2185 # GNU find accepts --version without a path.
find_version=$(/usr/bin/find --version)
ip_version=$(/usr/sbin/ip -Version)
arping_version=$(/usr/bin/arping -V 2>&1)
jq_version=$(/usr/bin/jq --version)
openssl_version=$(/usr/bin/openssl version)
ps_version=$(/usr/bin/ps --version)
tcpdump_version=$(/usr/bin/tcpdump --version 2>&1)
uuidgen_version=$(/usr/bin/uuidgen --version)

grep -Fq 'GNU bash, version 5.2.15' <<<"$bash_version"
grep -Fq 'sha256sum (GNU coreutils) 9.1' <<<"$sha256sum_version"
grep -Fq 'find (GNU findutils) 4.9.0' <<<"$find_version"
grep -Fq 'iproute2-6.1.0' <<<"$ip_version"
grep -Fq 'arping from iputils 20221126' <<<"$arping_version"
[[ "$jq_version" == jq-1.6 ]]
[[ "$openssl_version" == 'OpenSSL 3.0.20 '* ]]
grep -Fq 'ps from procps-ng 4.0.2' <<<"$ps_version"
grep -Fq 'tcpdump version 4.99.3' <<<"$tcpdump_version"
[[ "$uuidgen_version" == 'uuidgen from util-linux 2.38.1' ]]

for command_path in \
    /usr/bin/bash \
    /usr/bin/sha256sum \
    /usr/bin/find \
    /usr/bin/arping \
    /usr/bin/jq \
    /usr/bin/ndisc6 \
    /usr/bin/openssl \
    /usr/bin/ps \
    /usr/bin/tcpdump \
    /usr/bin/uuidgen \
    /usr/bin/uuidparse \
    /usr/sbin/uuidd; do
    [[ -x "$command_path" && ! -L "$command_path" ]]
done

manual_packages=$(apt-mark showmanual)
grep -Fxq uuid-runtime <<<"$manual_packages"

uuidd_passwd=$(getent passwd uuidd)
uuidd_group=$(getent group uuidd)
[[ -n "$uuidd_passwd" && -n "$uuidd_group" ]]
[[ "$(cut -d: -f1 <<<"$uuidd_passwd")" == uuidd ]]
[[ "$(cut -d: -f3 <<<"$uuidd_passwd")" == 109 ]]
[[ "$(cut -d: -f4 <<<"$uuidd_passwd")" == 115 ]]
[[ "$(cut -d: -f6 <<<"$uuidd_passwd")" == /run/uuidd ]]
[[ "$(cut -d: -f1 <<<"$uuidd_group")" == uuidd ]]
[[ "$(cut -d: -f3 <<<"$uuidd_group")" == 115 ]]
uuidd_password_state=$(passwd -S uuidd)
[[ "$(awk '{ print $2 }' <<<"$uuidd_password_state")" == L ]]
[[ "$(stat -c '%U:%G %a' /var/lib/libuuid)" == 'uuidd:uuidd 2775' ]]

printf '%s  %s\n' \
    4b93a446c6094a1ea265699d794171f358ea611d974eae6f728652c81e3df6ad \
    /etc/init.d/uuidd |
    sha256sum --check --status
printf '%s  %s\n' \
    a8090eeb6f09b0e895c97e2f27f9c656b27c269d3755f8da26e7f85f3aaaa4b9 \
    /lib/systemd/system/uuidd.service |
    sha256sum --check --status
printf '%s  %s\n' \
    21f7cc7b5ffaf73b27f00689e628797a2be947df144b1a0f7ba9356c8d0a4897 \
    /lib/systemd/system/uuidd.socket |
    sha256sum --check --status

assert_masked_inactive uuidd.service
assert_masked_inactive uuidd.socket
if pgrep -x uuidd >/dev/null; then
    printf 'Unexpected uuidd process during convergence validation.\n' >&2
    exit 1
fi
mapfile -t uuidd_start_links < <(
    find /etc -maxdepth 2 -type l \
        -path '/etc/rc*.d/S*uuidd' -print |
        sort
)
[[ "${#uuidd_start_links[@]}" -eq 0 ]]
mapfile -t uuidd_kill_links < <(
    find /etc -maxdepth 2 -type l \
        -path '/etc/rc*.d/K*uuidd' -print |
        sort
)
[[ "${#uuidd_kill_links[@]}" -gt 0 ]]

[[ ! -e /usr/sbin/policy-rc.d && ! -L /usr/sbin/policy-rc.d ]]
mapfile -t staging < <(
    find /tmp -mindepth 1 -maxdepth 1 \
        -name 'uuid-runtime-*' -print |
        sort
)
[[ "${#staging[@]}" -eq 0 ]]

[[ "$(dpkg-query -W -f='${db:Status-Abbrev}' caddy)" == 'ii ' ]]
[[ "$(dpkg-query -W -f='${Version}' caddy)" == 2.11.4 ]]
[[ "$(dpkg-query -W -f='${db:Status-Abbrev}' lsyncd)" == 'ii ' ]]
[[ "$(dpkg-query -W -f='${Version}' lsyncd)" == 2.2.3-1 ]]
for unit in caddy.service caddy-api.service lsyncd.service; do
    assert_masked_inactive "$unit"
done
if pgrep -x caddy >/dev/null ||
    pgrep -x lsyncd >/dev/null; then
    printf 'Unexpected Caddy or lsyncd process during validation.\n' >&2
    exit 1
fi

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
done

tcp_frontend=$(
    ss -H -ltnp |
        awk '$4 ~ /:80$|:443$/ { print }' |
        sort
)
[[ -n "$tcp_frontend" ]]
if grep -Fv 'users:(("lighttpd"' <<<"$tcp_frontend"; then
    printf 'A non-lighttpd process owns TCP 80 or 443.\n' >&2
    exit 1
fi
grep -Eq '[[:space:]][^[:space:]]*:80[[:space:]]' <<<"$tcp_frontend"
grep -Eq '[[:space:]][^[:space:]]*:443[[:space:]]' <<<"$tcp_frontend"
[[ -z "$(ss -H -lunp | awk '$4 ~ /:443$/ { print }' | sort)" ]]

[[ "$(package_inventory)" == "$inventory_before" ]]
[[ "$(protected_service_state)" == "$services_before" ]]
[[ "$(ss -H -lntup | sort)" == "$listeners_before" ]]
[[ -z "$(dpkg --audit)" ]]
bashrc_state_after=$(conffile_state /etc/skel/.bashrc)
sysctl_state_after=$(conffile_state /etc/sysctl.conf)
ip_chain_state_after=$(ip_command_chain_state)
[[ "$bashrc_state_after" == "$bashrc_state_before" ]]
[[ "$sysctl_state_after" == "$sysctl_state_before" ]]
[[ "$ip_chain_state_after" == "$ip_chain_state_before" ]]

printf '%s\n' '--- validated command versions ---'
printf '%s\n' \
    "$ip_version" \
    "$arping_version" \
    "$jq_version" \
    "$openssl_version" \
    "$uuidgen_version"
printf 'validated_package_count=%s\n' "${#packages[@]}"
printf 'pinned_conffile_difference_count=2\n'
printf 'unexpected_conffile_difference_count=0\n'
printf 'unexpected_payload_difference_count=0\n'
printf 'uuidd_sysv_kill_link_count=%s\n' "${#uuidd_kill_links[@]}"
printf 'ip_command_chain_valid=true\n'
printf 'validation_dependency_convergence_retry3_valid=true\n'
