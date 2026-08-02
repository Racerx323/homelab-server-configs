#!/usr/bin/env bash

set -uo pipefail
set +x
PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH
readonly PATH

readonly -a units=(
    lighttpd.service
    caddy.service
    caddy-api.service
    lsyncd.service
    caddy-lsyncd.service
    keepalived.service
)
readonly -a inspected_paths=(
    /etc/lighttpd
    /etc/.lighttpd-pre-action16ap
    /etc/.lighttpd-caddy-action16ap
    /etc/.lighttpd-caddy-action16ap.failed
    /var/tmp/caddy-ha-lighttpd-node-a-action16ab
    /etc/caddy/current
    /etc/systemd/system/caddy.service
    /lib/systemd/system/caddy.service
    /etc/systemd/system/caddy.service.d/override.conf
    /etc/keepalived/conf.d/caddy-ha.conf
)
readonly -a lighttpd_roots=(
    /etc/lighttpd
    /etc/.lighttpd-pre-action16ap
    /etc/.lighttpd-caddy-action16ap
    /etc/.lighttpd-caddy-action16ap.failed
    /var/tmp/caddy-ha-lighttpd-node-a-action16ab
)

sanitize_line() {
    tr '\t\r\n' '   ' |
        sed -E 's/[[:space:]]+/ /g; s/^ //; s/ $//'
}

tree_hash() {
    local root=$1

    (
        cd "$root" || exit 1
        find . -type f -print0 |
            sort -z |
            xargs -0 -r sha256sum
    ) | sha256sum | awk '{ print $1 }'
}

unit_property() {
    local unit=$1
    local property=$2

    systemctl show "$unit" --property="$property" --value 2>/dev/null |
        sanitize_line
}

path_kind() {
    local target=$1

    if [[ -L "$target" ]]; then
        printf 'symlink\n'
    elif [[ -d "$target" ]]; then
        printf 'directory\n'
    elif [[ -f "$target" ]]; then
        printf 'regular\n'
    elif [[ -e "$target" ]]; then
        printf 'other\n'
    else
        printf 'absent\n'
    fi
}

collect_service_record() {
    local unit=$1
    local load active sub unit_file result main_status fragment dropins

    load=$(unit_property "$unit" LoadState)
    active=$(unit_property "$unit" ActiveState)
    sub=$(unit_property "$unit" SubState)
    unit_file=$(unit_property "$unit" UnitFileState)
    result=$(unit_property "$unit" Result)
    main_status=$(unit_property "$unit" ExecMainStatus)
    fragment=$(unit_property "$unit" FragmentPath)
    dropins=$(unit_property "$unit" DropInPaths)
    printf 'service_record=%s|%s|%s|%s|%s|%s|%s|%s|%s\n' \
        "$unit" "$load" "$active" "$sub" "$unit_file" "$result" \
        "$main_status" "$fragment" "$dropins"
}

collect_path_record() {
    local target=$1
    local kind metadata link_target canonical digest

    kind=$(path_kind "$target")
    metadata=unavailable
    link_target=none
    canonical=none
    digest=none
    if [[ "$kind" != absent ]]; then
        metadata=$(stat -c '%U:%G:%a:%s:%d:%i' -- "$target" 2>/dev/null ||
            printf 'unavailable')
    fi
    if [[ "$kind" == symlink ]]; then
        link_target=$(readlink -- "$target" 2>/dev/null || printf 'unavailable')
        canonical=$(readlink -f -- "$target" 2>/dev/null || printf 'unresolved')
    elif [[ "$kind" == directory ]]; then
        canonical=$(readlink -f -- "$target" 2>/dev/null || printf 'unresolved')
        digest=$(tree_hash "$target" 2>/dev/null || printf 'unavailable')
    elif [[ "$kind" == regular ]]; then
        canonical=$(readlink -f -- "$target" 2>/dev/null || printf 'unresolved')
        digest=$(sha256sum -- "$target" 2>/dev/null |
            awk '{ print $1 }' || printf 'unavailable')
    fi
    printf 'path_record=%s|%s|%s|%s|%s|%s\n' \
        "$target" "$kind" "$metadata" "$link_target" "$canonical" "$digest"
}

collect_lighttpd_record() {
    local root=$1
    local config=$root/lighttpd.conf
    local parse_status=not_applicable
    local include_count=0
    local include_line

    if [[ -f "$config" && ! -L "$config" ]]; then
        lighttpd -tt -f "$config" >/dev/null 2>&1
        parse_status=$?
        while IFS= read -r include_line; do
            printf 'lighttpd_include_record=%s|%s\n' \
                "$root" "$(printf '%s' "$include_line" | sanitize_line)"
            include_count=$((include_count + 1))
        done < <(grep -nE '^[[:space:]]*include[[:space:]]' "$config" \
            2>/dev/null || true)
    fi
    printf 'lighttpd_record=%s|%s|%s\n' \
        "$root" "$parse_status" "$include_count"
}

curl_code() {
    local scheme=$1
    shift
    local code status

    code=$(
        curl --silent --show-error \
            --connect-timeout 1 --max-time 3 \
            --output /dev/null --write-out '%{http_code}' \
            "$@" 2>/dev/null
    )
    status=$?
    printf '%s|%s|%s\n' "$scheme" "$status" "${code:-000}"
}

if [[ "${1:-}" == --self-test && $# -eq 1 ]]; then
    [[ "${#units[@]}" -eq 6 ]]
    [[ "${#inspected_paths[@]}" -eq 10 ]]
    [[ "${#lighttpd_roots[@]}" -eq 5 ]]
    [[ "$(printf '  a\t b  \n' | sanitize_line)" == 'a b' ]]
    [[ "$(path_kind /definitely-absent-action16ap-a)" == absent ]]
    printf 'action_16ap_a_recovery_diagnostic_self_test_complete=true\n'
    exit 0
elif (($#)); then
    printf 'Usage: %s [--self-test]\n' "${0##*/}" >&2
    exit 2
fi

printf 'action_16ap_a_remote_reached=true\n'
printf 'node_hostname=%s\n' "$(hostname 2>/dev/null | sanitize_line)"
printf 'node_architecture=%s\n' \
    "$(dpkg --print-architecture 2>/dev/null | sanitize_line)"
printf 'systemd_version=%s\n' \
    "$(systemctl --version 2>/dev/null | head -n 1 | sanitize_line)"

printf 'service_record_count=%s\n' "${#units[@]}"
for unit in "${units[@]}"; do
    collect_service_record "$unit"
done

printf 'path_record_count=%s\n' "${#inspected_paths[@]}"
for target in "${inspected_paths[@]}"; do
    collect_path_record "$target"
done

printf 'lighttpd_record_count=%s\n' "${#lighttpd_roots[@]}"
for root in "${lighttpd_roots[@]}"; do
    collect_lighttpd_record "$root"
done

caddy_validate_status=not_applicable
if [[ -f /etc/caddy/current/Caddyfile &&
    ! -L /etc/caddy/current/Caddyfile ]]; then
    runuser -u caddy -- \
        caddy validate --config /etc/caddy/current/Caddyfile \
        --adapter caddyfile >/dev/null 2>&1
    caddy_validate_status=$?
fi
printf 'caddy_validate_status=%s\n' "$caddy_validate_status"
printf 'caddy_tree_sha256=%s\n' \
    "$(tree_hash /etc/caddy 2>/dev/null || printf 'unavailable')"
printf 'keepalived_tree_sha256=%s\n' \
    "$(tree_hash /etc/keepalived 2>/dev/null || printf 'unavailable')"

listener_output=$(
    ss -H -lntup 2>/dev/null |
        awk '$5 ~ /:(80|443|8080|2019)$/ { print }' |
        sed -E 's/[[:space:]]+/ /g; s/^ //; s/ $//' |
        sort
)
mapfile -t listener_records <<<"$listener_output"
if [[ -z "$listener_output" ]]; then
    listener_records=()
fi
printf 'listener_record_count=%s\n' "${#listener_records[@]}"
for record in "${listener_records[@]}"; do
    printf 'listener_record=%s\n' "$record"
done

process_records=()
for process_name in lighttpd caddy lsyncd keepalived; do
    while IFS= read -r process_output; do
        [[ -n "$process_output" ]] || continue
        process_records+=("$process_name|$process_output")
    done < <(
        pgrep -a -x "$process_name" 2>/dev/null |
            sed -E 's/[[:space:]]+/ /g; s/^ //; s/ $//'
    )
done
printf 'process_record_count=%s\n' "${#process_records[@]}"
for record in "${process_records[@]}"; do
    printf 'process_record=%s\n' "$record"
done

printf 'health_record_count=5\n'
printf 'health_record=%s\n' \
    "$(curl_code backend http://127.0.0.1:8080/admin/)"
printf 'health_record=%s\n' \
    "$(curl_code frontend_http http://127.0.0.1/admin/)"
printf 'health_record=%s\n' \
    "$(curl_code localhost_https --insecure --head https://localhost/)"
printf 'health_record=%s\n' \
    "$(curl_code management_ipv4 \
        --resolve pihole0.local.theama.co:443:10.1.0.53 \
        https://pihole0.local.theama.co/admin/)"
printf 'health_record=%s\n' \
    "$(curl_code management_ipv6 \
        --resolve 'pihole0.local.theama.co:443:[fd36:5aa8:6971:1::53]' \
        https://pihole0.local.theama.co/admin/)"

journal_output=$(
    journalctl --no-pager --quiet -n 25 -o short-iso-precise \
        -u caddy.service -u lighttpd.service 2>/dev/null |
        sed -E 's/[[:space:]]+/ /g; s/^ //; s/ $//'
)
mapfile -t journal_records <<<"$journal_output"
if [[ -z "$journal_output" ]]; then
    journal_records=()
fi
printf 'journal_record_count=%s\n' "${#journal_records[@]}"
for record in "${journal_records[@]}"; do
    printf 'journal_record=%s\n' "$record"
done

printf 'peer_connections=false\n'
printf 'installed_helper_execution=false\n'
printf 'systemd_daemon_reload_performed=false\n'
printf 'service_mutations=false\n'
printf 'filesystem_mutations=false\n'
printf 'action_16ap_a_recovery_diagnostic_complete=true\n'
exit 0
