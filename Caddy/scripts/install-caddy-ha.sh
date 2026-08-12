#!/usr/bin/env bash
set -euo pipefail

usage() {
    cat <<'EOF'
Usage: install-caddy-ha.sh --node node-a|node-b [OPTIONS]

Options:
  --component NAME       Install one component (default: all)
  --certificate-dir DIR  Prepared certificate directory
  --manifest FILE        Deployment manifest (default: repository manifest)
  --root DIRECTORY       Alternate filesystem root for testing
  --dry-run              Report changes without writing
  -h, --help             Show this help

Components:
  all, identities, directories, caddy, lighttpd, lsyncd, scripts, systemd,
  sysctl, tmpfiles

Keepalived is externally owned by homelab-dns/Keepalived/configs and cannot be
installed by this script.
EOF
}

node_role=
component=all
certificate_dir=
manifest_file=
root_prefix=/
dry_run=false

while (($#)); do
    case "$1" in
        --node)
            node_role=${2:-}
            shift 2
            ;;
        --component)
            component=${2:-}
            shift 2
            ;;
        --certificate-dir)
            certificate_dir=${2:-}
            shift 2
            ;;
        --manifest)
            manifest_file=${2:-}
            shift 2
            ;;
        --root)
            root_prefix=${2:-}
            shift 2
            ;;
        --dry-run)
            dry_run=true
            shift
            ;;
        -h | --help)
            usage
            exit 0
            ;;
        *)
            printf 'Unknown option: %s\n' "$1" >&2
            usage >&2
            exit 2
            ;;
    esac
done

if [[ ! "$node_role" =~ ^node-[ab]$ || "$root_prefix" != /* ]]; then
    usage >&2
    exit 2
fi

case "$component" in
    keepalived)
        printf '%s\n' \
            'Keepalived is externally owned by homelab-dns/Keepalived/configs; installation from Caddy is prohibited.' >&2
        exit 2
        ;;
    munin)
        printf '%s\n' \
            'Munin integration is deferred and cannot be installed by this script.' >&2
        exit 2
        ;;
    all | identities | directories | caddy | lighttpd | lsyncd | \
        scripts | systemd | sysctl | tmpfiles) ;;
    *)
        printf 'Unknown component: %s\n' "$component" >&2
        exit 2
        ;;
esac

if [[ "$root_prefix" == / && "$dry_run" == false && "$EUID" -ne 0 ]]; then
    printf 'Root is required for live filesystem installation.\n' >&2
    exit 1
fi

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
caddy_root=$(cd -- "$script_dir/.." && pwd)
case "$node_role" in
    node-a) lsyncd_source=$caddy_root/configs/lsyncd/caddy-node-a.lua ;;
    node-b) lsyncd_source=$caddy_root/configs/lsyncd/caddy-node-b.lua ;;
esac
readonly lsyncd_source
readonly script_lifecycle=$caddy_root/manifests/script-lifecycle.tsv
readonly systemd_lifecycle=$caddy_root/manifests/systemd-lifecycle.tsv
manifest_file=${manifest_file:-"$caddy_root/manifests/deployment.yaml"}
for required_manifest in \
    "$caddy_root/manifests/dependencies.yaml" \
    "$caddy_root/manifests/dns-records.yaml" \
    "$script_lifecycle" \
    "$systemd_lifecycle" \
    "$manifest_file"; do
    if [[ ! -s "$required_manifest" ]]; then
        printf 'Required manifest is missing or empty: %s\n' \
            "$required_manifest" >&2
        exit 1
    fi
done

validate_install_registry() {
    local install_registry=$1
    local install_source
    local install_lifecycle
    local install_deployable
    local install_target
    local install_mode
    local install_authority

    awk -F '\t' '
        /^[[:space:]]*(#|$)/ { next }
        NF != 6 { exit 1 }
        $2 !~ /^(production-current|historical-action|historical-superseded|workstation-only|rejected|deferred)$/ { exit 1 }
        $3 !~ /^(yes|no)$/ { exit 1 }
        $3 == "yes" && ($2 != "production-current" || $4 !~ /^\// || $5 !~ /^0[0-7][0-7][0-7]$/) { exit 1 }
        $3 == "no" && ($4 != "-" || $5 != "-") { exit 1 }
        seen_source[$1]++ { exit 1 }
        $3 == "yes" && seen_target[$4]++ { exit 1 }
        END { if (length(seen_source) == 0) exit 1 }
    ' "$install_registry" || return 1

    while IFS=$'\t' read -r install_source install_lifecycle \
        install_deployable install_target install_mode install_authority; do
        [[ -n "$install_source" && "$install_source" != \#* ]] || continue
        : "$install_authority"
        [[ "$install_source" == Caddy/* && "$install_source" != *..* ]] || return 1
        [[ -f "$caddy_root/${install_source#Caddy/}" &&
            ! -L "$caddy_root/${install_source#Caddy/}" ]] || return 1
        if [[ "$install_deployable" == yes ]]; then
            [[ -x "$caddy_root/${install_source#Caddy/}" ||
                "$install_mode" == 0644 ]] || return 1
        fi
    done <"$install_registry"
}

validate_install_registry "$script_lifecycle"
validate_install_registry "$systemd_lifecycle"
render_dir=$(mktemp -d "${TMPDIR:-/tmp}/caddy-render.XXXXXX")
trap 'rm -rf -- "$render_dir"' EXIT
"$script_dir/render-node-config.sh" \
    --node "$node_role" \
    --output "$render_dir" \
    --manifest "$manifest_file" \
    >/dev/null

root_path() {
    local path=$1
    if [[ "$root_prefix" == / ]]; then
        printf '%s' "$path"
    else
        printf '%s%s' "${root_prefix%/}" "$path"
    fi
}

timestamp=$(date -u +%Y%m%dT%H%M%SZ)
backup_root=$(root_path "/var/backups/caddy-ha/$timestamp")
changes=0

record() {
    printf '%s\n' "$*" >&2
}

ensure_directory() {
    local destination=$1
    local mode=$2
    local owner=${3:-root}
    local group=${4:-root}
    local normalized_mode=${mode#0}
    local metadata_matches=true
    if [[ "$root_prefix" == / && -d "$destination" ]] &&
        [[ "$(stat -c '%U:%G:%a' "$destination")" != "$owner:$group:$normalized_mode" ]]; then
        metadata_matches=false
    fi
    if [[ -d "$destination" && "$metadata_matches" == true ]]; then
        return
    fi
    changes=$((changes + 1))
    if [[ "$dry_run" == true ]]; then
        record "ENSURE directory $destination owner $owner:$group mode $mode"
    elif [[ "$root_prefix" == / ]]; then
        install -d -o "$owner" -g "$group" -m "$mode" "$destination"
    else
        install -d -m "$mode" "$destination"
    fi
}

install_one() {
    local source_file=$1
    local destination_file=$2
    local mode=$3
    local owner=${4:-root}
    local group=${5:-root}
    local normalized_mode=${mode#0}
    local metadata_matches=true

    if [[ "$root_prefix" == / && -f "$destination_file" ]] &&
        [[ "$(stat -c '%U:%G:%a' "$destination_file")" != "$owner:$group:$normalized_mode" ]]; then
        metadata_matches=false
    fi

    if [[ -f "$destination_file" ]] &&
        cmp --silent "$source_file" "$destination_file" &&
        [[ "$metadata_matches" == true ]]; then
        return
    fi

    changes=$((changes + 1))
    if [[ "$dry_run" == true ]]; then
        record "INSTALL $source_file -> $destination_file owner $owner:$group mode $mode"
        return
    fi

    if [[ ! -d "$(dirname "$destination_file")" ]]; then
        ensure_directory "$(dirname "$destination_file")" 0755
    fi
    if [[ -e "$destination_file" || -L "$destination_file" ]]; then
        if [[ "$root_prefix" == / ]]; then
            backup_path="$backup_root$destination_file"
        else
            backup_path="$backup_root${destination_file#"$root_prefix"}"
        fi
        install -d -m 0700 "$(dirname "$backup_path")"
        cp -a -- "$destination_file" "$backup_path"
    fi
    if [[ "$root_prefix" == / ]]; then
        install -o "$owner" -g "$group" -m "$mode" \
            "$source_file" "$destination_file"
    else
        install -m "$mode" "$source_file" "$destination_file"
    fi
}

install_tree() {
    local source_dir=$1
    local destination_dir=$2
    local mode=$3
    local relative
    while IFS= read -r -d '' source_file; do
        relative=${source_file#"$source_dir/"}
        install_one "$source_file" "$destination_dir/$relative" "$mode"
    done < <(find "$source_dir" -type f -print0)
}

install_registered() {
    local install_registry=$1
    local install_source
    local install_lifecycle
    local install_deployable
    local install_target
    local install_mode
    local install_authority

    while IFS=$'\t' read -r install_source install_lifecycle \
        install_deployable install_target install_mode install_authority; do
        [[ -n "$install_source" && "$install_source" != \#* ]] || continue
        : "$install_authority"
        [[ "$install_lifecycle" == production-current && "$install_deployable" == yes ]] || continue
        install_one "$caddy_root/${install_source#Caddy/}" \
            "$(root_path "$install_target")" "$install_mode"
    done <"$install_registry"
}

selected() {
    [[ "$component" == all || "$component" == "$1" ]]
}

if selected identities; then
    if [[ "$dry_run" == true || "$root_prefix" != / ]]; then
        record 'IDENTITY ensure groups caddy-tls/caddy-sync and users caddy-sync/keepalived_script'
        changes=$((changes + 1))
    else
        getent group caddy-tls >/dev/null ||
            groupadd --system caddy-tls
        getent group caddy-sync >/dev/null ||
            groupadd --system caddy-sync
        getent group keepalived_script >/dev/null ||
            groupadd --system keepalived_script
        id caddy-sync >/dev/null 2>&1 ||
            useradd \
                --system \
                --gid caddy-sync \
                --home-dir /var/lib/caddy-sync \
                --create-home \
                --shell /bin/sh \
                caddy-sync
        usermod --shell /bin/sh caddy-sync >/dev/null
        passwd --lock caddy-sync >/dev/null
        id keepalived_script >/dev/null 2>&1 ||
            useradd \
                --system \
                --gid keepalived_script \
                --no-create-home \
                --shell /usr/sbin/nologin \
                keepalived_script
        usermod -a -G caddy-tls caddy
        usermod -a -G caddy-tls caddy-sync
        usermod -a -G caddy-tls keepalived_script
    fi
fi

if selected directories; then
    ensure_directory "$(root_path /etc/caddy/releases)" 0750 root caddy-tls
    ensure_directory "$(root_path /var/lib/caddy-sync)" \
        0750 caddy-sync caddy-sync
    ensure_directory "$(root_path /var/lib/caddy-sync/outbound)" \
        0750 caddy-sync caddy-sync
    ensure_directory "$(root_path /var/lib/caddy-sync/incoming)" \
        0750 caddy-sync caddy-sync
    ensure_directory "$(root_path /var/lib/caddy-sync/quarantine)" \
        0750 caddy-sync caddy-sync
    ensure_directory "$(root_path /var/lib/caddy-sync/.ssh)" \
        0700 caddy-sync caddy-sync
fi

if selected caddy; then
    release_dir=$(root_path /etc/caddy/releases/bootstrap)
    ensure_directory "$release_dir" 0750 root caddy-tls
    ensure_directory "$release_dir/conf.d" 0750 root caddy-tls
    ensure_directory "$release_dir/tls" 0750 root caddy-tls
    install_one \
        "$caddy_root/configs/caddy/Caddyfile" \
        "$release_dir/Caddyfile" 0644
    install_tree \
        "$caddy_root/configs/caddy/conf.d" \
        "$release_dir/conf.d" 0644
    install_one "$render_dir/caddy-ha.env" \
        "$(root_path /etc/default/caddy-ha)" 0640 root caddy-tls

    if [[ -n "$certificate_dir" ]]; then
        for certificate_file in \
            leaf.pem intermediates.pem fullchain.pem privkey.pem \
            certificate-manifest.json; do
            if [[ ! -f "$certificate_dir/$certificate_file" ]]; then
                printf 'Missing prepared certificate file: %s\n' \
                    "$certificate_file" >&2
                exit 1
            fi
        done
        install_one "$certificate_dir/leaf.pem" \
            "$release_dir/tls/leaf.pem" 0644
        install_one "$certificate_dir/intermediates.pem" \
            "$release_dir/tls/intermediates.pem" 0644
        install_one "$certificate_dir/fullchain.pem" \
            "$release_dir/tls/fullchain.pem" 0644
        install_one "$certificate_dir/privkey.pem" \
            "$release_dir/tls/privkey.pem" 0640 root caddy-tls
        install_one "$certificate_dir/certificate-manifest.json" \
            "$release_dir/tls/certificate-manifest.json" 0644
    elif [[ "$dry_run" == false ]]; then
        printf 'The caddy component requires --certificate-dir.\n' >&2
        exit 2
    else
        record 'CERTIFICATES would install from --certificate-dir'
    fi

    current_link=$(root_path /etc/caddy/current)
    if [[ ! -L "$current_link" ]] ||
        [[ "$(readlink "$current_link")" != /etc/caddy/releases/bootstrap ]]; then
        changes=$((changes + 1))
        if [[ "$dry_run" == true ]]; then
            record "SYMLINK $current_link -> /etc/caddy/releases/bootstrap"
        else
            ln -sfn /etc/caddy/releases/bootstrap "$current_link"
        fi
    fi
fi

if selected lighttpd; then
    install_one \
        "$caddy_root/configs/lighttpd/desired-state.conf" \
        "$(root_path /usr/local/share/caddy-ha/lighttpd-desired-state.conf)" \
        0644
fi

if selected lsyncd; then
    install_one "$lsyncd_source" \
        "$(root_path /etc/lsyncd/caddy.lua)" 0644
fi

if selected scripts; then
    install_registered "$script_lifecycle"
fi

if selected systemd; then
    install_registered "$systemd_lifecycle"
fi

if selected sysctl; then
    install_one "$caddy_root/configs/sysctl/70-caddy-ha.conf" \
        "$(root_path /etc/sysctl.d/70-caddy-ha.conf)" 0644
fi

if selected tmpfiles; then
    install_one "$caddy_root/configs/tmpfiles.d/caddy-ha.conf" \
        "$(root_path /etc/tmpfiles.d/caddy-ha.conf)" 0644
fi

jq -n \
    --arg node "$node_role" \
    --arg component "$component" \
    --arg root "$root_prefix" \
    --argjson dry_run "$dry_run" \
    --argjson changes "$changes" \
    '{
        node: $node,
        component: $component,
        root: $root,
        dry_run: $dry_run,
        changes: $changes,
        service_mutations: false
    }'
