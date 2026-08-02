#!/usr/bin/env bash
set -euo pipefail

usage() {
    printf 'Usage: %s --source-root DIRECTORY --output DIRECTORY\n' \
        "${0##*/}"
}

source_root=
output_dir=
while (($#)); do
    case "$1" in
        --source-root)
            source_root=${2:-}
            shift 2
            ;;
        --output)
            output_dir=${2:-}
            shift 2
            ;;
        -h | --help)
            usage
            exit 0
            ;;
        *)
            usage >&2
            exit 2
            ;;
    esac
done

if [[ ! -d "$source_root" || -z "$output_dir" ||
    ! -f "$source_root/lighttpd.conf" ]]; then
    usage >&2
    exit 2
fi
if [[ -e "$output_dir" ]]; then
    printf 'Output path already exists: %s\n' "$output_dir" >&2
    exit 1
fi

umask 027
install -d -m 0750 "$output_dir"
cp -a -- "$source_root/." "$output_dir/"
# cp -a applies the source directory metadata to the existing destination.
# Reassert the protected staging-root mode after the copy.
chmod 0750 "$output_dir"
main_config="$output_dir/lighttpd.conf"

port_count=$(
    grep -Ec '^[[:space:]]*server\.port[[:space:]]*=' "$main_config" || true
)
if [[ "$port_count" -ne 1 ]]; then
    printf 'Expected exactly one global server.port assignment; found %s.\n' \
        "$port_count" >&2
    exit 1
fi
sed -Ei \
    's|^[[:space:]]*server\.port[[:space:]]*=.*$|server.port = 8080|' \
    "$main_config"

bind_count=$(
    grep -Ec '^[[:space:]]*server\.bind[[:space:]]*=' "$main_config" || true
)
if [[ "$bind_count" -gt 1 ]]; then
    printf 'Expected at most one global server.bind assignment; found %s.\n' \
        "$bind_count" >&2
    exit 1
elif [[ "$bind_count" -eq 1 ]]; then
    sed -Ei \
        's|^[[:space:]]*server\.bind[[:space:]]*=.*$|server.bind = "127.0.0.1"|' \
        "$main_config"
else
    sed -i \
        '/^[[:space:]]*server\.port[[:space:]]*=/a server.bind = "127.0.0.1"' \
        "$main_config"
fi

if grep -Eq \
    '^[[:space:]]*server\.errorlog-use-syslog[[:space:]]*=' \
    "$main_config"; then
    sed -Ei \
        's|^[[:space:]]*server\.errorlog-use-syslog[[:space:]]*=.*$|server.errorlog-use-syslog = "enable"|' \
        "$main_config"
elif grep -Eq '^[[:space:]]*server\.errorlog[[:space:]]*=' "$main_config"; then
    sed -Ei \
        's|^[[:space:]]*server\.errorlog[[:space:]]*=.*$|server.errorlog-use-syslog = "enable"|' \
        "$main_config"
else
    printf '\nserver.errorlog-use-syslog = "enable"\n' >>"$main_config"
fi

if ! grep -R -Eq '"mod_accesslog"' \
    "$main_config" "$output_dir/conf-enabled"; then
    printf '\nserver.modules += ( "mod_accesslog" )\n' >>"$main_config"
fi

if grep -Eq \
    '^[[:space:]]*accesslog\.use-syslog[[:space:]]*=' \
    "$main_config"; then
    sed -Ei \
        's|^[[:space:]]*accesslog\.use-syslog[[:space:]]*=.*$|accesslog.use-syslog = "enable"|' \
        "$main_config"
elif grep -Eq '^[[:space:]]*accesslog\.filename[[:space:]]*=' "$main_config"; then
    sed -Ei \
        's|^[[:space:]]*accesslog\.filename[[:space:]]*=.*$|accesslog.use-syslog = "enable"|' \
        "$main_config"
elif grep -R -Eq \
    '^[[:space:]]*accesslog\.(use-syslog|filename)[[:space:]]*:?[+]?=' \
    "$output_dir/conf-enabled"; then
    :
else
    printf '\naccesslog.use-syslog = "enable"\n' >>"$main_config"
fi

# Debian's helper creates an all-address IPv6 listener.
sed -Ei \
    's|^([[:space:]]*include_shell "/usr/share/lighttpd/use-ipv6\.pl.*)$|# disabled by caddy-ha: \1|' \
    "$main_config"
sed -i \
    "s|include \"/etc/lighttpd/conf-enabled/\\*.conf\"|include \"$output_dir/conf-enabled/*.conf\"|" \
    "$main_config"

disabled_dir="$output_dir/conf-disabled-by-caddy-ha"
install -d -m 0750 "$disabled_dir"
while IFS= read -r -d '' enabled_entry; do
    resolved=$(readlink -f "$enabled_entry")
    if grep -Eq \
        'ssl\.engine[[:space:]]*=[[:space:]]*"enable"|:443' \
        "$resolved"; then
        mv -- "$enabled_entry" "$disabled_dir/${enabled_entry##*/}"
    fi
done < <(
    find "$output_dir/conf-enabled" -maxdepth 1 \
        \( -type f -o -type l \) -print0
)

while IFS= read -r -d '' enabled_config; do
    if grep -Eq \
        '^[[:space:]]*server\.errorlog-use-syslog[[:space:]]*:?[+]?=' \
        "$enabled_config"; then
        sed -Ei \
            's|^[[:space:]]*server\.errorlog-use-syslog[[:space:]]*:?[+]?=.*$|server.errorlog-use-syslog := "enable"|' \
            "$enabled_config"
    fi
    if grep -Eq '^[[:space:]]*server\.errorlog[[:space:]]*:?[+]?=' \
        "$enabled_config"; then
        sed -Ei \
            's|^[[:space:]]*server\.errorlog[[:space:]]*:?[+]?=.*$|server.errorlog-use-syslog := "enable"|' \
            "$enabled_config"
    fi
    if grep -Eq \
        '^[[:space:]]*accesslog\.use-syslog[[:space:]]*:?[+]?=' \
        "$enabled_config"; then
        sed -Ei \
            's|^[[:space:]]*accesslog\.use-syslog[[:space:]]*:?[+]?=.*$|accesslog.use-syslog = "enable"|' \
            "$enabled_config"
    fi
    if grep -Eq '^[[:space:]]*accesslog\.filename[[:space:]]*:?[+]?=' \
        "$enabled_config"; then
        sed -Ei \
            's|^[[:space:]]*accesslog\.filename[[:space:]]*:?[+]?=.*$|accesslog.use-syslog = "enable"|' \
            "$enabled_config"
    fi
done < <(find -L "$output_dir/conf-enabled" -maxdepth 1 -type f -print0)

if grep -R -nE '/dev/(stderr|stdout)' \
    "$output_dir/lighttpd.conf" "$output_dir/conf-enabled"; then
    printf 'A device-backed log target remains in the staged lighttpd tree.\n' >&2
    exit 1
fi

if grep -R -nE \
    '^[[:space:]]*accesslog\.filename[[:space:]]*:?[+]?=' \
    "$output_dir/lighttpd.conf" "$output_dir/conf-enabled"; then
    printf 'A file-backed access-log target remains in the staged tree.\n' >&2
    exit 1
fi

if grep -R -nE \
    'ssl\.engine[[:space:]]*=[[:space:]]*"enable"|:443' \
    "$output_dir/lighttpd.conf" "$output_dir/conf-enabled"; then
    printf 'A network HTTPS listener remains in the staged lighttpd tree.\n' >&2
    exit 1
fi

validation_output=
if ! validation_output=$(lighttpd -tt -f "$main_config" 2>&1); then
    printf '%s\n' "$validation_output" >&2
    exit 1
fi
if grep -Fq 'unknown config-key' <<<"$validation_output"; then
    printf '%s\n' "$validation_output" >&2
    printf 'Staged lighttpd configuration contains an unknown key.\n' >&2
    exit 1
fi
if [[ -n "$validation_output" ]]; then
    printf '%s\n' "$validation_output"
fi
printf 'Prepared and validated staged lighttpd tree at %s\n' "$output_dir"
