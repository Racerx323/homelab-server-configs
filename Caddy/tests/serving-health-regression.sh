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
readonly caddy_helper_source=$caddy_root/scripts/check-caddy-serving-health.sh
readonly web_helper_source=$caddy_root/scripts/check-pihole-web-health.sh
readonly dns_helper_source=$dns_root/Keepalived/scripts/dns-check.sh
readonly node_a_keepalived=$dns_root/Keepalived/configs/keepalived-pihole0.conf
readonly node_b_keepalived=$dns_root/Keepalived/configs/keepalived-pihole00.conf
readonly proxy_route=$caddy_root/configs/caddy/conf.d/10-pihole-admin.caddy
readonly web_service=$caddy_root/systemd/caddy-pihole-web-health.service
root=$(mktemp -d /tmp/caddy-serving-health-regression.XXXXXX)
readonly root
trap 'rm -rf -- "$root"' EXIT
trap 'printf "serving_health_regression_failure_line=%s status=%s\n" "$LINENO" "$?" >&2' ERR

install -d -m 0700 "$root/bin" "$root/state" "$root/run" "$root/installed"
install -m 0755 "$caddy_helper_source" "$root/installed/check-caddy.sh"
install -m 0755 "$web_helper_source" "$root/installed/check-pihole-web-health.sh"
install -m 0755 "$dns_helper_source" "$root/installed/check-dns.sh"
readonly caddy_helper=$root/installed/check-caddy.sh
readonly web_helper=$root/installed/check-pihole-web-health.sh
readonly dns_helper=$root/installed/check-dns.sh
cmp -s "$caddy_helper_source" "$caddy_helper"
cmp -s "$web_helper_source" "$web_helper"
cmp -s "$dns_helper_source" "$dns_helper"
[[ $(stat -c '%a' "$caddy_helper") = 755 ]]
[[ $(stat -c '%a' "$web_helper") = 755 ]]
[[ $(stat -c '%a' "$dns_helper") = 755 ]]
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
grep -Fq 'wait "${health_pids[$health_index]}"' "$dns_helper"
# shellcheck disable=SC2016
grep -Fq 'health_result=${health_codes[$health_index]}' "$dns_helper"
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
# The sole backend must remain eligible after an individual request failure.
if grep -Eq '^[[:space:]]*fail_duration[[:space:]]' "$proxy_route"; then
    exit 1
fi
grep -Fq $'\t\t\ttransport http {' "$proxy_route"
grep -Fq $'\t\t\t\tkeepalive off' "$proxy_route"
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

# Exercise each family independently through the actual monitor entrypoint.
cat >"$root/bin/curl" <<'EOF'
#!/usr/bin/env bash
case "$1" in --ipv4) family=4 ;; --ipv6) family=6 ;; *) exit 64 ;; esac
IFS=' ' read -r result_code result_status result_url <"$WEB_TEST_ROOT/result-$family"
printf '%s %s\n' "$result_status" "$result_url"
printf 'sensitive-diagnostic-must-not-escape\n' >&2
exit "$result_code"
EOF
export WEB_TEST_ROOT=$root
export PIHOLE_WEB_HEALTH_ENVIRONMENT_FILE=$root/environment
export PIHOLE_WEB_HEALTH_STATE_DIRECTORY=$root/state
export PIHOLE_WEB_HEALTH_RUNTIME_DIRECTORY=$root/run
export PIHOLE_WEB_HEALTH_ENQUEUE_COMMAND=$root/bin/enqueue
export PIHOLE_WEB_HEALTH_CURL_COMMAND=$root/bin/curl
export PIHOLE_WEB_HEALTH_SYSTEMCTL_COMMAND=$root/bin/systemctl

while IFS='|' read -r test_v4 test_v6 expected_class expected_results; do
    rm -f -- "$root/state/state"
    : >"$root/enqueue.log"
    printf '%s https://pihole0.local.theama.co/admin/login.php\n' "$test_v4" >"$root/result-4"
    printf '%s https://pihole0.local.theama.co/admin/login.php\n' "$test_v6" >"$root/result-6"
    "$web_helper" >"$root/web-output" 2>&1
    grep -Fq -- "--failure-class $expected_class" "$root/enqueue.log"
    grep -Fq -- "$expected_results" "$root/enqueue.log"
    grep -Fq -- "$expected_results" "$root/web-output"
    "$web_helper" >>"$root/web-output" 2>&1
    [[ "$(wc -l <"$root/enqueue.log")" -eq 1 ]]
    printf '0 200 https://pihole0.local.theama.co/admin/login.php\n' >"$root/result-4"
    cp "$root/result-4" "$root/result-6"
    "$web_helper" >>"$root/web-output" 2>&1
    grep -Fxq 'state=healthy' "$root/state/state"
    grep -Fq -- '--event recovery' "$root/enqueue.log"
    [[ "$(wc -l <"$root/enqueue.log")" -eq 2 ]]
    "$web_helper" >>"$root/web-output" 2>&1
    [[ "$(wc -l <"$root/enqueue.log")" -eq 2 ]]
    if grep -Fq 'sensitive-diagnostic' "$root/enqueue.log" "$root/web-output"; then
        exit 1
    fi
done <<'EOF'
22 503|0 200|ipv4|IPv4=http-503 IPv6=healthy
0 200|22 503|ipv6|IPv4=healthy IPv6=http-503
22 503|22 503|dual-stack|IPv4=http-503 IPv6=http-503
7 000|60 000|dual-stack|IPv4=connection-error IPv6=tls-error
28 200|0 200|ipv4|IPv4=timeout IPv6=healthy
0 302|47 302|dual-stack|IPv4=http-302 IPv6=redirect-error
0 broken|56 000|dual-stack|IPv4=invalid-result IPv6=curl-error-56
EOF
# A redirect landing on another page must not be mistaken for healthy.
printf '0 200 https://example.invalid/private\n' >"$root/result-6"
"$web_helper" >"$root/web-output" 2>&1
grep -Fq 'IPv4=healthy IPv6=unexpected-terminal' "$root/enqueue.log"
if grep -Fq 'example.invalid' "$root/enqueue.log" "$root/web-output"; then
    exit 1
fi
# Failed enqueue remains pending; retry and recovery retain one episode.
printf 'reject\n' >"$root/enqueue-mode"
rm -f -- "$root/state/state"
: >"$root/enqueue.log"
"$web_helper" >/dev/null
grep -Fxq 'failure_enqueued=false' "$root/state/state"
health_episode=$(sed -n 's/^episode=//p' "$root/state/state")
printf 'accept\n' >"$root/enqueue-mode"
"$web_helper" >/dev/null
grep -Fq -- "--stable-id $health_episode-failure" "$root/enqueue.log"
printf '0 200 https://pihole0.local.theama.co/admin/login.php\n' >"$root/result-6"
"$web_helper" >/dev/null
grep -Fq -- "--stable-id $health_episode-recovery" "$root/enqueue.log"
printf '%s_web_family_classification=true\n' "$prefix"

grep -Fxq 'ReadWritePaths=/var/lib/caddy-apprise-queue' "$web_service"
grep -Fxq 'User=pi' "$web_service"
grep -Fxq 'Group=pi' "$web_service"
grep -Fxq 'SupplementaryGroups=caddy-tls' "$web_service"
if grep -Fq '/run/caddy-apprise' "$web_service"; then
    exit 1
fi
grep -Fxq 'RuntimeDirectory=caddy-pihole-web-health' "$web_service"
grep -Fxq 'StateDirectory=caddy-pihole-web-health' "$web_service"
printf '%s_web_monitor_namespace_and_identity_contract=true\n' "$prefix"

while IFS=$'\t' read -r health_repository health_source health_target \
    health_mode health_hash health_lifecycle; do
    [[ -n "$health_repository" && "$health_repository" != \#* ]] || continue
    [[ "$health_target" = /* && "$health_mode" =~ ^0[0-7]{3}$ ]]
    [[ "$health_lifecycle" = production-current ]]
    health_root=$server_root
    [[ "$health_repository" = homelab-server-configs ]] || health_root=$dns_root
    [[ -f "$health_root/$health_source" && ! -L "$health_root/$health_source" ]]
    if [[ "$health_source" = Caddy/scripts/check-pihole-web-health.sh ]]; then
        # Source may advance before deployment; accepted identities stay pinned.
        health_source_hash=$(awk -F '\t' '$1 == "node_a_pihole_web_health_helper" { print $6 }' "$caddy_root/manifests/production-artifacts.tsv")
        health_deployed_hash=$(awk -F '\t' '$1 == "node_a_pihole_web_health_helper" { print $7 }' "$caddy_root/manifests/production-artifacts.tsv")
        [[ "$health_deployed_hash" = "$health_hash" ]]
    else
        health_source_hash=$health_hash
    fi
    [[ "$(sha256sum "$health_root/$health_source" | awk '{ print $1 }')" = "$health_source_hash" ]]
done <"$caddy_root/manifests/serving-health-production.tsv"
printf '%s_accepted_manifest=true\n' "$prefix"
printf '%s_complete=true\n' "$prefix"
