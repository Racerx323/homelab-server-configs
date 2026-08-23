#!/usr/bin/env bash

set -Eeuo pipefail
set +x
PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH
readonly PATH

readonly prefix=keepalived_tracking_script_lifecycle_regression
test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
readonly caddy_root=${test_directory%/tests}
readonly server_root=${caddy_root%/Caddy}
readonly dns_root=${server_root%/homelab-server-configs}/homelab-dns
readonly caddy_helper=$caddy_root/scripts/check-caddy-serving-health.sh
readonly dns_helper=$dns_root/Keepalived/scripts/dns-check.sh
root=$(mktemp -d /tmp/keepalived-tracking-lifecycle.XXXXXX)
readonly root
trap 'rm -rf -- "$root"' EXIT
trap 'printf "%s_failure_line=%s status=%s\n" "$prefix" "$LINENO" "$?" >&2' ERR
chmod 0755 "$root"
residue_before=$(find /tmp -maxdepth 1 -type d \
    \( -name 'check-caddy-serving-health.*' -o -name 'check-dns.*' \) \
    -printf '%f\n' | sort)
readonly residue_before

install -d -m 0755 "$root/bin"
printf 'NODE_FQDN=pihole0.local.theama.co\nNODE_IPV4=10.1.0.53\nNODE_IPV6=fd36:5aa8:6971:1::53\n' >"$root/environment"
chmod 0644 "$root/environment"
printf 'healthy\n' >"$root/mode"
touch "$root/caddy-entered" "$root/dns-entered" "$root/identity.log"
chmod 0666 "$root/mode" "$root/caddy-entered" "$root/dns-entered" "$root/identity.log"

cat >"$root/bin/systemctl" <<'EOF'
#!/usr/bin/env bash
[[ "$1" = is-active && "$2" = --quiet ]]
case "$3" in caddy.service | pihole-FTL.service | unbound.service) exit 0 ;; esac
exit 1
EOF
cat >"$root/bin/curl" <<EOF
#!/usr/bin/env bash
printf 'caddy uid=%s gid=%s pgid=%s\n' "\$(id -u)" "\$(id -g)" \
    "\$(ps -o pgid= -p \$\$ | tr -d ' ')" >>"$root/identity.log"
printf 'entered\n' >"$root/caddy-entered"
case "\$(<"$root/mode")" in
    healthy) printf '204' ;;
    block) sleep 30 ;;
    ignore-term)
        trap '' TERM
        while :; do sleep 1; done
        ;;
    *) exit 2 ;;
esac
EOF
cat >"$root/bin/dig" <<EOF
#!/usr/bin/env bash
printf 'dns uid=%s gid=%s pgid=%s\n' "\$(id -u)" "\$(id -g)" \
    "\$(ps -o pgid= -p \$\$ | tr -d ' ')" >>"$root/identity.log"
printf 'entered\n' >"$root/dns-entered"
case "\$(<"$root/mode")" in
    healthy)
        case " \$* " in
            *' A '*) printf '10.1.0.55\n' ;;
            *' AAAA '*) printf 'fd36:5aa8:6971:1::55\n' ;;
            *) exit 2 ;;
        esac
        ;;
    block) sleep 30 ;;
    *) exit 2 ;;
esac
EOF
chmod 0755 "$root/bin/"*

wait_for_nonempty() {
    local lifecycle_path=$1
    local lifecycle_attempt

    for ((lifecycle_attempt = 0; lifecycle_attempt < 100; lifecycle_attempt++)); do
        [[ -s "$lifecycle_path" ]] && return 0
        sleep 0.02
    done
    return 1
}

group_exists() {
    local lifecycle_group=$1

    ps -eo pgid= | awk -v group="$lifecycle_group" \
        '$1 == group { found = 1 } END { exit !found }'
}

wait_for_group_exit() {
    local lifecycle_group=$1
    local lifecycle_attempt

    for ((lifecycle_attempt = 0; lifecycle_attempt < 100; lifecycle_attempt++)); do
        group_exists "$lifecycle_group" || return 0
        sleep 0.02
    done
    return 1
}

declare -a caddy_identity=()
declare -a dns_identity=()
caddy_expected_uid=$(id -u)
caddy_expected_gid=$(id -g)
dns_expected_uid=$caddy_expected_uid
dns_expected_gid=$caddy_expected_gid
if [[ $(id -u) -eq 0 ]]; then
    if id keepalived_script >/dev/null 2>&1 && getent group caddy-tls >/dev/null; then
        caddy_expected_uid=$(id -u keepalived_script)
        caddy_expected_gid=$(getent group caddy-tls | awk -F: '{ print $3 }')
    else
        caddy_expected_uid=19001
        caddy_expected_gid=19002
    fi
    if id pi >/dev/null 2>&1; then
        dns_expected_uid=$(id -u pi)
        dns_expected_gid=$(id -g pi)
    else
        dns_expected_uid=19003
        dns_expected_gid=19003
    fi
    caddy_identity=(/usr/bin/setpriv --reuid="$caddy_expected_uid"
        --regid="$caddy_expected_gid" --clear-groups)
    dns_identity=(/usr/bin/setpriv --reuid="$dns_expected_uid"
        --regid="$dns_expected_gid" --clear-groups)
fi
readonly caddy_expected_uid caddy_expected_gid dns_expected_uid dns_expected_gid

printf 'block\n' >"$root/mode"
: >"$root/caddy-entered"
setsid "${caddy_identity[@]}" env \
    "CADDY_SERVING_HEALTH_ENVIRONMENT_FILE=$root/environment" \
    "CADDY_SERVING_HEALTH_CURL_COMMAND=$root/bin/curl" \
    "CADDY_SERVING_HEALTH_SYSTEMCTL_COMMAND=$root/bin/systemctl" \
    "$caddy_helper" &
caddy_pid=$!
wait_for_nonempty "$root/caddy-entered"
kill -TERM -- "-$caddy_pid"
if wait "$caddy_pid"; then
    exit 1
else
    caddy_status=$?
fi
[[ "$caddy_status" -eq 143 ]]
wait_for_group_exit "$caddy_pid"
printf '%s_caddy_sigterm_group_exit=true\n' "$prefix"

printf 'block\n' >"$root/mode"
: >"$root/dns-entered"
setsid "${dns_identity[@]}" env \
    "DNS_CHECK_DIG_COMMAND=$root/bin/dig" \
    "DNS_CHECK_SYSTEMCTL_COMMAND=$root/bin/systemctl" \
    "$dns_helper" &
dns_pid=$!
wait_for_nonempty "$root/dns-entered"
kill -TERM -- "-$dns_pid"
if wait "$dns_pid"; then
    exit 1
else
    dns_status=$?
fi
[[ "$dns_status" -eq 143 ]]
wait_for_group_exit "$dns_pid"
printf '%s_dns_sigterm_group_exit=true\n' "$prefix"

printf 'ignore-term\n' >"$root/mode"
: >"$root/caddy-entered"
setsid "${caddy_identity[@]}" env \
    "CADDY_SERVING_HEALTH_ENVIRONMENT_FILE=$root/environment" \
    "CADDY_SERVING_HEALTH_CURL_COMMAND=$root/bin/curl" \
    "CADDY_SERVING_HEALTH_SYSTEMCTL_COMMAND=$root/bin/systemctl" \
    "$caddy_helper" &
stubborn_pid=$!
wait_for_nonempty "$root/caddy-entered"
timeout_started=$(date +%s)
kill -TERM -- "-$stubborn_pid"
if wait "$stubborn_pid"; then
    exit 1
else
    stubborn_status=$?
fi
[[ "$stubborn_status" -eq 143 ]]
group_exists "$stubborn_pid"
sleep 2
kill -KILL -- "-$stubborn_pid"
wait_for_group_exit "$stubborn_pid"
timeout_finished=$(date +%s)
((timeout_finished - timeout_started >= 2))
printf '%s_sigkill_escalation_boundary=true\n' "$prefix"

printf 'healthy\n' >"$root/mode"
: >"$root/identity.log"
for lifecycle_cycle in 1 2 3; do
    setsid "${caddy_identity[@]}" env \
        "CADDY_SERVING_HEALTH_ENVIRONMENT_FILE=$root/environment" \
        "CADDY_SERVING_HEALTH_CURL_COMMAND=$root/bin/curl" \
        "CADDY_SERVING_HEALTH_SYSTEMCTL_COMMAND=$root/bin/systemctl" \
        "$caddy_helper" &
    scheduled_caddy_pid=$!
    setsid "${dns_identity[@]}" env \
        "DNS_CHECK_DIG_COMMAND=$root/bin/dig" \
        "DNS_CHECK_SYSTEMCTL_COMMAND=$root/bin/systemctl" \
        "$dns_helper" &
    scheduled_dns_pid=$!
    wait "$scheduled_caddy_pid"
    wait "$scheduled_dns_pid"
    [[ "$lifecycle_cycle" -eq 3 ]] || sleep 3
done
[[ "$(grep -c '^caddy ' "$root/identity.log")" -eq 6 ]]
[[ "$(grep -c '^dns ' "$root/identity.log")" -eq 24 ]]
grep -Eq "^caddy uid=$caddy_expected_uid gid=$caddy_expected_gid pgid=[0-9]+$" \
    "$root/identity.log"
grep -Eq "^dns uid=$dns_expected_uid gid=$dns_expected_gid pgid=[0-9]+$" \
    "$root/identity.log"
printf '%s_three_second_repeated_execution=true\n' "$prefix"
printf '%s_identity_boundary=true\n' "$prefix"

printf 'failed\n' >"$root/mode"
if setsid "${caddy_identity[@]}" env \
    "CADDY_SERVING_HEALTH_ENVIRONMENT_FILE=$root/environment" \
    "CADDY_SERVING_HEALTH_CURL_COMMAND=$root/bin/curl" \
    "CADDY_SERVING_HEALTH_SYSTEMCTL_COMMAND=$root/bin/systemctl" \
    "$caddy_helper"; then
    exit 1
else
    caddy_failure_status=$?
fi
[[ "$caddy_failure_status" -eq 20 ]]
if setsid "${dns_identity[@]}" env \
    "DNS_CHECK_DIG_COMMAND=$root/bin/dig" \
    "DNS_CHECK_SYSTEMCTL_COMMAND=$root/bin/systemctl" \
    "$dns_helper"; then
    exit 1
else
    dns_failure_status=$?
fi
[[ "$dns_failure_status" -eq 20 ]]
printf '%s_distinct_failure_codes=true\n' "$prefix"

residue_after=$(find /tmp -maxdepth 1 -type d \
    \( -name 'check-caddy-serving-health.*' -o -name 'check-dns.*' \) \
    -printf '%f\n' | sort)
[[ "$residue_after" = "$residue_before" ]]
printf '%s_zero_helper_residue=true\n' "$prefix"
printf '%s_complete=true\n' "$prefix"
