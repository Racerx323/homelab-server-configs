#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH
readonly PATH

readonly current_link=/etc/caddy/current
readonly bootstrap_release=/etc/caddy/releases/bootstrap
readonly release=/etc/caddy/releases/action16ar-node-a-default-deny
readonly release_staging=/etc/caddy/releases/.action16ar-node-a-default-deny.staging
readonly temporary_link=/etc/caddy/current.action16ar-new
readonly environment_file=/etc/default/caddy-ha
readonly baseline_default_deny_relative=conf.d/90-default-deny.caddy
readonly correction_relative=conf.d/91-exact-listener-default-deny.caddy
readonly caddy_vrrp=/etc/keepalived/conf.d/caddy-ha.conf

readonly baseline_caddy_tree_sha256=6ae99faf2cb216466879f15139cdd6614234cf46d796f535387d51ecc9602161
readonly baseline_default_deny_sha256=9ce8430d11882f4e2008ff27f4f4a2fcad568f81081629289f64ad2450316b27
readonly correction_sha256=d3a31eabc6fd75784f5f3891d55dd80d3f024463d112d8dd68549c91bcde8ae7
readonly caddyfile_sha256=a41c7816e927c16278fab018675a3f2db5b2aae89dd5b181f1ecb06ec9beb86e
readonly health_route_sha256=05fa1d2875ee0639601447ccd31284d3df55fc8d5e8cedef4a291c61d44f4b27
readonly pihole_route_sha256=5621134920da9dde97122fe9968a2debdd0c980ac0e432323fb46e0c1139798c
readonly environment_sha256=2e439dd4c868736fd7a9dceff7ba3627a1d9fe8780ba7dcef2ce5d0e5e62a2b8
readonly caddy_package_record='install ok installed|caddy|2.11.4|arm64'
readonly readiness_seconds=25
readonly stability_seconds=2

staging_created=false
release_created=false
link_switched=false
mutation_started=false
transaction_complete=false
caddy_pid_before=
listeners_before=
services_before=
adapted_json=

write_correction() {
    cat <<'EOF'
https:// {
	bind {$NODE_IPV4} {$NODE_IPV6}
	import local_tls
	respond 421
}

https:// {
	bind 10.1.0.56 fd36:5aa8:6971:1::56
	import local_tls
	respond 421
}

https:// {
	bind 127.0.0.1 ::1
	import local_tls
	respond 421
}
EOF
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

listener_snapshot() {
    ss -H -lntup 2>/dev/null |
        awk '$5 ~ /:(80|443|8080|2019)$/ { print }' |
        sort
}

service_snapshot() {
    local unit

    for unit in \
        caddy lighttpd keepalived lsyncd caddy-lsyncd \
        caddy-validate-reload.path caddy-validate-reload.service; do
        printf '%s=%s/%s\n' \
            "$unit" \
            "$(systemctl is-active "$unit" 2>/dev/null || true)" \
            "$(systemctl is-enabled "$unit" 2>/dev/null || true)"
    done
}

probe_code() {
    local fqdn=$1
    local address=$2

    curl --noproxy '*' --insecure --silent --show-error \
        --connect-timeout 1 --max-time 4 \
        --resolve "$fqdn:443:$address" \
        --output /dev/null --write-out '%{http_code}' \
        "https://$fqdn/" 2>/dev/null
}

success_or_redirect() {
    [[ "$1" =~ ^[23][0-9][0-9]$ ]]
}

caddy_validate_release() {
    local root=$1

    runuser -u caddy -- \
        env \
        CADDY_CONFIG_ROOT="$root" \
        NODE_FQDN=pihole0.local.theama.co \
        NODE_IPV4=10.1.0.53 \
        NODE_IPV6=fd36:5aa8:6971:1::53 \
        caddy validate --config "$root/Caddyfile" --adapter caddyfile \
        >/dev/null
}

adapt_release() {
    local root=$1
    local output=$2

    runuser -u caddy -- \
        env \
        CADDY_CONFIG_ROOT="$root" \
        NODE_FQDN=pihole0.local.theama.co \
        NODE_IPV4=10.1.0.53 \
        NODE_IPV6=fd36:5aa8:6971:1::53 \
        caddy adapt --config "$root/Caddyfile" --adapter caddyfile \
        >"$output" 2>/dev/null
}

validate_corrected_routes() {
    local adapted_json=$1

    jq -e '
        def hostless_421:
            any(
                .routes[]?;
                ([.match[]?.host[]?] | length) == 0
                and any(
                    .handle[]? | .. | objects;
                    .handler? == "static_response"
                    and (.status_code // 200) == 421
                )
            );
        def has_hosts($wanted):
            ([.routes[]?.match[]?.host[]?] | unique | sort) as $actual
            | all($wanted[]; $actual | index(.) != null);
        def server($first; $second):
            [
                .[]
                | select(
                    ((.listen // []) | sort)
                    == ([$first, $second] | sort)
                )
            ];

        .apps.http.servers as $servers
        | ($servers | server(
            "10.1.0.53:443";
            "[fd36:5aa8:6971:1::53]:443"
        )) as $physical
        | ($servers | server(
            "10.1.0.56:443";
            "[fd36:5aa8:6971:1::56]:443"
        )) as $vip
        | ($servers | server("127.0.0.1:443"; "[::1]:443")) as $loopback
        | ([
            $servers[]
            | select((.listen // []) == [":443"])
        ]) as $wildcard_https
        | ([
            $servers[]
            | select((.listen // []) == [":80"])
        ]) as $wildcard_http
        | ($servers | length) == 5
        and ($physical | length) == 1
        and ($vip | length) == 1
        and ($loopback | length) == 1
        and ($wildcard_https | length) == 1
        and ($wildcard_http | length) == 1
        and ($physical[0] | has_hosts(["pihole0.local.theama.co"]))
        and ($vip[0] | has_hosts([
            "pihole-admin.local.theama.co",
            "proxy.local.theama.co"
        ]))
        and ($loopback[0] | has_hosts(["localhost"]))
        and ($physical[0] | hostless_421)
        and ($vip[0] | hostless_421)
        and ($loopback[0] | hostless_421)
        and ($wildcard_https[0] | hostless_421)
        and ($wildcard_http[0] | hostless_421)
    ' "$adapted_json" >/dev/null
}

baseline_ready_once() {
    local known_code

    [[ "$(systemctl is-active caddy.service 2>/dev/null || true)" == active ]] &&
        [[ "$(systemctl show caddy.service -p MainPID --value)" == "$caddy_pid_before" ]] &&
        [[ "$(listener_snapshot)" == "$listeners_before" ]] &&
        caddy_validate_release "$bootstrap_release" &&
        [[ "$(probe_code unexpected.local.theama.co 10.1.0.53)" == 200 ]] &&
        known_code=$(probe_code pihole0.local.theama.co 10.1.0.53) &&
        success_or_redirect "$known_code" &&
        [[ "$(probe_code localhost 127.0.0.1)" == 204 ]]
}

corrected_ready_once() {
    local known_code address

    [[ "$(systemctl is-active caddy.service 2>/dev/null || true)" == active ]] ||
        return 1
    [[ "$(systemctl show caddy.service -p MainPID --value)" == "$caddy_pid_before" ]] ||
        return 1
    [[ "$(listener_snapshot)" == "$listeners_before" ]] || return 1
    caddy_validate_release "$release" || return 1
    [[ "$(probe_code localhost 127.0.0.1)" == 204 ]] || return 1
    [[ "$(probe_code unexpected.local.theama.co 127.0.0.1)" == 421 ]] ||
        return 1
    for address in 10.1.0.53 '[fd36:5aa8:6971:1::53]'; do
        known_code=$(probe_code pihole0.local.theama.co "$address") ||
            return 1
        success_or_redirect "$known_code" || return 1
        [[ "$(probe_code unexpected.local.theama.co "$address")" == 421 ]] ||
            return 1
    done
}

wait_until_stable() {
    local probe=$1
    local deadline=$((SECONDS + readiness_seconds))

    while ((SECONDS < deadline)); do
        if "$probe"; then
            sleep "$stability_seconds"
            if "$probe"; then
                return 0
            fi
        fi
        sleep 0.2
    done
    return 1
}

rollback() {
    local status=$?
    local rollback_ok=true

    trap - EXIT
    if [[ "$transaction_complete" == true ]]; then
        exit "$status"
    fi
    set +e
    printf 'action_16ar_failure_status=%s\n' "$status" >&2

    if [[ "$adapted_json" == /tmp/caddy-action16ar-adapted.* ]]; then
        rm -f -- "$adapted_json" || rollback_ok=false
    elif [[ -n "$adapted_json" ]]; then
        rollback_ok=false
    fi
    rm -f -- "$temporary_link" || rollback_ok=false
    if [[ "$mutation_started" != true &&
        "$staging_created" != true &&
        "$release_created" != true &&
        "$link_switched" != true ]]; then
        if [[ "$rollback_ok" == true ]]; then
            printf 'action_16ar_rollback_not_required=true\n' >&2
            exit "$status"
        fi
        printf 'action_16ar_rollback_incomplete=true\n' >&2
        printf 'manual_intervention_required=true\n' >&2
        exit 125
    fi
    if [[ "$link_switched" == true ]]; then
        ln -s "$bootstrap_release" "$temporary_link" || rollback_ok=false
        mv -Tf -- "$temporary_link" "$current_link" || rollback_ok=false
        systemctl reload caddy.service || rollback_ok=false
        wait_until_stable baseline_ready_once || rollback_ok=false
    fi

    if [[ "$release_created" == true ]]; then
        rm -rf --one-file-system -- "$release" || rollback_ok=false
    fi
    if [[ "$staging_created" == true ]]; then
        rm -rf --one-file-system -- "$release_staging" || rollback_ok=false
    fi

    [[ -L "$current_link" ]] || rollback_ok=false
    [[ "$(readlink -e "$current_link")" == "$bootstrap_release" ]] ||
        rollback_ok=false
    [[ ! -e "$temporary_link" && ! -L "$temporary_link" ]] ||
        rollback_ok=false
    [[ ! -e "$release" && ! -L "$release" ]] || rollback_ok=false
    [[ ! -e "$release_staging" && ! -L "$release_staging" ]] ||
        rollback_ok=false
    [[ "$(tree_hash /etc/caddy)" == "$baseline_caddy_tree_sha256" ]] ||
        rollback_ok=false
    [[ "$(service_snapshot)" == "$services_before" ]] || rollback_ok=false
    [[ "$(listener_snapshot)" == "$listeners_before" ]] || rollback_ok=false
    [[ ! -e "$caddy_vrrp" && ! -L "$caddy_vrrp" ]] || rollback_ok=false

    if [[ "$rollback_ok" == true ]]; then
        printf 'action_16ar_rollback_complete=true\n' >&2
        exit "$status"
    fi
    printf 'action_16ar_rollback_incomplete=true\n' >&2
    printf 'manual_intervention_required=true\n' >&2
    exit 125
}

if [[ "${1:-}" == --self-test && $# -eq 1 ]]; then
    [[ "$correction_sha256" =~ ^[0-9a-f]{64}$ ]]
    [[ "$(write_correction | sha256sum | awk '{ print $1 }')" == "$correction_sha256" ]]
    [[ "$readiness_seconds" -eq 25 ]]
    [[ "$stability_seconds" -eq 2 ]]
    printf 'action_16ar_routing_correction_self_test_complete=true\n'
    exit 0
elif (($#)); then
    printf 'Usage: %s [--self-test]\n' "${0##*/}" >&2
    exit 2
fi

trap rollback EXIT

printf 'action_16ar_remote_reached=true\n'
[[ $EUID -eq 0 ]]
for command_name in \
    awk caddy cp curl date dpkg dpkg-query env find hostname install jq ln mv \
    readlink rm runuser sha256sum sleep sort ss stat systemctl touch xargs; do
    command -v "$command_name" >/dev/null
done

[[ "$(hostname)" == j1-svpihole0 ]]
[[ "$(dpkg --print-architecture)" == arm64 ]]
[[ "$(dpkg-query -W \
    -f='${Status}|${binary:Package}|${Version}|${Architecture}' caddy)" == "$caddy_package_record" ]]
[[ -L "$current_link" ]]
[[ "$(readlink -e "$current_link")" == "$bootstrap_release" ]]
[[ ! -e "$release" && ! -L "$release" ]]
[[ ! -e "$release_staging" && ! -L "$release_staging" ]]
[[ ! -e "$temporary_link" && ! -L "$temporary_link" ]]
[[ ! -e "$caddy_vrrp" && ! -L "$caddy_vrrp" ]]
[[ "$(tree_hash /etc/caddy)" == "$baseline_caddy_tree_sha256" ]]
[[ "$(sha256sum "$bootstrap_release/$baseline_default_deny_relative" |
    awk '{ print $1 }')" == "$baseline_default_deny_sha256" ]]
[[ ! -e "$bootstrap_release/$correction_relative" &&
    ! -L "$bootstrap_release/$correction_relative" ]]
[[ "$(sha256sum "$bootstrap_release/Caddyfile" |
    awk '{ print $1 }')" == "$caddyfile_sha256" ]]
[[ "$(sha256sum "$bootstrap_release/conf.d/00-health.caddy" |
    awk '{ print $1 }')" == "$health_route_sha256" ]]
[[ "$(sha256sum "$bootstrap_release/conf.d/10-pihole-admin.caddy" |
    awk '{ print $1 }')" == "$pihole_route_sha256" ]]
[[ "$(sha256sum "$environment_file" |
    awk '{ print $1 }')" == "$environment_sha256" ]]
[[ "$(systemctl is-active caddy.service)" == active ]]
[[ "$(systemctl is-enabled caddy.service 2>/dev/null || true)" == disabled ]]
[[ "$(systemctl is-active lighttpd.service)" == active ]]
[[ "$(systemctl is-enabled lighttpd.service)" == enabled ]]
[[ "$(systemctl is-active keepalived.service)" == active ]]
[[ "$(systemctl is-enabled keepalived.service)" == enabled ]]
[[ "$(systemctl is-active lsyncd.service 2>/dev/null || true)" == inactive ]]
[[ "$(systemctl is-enabled lsyncd.service 2>/dev/null || true)" == masked ]]
[[ "$(systemctl is-active caddy-lsyncd.service 2>/dev/null || true)" == inactive ]]
[[ "$(systemctl is-enabled caddy-lsyncd.service 2>/dev/null || true)" == disabled ]]
[[ "$(systemctl is-active caddy-validate-reload.path 2>/dev/null || true)" == inactive ]]
[[ "$(systemctl is-active caddy-validate-reload.service 2>/dev/null || true)" == inactive ]]
caddy_validate_release "$bootstrap_release"

caddy_pid_before=$(systemctl show caddy.service -p MainPID --value)
[[ "$caddy_pid_before" =~ ^[1-9][0-9]*$ ]]
listeners_before=$(listener_snapshot)
services_before=$(service_snapshot)
baseline_ready_once

printf 'action_16ar_preflight_complete=true\n'
printf 'action_16ar_mutation_started=true\n'
mutation_started=true

install -d -o root -g caddy-tls -m 0750 "$release_staging"
staging_created=true
cp -a -- "$bootstrap_release/." "$release_staging/"
write_correction |
    install -o root -g root -m 0644 /dev/stdin \
        "$release_staging/$correction_relative"
[[ "$(sha256sum "$release_staging/$correction_relative" |
    awk '{ print $1 }')" == "$correction_sha256" ]]

rm -f -- \
    "$release_staging/.complete" \
    "$release_staging/manifest.sha256" \
    "$release_staging/release-manifest.json"
jq -n \
    --arg revision action16ar-node-a-default-deny \
    --arg parent_revision bootstrap \
    --arg parent_path "$bootstrap_release" \
    --arg source_node node-a \
    --arg created_at "$(date --iso-8601=seconds)" \
    '{
        revision: $revision,
        parent_revision: $parent_revision,
        parent_path: $parent_path,
        source_node: $source_node,
        created_at: $created_at,
        deployment_action: "16ar-routing-correction"
    }' >"$release_staging/release-manifest.json"
(
    cd "$release_staging"
    find . -type f \
        ! -name manifest.sha256 \
        ! -name .complete \
        -print0 |
        sort -z |
        xargs -0 sha256sum
) >"$release_staging/manifest.sha256"
touch "$release_staging/.complete"
chown -R root:caddy-tls "$release_staging"
find "$release_staging" -type d -exec chmod 0550 {} +
find "$release_staging" -type f -exec chmod 0440 {} +
(
    cd "$release_staging"
    sha256sum --check --quiet manifest.sha256
)

adapted_json=$(mktemp /tmp/caddy-action16ar-adapted.XXXXXX)
adapt_release "$release_staging" "$adapted_json"
validate_corrected_routes "$adapted_json"
rm -f -- "$adapted_json"
adapted_json=
caddy_validate_release "$release_staging"

mv -- "$release_staging" "$release"
staging_created=false
release_created=true
[[ "$(stat -c '%U:%G:%a' "$release")" == root:caddy-tls:550 ]]
[[ -f "$release/.complete" ]]
[[ "$(jq -r '.revision' "$release/release-manifest.json")" == action16ar-node-a-default-deny ]]
(
    cd "$release"
    sha256sum --check --quiet manifest.sha256
)

ln -s "$release" "$temporary_link"
mv -Tf -- "$temporary_link" "$current_link"
link_switched=true
[[ "$(readlink -e "$current_link")" == "$release" ]]

systemctl reload caddy.service
wait_until_stable corrected_ready_once

[[ "$(service_snapshot)" == "$services_before" ]]
[[ "$(listener_snapshot)" == "$listeners_before" ]]
[[ ! -e "$caddy_vrrp" && ! -L "$caddy_vrrp" ]]

printf 'previous_release=%s\n' "$bootstrap_release"
printf 'selected_release=%s\n' "$(readlink -e "$current_link")"
printf 'caddy_main_pid_before=%s\n' "$caddy_pid_before"
printf 'caddy_main_pid_after=%s\n' \
    "$(systemctl show caddy.service -p MainPID --value)"
printf 'exact_listener_default_deny_sha256=%s\n' "$correction_sha256"
printf 'release_manifest_sha256=%s\n' \
    "$(sha256sum "$release/release-manifest.json" | awk '{ print $1 }')"
printf 'content_manifest_sha256=%s\n' \
    "$(sha256sum "$release/manifest.sha256" | awk '{ print $1 }')"
printf 'unknown_ipv4_code=421\n'
printf 'unknown_ipv6_code=421\n'
printf 'unknown_loopback_code=421\n'
printf 'caddy_reload_performed=true\n'
printf 'caddy_restart_performed=false\n'
printf 'systemd_daemon_reload_performed=false\n'
printf 'lighttpd_mutations=false\n'
printf 'keepalived_mutations=false\n'
printf 'lsyncd_mutations=false\n'
printf 'peer_connections=false\n'
printf 'action_16ar_routing_correction_complete=true\n'
transaction_complete=true
