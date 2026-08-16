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
root=$(mktemp -d /tmp/caddy-serving-health-regression.XXXXXX)
readonly root
trap 'rm -rf -- "$root"' EXIT

install -d -m 0700 "$root/bin" "$root/state" "$root/run"
printf 'NODE_FQDN=pihole0.local.theama.co\nNODE_IPV4=10.1.0.53\nNODE_IPV6=fd36:5aa8:6971:1::53\n' >"$root/environment"
printf 'healthy\n' >"$root/web-mode"
printf 'healthy\n' >"$root/caddy-mode"
printf 'exact\n' >"$root/dns-mode"
printf 'accept\n' >"$root/enqueue-mode"

cat >"$root/bin/systemctl" <<'EOF'
#!/usr/bin/env bash
[[ "$1" = is-active && "$2" = --quiet ]]
case "$3" in caddy.service | lighttpd.service | pihole-FTL.service | unbound.service) exit 0 ;; esac
exit 1
EOF
cat >"$root/bin/curl" <<EOF
#!/usr/bin/env bash
case " \$* " in *' --insecure '*) exit 64 ;; esac
case "\$*" in
    *'/admin/login.php'*)
        [[ "\$(<"$root/web-mode")" = healthy ]] || exit 22
        printf '200 https://pihole0.local.theama.co/admin/login.php\\n'
        ;;
    *'/healthz'*)
        if [[ "\$(<"$root/caddy-mode")" = fail-ipv6 && " \$* " = *' --ipv6 '* ]]; then
            exit 22
        fi
        printf '204\\n'
        ;;
    *) exit 2 ;;
esac
EOF
cat >"$root/bin/ss" <<'EOF'
#!/usr/bin/env bash
case "$*" in
    *-ltn*) printf 'LISTEN 0 4096 10.1.0.53:443 0.0.0.0:*\nLISTEN 0 4096 [fd36:5aa8:6971:1::53]:443 [::]:*\n' ;;
    *-lun*) printf 'UNCONN 0 0 10.1.0.53:443 0.0.0.0:*\nUNCONN 0 0 [fd36:5aa8:6971:1::53]:443 [::]:*\n' ;;
    *) exit 2 ;;
esac
EOF
cat >"$root/bin/enqueue" <<EOF
#!/usr/bin/env bash
[[ "\$(<"$root/enqueue-mode")" = accept ]] || exit 1
printf '%s\\n' "\$*" >>"$root/enqueue.log"
EOF
cat >"$root/bin/dig" <<EOF
#!/usr/bin/env bash
if [[ "\$(<"$root/dns-mode")" = extra ]]; then
    printf '10.1.0.55\n10.1.0.54\n'
    exit 0
fi
case " \$* " in
    *' A '*) printf '10.1.0.55\n' ;;
    *' AAAA '*) printf 'fd36:5aa8:6971:1::55\n' ;;
    *) exit 2 ;;
esac
EOF
chmod 0755 "$root/bin/"*

CADDY_SERVING_HEALTH_ENVIRONMENT_FILE=$root/environment \
    CADDY_SERVING_HEALTH_CURL_COMMAND=$root/bin/curl \
    CADDY_SERVING_HEALTH_SS_COMMAND=$root/bin/ss \
    CADDY_SERVING_HEALTH_SYSTEMCTL_COMMAND=$root/bin/systemctl \
    /usr/bin/timeout 2 /bin/bash "$caddy_helper" >"$root/caddy.out"
grep -Fxq 'caddy_serving_health_complete=true' "$root/caddy.out"
printf 'fail-ipv6\n' >"$root/caddy-mode"
if CADDY_SERVING_HEALTH_ENVIRONMENT_FILE=$root/environment \
    CADDY_SERVING_HEALTH_CURL_COMMAND=$root/bin/curl \
    CADDY_SERVING_HEALTH_SS_COMMAND=$root/bin/ss \
    CADDY_SERVING_HEALTH_SYSTEMCTL_COMMAND=$root/bin/systemctl \
    /usr/bin/timeout 2 /bin/bash "$caddy_helper" >/dev/null 2>&1; then
    exit 1
fi
printf 'healthy\n' >"$root/caddy-mode"
printf '%s_caddy_entrypoint=true\n' "$prefix"

PIHOLE_WEB_HEALTH_ENVIRONMENT_FILE=$root/environment \
    PIHOLE_WEB_HEALTH_STATE_DIRECTORY=$root/state \
    PIHOLE_WEB_HEALTH_RUNTIME_DIRECTORY=$root/run \
    PIHOLE_WEB_HEALTH_ENQUEUE_COMMAND=$root/bin/enqueue \
    PIHOLE_WEB_HEALTH_CURL_COMMAND=$root/bin/curl \
    PIHOLE_WEB_HEALTH_SYSTEMCTL_COMMAND=$root/bin/systemctl \
    /bin/bash "$web_helper" >"$root/web-healthy.out"
grep -Fxq 'state=healthy' "$root/state/state"

printf 'failed\n' >"$root/web-mode"
printf 'reject\n' >"$root/enqueue-mode"
PIHOLE_WEB_HEALTH_ENVIRONMENT_FILE=$root/environment \
    PIHOLE_WEB_HEALTH_STATE_DIRECTORY=$root/state \
    PIHOLE_WEB_HEALTH_RUNTIME_DIRECTORY=$root/run \
    PIHOLE_WEB_HEALTH_ENQUEUE_COMMAND=$root/bin/enqueue \
    PIHOLE_WEB_HEALTH_CURL_COMMAND=$root/bin/curl \
    PIHOLE_WEB_HEALTH_SYSTEMCTL_COMMAND=$root/bin/systemctl \
    /bin/bash "$web_helper" >"$root/web-pending.out"
grep -Fxq 'state=failed' "$root/state/state"
grep -Fxq 'failure_enqueued=false' "$root/state/state"
episode=$(sed -n 's/^episode=//p' "$root/state/state")
readonly episode

printf 'accept\n' >"$root/enqueue-mode"
PIHOLE_WEB_HEALTH_ENVIRONMENT_FILE=$root/environment \
    PIHOLE_WEB_HEALTH_STATE_DIRECTORY=$root/state \
    PIHOLE_WEB_HEALTH_RUNTIME_DIRECTORY=$root/run \
    PIHOLE_WEB_HEALTH_ENQUEUE_COMMAND=$root/bin/enqueue \
    PIHOLE_WEB_HEALTH_CURL_COMMAND=$root/bin/curl \
    PIHOLE_WEB_HEALTH_SYSTEMCTL_COMMAND=$root/bin/systemctl \
    /bin/bash "$web_helper" >"$root/web-enqueued.out"
grep -Fq -- "--stable-id $episode-failure" "$root/enqueue.log"
grep -Fxq 'failure_enqueued=true' "$root/state/state"

printf 'healthy\n' >"$root/web-mode"
PIHOLE_WEB_HEALTH_ENVIRONMENT_FILE=$root/environment \
    PIHOLE_WEB_HEALTH_STATE_DIRECTORY=$root/state \
    PIHOLE_WEB_HEALTH_RUNTIME_DIRECTORY=$root/run \
    PIHOLE_WEB_HEALTH_ENQUEUE_COMMAND=$root/bin/enqueue \
    PIHOLE_WEB_HEALTH_CURL_COMMAND=$root/bin/curl \
    PIHOLE_WEB_HEALTH_SYSTEMCTL_COMMAND=$root/bin/systemctl \
    /bin/bash "$web_helper" >"$root/web-recovery.out"
grep -Fq -- "--stable-id $episode-recovery" "$root/enqueue.log"
grep -Fxq 'state=healthy' "$root/state/state"
[[ "$(wc -l <"$root/enqueue.log")" -eq 2 ]]
printf '%s_web_transition_entrypoint=true\n' "$prefix"

if [[ -f "$dns_helper" ]]; then
    DNS_CHECK_DIG_COMMAND=$root/bin/dig \
        DNS_CHECK_SYSTEMCTL_COMMAND=$root/bin/systemctl \
        /bin/bash "$dns_helper" >"$root/dns.out"
    [[ "$(grep -c '^check=.* status=0 answer=' "$root/dns.out")" -eq 8 ]]
    printf 'extra\n' >"$root/dns-mode"
    if DNS_CHECK_DIG_COMMAND=$root/bin/dig \
        DNS_CHECK_SYSTEMCTL_COMMAND=$root/bin/systemctl \
        /usr/bin/timeout 2 /bin/bash "$dns_helper" >/dev/null 2>&1; then
        exit 1
    fi
    for keepalived_config in "$node_a_keepalived" "$node_b_keepalived"; do
        [[ "$(grep -Fc '        check-caddy' "$keepalived_config")" -eq 1 ]]
        [[ "$(grep -Fc '    interval 3' "$keepalived_config")" -eq 2 ]]
        [[ "$(grep -Fc '    timeout 2' "$keepalived_config")" -eq 2 ]]
        [[ "$(grep -Fc '    fall 2' "$keepalived_config")" -eq 2 ]]
        [[ "$(grep -Fc '    rise 3' "$keepalived_config")" -eq 2 ]]
        if grep -Fq 'lighttpd' "$keepalived_config"; then
            exit 1
        fi
    done
    printf '%s_dns_and_keepalived_entrypoints=true\n' "$prefix"
fi

grep -Fq 'User=pi' "$caddy_root/systemd/caddy-pihole-web-health.service"
grep -Fq 'StateDirectory=caddy-pihole-web-health' "$caddy_root/systemd/caddy-pihole-web-health.service"
grep -Fq 'OnUnitInactiveSec=30s' "$caddy_root/systemd/caddy-pihole-web-health.timer"
grep -Fq '@caddy_health path /healthz' "$caddy_root/configs/caddy/conf.d/10-pihole-admin.caddy"
printf '%s_systemd_and_route_contract=true\n' "$prefix"

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
