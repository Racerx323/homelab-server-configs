#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH
readonly PATH

readonly prefix=serving_health_scheduled_execution_regression
test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
readonly repository_root=${test_directory%/Caddy/tests}
readonly workspace_root=${repository_root%/homelab-server-configs}
readonly successor_registry=$repository_root/Caddy/manifests/deployable-successor.tsv
IFS=$'\t' read -r successor_status successor_action transaction_relative < <(
    awk -F '\t' 'NR == 2 { print $2 "\t" $3 "\t" $5 }' "$successor_registry"
)
[[ "$successor_status" = defined && "$successor_action" = 35aa ]]
readonly transaction=$repository_root/$transaction_relative
root=$(mktemp -d /tmp/caddy-action35aa-scheduled-regression.XXXXXX)
readonly root
payload=$root/payload
evidence=$root/evidence
target=$root/target
bin=$root/bin
readonly payload evidence target bin

cleanup() {
    chmod -R u+rwX -- "$root" 2>/dev/null || true
    rm -rf -- "$root"
}
trap cleanup EXIT
trap 'printf "regression_failure_line=%s status=%s\n" "$LINENO" "$?" >&2' ERR

install -d -m 0700 "$payload/manifests" "$payload/repositories" "$evidence" "$bin"
install -m 0600 "$repository_root/Caddy/manifests/serving-health-production.tsv" \
    "$payload/manifests/serving-health-production.tsv"
install -m 0600 "$repository_root/Caddy/manifests/action35aa-node-b-quarantine.tsv" \
    "$payload/manifests/action35aa-node-b-quarantine.tsv"
while IFS=$'\t' read -r repository source _; do
    [[ "$repository" = '# repository' ]] && continue
    destination=$payload/repositories/$repository/$source
    install -d -m 0700 "${destination%/*}"
    install -m 0600 "$workspace_root/$repository/$source" "$destination"
done <"$repository_root/Caddy/manifests/serving-health-production.tsv"

install -d -m 0755 "$target/etc/scripts" "$target/usr/local/libexec" \
    "$target/etc/default" "$target/run/caddy-serving-health/dns" \
    "$target/run/caddy-serving-health/proxy"
install -m 0755 "$workspace_root/homelab-dns/Keepalived/scripts/dns-check.sh" \
    "$target/etc/scripts/check-dns.sh"
install -m 0755 "$repository_root/Caddy/scripts/check-caddy-serving-health.sh" \
    "$target/usr/local/libexec/check-caddy.sh"
printf 'NODE_FQDN=pihole00.local.theama.co\nNODE_IPV4=10.1.0.54\nNODE_IPV6=fd36:5aa8:6971:1::54\n' \
    >"$target/etc/default/caddy-ha"
chmod 0640 "$target/etc/default/caddy-ha"

cat >"$bin/runuser" <<'RUNUSER'
#!/usr/bin/env bash
set -Eeuo pipefail
[[ "$1" = -u ]]
identity=$2
group=default
shift 2
if [[ "$1" = -g ]]; then
    group=$2
    shift 2
fi
[[ "$1" = -- ]]
shift
printf '%s\t%s\n' "$identity" "$group" >>"${0%/*}/runuser.calls"
exec "$@"
RUNUSER
cat >"$bin/systemctl" <<'SYSTEMCTL'
#!/usr/bin/env bash
set -Eeuo pipefail
printf '%s\n' "$*" >>"${0%/*}/systemctl.calls"
[[ "$1" = is-active && "$2" = --quiet ]]
SYSTEMCTL
cat >"$bin/dig" <<'DIG'
#!/usr/bin/env bash
set -Eeuo pipefail
profile=$(<"${0%/*}/profile")
if [[ "$profile" = dns-intermittent ]]; then
    exec 9>"${0%/*}/counter.lock"
    flock 9
    counter=$(<"${0%/*}/counter")
    counter=$((counter + 1))
    printf '%s\n' "$counter" >"${0%/*}/counter"
    flock -u 9
    if [[ "$counter" -gt 8 && "$counter" -le 16 ]]; then
        exit 1
    fi
fi
case " $* " in
    *' A '*) printf '10.1.0.55\n' ;;
    *' AAAA '*) printf 'fd36:5aa8:6971:1::55\n' ;;
    *) exit 64 ;;
esac
DIG
cat >"$bin/curl" <<'CURL'
#!/usr/bin/env bash
set -Eeuo pipefail
[[ "$(<"${0%/*}/profile")" != caddy-failure ]] || exit 7
printf '204\n'
CURL
cat >"$bin/ss" <<'SS'
#!/usr/bin/env bash
printf 'LISTEN 0 4096 10.1.0.54:443 0.0.0.0:*\n'
printf 'LISTEN 0 4096 [fd36:5aa8:6971:1::54]:443 [::]:*\n'
SS
cat >"$bin/sleep" <<'SLEEP'
#!/usr/bin/env bash
set -Eeuo pipefail
[[ $# -eq 1 && "$1" =~ ^[0-9]+([.][0-9]+)?$ ]]
SLEEP
chmod 0700 "$bin/"*
: >"$bin/runuser.calls"
: >"$bin/systemctl.calls"

run_scheduled() {
    local scenario=$1
    local expected=$2
    local status=0

    rm -f -- "$evidence/"scheduled-* "$target/run/caddy-serving-health/dns/status" \
        "$target/run/caddy-serving-health/proxy/status"
    : >"$bin/runuser.calls"
    : >"$bin/systemctl.calls"
    printf '0\n' >"$bin/counter"
    printf '%s\n' "$scenario" >"$bin/profile"
    if ACTION35AA_PRODUCTION_PATH_TEST=1 \
        ACTION35AA_TARGET_ROOT=$target \
        ACTION35AA_RUNUSER_COMMAND=$bin/runuser \
        ACTION35AA_DNS_DIG_COMMAND=$bin/dig \
        ACTION35AA_CURL_COMMAND=$bin/curl \
        ACTION35AA_SS_COMMAND=$bin/ss \
        ACTION35AA_SYSTEMCTL_COMMAND=$bin/systemctl \
        ACTION35AA_SLEEP_COMMAND=$bin/sleep \
        /bin/bash "$transaction" scheduled-check node-b "$payload" "$evidence" \
        >"$root/$scenario.stdout" 2>"$root/$scenario.stderr"; then
        status=0
    else
        status=$?
    fi
    [[ "$status" -eq "$expected" || ("$expected" -eq 1 && "$status" -ne 0) ]]
    if grep -Fq 'reload keepalived.service' "$bin/systemctl.calls"; then
        return 1
    fi
    iconv -f UTF-8 -t UTF-8 "$root/$scenario.stderr" >/dev/null
    ! LC_ALL=C grep -Paq '[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]' \
        "$root/$scenario.stderr"
}

run_scheduled success 0
[[ "$(find "$evidence" -maxdepth 1 -name 'scheduled-*-*.tsv' | wc -l)" -eq 10 ]]
[[ "$(grep -c $'^pi\tdefault$' "$bin/runuser.calls")" -eq 5 ]]
[[ "$(grep -c $'^keepalived_script\tcaddy-tls$' "$bin/runuser.calls")" -eq 5 ]]
for cycle in 1 2 3 4 5; do
    dns_start=$(awk -F '\t' 'NR == 2 { print $3 }' "$evidence/scheduled-$cycle-dns.tsv")
    caddy_start=$(awk -F '\t' 'NR == 2 { print $3 }' "$evidence/scheduled-$cycle-caddy.tsv")
    delta=$((dns_start - caddy_start))
    ((delta < 0)) && delta=$((-delta))
    [[ "$delta" -lt 500000000 ]]
done

run_scheduled dns-intermittent 1
grep -Fq 'scheduled_2_dns_success=false' "$root/dns-intermittent.stderr"

run_scheduled caddy-failure 1
grep -Fq 'scheduled_1_caddy_success=false' "$root/caddy-failure.stderr"

cp -a "$target/etc/scripts/check-dns.sh" "$root/check-dns.real"
cat >"$target/etc/scripts/check-dns.sh" <<'TIMEOUT'
#!/usr/bin/env bash
/usr/bin/sleep 3
TIMEOUT
chmod 0755 "$target/etc/scripts/check-dns.sh"
run_scheduled success 1
grep -Fq $'true\tnone' "$evidence/scheduled-1-dns.tsv"

cat >"$target/etc/scripts/check-dns.sh" <<'SIGNAL'
#!/usr/bin/env bash
kill -TERM "$$"
SIGNAL
chmod 0755 "$target/etc/scripts/check-dns.sh"
run_scheduled success 1
grep -Eq $'\t(143|124)\t(false|true)\t(15|none)\t' "$evidence/scheduled-1-dns.tsv"

cat >"$target/etc/scripts/check-dns.sh" <<'STALE'
#!/usr/bin/env bash
exit 0
STALE
chmod 0755 "$target/etc/scripts/check-dns.sh"
run_scheduled success 1
grep -Fq 'scheduled_1_dns_success=false' "$root/success.stderr"
install -m 0755 "$root/check-dns.real" "$target/etc/scripts/check-dns.sh"

printf '%s_complete=true\n' "$prefix"
