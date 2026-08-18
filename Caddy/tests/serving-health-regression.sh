#!/usr/bin/env bash

set -Eeuo pipefail
set +x
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=serving_health_regression
test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
readonly caddy_root=${test_directory%/tests}
readonly server_root=${caddy_root%/Caddy}
readonly dns_root=${server_root%/homelab-server-configs}/homelab-dns
readonly caddy_helper=$caddy_root/scripts/check-caddy-serving-health.sh
readonly web_helper=$caddy_root/scripts/check-pihole-web-health.sh
readonly dns_helper=$dns_root/Keepalived/scripts/dns-check.sh
readonly node_a_keepalived=$dns_root/Keepalived/configs/keepalived-pihole0.conf
readonly node_b_keepalived=$dns_root/Keepalived/configs/keepalived-pihole00.conf
readonly proxy_route=$caddy_root/configs/caddy/conf.d/10-pihole-admin.caddy
root=$(mktemp -d /tmp/caddy-serving-health-regression.XXXXXX)
readonly root
trap 'rm -rf -- "$root"' EXIT
trap 'printf "serving_health_regression_failure_line=%s status=%s\n" "$LINENO" "$?" >&2' ERR

install -d -m 0700 "$root/bin" "$root/state" "$root/run"
printf 'NODE_FQDN=pihole0.local.theama.co\nNODE_IPV4=10.1.0.53\nNODE_IPV6=fd36:5aa8:6971:1::53\n' >"$root/environment"
printf 'healthy\n' >"$root/caddy-mode"
printf 'exact\n' >"$root/dns-mode"
printf 'healthy\n' >"$root/web-mode"
printf 'accept\n' >"$root/enqueue-mode"

cat >"$root/bin/systemctl" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >>"$root/systemctl.log"
[[ "\$(<"$root/service-mode")" = active ]] || exit 3
[[ "\$1" = is-active && "\$2" = --quiet ]]
case "\$3" in caddy.service | lighttpd.service | pihole-FTL.service | unbound.service) exit 0 ;; esac
exit 1
EOF
cat >"$root/bin/curl" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >>"$root/curl.log"
case " \$* " in *' --insecure '*) exit 64 ;; esac
case "\$*" in
    *'/admin/login.php'*)
        [[ "\$(<"$root/web-mode")" = healthy ]] || exit 22
        printf '200 https://pihole0.local.theama.co/admin/login.php\n'
        ;;
    *'/healthz'*)
        case "\$(<"$root/caddy-mode")" in
            healthy) printf '204' ;;
            http) printf '503' ;;
            transport) exit 7 ;;
            *) exit 2 ;;
        esac
        ;;
    *) exit 2 ;;
esac
EOF
cat >"$root/bin/dig" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >>"$root/dig.log"
case "\$(<"$root/dns-mode")" in
    exact)
        case " \$* " in
            *' A '*) printf '10.1.0.55\n' ;;
            *' AAAA '*) printf 'fd36:5aa8:6971:1::55\n' ;;
            *) exit 2 ;;
        esac
        ;;
    mismatch) printf '192.0.2.1\n' ;;
    transport) exit 9 ;;
    *) exit 2 ;;
esac
EOF
cat >"$root/bin/enqueue" <<EOF
#!/usr/bin/env bash
[[ "\$(<"$root/enqueue-mode")" = accept ]] || exit 1
printf '%s\n' "\$*" >>"$root/enqueue.log"
EOF
chmod 0755 "$root/bin/"*
printf 'active\n' >"$root/service-mode"

: >"$root/curl.log"
CADDY_SERVING_HEALTH_ENVIRONMENT_FILE=$root/environment \
    CADDY_SERVING_HEALTH_CURL_COMMAND=$root/bin/curl \
    CADDY_SERVING_HEALTH_SYSTEMCTL_COMMAND=$root/bin/systemctl \
    "$caddy_helper"
[[ "$(wc -l <"$root/curl.log")" -eq 2 ]]
grep -Fq -- '--ipv4 --silent --fail --connect-timeout 0.5 --max-time 0.75' "$root/curl.log"
grep -Fq -- '--resolve pihole0.local.theama.co:443:10.1.0.53' "$root/curl.log"
grep -Fq -- '--ipv6 --silent --fail --connect-timeout 0.5 --max-time 0.75' "$root/curl.log"
grep -Fq -- '--resolve pihole0.local.theama.co:443:[fd36:5aa8:6971:1::53]' "$root/curl.log"

printf 'transport\n' >"$root/caddy-mode"
if CADDY_SERVING_HEALTH_ENVIRONMENT_FILE=$root/environment \
    CADDY_SERVING_HEALTH_CURL_COMMAND=$root/bin/curl \
    CADDY_SERVING_HEALTH_SYSTEMCTL_COMMAND=$root/bin/systemctl \
    "$caddy_helper"; then
    exit 1
fi
printf 'http\n' >"$root/caddy-mode"
if CADDY_SERVING_HEALTH_ENVIRONMENT_FILE=$root/environment \
    CADDY_SERVING_HEALTH_CURL_COMMAND=$root/bin/curl \
    CADDY_SERVING_HEALTH_SYSTEMCTL_COMMAND=$root/bin/systemctl \
    "$caddy_helper"; then
    exit 1
fi
printf 'healthy\n' >"$root/caddy-mode"
printf 'inactive\n' >"$root/service-mode"
if CADDY_SERVING_HEALTH_ENVIRONMENT_FILE=$root/environment \
    CADDY_SERVING_HEALTH_CURL_COMMAND=$root/bin/curl \
    CADDY_SERVING_HEALTH_SYSTEMCTL_COMMAND=$root/bin/systemctl \
    "$caddy_helper"; then
    exit 1
fi
printf 'active\n' >"$root/service-mode"
printf '%s_caddy_entrypoint=true\n' "$prefix"

: >"$root/dig.log"
DNS_CHECK_DIG_COMMAND=$root/bin/dig \
    DNS_CHECK_SYSTEMCTL_COMMAND=$root/bin/systemctl \
    "$dns_helper"
[[ "$(wc -l <"$root/dig.log")" -eq 8 ]]
for health_server in 127.0.0.1 ::1; do
    for health_port in 53 5335; do
        grep -Fq -- "@$health_server -p $health_port pihole.local.theama.co A +short +time=1 +tries=1" "$root/dig.log"
        grep -Fq -- "@$health_server -p $health_port pihole.local.theama.co AAAA +short +time=1 +tries=1" "$root/dig.log"
    done
done
printf 'mismatch\n' >"$root/dns-mode"
if DNS_CHECK_DIG_COMMAND=$root/bin/dig \
    DNS_CHECK_SYSTEMCTL_COMMAND=$root/bin/systemctl \
    "$dns_helper"; then
    exit 1
fi
printf 'transport\n' >"$root/dns-mode"
if DNS_CHECK_DIG_COMMAND=$root/bin/dig \
    DNS_CHECK_SYSTEMCTL_COMMAND=$root/bin/systemctl \
    "$dns_helper"; then
    exit 1
fi
printf 'exact\n' >"$root/dns-mode"
printf '%s_dns_entrypoint=true\n' "$prefix"

for health_helper in "$caddy_helper" "$dns_helper"; do
    if grep -En 'mktemp|trap |STATUS_FILE|logger|status_file|write_status|current_phase' \
        "$health_helper"; then
        exit 1
    fi
done
if grep -En 'wait |&$' "$caddy_helper"; then
    exit 1
fi
[[ "$(grep -Ec '&$' "$dns_helper")" -eq 2 ]]
# shellcheck disable=SC2016
grep -Fq 'wait "$health_pid" || health_result=1' "$dns_helper"
printf '%s_minimal_probe_contract=true\n' "$prefix"

for keepalived_config in "$node_a_keepalived" "$node_b_keepalived"; do
    [[ "$(grep -Fc '        check-caddy' "$keepalived_config")" -eq 1 ]]
    [[ "$(grep -Fc '    script_user pi' "$keepalived_config")" -eq 1 ]]
    [[ "$(grep -Fc '    user keepalived_script caddy-tls' "$keepalived_config")" -eq 1 ]]
    [[ "$(grep -Fc '    interval 3' "$keepalived_config")" -eq 2 ]]
    [[ "$(grep -Fc '    timeout 2' "$keepalived_config")" -eq 2 ]]
    [[ "$(grep -Fc '    fall 2' "$keepalived_config")" -eq 2 ]]
    [[ "$(grep -Fc '    rise 3' "$keepalived_config")" -eq 2 ]]
done
printf '%s_keepalived_contract=true\n' "$prefix"

grep -Fq $'\t\t\thealth_uri /admin/' "$proxy_route"
grep -Fq $'\t\t\thealth_interval 30s' "$proxy_route"
grep -Fq $'\t\t\thealth_timeout 3s' "$proxy_route"
grep -Fq $'\t\t\thealth_status 200' "$proxy_route"
grep -Fq $'\t\t\thealth_follow_redirects' "$proxy_route"
grep -Fq $'\t\t\tfail_duration 30s' "$proxy_route"
printf '%s_native_backend_health=true\n' "$prefix"

PIHOLE_WEB_HEALTH_ENVIRONMENT_FILE=$root/environment \
    PIHOLE_WEB_HEALTH_STATE_DIRECTORY=$root/state \
    PIHOLE_WEB_HEALTH_RUNTIME_DIRECTORY=$root/run \
    PIHOLE_WEB_HEALTH_ENQUEUE_COMMAND=$root/bin/enqueue \
    PIHOLE_WEB_HEALTH_CURL_COMMAND=$root/bin/curl \
    PIHOLE_WEB_HEALTH_SYSTEMCTL_COMMAND=$root/bin/systemctl \
    "$web_helper" >/dev/null
printf 'failed\n' >"$root/web-mode"
PIHOLE_WEB_HEALTH_ENVIRONMENT_FILE=$root/environment \
    PIHOLE_WEB_HEALTH_STATE_DIRECTORY=$root/state \
    PIHOLE_WEB_HEALTH_RUNTIME_DIRECTORY=$root/run \
    PIHOLE_WEB_HEALTH_ENQUEUE_COMMAND=$root/bin/enqueue \
    PIHOLE_WEB_HEALTH_CURL_COMMAND=$root/bin/curl \
    PIHOLE_WEB_HEALTH_SYSTEMCTL_COMMAND=$root/bin/systemctl \
    "$web_helper" >/dev/null
grep -Fxq 'state=failed' "$root/state/state"
grep -Fq -- '--application Proxy' "$root/enqueue.log"
printf '%s_web_monitor_entrypoint=true\n' "$prefix"

while IFS=$'\t' read -r health_repository health_source health_target \
    health_mode health_hash health_lifecycle; do
    [[ -n "$health_repository" && "$health_repository" != \#* ]] || continue
    [[ "$health_target" = /* && "$health_mode" =~ ^0[0-7]{3}$ ]]
    [[ "$health_lifecycle" = production-candidate ]]
    health_root=$server_root
    [[ "$health_repository" = homelab-server-configs ]] || health_root=$dns_root
    [[ -f "$health_root/$health_source" && ! -L "$health_root/$health_source" ]]
    [[ "$(sha256sum "$health_root/$health_source" | awk '{ print $1 }')" = "$health_hash" ]]
done <"$caddy_root/manifests/serving-health-production.tsv"
printf '%s_candidate_manifest=true\n' "$prefix"
printf '%s_complete=true\n' "$prefix"
