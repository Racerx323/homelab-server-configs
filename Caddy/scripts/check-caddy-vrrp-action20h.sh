#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export PATH
readonly PATH

readonly health_log_tag=caddy-ha-health
health_slow_stage_ms=1000
health_slow_total_ms=1500
readonly health_maximum_stream_bytes=4096
readonly health_maximum_stream_lines=32

health_runtime_root=
health_run_id=
health_stage=initialization
health_stage_started_ms=0
health_started_ms=0
health_last_status=0
health_failure_logged=false
health_test_mode=false

health_now_ms() { date +%s%3N; }
health_file_hash() { sha256sum "$1" | awk '{ print $1 }'; }
health_line_count() { awk 'END { print NR }' "$1"; }
health_stream_safe() {
    local health_safe_stream_path=$1

    [[ "$(wc -c <"$health_safe_stream_path")" -le "$health_maximum_stream_bytes" ]] || return 1
    [[ "$(health_line_count "$health_safe_stream_path")" -le "$health_maximum_stream_lines" ]] || return 1
    ! LC_ALL=C grep -n '[^[:print:][:space:]]' "$health_safe_stream_path" >/dev/null || return 1
    ! grep -Eqi \
        'BEGIN [A-Z ]*PRIVATE KEY|CADDY_TLS_PRIVATE_KEY_PEM|PRIVATE_KEY=|DOPPLER_TOKEN|Authorization:[[:space:]]*Bearer' \
        "$health_safe_stream_path" || return 1
}
health_log() {
    local health_log_message=$1

    if [[ "$health_test_mode" == true ]]; then
        printf 'caddy_ha_health_event=%s\n' "$health_log_message"
        return 0
    fi
    logger --tag "$health_log_tag" --priority daemon.warning -- "$health_log_message"
}
health_log_stream() {
    local health_stream_name=$1
    local health_stream_path=$2
    local health_stream_bytes
    local health_stream_lines
    local health_stream_sha256
    local health_stream_line

    health_stream_bytes=$(wc -c <"$health_stream_path") || return 1
    health_stream_lines=$(health_line_count "$health_stream_path") || return 1
    health_stream_sha256=$(health_file_hash "$health_stream_path") || return 1
    if ! health_stream_safe "$health_stream_path"; then
        health_log "event=stream run_id=$health_run_id stage=$health_stage stream=$health_stream_name classification=unsafe_suppressed bytes=$health_stream_bytes lines=$health_stream_lines sha256=$health_stream_sha256"
        return 0
    fi
    health_log "event=stream run_id=$health_run_id stage=$health_stage stream=$health_stream_name classification=bounded_safe bytes=$health_stream_bytes lines=$health_stream_lines sha256=$health_stream_sha256"
    [[ -s "$health_stream_path" ]] || return 0
    while IFS= read -r health_stream_line || [[ -n "$health_stream_line" ]]; do
        health_log "event=stream_content run_id=$health_run_id stage=$health_stage stream=$health_stream_name content=$health_stream_line"
    done <"$health_stream_path"
}
health_cleanup() {
    [[ -z "$health_runtime_root" ]] || rm -rf -- "$health_runtime_root"
}
health_on_signal() {
    local health_signal_name=$1
    local health_signal_status=$2
    local health_signal_now
    local health_signal_stage_elapsed
    local health_signal_total_elapsed

    health_signal_now=$(health_now_ms)
    health_signal_stage_elapsed=$((health_signal_now - health_stage_started_ms))
    health_signal_total_elapsed=$((health_signal_now - health_started_ms))
    health_log "event=terminated run_id=$health_run_id pid=$$ ppid=$PPID uid=$(id -u) gid=$(id -g) stage=$health_stage signal=$health_signal_name stage_elapsed_ms=$health_signal_stage_elapsed total_elapsed_ms=$health_signal_total_elapsed"
    health_failure_logged=true
    exit "$health_signal_status"
}
health_on_exit() {
    local health_exit_status=$?
    local health_exit_now
    local health_exit_total_elapsed

    if [[ -n "$health_run_id" ]]; then
        health_exit_now=$(health_now_ms)
        health_exit_total_elapsed=$((health_exit_now - health_started_ms))
        if [[ "$health_exit_status" -ne 0 && "$health_failure_logged" != true ]]; then
            health_log "event=helper_exit run_id=$health_run_id pid=$$ ppid=$PPID uid=$(id -u) gid=$(id -g) stage=$health_stage status=$health_exit_status total_elapsed_ms=$health_exit_total_elapsed"
        elif [[ "$health_exit_status" -eq 0 && "$health_exit_total_elapsed" -ge "$health_slow_total_ms" ]]; then
            health_log "event=helper_slow run_id=$health_run_id pid=$$ ppid=$PPID uid=$(id -u) gid=$(id -g) status=0 total_elapsed_ms=$health_exit_total_elapsed"
        fi
    fi
    health_cleanup
}
health_run_stage() {
    local health_stage_name=$1
    local health_stage_stdout
    local health_stage_stderr
    local health_stage_finished_ms
    local health_stage_elapsed_ms

    shift
    health_stage=$health_stage_name
    health_stage_started_ms=$(health_now_ms)
    health_stage_stdout=$health_runtime_root/$health_stage_name.stdout
    health_stage_stderr=$health_runtime_root/$health_stage_name.stderr
    : >"$health_stage_stdout"
    : >"$health_stage_stderr"
    chmod 0600 "$health_stage_stdout" "$health_stage_stderr"
    health_last_status=0
    "$@" >"$health_stage_stdout" 2>"$health_stage_stderr" || health_last_status=$?
    health_stage_finished_ms=$(health_now_ms)
    health_stage_elapsed_ms=$((health_stage_finished_ms - health_stage_started_ms))
    if [[ "$health_last_status" -ne 0 || "$health_stage_elapsed_ms" -ge "$health_slow_stage_ms" ]]; then
        health_log "event=stage run_id=$health_run_id pid=$$ ppid=$PPID uid=$(id -u) gid=$(id -g) stage=$health_stage status=$health_last_status elapsed_ms=$health_stage_elapsed_ms"
        health_log_stream stdout "$health_stage_stdout"
        health_log_stream stderr "$health_stage_stderr"
    fi
    if [[ "$health_last_status" -ne 0 ]]; then
        health_failure_logged=true
        cat "$health_stage_stderr" >&2
        return "$health_last_status"
    fi
    return 0
}
health_run_regression() {
    local health_regression_mode=$1

    health_test_mode=true
    health_started_ms=$(health_now_ms)
    health_stage_started_ms=$health_started_ms
    health_run_id="regression-$$"
    health_runtime_root=$(mktemp -d /tmp/caddy-health-instrumentation-regression.XXXXXX)
    install -d -m 0700 "$health_runtime_root/home" "$health_runtime_root/config" "$health_runtime_root/data"
    trap health_on_exit EXIT
    trap 'health_on_signal TERM 143' TERM
    case "$health_regression_mode" in
        success)
            health_run_stage service /bin/true
            ;;
        failure)
            health_run_stage validation /bin/false
            ;;
        slow)
            health_slow_stage_ms=0 health_run_stage endpoint /bin/true
            ;;
        term)
            health_stage=validation
            health_stage_started_ms=$(health_now_ms)
            health_on_signal TERM 143
            ;;
        *) return 64 ;;
    esac
}

case "${1:-}" in
    --self-test)
        [[ $# -eq 1 ]] || exit 64
        command -v date logger sha256sum systemctl curl >/dev/null
        printf 'caddy_ha_vrrp_health_self_test_complete=true\n'
        exit 0
        ;;
    --regression)
        [[ $# -eq 2 ]] || exit 64
        health_run_regression "$2"
        exit 0
        ;;
    "") [[ $# -eq 0 ]] || exit 64 ;;
    *)
        printf 'Usage: %s [--self-test|--regression success|failure|slow|term]\n' "${0##*/}" >&2
        exit 64
        ;;
esac

health_started_ms=$(health_now_ms)
health_stage_started_ms=$health_started_ms
health_run_id="${health_started_ms}-$$"
health_runtime_root=$(mktemp -d /tmp/caddy-health.XXXXXX)
trap health_on_exit EXIT
trap 'health_on_signal TERM 143' TERM
trap 'health_on_signal INT 130' INT
install -d -m 0700 "$health_runtime_root/home" "$health_runtime_root/config" "$health_runtime_root/data"
HOME=$health_runtime_root/home
XDG_CONFIG_HOME=$health_runtime_root/config
XDG_DATA_HOME=$health_runtime_root/data
export HOME XDG_CONFIG_HOME XDG_DATA_HOME

set -a
# shellcheck disable=SC1091
source /etc/default/caddy-ha
set +a

if ! health_run_stage service systemctl is-active --quiet caddy; then
    exit "$health_last_status"
fi
if ! health_run_stage endpoint curl \
    --insecure \
    --head \
    --fail \
    --silent \
    --show-error \
    --max-time 3 \
    https://localhost; then
    exit "$health_last_status"
fi
