#!/usr/bin/env bash

set -uo pipefail
set +x
PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH
readonly PATH

readonly current_link=/etc/caddy/current
readonly environment_file=/etc/default/caddy-ha
readonly caddy_admin=http://127.0.0.1:2019
readonly journal_since='2026-07-29 16:20:00 UTC'

readonly -a units=(
    caddy.service
    lighttpd.service
    keepalived.service
    lsyncd.service
    caddy-lsyncd.service
    caddy-api.service
    caddy-validate-reload.path
    caddy-validate-reload.service
)
readonly -a inspected_paths=(
    /etc/caddy/current
    /etc/caddy/releases/bootstrap
    /etc/caddy/releases/action16ar-node-a-default-deny
    /etc/caddy/releases/.action16ar-node-a-default-deny.staging
    /etc/caddy/current.action16ar-new
    /etc/default/caddy-ha
    /etc/keepalived/conf.d/caddy-ha.conf
    /etc/caddy/current/Caddyfile
    /etc/caddy/current/conf.d/90-default-deny.caddy
    /etc/caddy/current/conf.d/91-exact-listener-default-deny.caddy
    /etc/caddy/releases/action16ar-node-a-default-deny/.complete
    /etc/caddy/releases/action16ar-node-a-default-deny/manifest.sha256
    /etc/caddy/releases/action16ar-node-a-default-deny/release-manifest.json
    /etc/caddy/releases/.action16ar-node-a-default-deny.staging/.complete
    /etc/caddy/releases/.action16ar-node-a-default-deny.staging/manifest.sha256
    /etc/caddy/releases/.action16ar-node-a-default-deny.staging/release-manifest.json
)
readonly -a releases=(
    /etc/caddy/releases/bootstrap
    /etc/caddy/releases/action16ar-node-a-default-deny
    /etc/caddy/releases/.action16ar-node-a-default-deny.staging
)
readonly -a environment_keys=(
    NODE_ROLE
    NODE_FQDN
    NODE_IPV4
    NODE_IPV6
    PEER_ROLE
    PEER_IPV4
    PEER_IPV6
    CADDY_PRIORITY
    NETWORK_INTERFACE
    SYNC_TARGET
)

sanitize_value() {
    tr '\t\r\n' '   ' |
        sed -E \
            's/[[:space:]]+/ /g; s/^ //; s/ $//; s/[|]/%7C/g'
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

tree_hash() {
    local root=$1

    (
        cd "$root" || exit 1
        find . -type f -print0 |
            sort -z |
            xargs -0 -r sha256sum
    ) | sha256sum | awk '{ print $1 }'
}

file_hash() {
    local target=$1

    if [[ -f "$target" && ! -L "$target" ]]; then
        sha256sum -- "$target" 2>/dev/null |
            awk '{ print $1 }'
    else
        printf 'not_regular\n'
    fi
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
        metadata=$(stat -c '%U:%G:%a:%s:%d:%i:%Y' -- "$target" 2>/dev/null |
            sanitize_value)
        [[ -n "$metadata" ]] || metadata=unavailable
    fi
    if [[ "$kind" == symlink ]]; then
        link_target=$(readlink -- "$target" 2>/dev/null |
            sanitize_value)
        canonical=$(readlink -f -- "$target" 2>/dev/null |
            sanitize_value)
        [[ -n "$link_target" ]] || link_target=unavailable
        [[ -n "$canonical" ]] || canonical=unresolved
    elif [[ "$kind" == directory ]]; then
        canonical=$(readlink -f -- "$target" 2>/dev/null |
            sanitize_value)
        digest=$(tree_hash "$target" 2>/dev/null || printf 'unavailable')
        [[ -n "$canonical" ]] || canonical=unresolved
    elif [[ "$kind" == regular ]]; then
        canonical=$(readlink -f -- "$target" 2>/dev/null |
            sanitize_value)
        digest=$(file_hash "$target")
        [[ -n "$canonical" ]] || canonical=unresolved
    fi
    printf 'path_record=%s|%s|%s|%s|%s|%s\n' \
        "$target" "$kind" "$metadata" "$link_target" "$canonical" "$digest"
}

manifest_value() {
    local manifest=$1
    local expression=$2

    if [[ -f "$manifest" && ! -L "$manifest" ]] &&
        jq -e 'type == "object"' "$manifest" >/dev/null 2>&1; then
        jq -r "$expression // \"\"" "$manifest" 2>/dev/null |
            sanitize_value
    else
        printf 'unavailable\n'
    fi
}

collect_release_record() {
    local root=$1
    local kind metadata digest complete manifest_status revision parent
    local parent_path source_node deployment_action file_count correction_hash

    kind=$(path_kind "$root")
    metadata=unavailable
    digest=unavailable
    complete=absent
    manifest_status=not_applicable
    revision=unavailable
    parent=unavailable
    parent_path=unavailable
    source_node=unavailable
    deployment_action=unavailable
    file_count=0
    correction_hash=not_regular

    if [[ "$kind" == directory ]]; then
        metadata=$(stat -c '%U:%G:%a:%s:%d:%i:%Y' -- "$root" 2>/dev/null |
            sanitize_value)
        digest=$(tree_hash "$root" 2>/dev/null || printf 'unavailable')
        file_count=$(find "$root" -type f -printf '.' 2>/dev/null |
            wc -c)
        if [[ -f "$root/.complete" && ! -L "$root/.complete" ]]; then
            complete=regular
        elif [[ -e "$root/.complete" || -L "$root/.complete" ]]; then
            complete=invalid
        fi
        if [[ -f "$root/manifest.sha256" &&
            ! -L "$root/manifest.sha256" ]]; then
            (
                cd "$root" &&
                    sha256sum --check --quiet manifest.sha256
            ) >/dev/null 2>&1
            manifest_status=$?
        fi
        revision=$(manifest_value "$root/release-manifest.json" '.revision')
        parent=$(manifest_value \
            "$root/release-manifest.json" '.parent_revision')
        parent_path=$(manifest_value \
            "$root/release-manifest.json" '.parent_path')
        source_node=$(manifest_value \
            "$root/release-manifest.json" '.source_node')
        deployment_action=$(manifest_value \
            "$root/release-manifest.json" '.deployment_action')
        correction_hash=$(file_hash \
            "$root/conf.d/91-exact-listener-default-deny.caddy")
    fi

    printf 'release_record=%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s\n' \
        "$root" "$kind" "$metadata" "$digest" "$complete" \
        "$manifest_status" "$revision" "$parent" "$parent_path" \
        "$source_node" "$deployment_action" "$file_count" "$correction_hash"
}

unit_property() {
    local unit=$1
    local property=$2

    systemctl show "$unit" --property="$property" --value 2>/dev/null |
        sanitize_value
}

collect_service_record() {
    local unit=$1

    printf 'service_record=%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s\n' \
        "$unit" \
        "$(unit_property "$unit" LoadState)" \
        "$(unit_property "$unit" ActiveState)" \
        "$(unit_property "$unit" SubState)" \
        "$(unit_property "$unit" UnitFileState)" \
        "$(unit_property "$unit" Result)" \
        "$(unit_property "$unit" MainPID)" \
        "$(unit_property "$unit" ExecMainStatus)" \
        "$(unit_property "$unit" NRestarts)" \
        "$(unit_property "$unit" FragmentPath)" \
        "$(unit_property "$unit" DropInPaths)"
}

route_summary() {
    jq -c '
        to_entries[]
        | {
            server: .key,
            listen: (.value.listen // []),
            hosts: ([.value.routes[]?.match[]?.host[]?] | unique | sort),
            hostless_421: any(
                .value.routes[]?;
                ([.match[]?.host[]?] | length) == 0
                and any(
                    .handle[]? | .. | objects;
                    .handler? == "static_response"
                    and (.status_code // 200) == 421
                )
            )
        }
    '
}

collect_config_source() {
    local label=$1
    local json=$2
    local status=$3
    local digest=unavailable records='' record_count=0

    if [[ "$status" -eq 0 ]] && jq -e 'type == "object"' \
        <<<"$json" >/dev/null 2>&1; then
        digest=$(printf '%s' "$json" | sha256sum | awk '{ print $1 }')
        records=$(jq -c '.apps.http.servers' <<<"$json" 2>/dev/null |
            route_summary 2>/dev/null)
        record_count=$(grep -c . <<<"$records")
        [[ -n "$records" ]] || record_count=0
    fi
    printf 'config_record=%s|%s|%s|%s\n' \
        "$label" "$status" "$digest" "$record_count"
    while IFS= read -r record; do
        [[ -n "$record" ]] || continue
        printf 'route_record=%s|%s\n' \
            "$label" "$(printf '%s' "$record" | sanitize_value)"
    done <<<"$records"
}

run_probe() {
    local label=$1
    shift
    local output status metadata

    output=$(
        curl --noproxy '*' --insecure --silent --show-error \
            --connect-timeout 1 --max-time 4 \
            "$@" \
            --output /dev/null \
            --write-out \
            '%{http_code}|%{remote_ip}|%{http_version}|%{num_redirects}|%{size_download}' \
            2>/dev/null
    )
    status=$?
    metadata=$(printf '%s' "${output:-missing}" | sanitize_value)
    [[ -n "$metadata" ]] || metadata=missing
    printf 'probe_record=%s|%s|%s\n' "$label" "$status" "$metadata"
}

if [[ "${1:-}" == --self-test && $# -eq 1 ]]; then
    [[ "${#units[@]}" -eq 8 ]]
    [[ "${#inspected_paths[@]}" -eq 16 ]]
    [[ "${#releases[@]}" -eq 3 ]]
    [[ "${#environment_keys[@]}" -eq 10 ]]
    [[ "$(printf ' a|b\t c \n' | sanitize_value)" == 'a%7Cb c' ]]
    [[ "$(path_kind /definitely-absent-action16ar-a)" == absent ]]
    sample='{"srv0":{"listen":["10.1.0.53:443"],"routes":[{"handle":[{"handler":"subroute","routes":[{"handle":[{"handler":"static_response","status_code":421}]}]}]}]}}'
    grep -Fq '"hostless_421":true' < <(route_summary <<<"$sample")
    printf 'action_16ar_a_recovery_diagnostic_self_test_complete=true\n'
    exit 0
elif (($#)); then
    printf 'Usage: %s [--self-test]\n' "${0##*/}" >&2
    exit 2
fi

printf 'action_16ar_a_remote_reached=true\n'
printf 'node_hostname=%s\n' "$(hostname 2>/dev/null | sanitize_value)"
printf 'node_architecture=%s\n' \
    "$(dpkg --print-architecture 2>/dev/null | sanitize_value)"
printf 'collection_timestamp=%s\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ | sanitize_value)"

readonly -a required_commands=(
    awk caddy curl date dpkg find grep hostname journalctl jq pgrep readlink
    runuser sed sha256sum sort ss stat systemctl tr wc xargs
)
printf 'command_record_count=%s\n' "${#required_commands[@]}"
for command_name in "${required_commands[@]}"; do
    command -v "$command_name" >/dev/null 2>&1
    printf 'command_record=%s|%s\n' "$command_name" "$?"
done

printf 'path_record_count=%s\n' "${#inspected_paths[@]}"
for target in "${inspected_paths[@]}"; do
    collect_path_record "$target"
done

printf 'release_record_count=%s\n' "${#releases[@]}"
for release_root in "${releases[@]}"; do
    collect_release_record "$release_root"
done

printf 'environment_record_count=%s\n' "${#environment_keys[@]}"
for environment_key in "${environment_keys[@]}"; do
    environment_value=$(
        awk -F= -v key="$environment_key" \
            '$1 == key { print substr($0, length(key) + 2); exit }' \
            "$environment_file" 2>/dev/null |
            sanitize_value
    )
    printf 'environment_record=%s|%s\n' \
        "$environment_key" "${environment_value:-missing}"
done
printf 'environment_file_sha256=%s\n' "$(file_hash "$environment_file")"

printf 'service_record_count=%s\n' "${#units[@]}"
for unit in "${units[@]}"; do
    collect_service_record "$unit"
done
printf 'caddy_environment_files=%s\n' \
    "$(unit_property caddy.service EnvironmentFiles)"
printf 'caddy_invocation_id=%s\n' \
    "$(unit_property caddy.service InvocationID)"

current_root=$(readlink -f "$current_link" 2>/dev/null || true)
caddy_validate_status=not_applicable
adapted_json=
adapted_status=1
if [[ -n "$current_root" &&
    -f "$current_root/Caddyfile" &&
    ! -L "$current_root/Caddyfile" ]]; then
    runuser -u caddy -- \
        env \
        CADDY_CONFIG_ROOT="$current_root" \
        NODE_FQDN=pihole0.local.theama.co \
        NODE_IPV4=10.1.0.53 \
        NODE_IPV6=fd36:5aa8:6971:1::53 \
        caddy validate --config "$current_root/Caddyfile" \
        --adapter caddyfile >/dev/null 2>&1
    caddy_validate_status=$?
    adapted_json=$(
        runuser -u caddy -- \
            env \
            CADDY_CONFIG_ROOT="$current_root" \
            NODE_FQDN=pihole0.local.theama.co \
            NODE_IPV4=10.1.0.53 \
            NODE_IPV6=fd36:5aa8:6971:1::53 \
            caddy adapt --config "$current_root/Caddyfile" \
            --adapter caddyfile 2>/dev/null
    )
    adapted_status=$?
fi
printf 'caddy_validate_status=%s\n' "$caddy_validate_status"
collect_config_source adapted "$adapted_json" "$adapted_status"

runtime_json=$(curl --noproxy '*' --silent --show-error \
    --connect-timeout 1 --max-time 4 "$caddy_admin/config/" 2>/dev/null)
runtime_status=$?
collect_config_source runtime "$runtime_json" "$runtime_status"

printf 'tree_record_count=3\n'
for tree_root in /etc/caddy /etc/keepalived /etc/lighttpd; do
    printf 'tree_record=%s|%s\n' "$tree_root" \
        "$(tree_hash "$tree_root" 2>/dev/null || printf 'unavailable')"
done

listener_output=$(
    ss -H -lntup 2>/dev/null |
        sed -E 's/[[:space:]]+/ /g; s/^ //; s/ $//' |
        grep -E ':(80|443|8080|2019)([[:space:]]|$)' |
        sort
)
mapfile -t listener_records <<<"$listener_output"
if [[ -z "$listener_output" ]]; then
    listener_records=()
fi
printf 'listener_record_count=%s\n' "${#listener_records[@]}"
for listener_record in "${listener_records[@]}"; do
    printf 'listener_record=%s\n' \
        "$(printf '%s' "$listener_record" | sanitize_value)"
done

process_records=()
for process_name in caddy lighttpd keepalived lsyncd; do
    while IFS= read -r process_record; do
        [[ -n "$process_record" ]] || continue
        process_records+=("$process_name|$process_record")
    done < <(
        pgrep -a -x "$process_name" 2>/dev/null |
            sed -E 's/[[:space:]]+/ /g; s/^ //; s/ $//'
    )
done
printf 'process_record_count=%s\n' "${#process_records[@]}"
for process_record in "${process_records[@]}"; do
    printf 'process_record=%s\n' \
        "$(printf '%s' "$process_record" | sanitize_value)"
done

printf 'probe_record_count=8\n'
run_probe backend http://127.0.0.1:8080/admin/
run_probe localhost_health https://localhost/
run_probe management_ipv4 \
    --resolve pihole0.local.theama.co:443:10.1.0.53 \
    https://pihole0.local.theama.co/admin/
run_probe management_ipv6 \
    --resolve 'pihole0.local.theama.co:443:[fd36:5aa8:6971:1::53]' \
    https://pihole0.local.theama.co/admin/
run_probe unknown_ipv4 \
    --resolve unexpected.local.theama.co:443:10.1.0.53 \
    https://unexpected.local.theama.co/
run_probe unknown_ipv6 \
    --resolve 'unexpected.local.theama.co:443:[fd36:5aa8:6971:1::53]' \
    https://unexpected.local.theama.co/
run_probe unknown_loopback_ipv4 \
    --resolve unexpected.local.theama.co:443:127.0.0.1 \
    https://unexpected.local.theama.co/
run_probe unknown_loopback_ipv6 \
    --resolve 'unexpected.local.theama.co:443:[::1]' \
    https://unexpected.local.theama.co/

journal_output=$(
    journalctl --no-pager --quiet -n 80 -o short-iso-precise \
        --since "$journal_since" \
        -u caddy.service 2>/dev/null |
        sed -E 's/[[:space:]]+/ /g; s/^ //; s/ $//'
)
journal_status=$?
mapfile -t journal_records <<<"$journal_output"
if [[ -z "$journal_output" ]]; then
    journal_records=()
fi
printf 'journal_status=%s\n' "$journal_status"
printf 'journal_record_count=%s\n' "${#journal_records[@]}"
for journal_record in "${journal_records[@]}"; do
    printf 'journal_record=%s\n' \
        "$(printf '%s' "$journal_record" | sanitize_value)"
done

printf 'runtime_metrics_counter_effect=true\n'
printf 'peer_connections=false\n'
printf 'installed_helper_execution=false\n'
printf 'systemd_daemon_reload_performed=false\n'
printf 'service_mutations=false\n'
printf 'filesystem_mutations=false\n'
printf 'action_16ar_a_recovery_diagnostic_complete=true\n'
exit 0
