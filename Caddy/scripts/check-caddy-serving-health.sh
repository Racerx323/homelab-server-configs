#!/usr/bin/env bash

set -Eeuo pipefail
set +x
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly environment_file=${CADDY_SERVING_HEALTH_ENVIRONMENT_FILE:-/etc/default/caddy-ha}
readonly curl_command=${CADDY_SERVING_HEALTH_CURL_COMMAND:-/usr/bin/curl}
readonly ss_command=${CADDY_SERVING_HEALTH_SS_COMMAND:-/usr/bin/ss}
readonly systemctl_command=${CADDY_SERVING_HEALTH_SYSTEMCTL_COMMAND:-/usr/bin/systemctl}
readonly status_file=${CADDY_SERVING_HEALTH_STATUS_FILE:-/run/caddy-serving-health/proxy/status}
readonly date_command=${CADDY_SERVING_HEALTH_DATE_COMMAND:-/usr/bin/date}
readonly logger_command=${CADDY_SERVING_HEALTH_LOGGER_COMMAND:-/usr/bin/logger}
status_recorded=false
current_phase=startup

journal_status_fallback() {
    local serving_health_result=$1
    local serving_health_component=$2
    local serving_health_check=$3
    local serving_health_failure_class=$4
    local serving_health_exit_status=$5

    "$logger_command" --tag caddy-serving-health --priority daemon.warning -- \
        "application=Proxy component=$serving_health_component check=$serving_health_check result=$serving_health_result failure_class=$serving_health_failure_class exit_status=$serving_health_exit_status status_record=unavailable"
    status_recorded=true
}

write_status() {
    local serving_health_result=$1
    local serving_health_component=$2
    local serving_health_check=$3
    local serving_health_failure_class=$4
    local serving_health_network=$5
    local serving_health_status=$6
    local serving_health_directory=${status_file%/*}
    local serving_health_temporary

    if [[ ! -d "$serving_health_directory" || -L "$serving_health_directory" ]]; then
        journal_status_fallback "$serving_health_result" "$serving_health_component" \
            "$serving_health_check" status-directory-invalid 1
        return 0
    fi
    serving_health_temporary=$(mktemp "$serving_health_directory/.status.XXXXXX") || {
        journal_status_fallback "$serving_health_result" "$serving_health_component" \
            "$serving_health_check" status-create-failed 1
        return 0
    }
    printf 'schema=caddy-serving-health-status/v1\napplication=Proxy\ncomponent=%s\ncheck=%s\nresult=%s\nfailure_class=%s\nnetwork=%s\nstatus=%s\nobserved_epoch=%s\n' \
        "$serving_health_component" "$serving_health_check" "$serving_health_result" \
        "$serving_health_failure_class" "$serving_health_network" \
        "$serving_health_status" "$($date_command +%s)" >"$serving_health_temporary" || {
        rm -f -- "$serving_health_temporary"
        journal_status_fallback "$serving_health_result" "$serving_health_component" \
            "$serving_health_check" status-write-failed 1
        return 0
    }
    if ! chmod 0644 "$serving_health_temporary" ||
        ! mv -fT -- "$serving_health_temporary" "$status_file"; then
        rm -f -- "$serving_health_temporary"
        journal_status_fallback "$serving_health_result" "$serving_health_component" \
            "$serving_health_check" status-commit-failed 1
        return 0
    fi
    status_recorded=true
}

# Invoked indirectly by the EXIT trap below.
# shellcheck disable=SC2317
record_phase_exit() {
    local serving_health_exit_status=$1

    trap - EXIT
    if [[ -n "${capture_root:-}" && "$capture_root" = /tmp/check-caddy-serving-health.* &&
        -d "$capture_root" && ! -L "$capture_root" ]]; then
        rm -rf -- "$capture_root" || true
    fi
    if [[ "$serving_health_exit_status" -ne 0 && "$status_recorded" != true ]]; then
        write_status failed Caddy "$current_phase" phase-operation-failed \
            'not applicable' "phase=$current_phase exit=$serving_health_exit_status"
    fi
    exit "$serving_health_exit_status"
}

trap 'record_phase_exit "$?"' EXIT

fail() {
    local serving_health_label=$1
    local serving_health_probe_status=${2:-}
    local serving_health_component=Caddy
    local serving_health_check=$serving_health_label
    local serving_health_failure_class=serving-check-failed
    local serving_health_network='not applicable'
    local serving_health_status="check=$serving_health_label"

    case "$serving_health_label" in
        environment) serving_health_failure_class=environment-invalid ;;
        service) serving_health_failure_class=service-inactive ;;
        ipv4_https)
            serving_health_check=trusted-https
            serving_health_failure_class=transport-failure
            serving_health_network="IPv4=${NODE_IPV4:-unknown}:443 endpoint=/healthz"
            serving_health_status="curl=$serving_health_probe_status"
            ;;
        ipv6_https)
            serving_health_check=trusted-https
            serving_health_failure_class=transport-failure
            serving_health_network="IPv6=[${NODE_IPV6:-unknown}]:443 endpoint=/healthz"
            serving_health_status="curl=$serving_health_probe_status"
            ;;
        ipv4_status)
            serving_health_check=http-status
            serving_health_failure_class=unexpected-http-status
            serving_health_network="IPv4=${NODE_IPV4:-unknown}:443 endpoint=/healthz"
            serving_health_status="http=$serving_health_probe_status"
            ;;
        ipv6_status)
            serving_health_check=http-status
            serving_health_failure_class=unexpected-http-status
            serving_health_network="IPv6=[${NODE_IPV6:-unknown}]:443 endpoint=/healthz"
            serving_health_status="http=$serving_health_probe_status"
            ;;
        ipv4_result_missing | ipv4_result_malformed)
            serving_health_check=probe-result
            serving_health_failure_class=probe-result-${serving_health_label##*_}
            serving_health_network="IPv4=${NODE_IPV4:-unknown}:443 endpoint=/healthz"
            serving_health_status="record=$serving_health_probe_status"
            ;;
        ipv6_result_missing | ipv6_result_malformed)
            serving_health_check=probe-result
            serving_health_failure_class=probe-result-${serving_health_label##*_}
            serving_health_network="IPv6=[${NODE_IPV6:-unknown}]:443 endpoint=/healthz"
            serving_health_status="record=$serving_health_probe_status"
            ;;
        ipv4_signal)
            serving_health_check=trusted-https
            serving_health_failure_class=signal
            serving_health_network="IPv4=${NODE_IPV4:-unknown}:443 endpoint=/healthz"
            serving_health_status="curl=$serving_health_probe_status signal=$((serving_health_probe_status - 128))"
            ;;
        ipv6_signal)
            serving_health_check=trusted-https
            serving_health_failure_class=signal
            serving_health_network="IPv6=[${NODE_IPV6:-unknown}]:443 endpoint=/healthz"
            serving_health_status="curl=$serving_health_probe_status signal=$((serving_health_probe_status - 128))"
            ;;
        ipv4_tcp_listener | ipv4_udp_listener)
            serving_health_check=listener
            serving_health_failure_class=listener-mismatch
            serving_health_network="IPv4=${NODE_IPV4:-unknown}:443"
            ;;
        ipv6_tcp_listener | ipv6_udp_listener)
            serving_health_check=listener
            serving_health_failure_class=listener-mismatch
            serving_health_network="IPv6=[${NODE_IPV6:-unknown}]:443"
            ;;
    esac
    case "$serving_health_probe_status" in
        7) serving_health_failure_class=connection-refusal ;;
        28) serving_health_failure_class=timeout ;;
        35 | 51 | 58 | 59 | 60 | 77 | 80 | 82 | 83 | 90 | 91)
            serving_health_failure_class=TLS-verification
            ;;
    esac
    write_status failed "$serving_health_component" "$serving_health_check" \
        "$serving_health_failure_class" "$serving_health_network" "$serving_health_status"
    printf 'caddy_serving_health_check_%s=false\n' "$serving_health_label" >&2
    exit 1
}

current_phase=environment-metadata
[[ -f "$environment_file" && ! -L "$environment_file" ]] || fail environment
current_phase=environment-load
# shellcheck disable=SC1090
source "$environment_file"
current_phase=environment-values
: "${NODE_FQDN:?missing NODE_FQDN}"
: "${NODE_IPV4:?missing NODE_IPV4}"
: "${NODE_IPV6:?missing NODE_IPV6}"
readonly NODE_FQDN NODE_IPV4 NODE_IPV6

current_phase=caddy-service
"$systemctl_command" is-active --quiet caddy.service || fail service

current_phase=capture-create
capture_root=$(mktemp -d /tmp/check-caddy-serving-health.XXXXXX)
readonly capture_root

probe() {
    local serving_health_family=$1
    local serving_health_address=$2
    local serving_health_output=$3

    local serving_health_error=${serving_health_output}.stderr
    local serving_health_status=0

    "$curl_command" "--ipv$serving_health_family" --silent --show-error \
        --fail --max-time 1 --max-redirs 0 --output /dev/null \
        --write-out '%{http_code}\n' \
        --resolve "$NODE_FQDN:443:$serving_health_address" \
        "https://$NODE_FQDN/healthz" >"$serving_health_output" \
        2>"$serving_health_error" || serving_health_status=$?
    printf '%s\n' "$serving_health_status" >"$serving_health_output.status"
    return "$serving_health_status"
}

validate_probe_result() {
    local serving_health_family=$1
    local serving_health_address=$2
    local serving_health_output=$3
    local serving_health_wait_ok=$4
    local serving_health_label_prefix=ipv4
    local serving_health_status_path=${serving_health_output}.status
    local serving_health_probe_status
    local serving_health_http_status

    [[ "$serving_health_family" = 4 ]] || serving_health_label_prefix=ipv6
    if [[ ! -f "$serving_health_status_path" || -L "$serving_health_status_path" ]]; then
        fail "${serving_health_label_prefix}_result_missing" status
    fi
    if [[ "$(wc -c <"$serving_health_status_path")" -gt 4 ]] ||
        ! grep -Eq '^(0|[1-9][0-9]{0,2})$' "$serving_health_status_path"; then
        fail "${serving_health_label_prefix}_result_malformed" status
    fi
    IFS= read -r serving_health_probe_status <"$serving_health_status_path" ||
        fail "${serving_health_label_prefix}_result_malformed" status
    if [[ "$serving_health_probe_status" -gt 255 ]]; then
        fail "${serving_health_label_prefix}_result_malformed" status
    fi
    if [[ "$serving_health_wait_ok" = true && "$serving_health_probe_status" -ne 0 ]] ||
        [[ "$serving_health_wait_ok" = false && "$serving_health_probe_status" -eq 0 ]]; then
        fail "${serving_health_label_prefix}_result_malformed" wait-status
    fi
    if [[ "$serving_health_probe_status" -ge 129 &&
        "$serving_health_probe_status" -le 192 ]]; then
        fail "${serving_health_label_prefix}_signal" "$serving_health_probe_status"
    fi
    if [[ "$serving_health_probe_status" -ne 0 ]]; then
        fail "${serving_health_label_prefix}_https" "$serving_health_probe_status"
    fi
    if [[ ! -f "$serving_health_output" || -L "$serving_health_output" ]]; then
        fail "${serving_health_label_prefix}_result_missing" output
    fi
    if [[ "$(wc -c <"$serving_health_output")" -gt 4 ]] ||
        ! grep -Eq '^[0-9]{3}$' "$serving_health_output"; then
        fail "${serving_health_label_prefix}_result_malformed" output
    fi
    IFS= read -r serving_health_http_status <"$serving_health_output" ||
        fail "${serving_health_label_prefix}_result_malformed" output
    [[ "$serving_health_http_status" = 204 ]] ||
        fail "${serving_health_label_prefix}_status" "$serving_health_http_status"
    printf 'family=%s address=%s curl=0 http=204\n' \
        "$serving_health_family" "$serving_health_address"
}

current_phase=probe-launch
probe 4 "$NODE_IPV4" "$capture_root/ipv4" &
ipv4_pid=$!
probe 6 "[$NODE_IPV6]" "$capture_root/ipv6" &
ipv6_pid=$!
readonly ipv4_pid ipv6_pid

ipv4_ok=true
ipv6_ok=true
current_phase=probe-wait
wait "$ipv4_pid" || ipv4_ok=false
wait "$ipv6_pid" || ipv6_ok=false
current_phase=probe-result
validate_probe_result 4 "$NODE_IPV4" "$capture_root/ipv4" "$ipv4_ok" >/dev/null
validate_probe_result 6 "$NODE_IPV6" "$capture_root/ipv6" "$ipv6_ok" >/dev/null

current_phase=listener-tcp-capture
"$ss_command" -H -ltn >"$capture_root/tcp"
current_phase=listener-udp-capture
"$ss_command" -H -lun >"$capture_root/udp"
current_phase=listener-validate
grep -Fq -- "$NODE_IPV4:443" "$capture_root/tcp" || fail ipv4_tcp_listener
grep -Fq -- "[$NODE_IPV6]:443" "$capture_root/tcp" || fail ipv6_tcp_listener
grep -Fq -- "$NODE_IPV4:443" "$capture_root/udp" || fail ipv4_udp_listener
grep -Fq -- "[$NODE_IPV6]:443" "$capture_root/udp" || fail ipv6_udp_listener

current_phase=status-healthy
write_status healthy Caddy serving-health none \
    "IPv4=$NODE_IPV4:443 IPv6=[$NODE_IPV6]:443 endpoint=/healthz" \
    'service=active https=204 listeners=present'

current_phase=completion-output
printf 'caddy_serving_health_check_service=true\n'
printf 'caddy_serving_health_check_ipv4_https=true\n'
printf 'caddy_serving_health_check_ipv6_https=true\n'
printf 'caddy_serving_health_check_listeners=true\n'
printf 'caddy_serving_health_complete=true\n'
