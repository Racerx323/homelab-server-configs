#!/usr/bin/env bash
# ssh-local-evidence-contract-v1

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=serving_health_deployment_outer
readonly transaction_sha256=89a5c89820e1d8139b915a310fe8073d241dca552dc900ac6a73ec53154fde0f
readonly operation_sha256=d561a3f4fb5457b7902b31398868f3a65775d575005053779f261fc1149c233b
node_a_host=pi@10.1.0.53
node_b_host=pi@10.1.0.54
apprise_host=pi@10.1.3.83
readonly max_stream_bytes=1048576
readonly continuity_retry_window_seconds=12

usage() {
    printf 'Usage: %s [--production-path-test]\n' "${0##*/}" >&2
}

regular_file() {
    [[ -f "$1" && ! -L "$1" ]]
}

safe_capture() {
    local serving_health_path=$1

    regular_file "$serving_health_path"
    [[ "$(stat -c '%s' "$serving_health_path")" -le "$max_stream_bytes" ]]
    iconv -f UTF-8 -t UTF-8 "$serving_health_path" >/dev/null
    ! LC_ALL=C grep -Paq '[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]' "$serving_health_path"
}

capture() {
    local serving_health_label=$1
    shift
    local serving_health_stdout=$workstation_evidence/$serving_health_label.stdout
    local serving_health_stderr=$workstation_evidence/$serving_health_label.stderr
    local serving_health_status=$workstation_evidence/$serving_health_label.status
    local serving_health_rc=0

    : >"$serving_health_stdout"
    : >"$serving_health_stderr"
    if "$@" >"$serving_health_stdout" 2>"$serving_health_stderr"; then
        serving_health_rc=0
    else
        serving_health_rc=$?
    fi
    printf '%s\n' "$serving_health_rc" >"$serving_health_status"
    chmod 0600 "$serving_health_stdout" "$serving_health_stderr" "$serving_health_status"
    safe_capture "$serving_health_stdout"
    safe_capture "$serving_health_stderr"
    return "$serving_health_rc"
}

build_payload() {
    local serving_health_repository serving_health_source serving_health_target serving_health_mode
    local serving_health_hash serving_health_lifecycle serving_health_source_path serving_health_destination

    install -d -m 0700 "$payload_stage/manifests" "$payload_stage/repositories"
    if [[ "$operation_scope" = external-notification-attribution-read-only ]]; then
        printf 'read-only external attribution; no production payload\n' \
            >"$payload_stage/manifests/README"
        chmod 0600 "$payload_stage/manifests/README"
        tar --sort=name --mtime='UTC 1970-01-01' --owner=0 --group=0 --numeric-owner \
            -C "$payload_stage" -cf "$payload_archive" .
        chmod 0600 "$payload_archive"
        sha256sum "$payload_archive" >"$workstation_evidence/payload.sha256"
        chmod 0600 "$workstation_evidence/payload.sha256"
        return
    fi
    if [[ "$operation_scope" = pihole-web-health-unit-only ]]; then
        {
            sed -n '1p' "$repository_root/Caddy/manifests/serving-health-production.tsv"
            awk -F '\t' '
                $2 == "Caddy/systemd/caddy-pihole-web-health.service" { print }
            ' "$repository_root/Caddy/manifests/serving-health-production.tsv"
        } >"$payload_stage/manifests/serving-health-production.tsv"
        [[ "$(wc -l <"$payload_stage/manifests/serving-health-production.tsv")" -eq 2 ]]
        chmod 0600 "$payload_stage/manifests/serving-health-production.tsv"
    elif [[ "$operation_scope" = notification-standardization-only ]]; then
        {
            sed -n '1p' "$repository_root/Caddy/manifests/serving-health-production.tsv"
            awk -F '\t' '
                $2 == "Caddy/scripts/caddy-apprise-enqueue.sh" ||
                $2 == "Caddy/scripts/caddy-apprise-delivery-worker.sh" ||
                $2 == "Caddy/configs/tmpfiles.d/caddy-ha.conf" ||
                $2 == "Caddy/scripts/check-caddy-serving-health.sh" ||
                $2 == "Keepalived/scripts/dns-check.sh" ||
                $2 == "Keepalived/scripts/keepalived-notify.sh" { print }
            ' "$repository_root/Caddy/manifests/serving-health-production.tsv"
        } >"$payload_stage/manifests/serving-health-production.tsv"
        [[ "$(wc -l <"$payload_stage/manifests/serving-health-production.tsv")" -eq 7 ]]
        chmod 0600 "$payload_stage/manifests/serving-health-production.tsv"
    else
        install -m 0600 "$repository_root/Caddy/manifests/serving-health-production.tsv" \
            "$payload_stage/manifests/serving-health-production.tsv"
    fi
    install -m 0600 "$repository_root/Caddy/manifests/production-artifacts.tsv" \
        "$payload_stage/manifests/production-artifacts.tsv"
    install -m 0600 "$repository_root/Caddy/manifests/current-live-state.tsv" \
        "$payload_stage/manifests/current-live-state.tsv"
    install -m 0600 "$repository_root/Caddy/manifests/serving-health-quarantine-baseline.tsv" \
        "$payload_stage/manifests/serving-health-quarantine-baseline.tsv"
    while IFS=$'\t' read -r serving_health_repository serving_health_source serving_health_target \
        serving_health_mode serving_health_hash serving_health_lifecycle; do
        [[ "$serving_health_repository" = '# repository' ]] && continue
        [[ "$serving_health_mode" =~ ^0[0-7]{3}$ && "$serving_health_lifecycle" = production-current ]]
        [[ "$serving_health_target" = /* ]]
        serving_health_source_path=${workspace_root}/$serving_health_repository/$serving_health_source
        regular_file "$serving_health_source_path"
        [[ "$(sha256sum "$serving_health_source_path" | awk '{ print $1 }')" = "$serving_health_hash" ]]
        serving_health_destination=$payload_stage/repositories/$serving_health_repository/$serving_health_source
        install -d -m 0700 "$(dirname -- "$serving_health_destination")"
        install -m 0600 "$serving_health_source_path" "$serving_health_destination"
    done <"$repository_root/Caddy/manifests/serving-health-production.tsv"
    tar --sort=name --mtime='UTC 1970-01-01' --owner=0 --group=0 --numeric-owner \
        -C "$payload_stage" -cf "$payload_archive" .
    chmod 0600 "$payload_archive"
    sha256sum "$payload_archive" >"$workstation_evidence/payload.sha256"
    chmod 0600 "$workstation_evidence/payload.sha256"
}

write_remote_programs() {
    cat >"$prepare_program" <<'PROGRAM'
set -Eeuo pipefail
umask 077
readonly remote_root=$1
readonly archive=$2
case "$remote_root" in /tmp/caddy-serving-health-*) ;; *) exit 64 ;; esac
case "$archive" in /tmp/caddy-serving-health-*.tar) ;; *) exit 64 ;; esac
[[ ! -e "$remote_root" && ! -L "$remote_root" ]]
[[ ! -e "$archive" && ! -L "$archive" ]]
install -d -m 0700 "$remote_root"
PROGRAM
    cat >"$accept_program" <<'PROGRAM'
set -Eeuo pipefail
umask 077
readonly remote_root=$1
readonly archive=$2
readonly expected_hash=$3
case "$remote_root" in /tmp/caddy-serving-health-*) ;; *) exit 64 ;; esac
case "$archive" in /tmp/caddy-serving-health-*.tar) ;; *) exit 64 ;; esac
[[ -d "$remote_root" && ! -L "$remote_root" ]]
[[ -f "$archive" && ! -L "$archive" ]]
expected_metadata=pi:pi:600
if [[ "${CADDY_SERVING_HEALTH_PRODUCTION_PATH_TEST:-0}" = 1 ]]; then
    expected_metadata="$(id -un):$(id -gn):600"
fi
[[ "$(stat -c '%U:%G:%a' "$archive")" = "$expected_metadata" ]]
[[ "$(sha256sum "$archive" | awk '{ print $1 }')" = "$expected_hash" ]]
tar -C "$remote_root" --no-same-owner --no-same-permissions -xf "$archive"
rm -f -- "$archive"
find "$remote_root" -type d -exec chmod 0700 {} +
find "$remote_root" -type f -exec chmod 0600 {} +
install -d -m 0700 "$remote_root/evidence"
PROGRAM
    cat >"$disposition_program" <<'PROGRAM'
set -Eeuo pipefail
readonly remote_root=$1
readonly archive=$2
case "$remote_root" in /tmp/caddy-serving-health-*) ;; *) exit 64 ;; esac
case "$archive" in /tmp/caddy-serving-health-*.tar) ;; *) exit 64 ;; esac
if [[ -e "$remote_root" || -L "$remote_root" ]]; then
    [[ -d "$remote_root" && ! -L "$remote_root" ]]
    rm -rf -- "$remote_root"
fi
if [[ -e "$archive" || -L "$archive" ]]; then
    [[ -f "$archive" && ! -L "$archive" ]]
    rm -f -- "$archive"
fi
PROGRAM
    cat >"$readback_program" <<'PROGRAM'
set -Eeuo pipefail
readonly evidence_root=$1
case "$evidence_root" in /tmp/caddy-serving-health-*) ;; *) exit 64 ;; esac
[[ -d "$evidence_root" && ! -L "$evidence_root" ]]
find "$evidence_root" -maxdepth 1 -type f \
    \( -name '*.stdout' -o -name '*.stderr' -o -name '*.status' \
       -o -name '*.tsv' \) -print0 | LC_ALL=C sort -z |
while IFS= read -r -d '' file; do
    [[ ! -L "$file" && "$(stat -c '%s' "$file")" -le 1048576 ]]
    printf 'file=%s bytes=%s sha256=%s\n' "${file##*/}" \
        "$(stat -c '%s' "$file")" "$(sha256sum "$file" | awk '{ print $1 }')"
    base64 -w 0 "$file"
    printf '\n'
done
PROGRAM
    cat >"$external_accept_program" <<'PROGRAM'
set -Eeuo pipefail
umask 077
readonly remote_program=$1
readonly expected_hash=$2
readonly evidence_root=$3
case "$remote_program" in /tmp/caddy-notification-attribution-*.sh) ;; *) exit 64 ;; esac
case "$evidence_root" in /tmp/caddy-serving-health-*) ;; *) exit 64 ;; esac
[[ -f "$remote_program" && ! -L "$remote_program" ]]
[[ "$(stat -c '%a' "$remote_program")" = 755 ]]
expected_owner=pi:pi
if [[ "${CADDY_SERVING_HEALTH_PRODUCTION_PATH_TEST:-0}" = 1 ]]; then
    expected_owner=$(id -un):$(id -gn)
fi
[[ "$(stat -c '%U:%G' "$remote_program")" = "$expected_owner" ]]
[[ "$(sha256sum "$remote_program" | awk '{ print $1 }')" = "$expected_hash" ]]
[[ ! -e "$evidence_root" && ! -L "$evidence_root" ]]
install -d -m 0700 "$evidence_root"
exec /bin/bash "$remote_program" external-attribution-capture external-apprise \
    "$evidence_root" "$evidence_root"
PROGRAM
    cat >"$external_readback_program" <<'PROGRAM'
set -Eeuo pipefail
readonly evidence_root=$1
expected_owner=root:root
if [[ "${CADDY_SERVING_HEALTH_PRODUCTION_PATH_TEST:-0}" = 1 ]]; then
    expected_owner=$(id -un):$(id -gn)
fi
case "$evidence_root" in /tmp/caddy-serving-health-*) ;; *) exit 64 ;; esac
[[ -d "$evidence_root" && ! -L "$evidence_root" ]]
[[ "$(stat -c '%U:%G' "$evidence_root")" = "$expected_owner" ]]
[[ "$(stat -c '%a' "$evidence_root")" = 700 ]]
find "$evidence_root" -maxdepth 1 -type f -print0 | LC_ALL=C sort -z |
while IFS= read -r -d '' file; do
    [[ ! -L "$file" && "$(stat -c '%a' "$file")" = 600 ]]
    [[ "$(stat -c '%U:%G' "$file")" = "$expected_owner" ]]
    [[ "$(stat -c '%s' "$file")" -le 1048576 ]]
    iconv -f UTF-8 -t UTF-8 "$file" >/dev/null
    ! LC_ALL=C grep -Paq '[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]' "$file"
    ! grep -Eiq '([A-Za-z][A-Za-z0-9+.-]*://[^[]|authorization:[[:space:]]*[^[]|((token|password|api[_-]?key|webhook)[=:])[^[])' "$file"
    printf 'file=%s bytes=%s sha256=%s\n' "${file##*/}" \
        "$(stat -c '%s' "$file")" "$(sha256sum "$file" | awk '{ print $1 }')"
    base64 -w 0 "$file"
    printf '\n'
done
PROGRAM
    cat >"$external_cleanup_program" <<'PROGRAM'
set -Eeuo pipefail
readonly remote_program=$1
case "$remote_program" in /tmp/caddy-notification-attribution-*.sh) ;; *) exit 64 ;; esac
if [[ -e "$remote_program" || -L "$remote_program" ]]; then
    [[ -f "$remote_program" && ! -L "$remote_program" ]]
    rm -f -- "$remote_program"
fi
[[ ! -e "$remote_program" && ! -L "$remote_program" ]]
PROGRAM
    chmod 0600 "$prepare_program" "$accept_program" "$disposition_program" \
        "$readback_program" "$external_accept_program" "$external_readback_program" \
        "$external_cleanup_program"
}

ssh_stream() {
    local serving_health_host=$1
    local serving_health_program=$2
    shift 2
    "$ssh_command" "$serving_health_host" \
        "cd / && sudo -n /bin/bash -s --$(printf ' %q' "$@")" <"$serving_health_program"
}

upload_payload() {
    local serving_health_role=$1
    local serving_health_host=$2
    local serving_health_remote_root=$3
    local serving_health_remote_archive=$4
    local serving_health_hash

    serving_health_hash=$(awk '{ print $1 }' "$workstation_evidence/payload.sha256")
    capture "$serving_health_role-upload-prepare" ssh_stream "$serving_health_host" \
        "$prepare_program" "$serving_health_remote_root" "$serving_health_remote_archive"
    capture "$serving_health_role-upload-copy" "$scp_command" -p -- \
        "$payload_archive" "$serving_health_host:$serving_health_remote_archive"
    capture "$serving_health_role-upload-accept" ssh_stream "$serving_health_host" \
        "$accept_program" "$serving_health_remote_root" "$serving_health_remote_archive" \
        "$serving_health_hash"
}

remote_transaction() {
    local serving_health_label=$1
    local serving_health_host=$2
    shift 2

    capture "$serving_health_label" ssh_stream "$serving_health_host" "$transaction" "$@"
}

readback() {
    local serving_health_role=$1
    local serving_health_host=$2
    local serving_health_remote_evidence=$3

    capture "$serving_health_role-readback" ssh_stream "$serving_health_host" \
        "$readback_program" "$serving_health_remote_evidence"
}

extract_readback_file() {
    local serving_health_stream=$1
    local serving_health_name=$2
    local serving_health_destination=$3
    local serving_health_metadata serving_health_encoded serving_health_count=0
    local serving_health_bytes serving_health_hash

    [[ "$serving_health_name" =~ ^[a-zA-Z0-9._-]+$ ]] || return 1
    safe_capture "$serving_health_stream" || return 1
    [[ ! -e "$serving_health_destination" && ! -L "$serving_health_destination" ]] || return 1
    exec 3<"$serving_health_stream"
    while IFS= read -r serving_health_metadata <&3; do
        IFS= read -r serving_health_encoded <&3 || {
            exec 3<&-
            return 1
        }
        [[ "$serving_health_metadata" =~ ^file=([a-zA-Z0-9._-]+)[[:space:]]bytes=([0-9]+)[[:space:]]sha256=([0-9a-f]{64})$ ]] || {
            exec 3<&-
            return 1
        }
        [[ "${BASH_REMATCH[2]}" -le "$max_stream_bytes" ]] || {
            exec 3<&-
            return 1
        }
        if [[ "${BASH_REMATCH[1]}" = "$serving_health_name" ]]; then
            serving_health_count=$((serving_health_count + 1))
            serving_health_bytes=${BASH_REMATCH[2]}
            serving_health_hash=${BASH_REMATCH[3]}
            printf '%s' "$serving_health_encoded" | base64 --decode \
                >"$serving_health_destination" || {
                exec 3<&-
                return 1
            }
        fi
    done
    exec 3<&-
    [[ "$serving_health_count" -eq 1 ]] || return 1
    chmod 0600 "$serving_health_destination" || return 1
    safe_capture "$serving_health_destination" || return 1
    [[ "$(stat -c '%s' "$serving_health_destination")" -eq "$serving_health_bytes" ]] || return 1
    [[ "$(sha256sum "$serving_health_destination" | awk '{ print $1 }')" = "$serving_health_hash" ]] || return 1
}

correlate_controlled_exercise_continuity() {
    local serving_health_correlation_root=$workstation_evidence/continuity-correlation
    local serving_health_role serving_health_availability serving_health_monitor
    local serving_health_failure_count=0 serving_health_classification serving_health_peer
    local serving_health_recovery_end serving_health_start_epoch serving_health_recovery_epoch
    local serving_health_recovery_seconds
    local serving_health_monitor_candidate serving_health_transition_observed

    if [[ -e "$serving_health_correlation_root" || -L "$serving_health_correlation_root" ]]; then
        [[ -d "$serving_health_correlation_root" && ! -L "$serving_health_correlation_root" ]] || return 1
        rm -rf -- "$serving_health_correlation_root"
    fi
    install -d -m 0700 "$serving_health_correlation_root"
    printf '%s\n' $'role\tscenario\tsequence\tprobe\tfamily\tstart\tend\tclassification' \
        >"$serving_health_correlation_root/classifications.tsv"
    chmod 0600 "$serving_health_correlation_root/classifications.tsv"
    for serving_health_role in node-a node-b; do
        serving_health_availability=$serving_health_correlation_root/$serving_health_role-availability.tsv
        serving_health_monitor=$serving_health_correlation_root/$serving_health_role-vip-address-monitor.tsv
        extract_readback_file "$workstation_evidence/$serving_health_role-readback.stdout" \
            availability.tsv "$serving_health_availability" || return 1
        extract_readback_file "$workstation_evidence/$serving_health_role-readback.stdout" \
            vip-address-monitor.tsv "$serving_health_monitor" || return 1
        awk -F '\t' '
            NR == 1 {
                if ($0 != "role\tscenario\tsequence\tprobe\tfamily\tendpoint\tport\tattempt\tstart\tend\texit_status\tresult\tvalue\tstderr_class\tconnect\ttls\tfirst_byte\ttotal\tremote\tlocal\tstate4\tstate6\tvip_count") exit 1
                next
            }
            NF != 23 || $1 !~ /^node-[ab]$/ || $2 !~ /^(baseline|final|node-[ab]-(caddy|lighttpd|pihole-ftl|unbound|keepalived))$/ ||
            $3 !~ /^[1-9][0-9]*$/ || $4 !~ /^(dns|proxy_https|node_ui|shared_ui)$/ ||
            $5 !~ /^[46]$/ || $7 !~ /^(53|443)$/ || $8 !~ /^(primary|retry)$/ ||
            $11 !~ /^[0-9]+$/ || $12 !~ /^(success|failure)$/ || $23 !~ /^[0-4]$/ { exit 1 }
            {
                key=$1 FS $2 FS $3 FS $4 FS $5 FS $8
                if (seen[key]++ || $3 < previous_sequence) exit 1
                previous_sequence=$3
                base=$1 FS $2 FS $3 FS $4 FS $5
                if ($8 == "retry" && !primary[base]) exit 1
                if ($8 == "primary") primary[base]=1
            }
            END { if (NR < 9) exit 1 }
        ' "$serving_health_availability" || return 1
        awk -F '\t' '
            NR == 1 { if ($1 != "observer-start" || NF != 4) exit 1; next }
            $1 == "address-event" && NF == 3 { next }
            $1 == "observer-end" && NF == 3 && $3 ~ /^status=(0|143)$/ { ended++ ; next }
            { exit 1 }
            END { exit(ended == 1 ? 0 : 1) }
        ' "$serving_health_monitor" || return 1
    done
    while IFS=$'\t' read -r role scenario sequence probe family _endpoint _port attempt \
        start end _status result _value _error_class _connect _tls _first _total _remote _local_ip \
        state4 state6 vip_count; do
        [[ "$role" = role || "$attempt" != primary || "$result" = success ]] && continue
        if [[ "$scenario" = node-a-lighttpd || "$scenario" = node-b-lighttpd ]] &&
            { [[ "$probe" = shared_ui ]] ||
                [[ "$probe" = node_ui && "$role" = "${scenario%-lighttpd}" ]]; }; then
            printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$role" "$scenario" "$sequence" \
                "$probe" "$family" "$start" "$end" expected-notification-only-outage \
                >>"$serving_health_correlation_root/classifications.tsv"
            continue
        fi
        if [[ "$scenario" = node-a-caddy || "$scenario" = node-b-caddy ]] &&
            [[ "$probe" = node_ui && "$role" = "${scenario%-caddy}" ]]; then
            printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$role" "$scenario" "$sequence" \
                "$probe" "$family" "$start" "$end" expected-node-local-caddy-outage \
                >>"$serving_health_correlation_root/classifications.tsv"
            continue
        fi
        serving_health_recovery_end=$(awk -F '\t' -v role="$role" -v scenario="$scenario" \
            -v probe="$probe" -v family="$family" -v failed_end="$end" '
                NR > 1 && $1 == role && $2 == scenario && $4 == probe && $5 == family &&
                    $9 >= failed_end && $12 == "success" { print $10; exit }
            ' "$serving_health_correlation_root/$role-availability.tsv")
        serving_health_transition_observed=false
        if [[ -n "$serving_health_recovery_end" ]]; then
            serving_health_start_epoch=$(/usr/bin/date -u -d "$start" +%s) || return 1
            serving_health_recovery_epoch=$(/usr/bin/date -u -d "$serving_health_recovery_end" +%s) || return 1
            serving_health_recovery_seconds=$((serving_health_recovery_epoch - serving_health_start_epoch))
            if [[ "$serving_health_recovery_epoch" -ge "$serving_health_start_epoch" &&
                "$serving_health_recovery_seconds" -le "$continuity_retry_window_seconds" ]]; then
                for serving_health_monitor_candidate in \
                    "$serving_health_correlation_root/node-a-vip-address-monitor.tsv" \
                    "$serving_health_correlation_root/node-b-vip-address-monitor.tsv"; do
                    if awk -F '\t' -v start="$start" -v recovery="$serving_health_recovery_end" '
                        $1 == "address-event" && $2 >= start && $2 <= recovery {
                            found=1
                        }
                        END { exit !found }
                    ' "$serving_health_monitor_candidate"; then
                        serving_health_transition_observed=true
                        break
                    fi
                done
            fi
        fi
        if [[ "$serving_health_transition_observed" = true ]]; then
            printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$role" "$scenario" "$sequence" \
                "$probe" "$family" "$start" "$end" bounded-convergence-retry \
                >>"$serving_health_correlation_root/classifications.tsv"
            continue
        fi
        serving_health_failure_count=$((serving_health_failure_count + 1))
        if [[ "$role" = node-a ]]; then serving_health_peer=node-b; else serving_health_peer=node-a; fi
        serving_health_monitor=$serving_health_correlation_root/$role-vip-address-monitor.tsv
        if awk -F '\t' -v start="$start" -v end="$end" \
            '$1 == "address-event" && $2 >= start && $2 <= end { found=1 } END { exit !found }' \
            "$serving_health_monitor"; then
            serving_health_classification=handoff-overlap
        elif awk -F '\t' -v role="$role" -v scenario="$scenario" -v sequence="$sequence" \
            -v probe="$probe" -v family="$family" '
                NR > 1 && $1 == role && $2 == scenario && $3 == sequence && $4 == probe &&
                $5 != family && $8 == "primary" && $12 == "success" { found=1 }
                END { exit !found }
            ' "$serving_health_correlation_root/$role-availability.tsv"; then
            serving_health_classification='family-degraded'
        elif [[ "$state4" = Master && "$state6" = Master && "$vip_count" -eq 4 ]]; then
            serving_health_classification=settled-owner-serving-failure
        elif awk -F '\t' -v start="$start" -v end="$end" '
            NR > 1 && $9 <= end && $10 >= start && $21 == "Master" &&
            $22 == "Master" && $23 == 4 { found=1 }
            END { exit !found }
        ' "$serving_health_correlation_root/$serving_health_peer-availability.tsv"; then
            serving_health_classification=settled-owner-serving-failure
        else
            serving_health_classification=unclassified-insufficient-evidence
        fi
        printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$role" "$scenario" "$sequence" \
            "$probe" "$family" "$start" "$end" "$serving_health_classification" \
            >>"$serving_health_correlation_root/classifications.tsv"
    done < <(
        tail -n +2 "$serving_health_correlation_root/node-a-availability.tsv"
        tail -n +2 "$serving_health_correlation_root/node-b-availability.tsv"
    )
    safe_capture "$serving_health_correlation_root/classifications.tsv" || return 1
    [[ "$serving_health_failure_count" -eq 0 ]]
}

cleanup_remote() {
    local serving_health_role=$1
    local serving_health_host=$2
    local serving_health_remote_root=$3
    local serving_health_remote_archive=$4

    capture "$serving_health_role-disposition" ssh_stream "$serving_health_host" \
        "$disposition_program" "$serving_health_remote_root" "$serving_health_remote_archive"
}

run_web_health_unit_live() {
    local serving_health_node_b_mutated=false
    local serving_health_node_a_mutated=false
    local serving_health_failure=0
    local serving_health_phase_status=0

    if upload_payload node-b "$node_b_host" "$node_b_payload" "$node_b_archive" &&
        upload_payload node-a "$node_a_host" "$node_a_payload" "$node_a_archive" &&
        remote_transaction node-b-web-unit-preflight "$node_b_host" web-unit-preflight \
            node-b "$node_b_payload" "$node_b_evidence" &&
        remote_transaction node-a-web-unit-preflight "$node_a_host" web-unit-preflight \
            node-a "$node_a_payload" "$node_a_evidence"; then
        :
    else
        serving_health_phase_status=$?
        readback node-a-failure "$node_a_host" "$node_a_evidence" || :
        readback node-b-failure "$node_b_host" "$node_b_evidence" || :
        cleanup_remote node-a "$node_a_host" "$node_a_payload" "$node_a_archive" || :
        cleanup_remote node-b "$node_b_host" "$node_b_payload" "$node_b_archive" || :
        return "$serving_health_phase_status"
    fi

    serving_health_node_b_mutated=true
    remote_transaction node-b-web-unit-install "$node_b_host" web-unit-install \
        node-b "$node_b_payload" "$node_b_evidence" || serving_health_failure=$?
    if [[ "$serving_health_failure" -eq 0 ]]; then
        remote_transaction node-b-web-unit-accept "$node_b_host" web-unit-accept \
            node-b "$node_b_payload" "$node_b_evidence" || serving_health_failure=$?
    fi
    if [[ "$serving_health_failure" -eq 0 ]]; then
        serving_health_node_a_mutated=true
        remote_transaction node-a-web-unit-install "$node_a_host" web-unit-install \
            node-a "$node_a_payload" "$node_a_evidence" || serving_health_failure=$?
    fi
    if [[ "$serving_health_failure" -eq 0 ]]; then
        remote_transaction node-a-web-unit-accept "$node_a_host" web-unit-accept \
            node-a "$node_a_payload" "$node_a_evidence" || serving_health_failure=$?
    fi

    readback node-a "$node_a_host" "$node_a_evidence" || {
        [[ "$serving_health_failure" -ne 0 ]] || serving_health_failure=1
    }
    readback node-b "$node_b_host" "$node_b_evidence" || {
        [[ "$serving_health_failure" -ne 0 ]] || serving_health_failure=1
    }

    if [[ "$serving_health_failure" -ne 0 ]]; then
        if [[ "$serving_health_node_a_mutated" = true ]]; then
            remote_transaction node-a-web-unit-rollback "$node_a_host" web-unit-rollback \
                node-a "$node_a_payload" "$node_a_evidence" || exit 125
        fi
        if [[ "$serving_health_node_b_mutated" = true ]]; then
            remote_transaction node-b-web-unit-rollback "$node_b_host" web-unit-rollback \
                node-b "$node_b_payload" "$node_b_evidence" || exit 125
        fi
        readback node-a-rollback "$node_a_host" "$node_a_evidence" || exit 125
        readback node-b-rollback "$node_b_host" "$node_b_evidence" || exit 125
        cleanup_remote node-a "$node_a_host" "$node_a_payload" "$node_a_archive" || exit 125
        cleanup_remote node-b "$node_b_host" "$node_b_payload" "$node_b_archive" || exit 125
        return "$serving_health_failure"
    fi

    cleanup_remote node-a "$node_a_host" "$node_a_payload" "$node_a_archive"
    cleanup_remote node-b "$node_b_host" "$node_b_payload" "$node_b_archive"
}

run_notification_standardization_live() {
    local notification_node_b_mutated=false
    local notification_node_a_mutated=false
    local notification_failure=0
    local notification_phase_status=0

    if upload_payload node-b "$node_b_host" "$node_b_payload" "$node_b_archive" &&
        upload_payload node-a "$node_a_host" "$node_a_payload" "$node_a_archive" &&
        remote_transaction node-b-notification-preflight "$node_b_host" notification-preflight \
            node-b "$node_b_payload" "$node_b_evidence" &&
        remote_transaction node-a-notification-preflight "$node_a_host" notification-preflight \
            node-a "$node_a_payload" "$node_a_evidence"; then
        :
    else
        notification_phase_status=$?
        readback node-a-failure "$node_a_host" "$node_a_evidence" || :
        readback node-b-failure "$node_b_host" "$node_b_evidence" || :
        cleanup_remote node-a "$node_a_host" "$node_a_payload" "$node_a_archive" || :
        cleanup_remote node-b "$node_b_host" "$node_b_payload" "$node_b_archive" || :
        return "$notification_phase_status"
    fi
    notification_node_b_mutated=true
    remote_transaction node-b-notification-install "$node_b_host" notification-install \
        node-b "$node_b_payload" "$node_b_evidence" || notification_failure=$?
    if [[ "$notification_failure" -eq 0 ]]; then
        remote_transaction node-b-notification-accept "$node_b_host" notification-accept \
            node-b "$node_b_payload" "$node_b_evidence" || notification_failure=$?
    fi
    if [[ "$notification_failure" -eq 0 ]]; then
        notification_node_a_mutated=true
        remote_transaction node-a-notification-install "$node_a_host" notification-install \
            node-a "$node_a_payload" "$node_a_evidence" || notification_failure=$?
    fi
    if [[ "$notification_failure" -eq 0 ]]; then
        remote_transaction node-a-notification-accept "$node_a_host" notification-accept \
            node-a "$node_a_payload" "$node_a_evidence" || notification_failure=$?
    fi
    readback node-a "$node_a_host" "$node_a_evidence" || {
        [[ "$notification_failure" -ne 0 ]] || notification_failure=1
    }
    readback node-b "$node_b_host" "$node_b_evidence" || {
        [[ "$notification_failure" -ne 0 ]] || notification_failure=1
    }
    if [[ "$notification_failure" -ne 0 ]]; then
        if [[ "$notification_node_a_mutated" = true ]]; then
            remote_transaction node-a-notification-rollback "$node_a_host" notification-rollback \
                node-a "$node_a_payload" "$node_a_evidence" || exit 125
        fi
        if [[ "$notification_node_b_mutated" = true ]]; then
            remote_transaction node-b-notification-rollback "$node_b_host" notification-rollback \
                node-b "$node_b_payload" "$node_b_evidence" || exit 125
        fi
        readback node-a-rollback "$node_a_host" "$node_a_evidence" || exit 125
        readback node-b-rollback "$node_b_host" "$node_b_evidence" || exit 125
        cleanup_remote node-a "$node_a_host" "$node_a_payload" "$node_a_archive" || exit 125
        cleanup_remote node-b "$node_b_host" "$node_b_payload" "$node_b_archive" || exit 125
        return "$notification_failure"
    fi
    cleanup_remote node-a "$node_a_host" "$node_a_payload" "$node_a_archive"
    cleanup_remote node-b "$node_b_host" "$node_b_payload" "$node_b_archive"
}

run_external_attribution_live() {
    local attribution_remote_program=/tmp/caddy-notification-attribution-$run_id.sh
    local attribution_remote_evidence=/tmp/caddy-serving-health-$run_id-external-attribution
    local attribution_transaction_hash attribution_status=0 attribution_readback_status=0
    local attribution_cleanup_status=0

    attribution_transaction_hash=$(sha256sum "$transaction" | awk '{ print $1 }')
    capture external-program-copy "$scp_command" -p -- "$transaction" \
        "$apprise_host:$attribution_remote_program" || attribution_status=$?
    if [[ "$attribution_status" -eq 0 ]]; then
        capture external-capture ssh_stream "$apprise_host" "$external_accept_program" \
            "$attribution_remote_program" "$attribution_transaction_hash" \
            "$attribution_remote_evidence" || attribution_status=$?
    fi
    if [[ -e "$workstation_evidence/external-capture.status" ]]; then
        capture external-readback ssh_stream "$apprise_host" "$external_readback_program" \
            "$attribution_remote_evidence" || attribution_readback_status=$?
    else
        attribution_readback_status=71
    fi
    capture external-program-cleanup ssh_stream "$apprise_host" "$external_cleanup_program" \
        "$attribution_remote_program" || attribution_cleanup_status=$?
    [[ "$attribution_cleanup_status" -eq 0 ]] || return 72
    [[ "$attribution_readback_status" -eq 0 ]] || return 71
    return "$attribution_status"
}

exercise_expect_pair() {
    local serving_health_label=$1
    local serving_health_node_a_expectation=$2
    local serving_health_node_b_expectation=$3

    remote_transaction "$serving_health_label-node-a-ownership" "$node_a_host" \
        exercise-ownership node-a "$node_a_payload" "$node_a_evidence" \
        "$serving_health_node_a_expectation" &&
        remote_transaction "$serving_health_label-node-b-ownership" "$node_b_host" \
            exercise-ownership node-b "$node_b_payload" "$node_b_evidence" \
            "$serving_health_node_b_expectation"
}

run_controlled_exercise_scenario() {
    local serving_health_scenario=$1
    local serving_health_role
    local serving_health_host serving_health_payload_root serving_health_remote_evidence
    local serving_health_node_a_expectation serving_health_node_b_expectation
    local serving_health_stop_status

    case "$serving_health_scenario" in
        node-a-*)
            serving_health_role=node-a
            serving_health_host=$node_a_host
            serving_health_payload_root=$node_a_payload
            serving_health_remote_evidence=$node_a_evidence
            ;;
        node-b-*)
            serving_health_role=node-b
            serving_health_host=$node_b_host
            serving_health_payload_root=$node_b_payload
            serving_health_remote_evidence=$node_b_evidence
            ;;
        *) return 64 ;;
    esac
    remote_transaction "$serving_health_scenario-node-a-sampler-scenario" "$node_a_host" \
        sampler-scenario node-a "$node_a_payload" "$node_a_evidence" \
        "$serving_health_scenario" || return $?
    remote_transaction "$serving_health_scenario-node-b-sampler-scenario" "$node_b_host" \
        sampler-scenario node-b "$node_b_payload" "$node_b_evidence" \
        "$serving_health_scenario" || return $?
    remote_transaction "$serving_health_scenario-cursor" "$serving_health_host" \
        exercise-cursor "$serving_health_role" "$serving_health_payload_root" \
        "$serving_health_remote_evidence" "$serving_health_scenario" || return $?
    exercise_current_scenario=$serving_health_scenario
    exercise_current_role=$serving_health_role
    if remote_transaction "$serving_health_scenario-stop" "$serving_health_host" \
        exercise-service "$serving_health_role" "$serving_health_payload_root" \
        "$serving_health_remote_evidence" "$serving_health_scenario:stop"; then
        exercise_service_mutated=true
    else
        serving_health_stop_status=$?
        if [[ "$serving_health_stop_status" -eq 125 ]]; then
            exercise_service_mutated=true
        fi
        return "$serving_health_stop_status"
    fi
    case "$serving_health_scenario" in
        node-a-lighttpd)
            serving_health_node_a_expectation=master4
            serving_health_node_b_expectation=backup0
            ;;
        node-a-keepalived)
            serving_health_node_a_expectation=skip
            serving_health_node_b_expectation=master4
            ;;
        node-a-*)
            serving_health_node_a_expectation=fault0
            serving_health_node_b_expectation=master4
            ;;
        node-b-lighttpd)
            serving_health_node_a_expectation=master4
            serving_health_node_b_expectation=backup0
            ;;
        node-b-*)
            serving_health_node_a_expectation=master4
            serving_health_node_b_expectation=fault0
            ;;
    esac
    if [[ "$serving_health_node_a_expectation" = skip ]]; then
        remote_transaction "$serving_health_scenario-node-b-ownership" "$node_b_host" \
            exercise-ownership node-b "$node_b_payload" "$node_b_evidence" master4 || return $?
    else
        exercise_expect_pair "$serving_health_scenario" \
            "$serving_health_node_a_expectation" "$serving_health_node_b_expectation" || return $?
    fi
    if [[ "$serving_health_scenario" = *-lighttpd ]]; then
        remote_transaction "$serving_health_scenario-observe" "$serving_health_host" \
            exercise-observe "$serving_health_role" "$serving_health_payload_root" \
            "$serving_health_remote_evidence" "$serving_health_scenario" || return $?
    fi
    remote_transaction "$serving_health_scenario-start" "$serving_health_host" \
        exercise-service "$serving_health_role" "$serving_health_payload_root" \
        "$serving_health_remote_evidence" "$serving_health_scenario:start" || return $?
    exercise_service_mutated=false
    exercise_expect_pair "$serving_health_scenario-restored" master4 backup0 || return $?
    remote_transaction "$serving_health_scenario-journal" "$serving_health_host" \
        exercise-journal "$serving_health_role" "$serving_health_payload_root" \
        "$serving_health_remote_evidence" "$serving_health_scenario" || return $?
}

run_controlled_failure_exercise_live() {
    local serving_health_failure=0 serving_health_acceptance_failure=0
    local serving_health_recovery_failure=0 serving_health_scenario
    local -a serving_health_scenarios=(
        node-a-caddy node-a-lighttpd node-a-pihole-ftl node-a-unbound
        node-a-keepalived node-b-caddy node-b-lighttpd
        node-b-pihole-ftl node-b-unbound
    )

    exercise_service_mutated=false
    exercise_current_scenario=
    exercise_current_role=
    if upload_payload node-b "$node_b_host" "$node_b_payload" "$node_b_archive" &&
        upload_payload node-a "$node_a_host" "$node_a_payload" "$node_a_archive" &&
        remote_transaction node-b-exercise-preflight "$node_b_host" exercise-preflight \
            node-b "$node_b_payload" "$node_b_evidence" &&
        remote_transaction node-a-exercise-preflight "$node_a_host" exercise-preflight \
            node-a "$node_a_payload" "$node_a_evidence" &&
        exercise_expect_pair exercise-baseline master4 backup0 &&
        remote_transaction node-b-exercise-sampler-start "$node_b_host" sampler-start \
            node-b "$node_b_payload" "$node_b_evidence" shared-only &&
        remote_transaction node-a-exercise-sampler-start "$node_a_host" sampler-start \
            node-a "$node_a_payload" "$node_a_evidence" shared-only; then
        :
    else
        serving_health_failure=$?
    fi
    if [[ "$serving_health_failure" -ne 0 ]]; then
        if [[ -f "$workstation_evidence/node-a-upload-accept.status" &&
            "$(<"$workstation_evidence/node-a-upload-accept.status")" -eq 0 ]]; then
            readback node-a-preflight-failure "$node_a_host" "$node_a_evidence" || :
        fi
        if [[ -f "$workstation_evidence/node-b-upload-accept.status" &&
            "$(<"$workstation_evidence/node-b-upload-accept.status")" -eq 0 ]]; then
            readback node-b-preflight-failure "$node_b_host" "$node_b_evidence" || :
        fi
        if [[ -f "$workstation_evidence/node-a-upload-prepare.status" ]]; then
            cleanup_remote node-a "$node_a_host" "$node_a_payload" "$node_a_archive" || :
        fi
        if [[ -f "$workstation_evidence/node-b-upload-prepare.status" ]]; then
            cleanup_remote node-b "$node_b_host" "$node_b_payload" "$node_b_archive" || :
        fi
        return "$serving_health_failure"
    fi
    if [[ "$serving_health_failure" -eq 0 ]]; then
        for serving_health_scenario in "${serving_health_scenarios[@]}"; do
            if run_controlled_exercise_scenario "$serving_health_scenario"; then
                :
            else
                serving_health_failure=$?
                break
            fi
        done
    fi
    if [[ "$serving_health_failure" -ne 0 && "$exercise_service_mutated" = true ]]; then
        if [[ "$exercise_current_role" = node-a ]]; then
            remote_transaction exercise-emergency-restore "$node_a_host" exercise-service \
                node-a "$node_a_payload" "$node_a_evidence" \
                "$exercise_current_scenario:restore" || serving_health_recovery_failure=1
        else
            remote_transaction exercise-emergency-restore "$node_b_host" exercise-service \
                node-b "$node_b_payload" "$node_b_evidence" \
                "$exercise_current_scenario:restore" || serving_health_recovery_failure=1
        fi
    fi
    if [[ -e "$workstation_evidence/node-a-exercise-sampler-start.status" ]]; then
        remote_transaction node-a-exercise-sampler-final "$node_a_host" sampler-scenario \
            node-a "$node_a_payload" "$node_a_evidence" final || serving_health_acceptance_failure=1
        remote_transaction node-a-exercise-sampler-stop "$node_a_host" sampler-stop \
            node-a "$node_a_payload" "$node_a_evidence" shared-only || serving_health_acceptance_failure=1
    fi
    if [[ -e "$workstation_evidence/node-b-exercise-sampler-start.status" ]]; then
        remote_transaction node-b-exercise-sampler-final "$node_b_host" sampler-scenario \
            node-b "$node_b_payload" "$node_b_evidence" final || serving_health_acceptance_failure=1
        remote_transaction node-b-exercise-sampler-stop "$node_b_host" sampler-stop \
            node-b "$node_b_payload" "$node_b_evidence" shared-only || serving_health_acceptance_failure=1
    fi
    exercise_expect_pair exercise-final master4 backup0 || serving_health_recovery_failure=1
    remote_transaction node-a-exercise-final-residue "$node_a_host" exercise-final-residue \
        node-a "$node_a_payload" "$node_a_evidence" || serving_health_recovery_failure=1
    remote_transaction node-b-exercise-final-residue "$node_b_host" exercise-final-residue \
        node-b "$node_b_payload" "$node_b_evidence" || serving_health_recovery_failure=1
    local serving_health_readback_failure=0
    readback node-a "$node_a_host" "$node_a_evidence" || serving_health_readback_failure=1
    readback node-b "$node_b_host" "$node_b_evidence" || serving_health_readback_failure=1
    if [[ "$serving_health_readback_failure" -eq 0 ]]; then
        correlate_controlled_exercise_continuity || serving_health_acceptance_failure=1
    else
        serving_health_acceptance_failure=1
    fi
    cleanup_remote node-a "$node_a_host" "$node_a_payload" "$node_a_archive" || serving_health_recovery_failure=1
    cleanup_remote node-b "$node_b_host" "$node_b_payload" "$node_b_archive" || serving_health_recovery_failure=1
    [[ "$serving_health_recovery_failure" -eq 0 ]] || return 125
    if [[ "$serving_health_failure" -eq 0 && "$serving_health_acceptance_failure" -ne 0 ]]; then
        return 1
    fi
    if [[ "$serving_health_failure" -eq 125 ]]; then
        return 1
    fi
    return "$serving_health_failure"
}

run_live() {
    local serving_health_node_b_mutated=false
    local serving_health_node_a_mutated=false
    local serving_health_failure=0
    local serving_health_phase_status=0
    local serving_health_target_revision=

    if [[ "$operation_scope" = pihole-web-health-unit-only ]]; then
        run_web_health_unit_live
        return
    fi
    if [[ "$operation_scope" = notification-standardization-only ]]; then
        run_notification_standardization_live
        return
    fi
    if [[ "$operation_scope" = external-notification-attribution-read-only ]]; then
        run_external_attribution_live
        return
    fi
    if [[ "$operation_scope" = controlled-serving-failure-exercise ]]; then
        run_controlled_failure_exercise_live
        return
    fi

    if upload_payload node-b "$node_b_host" "$node_b_payload" "$node_b_archive" &&
        upload_payload node-a "$node_a_host" "$node_a_payload" "$node_a_archive" &&
        remote_transaction node-b-preflight "$node_b_host" preflight node-b \
            "$node_b_payload" "$node_b_evidence" &&
        remote_transaction node-a-preflight "$node_a_host" preflight node-a \
            "$node_a_payload" "$node_a_evidence" &&
        remote_transaction node-b-candidate-check "$node_b_host" candidate-check node-b \
            "$node_b_payload" "$node_b_evidence" &&
        remote_transaction node-b-journal-cursor "$node_b_host" journal-cursor node-b \
            "$node_b_payload" "$node_b_evidence" &&
        remote_transaction node-a-journal-cursor "$node_a_host" journal-cursor node-a \
            "$node_a_payload" "$node_a_evidence" &&
        remote_transaction node-b-sampler-start "$node_b_host" sampler-start node-b \
            "$node_b_payload" "$node_b_evidence" &&
        remote_transaction node-a-sampler-start "$node_a_host" sampler-start node-a \
            "$node_a_payload" "$node_a_evidence"; then
        :
    else
        serving_health_phase_status=$?
        readback node-a-failure "$node_a_host" "$node_a_evidence" || :
        readback node-b-failure "$node_b_host" "$node_b_evidence" || :
        cleanup_remote node-a "$node_a_host" "$node_a_payload" "$node_a_archive" || :
        cleanup_remote node-b "$node_b_host" "$node_b_payload" "$node_b_archive" || :
        return "$serving_health_phase_status"
    fi

    serving_health_node_b_mutated=true
    if remote_transaction node-b-retained-disposition "$node_b_host" \
        retained-disposition node-b "$node_b_payload" "$node_b_evidence"; then
        :
    else
        serving_health_failure=$?
    fi
    if [[ "$serving_health_failure" -eq 0 ]]; then
        if remote_transaction node-b-install "$node_b_host" install node-b \
            "$node_b_payload" "$node_b_evidence"; then
            :
        else
            serving_health_failure=$?
        fi
    fi
    if [[ "$serving_health_failure" -eq 0 ]]; then
        if remote_transaction node-b-accept "$node_b_host" accept node-b \
            "$node_b_payload" "$node_b_evidence"; then
            :
        else
            serving_health_failure=$?
        fi
    fi
    if [[ "$serving_health_failure" -eq 0 ]]; then
        if remote_transaction node-b-ownership "$node_b_host" ownership node-b \
            "$node_b_payload" "$node_b_evidence"; then
            :
        else
            serving_health_failure=$?
        fi
    fi
    if [[ "$serving_health_failure" -eq 0 ]]; then
        serving_health_node_a_mutated=true
        if remote_transaction node-a-quarantine-disposition "$node_a_host" \
            node-a-quarantine-disposition node-a "$node_a_payload" "$node_a_evidence"; then
            :
        else
            serving_health_failure=$?
        fi
    fi
    if [[ "$serving_health_failure" -eq 0 ]]; then
        if remote_transaction node-a-promote "$node_a_host" promote node-a \
            "$node_a_payload" "$node_a_evidence"; then
            :
        else
            serving_health_failure=$?
        fi
    fi
    if [[ "$serving_health_failure" -eq 0 ]]; then
        if remote_transaction node-a-post-promote-candidate-check "$node_a_host" \
            candidate-check node-a "$node_a_payload" "$node_a_evidence"; then
            :
        else
            serving_health_failure=$?
        fi
    fi
    if [[ "$serving_health_failure" -eq 0 ]]; then
        if remote_transaction node-a-consume-serving-outbound "$node_a_host" \
            consume node-a "$node_a_payload" "$node_a_evidence"; then
            :
        else
            serving_health_failure=$?
        fi
    fi
    if [[ "$serving_health_failure" -eq 0 ]]; then
        if remote_transaction node-a-publish "$node_a_host" publish node-a \
            "$node_a_payload" "$node_a_evidence"; then
            serving_health_target_revision=$(sed -n \
                's/^Published protocol-v2 release \([A-Za-z0-9][A-Za-z0-9._-]*\) for receiver validation\.$/\1/p' \
                "$workstation_evidence/node-a-publish.stdout")
            if [[ ! "$serving_health_target_revision" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ||
                "$(grep -Ec '^Published protocol-v2 release [A-Za-z0-9][A-Za-z0-9._-]* for receiver validation\.$' \
                    "$workstation_evidence/node-a-publish.stdout")" -ne 1 ]]; then
                serving_health_failure=1
            fi
        else
            serving_health_failure=$?
        fi
    fi
    if [[ "$serving_health_failure" -eq 0 ]]; then
        # publish already records this revision in Node A's evidence root.
        # Node B alone needs an explicit record before receiver acceptance.
        if remote_transaction node-b-record-target "$node_b_host" record-target node-b \
            "$node_b_payload" "$node_b_evidence" "$serving_health_target_revision" &&
            remote_transaction node-b-wait-target "$node_b_host" wait-target node-b \
                "$node_b_payload" "$node_b_evidence" &&
            remote_transaction node-b-target-accept "$node_b_host" accept node-b \
                "$node_b_payload" "$node_b_evidence"; then
            :
        else
            serving_health_failure=$?
        fi
    fi
    if [[ "$serving_health_failure" -eq 0 ]]; then
        if remote_transaction node-a-promote-target "$node_a_host" promote-target node-a \
            "$node_a_payload" "$node_a_evidence"; then
            :
        else
            serving_health_failure=$?
        fi
    fi
    if [[ "$serving_health_failure" -eq 0 ]]; then
        if remote_transaction node-a-install "$node_a_host" install node-a \
            "$node_a_payload" "$node_a_evidence"; then
            :
        else
            serving_health_failure=$?
        fi
    fi
    if [[ "$serving_health_failure" -eq 0 ]]; then
        if remote_transaction node-a-accept "$node_a_host" accept node-a \
            "$node_a_payload" "$node_a_evidence"; then
            :
        else
            serving_health_failure=$?
        fi
    fi
    if [[ "$serving_health_failure" -eq 0 ]]; then
        if remote_transaction node-a-ownership "$node_a_host" ownership node-a \
            "$node_a_payload" "$node_a_evidence"; then
            :
        else
            serving_health_failure=$?
        fi
    fi
    if [[ "$serving_health_failure" -eq 0 ]]; then
        if remote_transaction node-b-ownership-final "$node_b_host" ownership node-b \
            "$node_b_payload" "$node_b_evidence"; then
            :
        else
            serving_health_failure=$?
        fi
    fi
    if [[ "$serving_health_failure" -eq 0 ]]; then
        if remote_transaction node-a-consume-target-outbound "$node_a_host" consume-target node-a \
            "$node_a_payload" "$node_a_evidence"; then
            :
        else
            serving_health_failure=$?
        fi
    fi
    if [[ "$serving_health_failure" -eq 0 ]]; then
        if remote_transaction node-a-final-residue "$node_a_host" final-residue node-a \
            "$node_a_payload" "$node_a_evidence" &&
            remote_transaction node-b-final-residue "$node_b_host" final-residue node-b \
                "$node_b_payload" "$node_b_evidence"; then
            :
        else
            serving_health_failure=$?
        fi
    fi

    if ! remote_transaction node-a-journal-capture "$node_a_host" journal-capture node-a \
        "$node_a_payload" "$node_a_evidence"; then
        [[ "$serving_health_failure" -ne 0 ]] || serving_health_failure=1
    fi
    if ! remote_transaction node-b-journal-capture "$node_b_host" journal-capture node-b \
        "$node_b_payload" "$node_b_evidence"; then
        [[ "$serving_health_failure" -ne 0 ]] || serving_health_failure=1
    fi

    if ! remote_transaction node-a-sampler-stop "$node_a_host" sampler-stop node-a \
        "$node_a_payload" "$node_a_evidence"; then
        [[ "$serving_health_failure" -ne 0 ]] || serving_health_failure=1
    fi
    if ! remote_transaction node-b-sampler-stop "$node_b_host" sampler-stop node-b \
        "$node_b_payload" "$node_b_evidence"; then
        [[ "$serving_health_failure" -ne 0 ]] || serving_health_failure=1
    fi
    if ! readback node-a "$node_a_host" "$node_a_evidence"; then
        [[ "$serving_health_failure" -ne 0 ]] || serving_health_failure=1
    fi
    if ! readback node-b "$node_b_host" "$node_b_evidence"; then
        [[ "$serving_health_failure" -ne 0 ]] || serving_health_failure=1
    fi

    if [[ "$serving_health_failure" -ne 0 ]]; then
        if [[ "$serving_health_node_a_mutated" = true ]]; then
            remote_transaction node-a-rollback "$node_a_host" rollback node-a \
                "$node_a_payload" "$node_a_evidence" || exit 125
        fi
        if [[ "$serving_health_node_b_mutated" = true ]]; then
            remote_transaction node-b-rollback "$node_b_host" rollback node-b \
                "$node_b_payload" "$node_b_evidence" || exit 125
        fi
        readback node-a-rollback "$node_a_host" "$node_a_evidence" || exit 125
        readback node-b-rollback "$node_b_host" "$node_b_evidence" || exit 125
        cleanup_remote node-a "$node_a_host" "$node_a_payload" "$node_a_archive" || exit 125
        cleanup_remote node-b "$node_b_host" "$node_b_payload" "$node_b_archive" || exit 125
        return "$serving_health_failure"
    fi

    cleanup_remote node-a "$node_a_host" "$node_a_payload" "$node_a_archive"
    cleanup_remote node-b "$node_b_host" "$node_b_payload" "$node_b_archive"
}

write_decision() {
    local serving_health_scenario=$1
    local serving_health_expectation=$2
    local serving_health_status=$3
    local serving_health_expected=$4
    local serving_health_observed=$5
    local serving_health_raw=$6
    local serving_health_decision=$7
    local serving_health_raw_hash

    serving_health_raw_hash=$(sha256sum "$serving_health_raw" | awk '{ print $1 }')
    printf 'scenario\texpectation\tstatus\texpected\tobserved\traw-sha256\n%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$serving_health_scenario" "$serving_health_expectation" "$serving_health_status" \
        "$serving_health_expected" "$serving_health_observed" "$serving_health_raw_hash" \
        >"$serving_health_decision"
    chmod 0600 "$serving_health_raw" "$serving_health_decision"
}

web_health_unit_outer_production_path_test() {
    local serving_health_test_root=${CADDY_PRODUCTION_PATH_EVIDENCE_ROOT:?missing evidence root}
    local serving_health_remote_base
    local serving_health_node_root
    local serving_health_queue_directory
    local serving_health_installed
    local serving_health_failure_status=0
    local serving_health_raw
    local serving_health_decision
    local serving_health_observed

    serving_health_remote_base=$(mktemp -d /tmp/caddy-serving-health-web-outer.XXXXXX)
    test_remote_base=$serving_health_remote_base
    export CADDY_SERVING_HEALTH_TEST_REMOTE_BASE=$test_remote_base
    install -d -m 0700 "$test_remote_base/bin"
    for serving_health_node_root in node-a-root node-b-root; do
        install -d -m 0755 "$test_remote_base/$serving_health_node_root/etc/systemd/system"
        install -d -m 0700 "$test_remote_base/$serving_health_node_root/var/lib/caddy-apprise-queue"
        for serving_health_queue_directory in pending inflight dead-letter delivered; do
            install -d -m 0700 \
                "$test_remote_base/$serving_health_node_root/var/lib/caddy-apprise-queue/$serving_health_queue_directory"
        done
        serving_health_installed=$test_remote_base/$serving_health_node_root/etc/systemd/system/caddy-pihole-web-health.service
        sed -e '/^SupplementaryGroups=caddy-tls$/d' \
            -e 's|^ReadWritePaths=/var/lib/caddy-apprise-queue$|ReadWritePaths=/var/lib/caddy-apprise-queue /run/caddy-apprise|' \
            "$repository_root/Caddy/systemd/caddy-pihole-web-health.service" >"$serving_health_installed"
        chmod 0644 "$serving_health_installed"
        [[ "$(sha256sum "$serving_health_installed" | awk '{ print $1 }')" = a1afee302fa521c9d4ba2eb6d7085e98f261ec5fdd464c156dd11aa1f1cfa3f0 ]]
    done

    cat >"$test_remote_base/bin/sudo" <<'SUDO'
#!/usr/bin/env bash
set -Eeuo pipefail
[[ "$1" = -n ]]
shift
export CADDY_SERVING_HEALTH_PRODUCTION_PATH_TEST=1
exec "$@"
SUDO
    cat >"$test_remote_base/bin/systemctl" <<'SYSTEMCTL'
#!/usr/bin/env bash
set -Eeuo pipefail
printf '%s\t%s\n' "${CADDY_SERVING_HEALTH_TEST_NODE:?}" "$*" \
    >>"$CADDY_SERVING_HEALTH_TEST_REMOTE_BASE/systemctl.calls"
case "$1" in
    is-enabled)
        if [[ "${2:-}" = --quiet ]]; then
            [[ "${3:-}" = caddy-pihole-web-health.timer ]]
            exit
        fi
        [[ "${2:-}" = caddy-pihole-web-health.service ]]
        printf 'static\n'
        ;;
    is-active) exit 0 ;;
    daemon-reload) exit 0 ;;
    start)
        [[ "${2:-}" = caddy-pihole-web-health.service ]]
        if [[ "$CADDY_SERVING_HEALTH_TEST_NODE" = node-a &&
            -e "$CADDY_SERVING_HEALTH_TEST_REMOTE_BASE/fail-node-a" ]]; then
            exit 1
        fi
        printf '%s\n' \
            'pihole_web_health event=healthy' \
            'Finished caddy-pihole-web-health.service - direct invocation' \
            >>"$CADDY_SERVING_HEALTH_TARGET_ROOT/service.journal"
        ;;
    show)
        printf '%s\n' 'LoadState=loaded' 'ActiveState=inactive' 'SubState=dead' \
            'Result=success' 'ExecMainStatus=0' \
            'FragmentPath=/etc/systemd/system/caddy-pihole-web-health.service' \
            'ReadWritePaths=/var/lib/caddy-apprise-queue' \
            'SupplementaryGroups=caddy-tls'
        ;;
    *) exit 64 ;;
esac
SYSTEMCTL
    cat >"$test_remote_base/bin/journalctl" <<'JOURNALCTL'
#!/usr/bin/env bash
set -Eeuo pipefail
printf '%s\t%s\n' "${CADDY_SERVING_HEALTH_TEST_NODE:?}" "$*" \
    >>"$CADDY_SERVING_HEALTH_TEST_REMOTE_BASE/journalctl.calls"
if [[ " $* " = *' --show-cursor '* ]]; then
    cursor_count=0
    if [[ -f "$CADDY_SERVING_HEALTH_TARGET_ROOT/cursor-count" ]]; then
        cursor_count=$(<"$CADDY_SERVING_HEALTH_TARGET_ROOT/cursor-count")
    fi
    ((cursor_count += 1))
    printf '%s\n' "$cursor_count" >"$CADDY_SERVING_HEALTH_TARGET_ROOT/cursor-count"
    printf '%s\n' \
        "-- cursor: s=web-health-$CADDY_SERVING_HEALTH_TEST_NODE-$cursor_count"
    exit
fi
if [[ ! -e "$CADDY_SERVING_HEALTH_TARGET_ROOT/timer-observed" ]]; then
    printf '%s\n' \
        'pihole_web_health event=healthy' \
        'Finished caddy-pihole-web-health.service - timer invocation' \
        >"$CADDY_SERVING_HEALTH_TARGET_ROOT/timer.journal"
    : >"$CADDY_SERVING_HEALTH_TARGET_ROOT/timer-observed"
fi
cat "$CADDY_SERVING_HEALTH_TARGET_ROOT/timer.journal"
JOURNALCTL
    cat >"$test_remote_base/bin/sleep" <<'SLEEP'
#!/usr/bin/env bash
set -Eeuo pipefail
[[ $# -eq 1 && "$1" =~ ^[0-9]+([.][0-9]+)?$ ]]
SLEEP
    cat >"$test_remote_base/fake-ssh" <<'SSH'
#!/usr/bin/env bash
set -Eeuo pipefail
host=$1
shift
command="$*"
case "$host" in
    test-node-a) node=node-a ;;
    test-node-b) node=node-b ;;
    *) exit 64 ;;
esac
target_root=$CADDY_SERVING_HEALTH_TEST_REMOTE_BASE/$node-root
printf '%s\t%s\n' "$node" "$command" >>"$CADDY_SERVING_HEALTH_TEST_REMOTE_BASE/ssh.calls"
PATH="$CADDY_SERVING_HEALTH_TEST_REMOTE_BASE/bin:/usr/bin:/bin" \
    CADDY_SERVING_HEALTH_TEST_NODE=$node \
    CADDY_SERVING_HEALTH_TARGET_ROOT=$target_root \
    CADDY_SERVING_HEALTH_SYSTEMCTL_COMMAND="$CADDY_SERVING_HEALTH_TEST_REMOTE_BASE/bin/systemctl" \
    CADDY_SERVING_HEALTH_JOURNALCTL_COMMAND="$CADDY_SERVING_HEALTH_TEST_REMOTE_BASE/bin/journalctl" \
    CADDY_SERVING_HEALTH_SLEEP_COMMAND="$CADDY_SERVING_HEALTH_TEST_REMOTE_BASE/bin/sleep" \
    CADDY_SERVING_HEALTH_WEB_OBSERVATION_ATTEMPTS=2 \
    CADDY_SERVING_HEALTH_WEB_OBSERVATION_DELAY=0 \
    /bin/bash -c "$command"
SSH
    cat >"$test_remote_base/fake-scp" <<'SCP'
#!/usr/bin/env bash
set -Eeuo pipefail
[[ "$1" = -p && "$2" = -- ]]
source=$3
target=${4#*:}
printf '%s\t%s\n' "${4%%:*}" "$target" >>"$CADDY_SERVING_HEALTH_TEST_REMOTE_BASE/scp.calls"
install -m 0600 "$source" "$target"
SCP
    chmod 0700 "$test_remote_base/bin/"* "$test_remote_base/fake-ssh" \
        "$test_remote_base/fake-scp"
    : >"$test_remote_base/systemctl.calls"
    : >"$test_remote_base/journalctl.calls"
    : >"$test_remote_base/ssh.calls"
    : >"$test_remote_base/scp.calls"
    : >"$test_remote_base/node-a-root/service.journal"
    : >"$test_remote_base/node-b-root/service.journal"
    ssh_command=$test_remote_base/fake-ssh
    scp_command=$test_remote_base/fake-scp
    node_a_host=test-node-a
    node_b_host=test-node-b

    : >"$test_remote_base/fail-node-a"
    if run_web_health_unit_live; then
        serving_health_failure_status=0
    else
        serving_health_failure_status=$?
    fi
    [[ "$serving_health_failure_status" -ne 0 && "$serving_health_failure_status" -ne 125 ]]
    for serving_health_node_root in node-a-root node-b-root; do
        serving_health_installed=$test_remote_base/$serving_health_node_root/etc/systemd/system/caddy-pihole-web-health.service
        [[ "$(sha256sum "$serving_health_installed" | awk '{ print $1 }')" = a1afee302fa521c9d4ba2eb6d7085e98f261ec5fdd464c156dd11aa1f1cfa3f0 ]]
    done
    serving_health_raw=$serving_health_test_root/raw/outer-reverse-rollback.txt
    serving_health_decision=$serving_health_test_root/decisions/outer-reverse-rollback.tsv
    {
        grep -E 'web-unit-(install|rollback)' "$test_remote_base/ssh.calls"
        cat "$workstation_evidence/node-a-rollback-readback.stdout"
    } >"$serving_health_raw"
    grep -Fq $'node-a\tcd / && sudo -n /bin/bash -s -- web-unit-rollback' "$serving_health_raw"
    grep -Fq $'node-b\tcd / && sudo -n /bin/bash -s -- web-unit-rollback' "$serving_health_raw"
    grep -Fq 'file=web_unit_failure_journal.stdout' "$serving_health_raw"
    write_decision outer-reverse-rollback reject "$serving_health_failure_status" \
        node-a-accept-success node-a-accept-failed-and-both-restored \
        "$serving_health_raw" "$serving_health_decision"

    rm -f -- "$test_remote_base/fail-node-a"
    : >"$test_remote_base/ssh.calls"
    : >"$test_remote_base/scp.calls"
    : >"$test_remote_base/systemctl.calls"
    : >"$test_remote_base/journalctl.calls"
    rm -f -- "$test_remote_base/node-a-root/timer-observed" \
        "$test_remote_base/node-b-root/timer-observed" \
        "$test_remote_base/node-a-root/timer.journal" \
        "$test_remote_base/node-b-root/timer.journal" \
        "$test_remote_base/node-a-root/cursor-count" \
        "$test_remote_base/node-b-root/cursor-count"
    : >"$test_remote_base/node-a-root/service.journal"
    : >"$test_remote_base/node-b-root/service.journal"
    run_web_health_unit_live

    serving_health_raw=$serving_health_test_root/raw/outer-preflight.txt
    serving_health_decision=$serving_health_test_root/decisions/outer-preflight.tsv
    cat "$test_remote_base/scp.calls" "$test_remote_base/ssh.calls" >"$serving_health_raw"
    serving_health_observed=$(wc -l <"$serving_health_raw")
    write_decision outer-preflight reach 0 "$serving_health_observed" \
        "$serving_health_observed" "$serving_health_raw" "$serving_health_decision"

    serving_health_raw=$serving_health_test_root/raw/outer-standby-first.txt
    serving_health_decision=$serving_health_test_root/decisions/outer-standby-first.tsv
    grep -E 'web-unit-(install|accept)' "$test_remote_base/ssh.calls" >"$serving_health_raw"
    [[ "$(sed -n '1p' "$serving_health_raw")" = *$'node-b\t'*web-unit-install* ]]
    [[ "$(sed -n '2p' "$serving_health_raw")" = *$'node-b\t'*web-unit-accept* ]]
    [[ "$(sed -n '3p' "$serving_health_raw")" = *$'node-a\t'*web-unit-install* ]]
    [[ "$(sed -n '4p' "$serving_health_raw")" = *$'node-a\t'*web-unit-accept* ]]
    write_decision outer-standby-first accept 0 node-b-then-node-a node-b-then-node-a \
        "$serving_health_raw" "$serving_health_decision"

    serving_health_raw=$serving_health_test_root/raw/outer-evidence-readback.txt
    serving_health_decision=$serving_health_test_root/decisions/outer-evidence-readback.tsv
    cat "$workstation_evidence/node-b-readback.stdout" \
        "$workstation_evidence/node-a-readback.stdout" >"$serving_health_raw"
    grep -Fq 'file=web_unit_timer_journal.stdout' "$serving_health_raw"
    write_decision outer-evidence-readback accept 0 both-nodes both-nodes \
        "$serving_health_raw" "$serving_health_decision"

    serving_health_raw=$serving_health_test_root/raw/outer-zero-residue.txt
    serving_health_decision=$serving_health_test_root/decisions/outer-zero-residue.tsv
    {
        printf 'node_a_payload_absent=%s\n' "$([[ ! -e "$node_a_payload" ]] && printf true || printf false)"
        printf 'node_b_payload_absent=%s\n' "$([[ ! -e "$node_b_payload" ]] && printf true || printf false)"
    } >"$serving_health_raw"
    grep -Fxq 'node_a_payload_absent=true' "$serving_health_raw"
    grep -Fxq 'node_b_payload_absent=true' "$serving_health_raw"
    write_decision outer-zero-residue accept 0 absent absent \
        "$serving_health_raw" "$serving_health_decision"

    if grep -Eq $'\t(restart|reload) (caddy|lighttpd|pihole-FTL|unbound|keepalived)\\.service$' \
        "$test_remote_base/systemctl.calls"; then
        return 1
    fi
    chmod -R u+rwX -- "$serving_health_remote_base"
    rm -rf -- "$serving_health_remote_base"
    printf '%s_production_path_test_complete=true\n' "$prefix"
}

external_attribution_outer_production_path_test() {
    local attribution_test_root=${CADDY_PRODUCTION_PATH_EVIDENCE_ROOT:?missing evidence root}
    local attribution_remote_base attribution_fixture attribution_program attribution_evidence
    local attribution_raw attribution_decision attribution_status attribution_observed
    local attribution_transaction_hash

    attribution_remote_base=$(mktemp -d /tmp/caddy-notification-attribution-outer.XXXXXX)
    attribution_transaction_hash=$(sha256sum "$transaction" | awk '{ print $1 }')
    test_remote_base=$attribution_remote_base
    export CADDY_SERVING_HEALTH_TEST_REMOTE_BASE=$test_remote_base
    attribution_fixture=$test_remote_base/scan
    install -d -m 0700 "$attribution_fixture/usr/local/bin" "$test_remote_base/bin"
    printf '%s\n' '[Failover Alert] Pi-hole DNS Cluster' \
        >"$attribution_fixture/usr/local/bin/legacy-caller.sh"
    chmod 0600 "$attribution_fixture/usr/local/bin/legacy-caller.sh"
    cat >"$test_remote_base/fake-journalctl" <<'JOURNAL'
#!/usr/bin/env bash
set -Eeuo pipefail
printf '%s\n' '2026-08-23T12:00:00Z 10.1.3.10 POST /notify/apprise 200 legacy-agent apprise-api destinations=3 [Failover Alert] Pi-hole DNS Cluster'
JOURNAL
    cat >"$test_remote_base/fake-podman" <<'PODMAN'
#!/usr/bin/env bash
set -Eeuo pipefail
exit 0
PODMAN
    cat >"$test_remote_base/bin/sudo" <<'SUDO'
#!/usr/bin/env bash
set -Eeuo pipefail
[[ "$1" = -n ]]
shift
exec "$@"
SUDO
    cat >"$test_remote_base/fake-scp" <<'SCP'
#!/usr/bin/env bash
set -Eeuo pipefail
[[ "$1" = -p && "$2" = -- ]]
source=$3
target=${4#*:}
printf '%s\t%s\n' "${4%%:*}" "$target" >>"$CADDY_SERVING_HEALTH_TEST_REMOTE_BASE/scp.calls"
install -m 0755 "$source" "$target"
SCP
    cat >"$test_remote_base/fake-ssh" <<'SSH'
#!/usr/bin/env bash
set -Eeuo pipefail
host=$1
shift
[[ "$host" = test-apprise ]]
printf '%s\n' "$*" >>"$CADDY_SERVING_HEALTH_TEST_REMOTE_BASE/ssh.calls"
PATH="$CADDY_SERVING_HEALTH_TEST_REMOTE_BASE/bin:/usr/bin:/bin" \
    CADDY_SERVING_HEALTH_PRODUCTION_PATH_TEST=1 \
    CADDY_ATTRIBUTION_SCAN_ROOTS="$CADDY_SERVING_HEALTH_TEST_REMOTE_BASE/scan" \
    CADDY_ATTRIBUTION_JOURNALCTL_COMMAND="$CADDY_SERVING_HEALTH_TEST_REMOTE_BASE/fake-journalctl" \
    CADDY_ATTRIBUTION_PODMAN_COMMAND="$CADDY_SERVING_HEALTH_TEST_REMOTE_BASE/fake-podman" \
    /bin/bash -c "$*"
SSH
    chmod 0700 "$test_remote_base/fake-journalctl" "$test_remote_base/fake-podman" \
        "$test_remote_base/fake-scp" "$test_remote_base/fake-ssh" \
        "$test_remote_base/bin/sudo"
    : >"$test_remote_base/scp.calls"
    : >"$test_remote_base/ssh.calls"
    ssh_command=$test_remote_base/fake-ssh
    scp_command=$test_remote_base/fake-scp
    apprise_host=test-apprise
    run_external_attribution_live
    attribution_program=/tmp/caddy-notification-attribution-$run_id.sh
    attribution_evidence=/tmp/caddy-serving-health-$run_id-external-attribution

    attribution_raw=$attribution_test_root/raw/outer-preflight.txt
    attribution_decision=$attribution_test_root/decisions/outer-preflight.tsv
    cat "$test_remote_base/scp.calls" "$test_remote_base/ssh.calls" >"$attribution_raw"
    grep -Fq 'test-apprise' "$attribution_raw"
    grep -Fq "$attribution_transaction_hash" "$attribution_raw"
    write_decision outer-preflight reach 0 real-ssh-stream real-ssh-stream \
        "$attribution_raw" "$attribution_decision"

    attribution_raw=$attribution_test_root/raw/exact-remote-cleanup.txt
    attribution_decision=$attribution_test_root/decisions/exact-remote-cleanup.tsv
    printf 'remote_program=%s\nremote_program_absent=%s\nremote_evidence_preserved=%s\n' \
        "$attribution_program" "$([[ ! -e "$attribution_program" && ! -L "$attribution_program" ]] && printf true || printf false)" \
        "$([[ -d "$attribution_evidence" && ! -L "$attribution_evidence" ]] && printf true || printf false)" \
        >"$attribution_raw"
    grep -Fxq 'remote_program_absent=true' "$attribution_raw"
    grep -Fxq 'remote_evidence_preserved=true' "$attribution_raw"
    write_decision exact-remote-cleanup accept 0 absent absent \
        "$attribution_raw" "$attribution_decision"

    attribution_raw=$attribution_test_root/raw/evidence-readback-success.txt
    attribution_decision=$attribution_test_root/decisions/evidence-readback-success.tsv
    cp "$workstation_evidence/external-readback.stdout" "$attribution_raw"
    grep -Fq 'file=attribution.tsv' "$attribution_raw"
    write_decision evidence-readback-success accept 0 complete complete \
        "$attribution_raw" "$attribution_decision"

    attribution_raw=$attribution_test_root/raw/evidence-readback-failure.txt
    attribution_decision=$attribution_test_root/decisions/evidence-readback-failure.tsv
    if ssh_stream "$apprise_host" "$external_readback_program" \
        "$attribution_evidence-absent" >"$attribution_raw" 2>&1; then
        attribution_status=0
    else
        attribution_status=$?
    fi
    printf 'exit_status=%s\n' "$attribution_status" >>"$attribution_raw"
    [[ "$attribution_status" -ne 0 ]]
    write_decision evidence-readback-failure reject "$attribution_status" present absent \
        "$attribution_raw" "$attribution_decision"

    attribution_raw=$attribution_test_root/raw/zero-production-mutation-outer.txt
    attribution_decision=$attribution_test_root/decisions/zero-production-mutation-outer.tsv
    attribution_observed=$(sha256sum "$attribution_fixture/usr/local/bin/legacy-caller.sh" | awk '{ print $1 }')
    printf 'fixture_sha256=%s\n' "$attribution_observed" >"$attribution_raw"
    write_decision zero-production-mutation-outer accept 0 "$attribution_observed" \
        "$attribution_observed" "$attribution_raw" "$attribution_decision"
    chmod -R u+rwX -- "$attribution_evidence" "$test_remote_base"
    rm -rf -- "$attribution_evidence" "$test_remote_base"
    printf '%s_external_attribution_production_path_test_complete=true\n' "$prefix"
    printf '%s_production_path_test_complete=true\n' "$prefix"
}

controlled_failure_outer_production_path_test() {
    local exercise_test_root=${CADDY_PRODUCTION_PATH_EVIDENCE_ROOT:?missing evidence root}
    local exercise_remote_base exercise_raw exercise_decision exercise_status
    local exercise_role exercise_node_root exercise_key exercise_repository exercise_source
    local exercise_target exercise_inventory_node exercise_source_hash exercise_deployed_hash
    local exercise_accepted exercise_lifecycle exercise_source_path exercise_installed
    local exercise_revision exercise_parent exercise_release
    local exercise_stream exercise_original exercise_payload_file exercise_symlink

    exercise_replace_readback_entry() {
        local exercise_stream=$1 exercise_name=$2 exercise_payload_file=$3
        local exercise_replacement=$exercise_test_root/readback-replacement.tmp
        local exercise_metadata exercise_encoded exercise_current_name

        : >"$exercise_replacement"
        exec 4<"$exercise_stream"
        while IFS= read -r exercise_metadata <&4; do
            IFS= read -r exercise_encoded <&4 || {
                exec 4<&-
                return 1
            }
            exercise_current_name=${exercise_metadata#file=}
            exercise_current_name=${exercise_current_name%% *}
            if [[ "$exercise_current_name" = "$exercise_name" ]]; then
                {
                    printf 'file=%s bytes=%s sha256=%s\n' "$exercise_name" \
                        "$(stat -c '%s' "$exercise_payload_file")" \
                        "$(sha256sum "$exercise_payload_file" | awk '{ print $1 }')"
                    base64 -w 0 "$exercise_payload_file"
                    printf '\n'
                } >>"$exercise_replacement"
            else
                printf '%s\n%s\n' "$exercise_metadata" "$exercise_encoded" \
                    >>"$exercise_replacement"
            fi
        done
        exec 4<&-
        mv -T -- "$exercise_replacement" "$exercise_stream"
        chmod 0600 "$exercise_stream"
    }

    exercise_expect_correlation_rejection() {
        local exercise_case=$1 exercise_stream=$2 exercise_original=$3
        local exercise_raw=$exercise_test_root/raw/outer-continuity-$exercise_case.txt
        local exercise_decision=$exercise_test_root/decisions/outer-continuity-$exercise_case.tsv
        local exercise_case_status

        if correlate_controlled_exercise_continuity >"$exercise_raw" 2>&1; then
            exercise_case_status=0
        else
            exercise_case_status=$?
        fi
        printf 'exit_status=%s\n' "$exercise_case_status" >>"$exercise_raw"
        [[ "$exercise_case_status" -ne 0 ]]
        write_decision "outer-continuity-$exercise_case" reject "$exercise_case_status" \
            valid-complete-readback "$exercise_case" "$exercise_raw" "$exercise_decision"
        cp -- "$exercise_original" "$exercise_stream"
    }

    CADDY_CONTROLLED_EXERCISE_CONTRACT_ONLY=1 \
        CADDY_PRODUCTION_PATH_EVIDENCE_ROOT=$exercise_test_root \
        /bin/bash "$transaction" --production-path-test >/dev/null

    exercise_remote_base=$(mktemp -d /tmp/caddy-controlled-exercise-outer.XXXXXX)
    test_remote_base=$exercise_remote_base
    export CADDY_SERVING_HEALTH_TEST_REMOTE_BASE=$test_remote_base
    install -d -m 0700 "$test_remote_base/bin"
    cat >"$test_remote_base/bin/systemctl" <<'SYSTEMCTL'
#!/usr/bin/env bash
set -Eeuo pipefail
service=${*: -1}
state_directory=$CADDY_SERVING_HEALTH_TEST_REMOTE_BASE/state
state_file=$state_directory/$CADDY_SERVING_HEALTH_TEST_NODE-${service//[^a-zA-Z0-9]/_}.inactive
event_log=$CADDY_SERVING_HEALTH_TEST_REMOTE_BASE/journal.log
install -d -m 0700 "$state_directory"
printf '%s\t%s\t%s\n' "$CADDY_SERVING_HEALTH_TEST_NODE" "$1" "$service" \
    >>"$CADDY_SERVING_HEALTH_TEST_REMOTE_BASE/systemctl.calls"
case "$1" in
    is-active) [[ ! -e "$state_file" ]] ;;
    is-enabled)
        if [[ "${2:-}" = --quiet ]]; then
            exit 0
        fi
        case "${2:-}" in
            caddy-api.service | lsyncd.service) printf 'masked\n' ;;
            *) printf 'enabled\n' ;;
        esac
        ;;
    show)
        [[ -e "$state_file" ]] && cat "$state_file" || printf 'active\n'
        ;;
    stop)
        if [[ -e "$CADDY_SERVING_HEALTH_TEST_REMOTE_BASE/fail-next-stop" ]]; then
            rm -f -- "$CADDY_SERVING_HEALTH_TEST_REMOTE_BASE/fail-next-stop"
            exit 1
        fi
        case "$service" in
            lighttpd.service) printf 'failed\n' >"$state_file" ;;
            *) printf 'inactive\n' >"$state_file" ;;
        esac
        case "$service" in
            caddy.service)
                printf '%s\n' \
                    'Keepalived_vrrp: VRRP_Script(check-caddy) failed (exited with status 1)' \
                    'event=enqueued event_id=caddy-failure source=keepalived severity=failure' \
                    >>"$event_log"
                ;;
            pihole-FTL.service | unbound.service)
                printf '%s\n' \
                    'Keepalived_vrrp: VRRP_Script(check-dns) failed (exited with status 1)' \
                    'event=enqueued event_id=dns-failure source=keepalived severity=failure' \
                    >>"$event_log"
                ;;
            lighttpd.service)
                printf '%s\n' \
                    'pihole_web_health event=failure-retained' \
                    'event=enqueued event_id=web-failure source=pihole-web severity=failure' \
                    >>"$event_log"
                ;;
        esac
        ;;
    start)
        rm -f -- "$state_file"
        case "$service" in
            caddy.service)
                printf '%s\n' \
                    'Keepalived_vrrp: VRRP_Script(check-caddy) succeeded' \
                    'event=enqueued event_id=caddy-recovery source=keepalived severity=success' \
                    >>"$event_log"
                ;;
            pihole-FTL.service | unbound.service)
                printf '%s\n' \
                    'Keepalived_vrrp: VRRP_Script(check-dns) succeeded' \
                    'event=enqueued event_id=dns-recovery source=keepalived severity=success' \
                    >>"$event_log"
                ;;
            lighttpd.service)
                printf '%s\n' \
                    'pihole_web_health event=recovery-enqueued' \
                    'event=enqueued event_id=web-recovery source=pihole-web severity=success' \
                    >>"$event_log"
                ;;
            keepalived.service)
                printf '%s\n' \
                    'systemd: Started keepalived.service' \
                    'event=enqueued event_id=keepalived-recovery source=keepalived severity=success' \
                    >>"$event_log"
                ;;
        esac
        ;;
    *) exit 64 ;;
esac
SYSTEMCTL
    cat >"$test_remote_base/bin/busctl" <<'BUSCTL'
#!/usr/bin/env bash
set -Eeuo pipefail
state_directory=$CADDY_SERVING_HEALTH_TEST_REMOTE_BASE/state
active() { [[ ! -e "$state_directory/$1-${2//[^a-zA-Z0-9]/_}.inactive" ]]; }
if ! active node-a keepalived.service; then
    [[ "$CADDY_SERVING_HEALTH_TEST_NODE" = node-b ]] && state=Master || state=Fault
elif ! active node-a caddy.service || ! active node-a pihole-FTL.service || \
    ! active node-a unbound.service; then
    [[ "$CADDY_SERVING_HEALTH_TEST_NODE" = node-a ]] && state=Fault || state=Master
elif ! active node-b caddy.service || ! active node-b pihole-FTL.service || \
    ! active node-b unbound.service; then
    [[ "$CADDY_SERVING_HEALTH_TEST_NODE" = node-a ]] && state=Master || state=Fault
else
    [[ "$CADDY_SERVING_HEALTH_TEST_NODE" = node-a ]] && state=Master || state=Backup
fi
printf 's "%s"\n' "$state"
BUSCTL
    cat >"$test_remote_base/bin/ip" <<'IP'
#!/usr/bin/env bash
set -Eeuo pipefail
if [[ " $* " = *' monitor address '* ]]; then
    trap 'exit 143' TERM
    while :; do
        if [[ -e "$CADDY_SERVING_HEALTH_TEST_REMOTE_BASE/convergence-address-event" ]]; then
            rm -f -- "$CADDY_SERVING_HEALTH_TEST_REMOTE_BASE/convergence-address-event"
            printf '%s\n' 'Deleted 10.1.0.55/22 dev eth0'
        fi
        /usr/bin/sleep 0.01
    done
fi
state=$($CADDY_SERVING_HEALTH_TEST_REMOTE_BASE/bin/busctl)
if [[ "$state" = 's "Master"' ]]; then
    printf '%s\n' \
        '1: eth0    inet 10.1.0.55/22 scope global eth0' \
        '1: eth0    inet 10.1.0.56/22 scope global eth0' \
        '1: eth0    inet6 fd36:5aa8:6971:1::55/128 scope global' \
        '1: eth0    inet6 fd36:5aa8:6971:1::56/128 scope global'
fi
IP
    cat >"$test_remote_base/bin/journalctl" <<'JOURNALCTL'
#!/usr/bin/env bash
set -Eeuo pipefail
arguments=$*
printf '%s\n' "$*" >>"$CADDY_SERVING_HEALTH_TEST_REMOTE_BASE/journalctl.calls"
if [[ " $* " = *' --show-cursor '* ]]; then
    lines=0
    [[ ! -f "$CADDY_SERVING_HEALTH_TEST_REMOTE_BASE/journal.log" ]] || \
        lines=$(wc -l <"$CADDY_SERVING_HEALTH_TEST_REMOTE_BASE/journal.log")
    printf '%s\n' "-- cursor: s=$lines"
elif [[ -f "$CADDY_SERVING_HEALTH_TEST_REMOTE_BASE/journal.log" ]]; then
    cursor=0
    while [[ $# -gt 0 ]]; do
        if [[ "$1" = --after-cursor ]]; then
            cursor=${2#s=}
            break
        fi
        shift
    done
    if [[ " $arguments " = *' -t '* ]]; then
        tail -n "+$((cursor + 1))" "$CADDY_SERVING_HEALTH_TEST_REMOTE_BASE/journal.log" |
            grep -E 'event=enqueued|keepalived-notify' || :
    else
        tail -n "+$((cursor + 1))" "$CADDY_SERVING_HEALTH_TEST_REMOTE_BASE/journal.log" |
            grep -Ev '^event=enqueued' || :
    fi
fi
JOURNALCTL
    cat >"$test_remote_base/bin/dig" <<'DIG'
#!/usr/bin/env bash
set -Eeuo pipefail
if [[ -e "$CADDY_SERVING_HEALTH_TEST_REMOTE_BASE/fail-next-curl" ]]; then
    rm -f -- "$CADDY_SERVING_HEALTH_TEST_REMOTE_BASE/fail-next-curl"
    exit 16
fi
if [[ -e "$CADDY_SERVING_HEALTH_TEST_REMOTE_BASE/inject-convergence-dns" ]]; then
    rm -f -- "$CADDY_SERVING_HEALTH_TEST_REMOTE_BASE/inject-convergence-dns"
    : >"$CADDY_SERVING_HEALTH_TEST_REMOTE_BASE/convergence-address-event"
    /usr/bin/sleep 0.1
    exit 9
fi
case " $* " in
    *' AAAA '*) printf '%s\n' 'fd36:5aa8:6971:1::55' ;;
    *) printf '%s\n' '10.1.0.55' ;;
esac
DIG
    cat >"$test_remote_base/bin/curl" <<'CURL'
#!/usr/bin/env bash
set -Eeuo pipefail
scenario_file=${CADDY_PRODUCTION_PATH_EVIDENCE_ROOT:?}/availability.scenario
scenario=$([[ -f "$scenario_file" ]] && cat "$scenario_file" || printf baseline)
if [[ "$scenario" =~ ^node-[ab]-lighttpd$ ]]; then
    affected_role=${scenario%-lighttpd}
    state_file=$CADDY_SERVING_HEALTH_TEST_REMOTE_BASE/state/${affected_role}-lighttpd_service.inactive
    if [[ -e "$state_file" ]] &&
        { [[ " $* " = *' https://pihole-admin.local.theama.co/'* ]] ||
            [[ "$CADDY_SERVING_HEALTH_TEST_NODE" = "$affected_role" &&
                " $* " = *'/admin/login.php'* ]]; }; then
        printf '%s\n' 'curl: (22) The requested URL returned error: 503' >&2
        exit 22
    fi
fi
case " $* " in
    *' https://proxy.local.theama.co/ '*) status=204 ;;
    *) status=200 ;;
esac
printf '%s\t0.001\t0.002\t0.003\t0.004\t10.1.0.56\t10.1.0.53' "$status"
CURL
    cat >"$test_remote_base/bin/date" <<'DATE'
#!/usr/bin/env bash
set -Eeuo pipefail
/usr/bin/date "$@"
DATE
    cat >"$test_remote_base/bin/sleep" <<'SLEEP'
#!/usr/bin/env bash
set -Eeuo pipefail
case "${1:-}" in
    0.01) /usr/bin/sleep 0.01 ;;
    1) /usr/bin/sleep 0.05 ;;
esac
SLEEP
    cat >"$test_remote_base/bin/sudo" <<'SUDO'
#!/usr/bin/env bash
set -Eeuo pipefail
[[ "$1" = -n ]]
shift
if [[ "$1" = /bin/bash && "$2" = -s && "$3" = -- &&
    ( "${4:-}" = exercise-* || "${4:-}" = sampler-* ) ]]; then
    mode=$4
    role=$5
    argument=${8:-}
    if [[ "$mode" = sampler-scenario && "$argument" = node-a-caddy &&
        -e "$CADDY_SERVING_HEALTH_TEST_REMOTE_BASE/fail-next-convergence-dns" ]]; then
        rm -f -- "$CADDY_SERVING_HEALTH_TEST_REMOTE_BASE/fail-next-convergence-dns"
        : >"$CADDY_SERVING_HEALTH_TEST_REMOTE_BASE/inject-convergence-dns"
    fi
    printf '%s\t%s\t%s\n' "$role" "$mode" "$argument" \
        >>"$CADDY_SERVING_HEALTH_TEST_REMOTE_BASE/transaction.calls"
    node_root=$CADDY_SERVING_HEALTH_TEST_REMOTE_BASE/$role-root
    exec env \
        CADDY_SERVING_HEALTH_PRODUCTION_PATH_TEST=1 \
        CADDY_SERVING_HEALTH_TARGET_ROOT="$node_root" \
        CADDY_SERVING_HEALTH_RELEASES_ROOT="$node_root/etc/caddy/releases" \
        CADDY_SERVING_HEALTH_SYSTEMCTL_COMMAND="$CADDY_SERVING_HEALTH_TEST_REMOTE_BASE/bin/systemctl" \
        CADDY_SERVING_HEALTH_BUSCTL_COMMAND="$CADDY_SERVING_HEALTH_TEST_REMOTE_BASE/bin/busctl" \
        CADDY_SERVING_HEALTH_IP_COMMAND="$CADDY_SERVING_HEALTH_TEST_REMOTE_BASE/bin/ip" \
        CADDY_SERVING_HEALTH_JOURNALCTL_COMMAND="$CADDY_SERVING_HEALTH_TEST_REMOTE_BASE/bin/journalctl" \
        CADDY_SERVING_HEALTH_DNS_DIG_COMMAND="$CADDY_SERVING_HEALTH_TEST_REMOTE_BASE/bin/dig" \
        CADDY_SERVING_HEALTH_CURL_COMMAND="$CADDY_SERVING_HEALTH_TEST_REMOTE_BASE/bin/curl" \
        CADDY_SERVING_HEALTH_DATE_COMMAND="$CADDY_SERVING_HEALTH_TEST_REMOTE_BASE/bin/date" \
        CADDY_SERVING_HEALTH_SLEEP_COMMAND="$CADDY_SERVING_HEALTH_TEST_REMOTE_BASE/bin/sleep" \
        CADDY_SERVING_HEALTH_OWNERSHIP_ATTEMPTS=2 \
        CADDY_SERVING_HEALTH_OWNERSHIP_STABLE_SAMPLES=1 \
        CADDY_SERVING_HEALTH_OWNERSHIP_SAMPLE_DELAY=0 \
        CADDY_SERVING_HEALTH_SAMPLER_MAX_CYCLES=200 \
        CADDY_SERVING_HEALTH_SAMPLER_DELAY=0.01 \
        CADDY_SERVING_HEALTH_TEST_NODE="$role" \
        "$@"
fi
exec "$@"
SUDO
    cat >"$test_remote_base/fake-ssh" <<'SSH'
#!/usr/bin/env bash
set -Eeuo pipefail
host=$1
shift
command="$*"
case "$host" in test-node-a) node=node-a ;; test-node-b) node=node-b ;; *) exit 64 ;; esac
printf '%s\t%s\n' "$node" "$command" >>"$CADDY_SERVING_HEALTH_TEST_REMOTE_BASE/ssh.calls"
PATH="$CADDY_SERVING_HEALTH_TEST_REMOTE_BASE/bin:/usr/bin:/bin" \
    CADDY_SERVING_HEALTH_TEST_NODE=$node \
    CADDY_SERVING_HEALTH_PRODUCTION_PATH_TEST=1 /bin/bash -c "$command"
SSH
    cat >"$test_remote_base/fake-scp" <<'SCP'
#!/usr/bin/env bash
set -Eeuo pipefail
[[ "$1" = -p && "$2" = -- ]]
source=$3
target=${4#*:}
printf '%s\t%s\n' "${4%%:*}" "$target" >>"$CADDY_SERVING_HEALTH_TEST_REMOTE_BASE/scp.calls"
install -m 0600 "$source" "$target"
SCP
    chmod 0700 "$test_remote_base/bin/sudo" "$test_remote_base/bin/systemctl" \
        "$test_remote_base/bin/busctl" "$test_remote_base/bin/ip" \
        "$test_remote_base/bin/journalctl" "$test_remote_base/bin/dig" \
        "$test_remote_base/bin/curl" "$test_remote_base/bin/date" \
        "$test_remote_base/bin/sleep" \
        "$test_remote_base/fake-ssh" "$test_remote_base/fake-scp"
    : >"$test_remote_base/ssh.calls"
    : >"$test_remote_base/scp.calls"
    : >"$test_remote_base/transaction.calls"
    : >"$test_remote_base/systemctl.calls"
    : >"$test_remote_base/journalctl.calls"
    : >"$test_remote_base/journal.log"
    ssh_command=$test_remote_base/fake-ssh
    scp_command=$test_remote_base/fake-scp
    node_a_host=test-node-a
    node_b_host=test-node-b

    exercise_revision=$(awk -F '\t' '$2 == "node-a" && $3 == "release" { print $4 }' \
        "$repository_root/Caddy/manifests/current-live-state.tsv" |
        sed -n 's/.*revision=\([^,]*\).*/\1/p')
    exercise_parent=$(awk -F '\t' '$2 == "node-a" && $3 == "release" { print $4 }' \
        "$repository_root/Caddy/manifests/current-live-state.tsv" |
        sed -n 's/.*parent=\([^,]*\).*/\1/p')
    for exercise_role in node-a node-b; do
        exercise_node_root=$test_remote_base/$exercise_role-root
        install -d -m 0700 "$exercise_node_root"
        while IFS=$'\t' read -r exercise_key exercise_repository exercise_source \
            exercise_target exercise_inventory_node exercise_source_hash \
            exercise_deployed_hash exercise_accepted exercise_lifecycle; do
            [[ "$exercise_key" = '# key' ]] && continue
            [[ "$exercise_inventory_node" = "$exercise_role" ||
                "$exercise_inventory_node" = both ]] || continue
            [[ "$exercise_repository" != runtime-generated ]] || continue
            [[ -n "$exercise_accepted" && "$exercise_lifecycle" = production-current ]]
            exercise_installed=$exercise_node_root$exercise_target
            install -d -m 0755 "$(dirname -- "$exercise_installed")"
            case "$exercise_key" in
                *_caddy_environment)
                    if [[ "$exercise_role" = node-a ]]; then
                        printf 'NODE_FQDN=pihole0.local.theama.co\nNODE_IPV4=10.1.0.53\nNODE_IPV6=fd36:5aa8:6971:1::53\n' \
                            >"$exercise_installed"
                    else
                        printf 'NODE_FQDN=pihole00.local.theama.co\nNODE_IPV4=10.1.0.54\nNODE_IPV6=fd36:5aa8:6971:1::54\n' \
                            >"$exercise_installed"
                    fi
                    ;;
                *_protocol_v2_reconciler)
                    git -C "$repository_root" show \
                        d131b9d:Caddy/scripts/reconcile-release-v2.sh \
                        >"$exercise_installed"
                    ;;
                *)
                    exercise_source_path=$workspace_root/$exercise_repository/$exercise_source
                    [[ "$(sha256sum "$exercise_source_path" | awk '{ print $1 }')" = "$exercise_source_hash" ]]
                    install -m 0600 "$exercise_source_path" "$exercise_installed"
                    ;;
            esac
            case "$exercise_target" in
                /etc/default/caddy-ha) chmod 0640 "$exercise_installed" ;;
                /etc/scripts/* | /usr/local/bin/* | /usr/local/libexec/*)
                    chmod 0755 "$exercise_installed"
                    ;;
                *) chmod 0644 "$exercise_installed" ;;
            esac
            [[ "$(sha256sum "$exercise_installed" | awk '{ print $1 }')" = "$exercise_deployed_hash" ]]
        done <"$repository_root/Caddy/manifests/production-artifacts.tsv"
        exercise_release=$exercise_node_root/etc/caddy/releases/$exercise_revision
        install -d -m 0750 "$exercise_release"
        cp -a -- "$repository_root/Caddy/configs/caddy/." "$exercise_release/"
        jq -n --arg revision "$exercise_revision" --arg parent "$exercise_parent" \
            '{revision:$revision,parent_revision:$parent,source_node:"node-a",created_at:"2026-08-18T17:15:16-05:00"}' \
            >"$exercise_release/release-manifest.json"
        (
            cd "$exercise_release"
            find . -type f ! -path ./manifest.sha256 ! -path ./.complete \
                ! -path ./.finalize-request -print0 | LC_ALL=C sort -z | xargs -0 sha256sum
        ) >"$exercise_release/manifest.sha256"
        find "$exercise_release" -type d -exec chmod 0550 {} +
        find "$exercise_release" -type f -exec chmod 0440 {} +
        install -d -m 0755 "$exercise_node_root/etc/caddy"
        ln -s "releases/$exercise_revision" "$exercise_node_root/etc/caddy/current"
        install -d -m 0700 "$exercise_node_root/var/lib/caddy-apprise-queue"/{pending,inflight,dead-letter,delivered}
        chmod 0700 "$exercise_node_root/var/lib/caddy-apprise-queue" \
            "$exercise_node_root/var/lib/caddy-apprise-queue"/*
        install -d -m 0755 "$exercise_node_root/var/lib/caddy-serving-health"
        install -d -m 0700 \
            "$exercise_node_root/var/lib/caddy-serving-health/keepalived-notify"
        if [[ "$exercise_role" = node-a ]]; then
            printf 'MASTER\n' >"$exercise_node_root/var/lib/caddy-serving-health/keepalived-notify/PIHOLE_DUALSTACK.state"
        else
            printf 'BACKUP\n' >"$exercise_node_root/var/lib/caddy-serving-health/keepalived-notify/PIHOLE_DUALSTACK.state"
        fi
        chmod 0600 \
            "$exercise_node_root/var/lib/caddy-serving-health/keepalived-notify/PIHOLE_DUALSTACK.state"
    done

    exercise_release=$test_remote_base/node-b-root/etc/caddy/releases/$exercise_revision
    chmod 0640 "$exercise_release/release-manifest.json"
    cp -- "$exercise_release/release-manifest.json" \
        "$test_remote_base/node-b-release-manifest.saved"
    jq '.revision = "stale-release"' "$test_remote_base/node-b-release-manifest.saved" \
        >"$exercise_release/release-manifest.json"
    chmod 0440 "$exercise_release/release-manifest.json"
    if run_controlled_failure_exercise_live; then
        exercise_status=0
    else
        exercise_status=$?
    fi
    [[ "$exercise_status" -ne 0 && "$exercise_status" -ne 125 ]]
    exercise_raw=$exercise_test_root/raw/outer-stale-preflight.txt
    exercise_decision=$exercise_test_root/decisions/outer-stale-preflight.tsv
    cat "$workstation_evidence/node-b-exercise-preflight.stdout" \
        "$workstation_evidence/node-b-exercise-preflight.stderr" >"$exercise_raw"
    grep -Fq 'serving_health_deployment_check_current_live_release_revision=false' \
        "$exercise_raw"
    write_decision outer-stale-preflight reject "$exercise_status" \
        current-production-release stale-release "$exercise_raw" "$exercise_decision"
    chmod 0750 "$exercise_release"
    chmod 0640 "$exercise_release/release-manifest.json"
    mv -- "$test_remote_base/node-b-release-manifest.saved" \
        "$exercise_release/release-manifest.json"
    chmod 0440 "$exercise_release/release-manifest.json"
    chmod 0550 "$exercise_release"

    : >"$test_remote_base/fail-next-stop"
    if run_controlled_failure_exercise_live; then
        exercise_status=0
    else
        exercise_status=$?
    fi
    [[ "$exercise_status" -ne 0 && "$exercise_status" -ne 125 ]]
    exercise_raw=$exercise_test_root/raw/outer-restored-failure-non125.txt
    exercise_decision=$exercise_test_root/decisions/outer-restored-failure-non125.tsv
    {
        printf 'exit_status=%s\n' "$exercise_status"
        find "$test_remote_base/state" -type f -printf '%f\n' 2>/dev/null | LC_ALL=C sort
        grep -F 'exercise-service' "$test_remote_base/transaction.calls"
    } >"$exercise_raw"
    [[ -z "$(find "$test_remote_base/state" -type f -print -quit 2>/dev/null)" ]]
    write_decision outer-restored-failure-non125 reject "$exercise_status" all-services-restored \
        failed-step-restored "$exercise_raw" "$exercise_decision"

    : >"$test_remote_base/fail-next-curl"
    if run_controlled_failure_exercise_live; then
        exercise_status=0
    else
        exercise_status=$?
    fi
    [[ "$exercise_status" -ne 0 && "$exercise_status" -ne 125 ]]
    exercise_raw=$exercise_test_root/raw/outer-acceptance-failure-non125.txt
    exercise_decision=$exercise_test_root/decisions/outer-acceptance-failure-non125.tsv
    {
        printf 'exit_status=%s\n' "$exercise_status"
        grep -F 'sampler-stop' "$test_remote_base/transaction.calls" | tail -2
    } >"$exercise_raw"
    write_decision outer-acceptance-failure-non125 reject "$exercise_status" \
        restored-acceptance-failure restored-acceptance-failure \
        "$exercise_raw" "$exercise_decision"
    exercise_raw=$exercise_test_root/raw/outer-causal-continuity-classification.txt
    exercise_decision=$exercise_test_root/decisions/outer-causal-continuity-classification.tsv
    cp -- "$workstation_evidence/continuity-correlation/classifications.tsv" "$exercise_raw"
    grep -Eq $'\t(handoff-overlap|settled-owner-serving-failure|family-degraded|unclassified-insufficient-evidence)$' \
        "$exercise_raw"
    write_decision outer-causal-continuity-classification reject "$exercise_status" \
        continuous-success classified-primary-failure "$exercise_raw" "$exercise_decision"

    : >"$test_remote_base/ssh.calls"
    : >"$test_remote_base/scp.calls"
    : >"$test_remote_base/transaction.calls"
    : >"$test_remote_base/fail-next-convergence-dns"
    run_controlled_failure_exercise_live
    exercise_raw=$exercise_test_root/raw/outer-bounded-convergence-retry.txt
    exercise_decision=$exercise_test_root/decisions/outer-bounded-convergence-retry.tsv
    cp -- "$workstation_evidence/continuity-correlation/classifications.tsv" "$exercise_raw"
    grep -Eq $'\tbounded-convergence-retry$' "$exercise_raw"
    write_decision outer-bounded-convergence-retry accept 0 \
        causally-correlated-bounded-recovery causally-correlated-bounded-recovery \
        "$exercise_raw" "$exercise_decision"
    exercise_stream=$workstation_evidence/node-a-readback.stdout
    exercise_original=$exercise_test_root/node-a-readback.saved
    exercise_payload_file=$exercise_test_root/node-a-availability.saved
    cp -- "$exercise_stream" "$exercise_original"
    extract_readback_file "$exercise_stream" availability.tsv "$exercise_payload_file"

    awk '
        $0 ~ /^file=availability\.tsv / { getline; next }
        { print }
    ' "$exercise_original" >"$exercise_stream"
    exercise_expect_correlation_rejection missing "$exercise_stream" "$exercise_original"

    awk '
        $0 ~ /^file=availability\.tsv / {
            metadata=$0; getline; print metadata; print; print metadata; print; next
        }
        { print }
    ' "$exercise_original" >"$exercise_stream"
    exercise_expect_correlation_rejection duplicate "$exercise_stream" "$exercise_original"

    awk -F '\t' -v OFS='\t' 'NR == 2 { $3="not-a-sequence" } { print }' \
        "$exercise_payload_file" >"$exercise_test_root/node-a-availability.malformed"
    exercise_replace_readback_entry "$exercise_stream" availability.tsv \
        "$exercise_test_root/node-a-availability.malformed"
    exercise_expect_correlation_rejection malformed "$exercise_stream" "$exercise_original"

    awk 'NR == 1 { header=$0; next } { rows[++count]=$0 }
        END { print header; for (row_index=count; row_index >= 1; row_index--) print rows[row_index] }' \
        "$exercise_payload_file" >"$exercise_test_root/node-a-availability.reordered"
    exercise_replace_readback_entry "$exercise_stream" availability.tsv \
        "$exercise_test_root/node-a-availability.reordered"
    exercise_expect_correlation_rejection reordered "$exercise_stream" "$exercise_original"

    sed '0,/bytes=[0-9][0-9]*/s//bytes=1048577/' "$exercise_original" >"$exercise_stream"
    exercise_expect_correlation_rejection oversized "$exercise_stream" "$exercise_original"

    sed '$d' "$exercise_original" >"$exercise_stream"
    exercise_expect_correlation_rejection incomplete "$exercise_stream" "$exercise_original"

    exercise_symlink=$exercise_test_root/readback-destination.symlink
    ln -s /tmp/caddy-readback-unsafe "$exercise_symlink"
    exercise_raw=$exercise_test_root/raw/outer-continuity-symlinked.txt
    exercise_decision=$exercise_test_root/decisions/outer-continuity-symlinked.tsv
    if extract_readback_file "$exercise_original" availability.tsv "$exercise_symlink" \
        >"$exercise_raw" 2>&1; then exercise_status=0; else exercise_status=$?; fi
    [[ "$exercise_status" -ne 0 ]]
    write_decision outer-continuity-symlinked reject "$exercise_status" regular-file symlink \
        "$exercise_raw" "$exercise_decision"
    rm -f -- "$exercise_symlink"

    exercise_raw=$exercise_test_root/raw/outer-preflight.txt
    exercise_decision=$exercise_test_root/decisions/outer-preflight.tsv
    cat "$test_remote_base/scp.calls" "$test_remote_base/ssh.calls" >"$exercise_raw"
    grep -Fq $'node-b\tcd / && sudo -n /bin/bash -s -- exercise-preflight node-b' "$exercise_raw"
    grep -Fq $'node-a\tcd / && sudo -n /bin/bash -s -- exercise-preflight node-a' "$exercise_raw"
    write_decision outer-preflight reach 0 dual-node-preflight dual-node-preflight \
        "$exercise_raw" "$exercise_decision"

    exercise_raw=$exercise_test_root/raw/outer-real-preflight.txt
    exercise_decision=$exercise_test_root/decisions/outer-real-preflight.tsv
    cat "$workstation_evidence/node-b-exercise-preflight.stdout" \
        "$workstation_evidence/node-a-exercise-preflight.stdout" >"$exercise_raw"
    [[ "$(grep -Fc 'serving_health_deployment_check_current_live_manifest_valid=true' \
        "$exercise_raw")" -eq 2 ]]
    [[ "$(grep -Fc 'serving_health_deployment_check_notification_state_inventory=true' \
        "$exercise_raw")" -eq 2 ]]
    [[ "$(grep -Fc 'serving_health_deployment_check_exercise_mutation_residue_absent=true' \
        "$exercise_raw")" -eq 2 ]]
    write_decision outer-real-preflight reach 0 \
        dual-node-real-transaction-preflight dual-node-real-transaction-preflight \
        "$exercise_raw" "$exercise_decision"

    exercise_raw=$exercise_test_root/raw/outer-full-scenario-sequence.txt
    exercise_decision=$exercise_test_root/decisions/outer-full-scenario-sequence.tsv
    cp -- "$test_remote_base/transaction.calls" "$exercise_raw"
    for scenario in node-a-caddy node-a-lighttpd node-a-pihole-ftl node-a-unbound \
        node-a-keepalived node-b-caddy node-b-lighttpd node-b-pihole-ftl node-b-unbound; do
        grep -Fq "$scenario" "$exercise_raw"
    done
    write_decision outer-full-scenario-sequence accept 0 complete complete \
        "$exercise_raw" "$exercise_decision"

    exercise_raw=$exercise_test_root/raw/outer-readback-cleanup.txt
    exercise_decision=$exercise_test_root/decisions/outer-readback-cleanup.tsv
    {
        printf 'node_a_payload=%s\n' "$([[ ! -e "$node_a_payload" ]] && printf absent || printf present)"
        printf 'node_b_payload=%s\n' "$([[ ! -e "$node_b_payload" ]] && printf absent || printf present)"
        grep -F 'sampler-' "$test_remote_base/transaction.calls"
    } >"$exercise_raw"
    grep -Fxq 'node_a_payload=absent' "$exercise_raw"
    grep -Fxq 'node_b_payload=absent' "$exercise_raw"
    write_decision outer-readback-cleanup accept 0 absent absent \
        "$exercise_raw" "$exercise_decision"
    chmod -R u+rwX -- "$exercise_remote_base"
    rm -rf -- "$exercise_remote_base"
    printf '%s_controlled_failure_exercise_production_path_test_complete=true\n' "$prefix"
    printf '%s_production_path_test_complete=true\n' "$prefix"
}

notification_outer_production_path_test() {
    local notification_test_root=${CADDY_PRODUCTION_PATH_EVIDENCE_ROOT:?missing evidence root}
    local notification_remote_root notification_node_root notification_path
    local notification_raw notification_decision notification_status notification_observed

    notification_remote_root=$(mktemp -d /tmp/caddy-notification-outer.XXXXXX)
    test_remote_base=$notification_remote_root
    export CADDY_SERVING_HEALTH_TEST_REMOTE_BASE=$test_remote_base
    install -d -m 0700 "$test_remote_base/bin"
    for notification_node_root in node-a-root node-b-root; do
        install -d -m 0700 "$test_remote_base/$notification_node_root/var/lib/caddy-apprise-queue"/{pending,inflight,dead-letter,delivered}
        chmod 0700 "$test_remote_base/$notification_node_root/var/lib/caddy-apprise-queue" \
            "$test_remote_base/$notification_node_root/var/lib/caddy-apprise-queue"/*
        install -d -m 0755 \
            "$test_remote_base/$notification_node_root/var/lib/caddy-serving-health"
        install -d -m 0700 \
            "$test_remote_base/$notification_node_root/var/lib/caddy-serving-health/keepalived-notify"
        if [[ "$notification_node_root" = node-a-root ]]; then
            printf 'MASTER\n' \
                >"$test_remote_base/$notification_node_root/var/lib/caddy-serving-health/keepalived-notify/PIHOLE_DUALSTACK.state"
        else
            printf 'BACKUP\n' \
                >"$test_remote_base/$notification_node_root/var/lib/caddy-serving-health/keepalived-notify/PIHOLE_DUALSTACK.state"
        fi
        chmod 0600 \
            "$test_remote_base/$notification_node_root/var/lib/caddy-serving-health/keepalived-notify/PIHOLE_DUALSTACK.state"
        while IFS=$'\t' read -r notification_repository notification_source notification_path \
            notification_mode _notification_baseline _notification_candidate; do
            install -d -m 0755 "$test_remote_base/$notification_node_root/$(dirname "$notification_path")"
            if [[ "$notification_repository" = homelab-server-configs ]]; then
                git -C "$repository_root" show \
                    "eb1e4471f87af7c80662d4e8aabb577e848bd03c:$notification_source" \
                    >"$test_remote_base/$notification_node_root$notification_path"
            else
                git -C "$workspace_root/homelab-dns" show "ab9965fd:$notification_source" \
                    >"$test_remote_base/$notification_node_root$notification_path"
            fi
            chmod "$notification_mode" "$test_remote_base/$notification_node_root$notification_path"
        done < <(
            printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
                homelab-server-configs Caddy/scripts/caddy-apprise-enqueue.sh /usr/local/libexec/caddy-apprise-enqueue 0755 x x \
                homelab-server-configs Caddy/scripts/caddy-apprise-delivery-worker.sh /usr/local/libexec/caddy-apprise-delivery-worker 0755 x x \
                homelab-dns Keepalived/scripts/keepalived-notify.sh /usr/local/bin/keepalived-notify.sh 0755 x x \
                homelab-server-configs Caddy/configs/tmpfiles.d/caddy-ha.conf /etc/tmpfiles.d/caddy-ha.conf 0644 x x \
                homelab-dns Keepalived/scripts/dns-check.sh /etc/scripts/check-dns.sh 0755 x x \
                homelab-server-configs Caddy/scripts/check-caddy-serving-health.sh /usr/local/libexec/check-caddy.sh 0755 x x
        )
    done
    cat >"$test_remote_base/bin/sudo" <<'SUDO'
#!/usr/bin/env bash
set -Eeuo pipefail
[[ "$1" = -n ]]
shift
export CADDY_SERVING_HEALTH_PRODUCTION_PATH_TEST=1
exec "$@"
SUDO
    cat >"$test_remote_base/bin/systemctl" <<'SYSTEMCTL'
#!/usr/bin/env bash
printf '%s\t%s\n' "${CADDY_SERVING_HEALTH_TEST_NODE:?}" "$*" >>"$CADDY_SERVING_HEALTH_TEST_REMOTE_BASE/systemctl.calls"
[[ "$1" = is-active && "$2" = --quiet ]]
SYSTEMCTL
    cat >"$test_remote_base/bin/tmpfiles" <<'TMPFILES'
#!/usr/bin/env bash
printf '%s\t%s\n' "${CADDY_SERVING_HEALTH_TEST_NODE:?}" "$*" >>"$CADDY_SERVING_HEALTH_TEST_REMOTE_BASE/tmpfiles.calls"
install -d -m 0755 "$CADDY_SERVING_HEALTH_TARGET_ROOT/var/lib/caddy-serving-health"
install -d -m 0700 "$CADDY_SERVING_HEALTH_TARGET_ROOT/var/lib/caddy-serving-health/keepalived-notify"
TMPFILES
    cat >"$test_remote_base/bin/busctl" <<'BUSCTL'
#!/usr/bin/env bash
set -Eeuo pipefail
printf '%s\t%s\n' "${CADDY_SERVING_HEALTH_TEST_NODE:?}" "$*" >>"$CADDY_SERVING_HEALTH_TEST_REMOTE_BASE/busctl.calls"
if [[ "$CADDY_SERVING_HEALTH_TEST_NODE" = node-a ]]; then
    printf 's "Master"\n'
else
    printf 's "Backup"\n'
fi
BUSCTL
    cat >"$test_remote_base/bin/ip" <<'IP'
#!/usr/bin/env bash
set -Eeuo pipefail
printf '%s\t%s\n' "${CADDY_SERVING_HEALTH_TEST_NODE:?}" "$*" >>"$CADDY_SERVING_HEALTH_TEST_REMOTE_BASE/ip.calls"
if [[ "$CADDY_SERVING_HEALTH_TEST_NODE" = node-a ]]; then
    printf '2: eth0    inet 10.1.0.55/22 scope global eth0\n'
    printf '2: eth0    inet 10.1.0.56/22 scope global eth0\n'
    printf '2: eth0    inet6 fd36:5aa8:6971:1::55/128 scope global\n'
    printf '2: eth0    inet6 fd36:5aa8:6971:1::56/128 scope global\n'
else
    printf '2: eth0    inet 10.1.0.54/22 scope global eth0\n'
    printf '2: eth0    inet6 fd36:5aa8:6971:1::54/64 scope global\n'
fi
IP
    cat >"$test_remote_base/fake-ssh" <<'SSH'
#!/usr/bin/env bash
set -Eeuo pipefail
host=$1
shift
command="$*"
case "$host" in test-node-a) node=node-a ;; test-node-b) node=node-b ;; *) exit 64 ;; esac
target_root=$CADDY_SERVING_HEALTH_TEST_REMOTE_BASE/$node-root
printf '%s\t%s\n' "$node" "$command" >>"$CADDY_SERVING_HEALTH_TEST_REMOTE_BASE/ssh.calls"
if [[ "$node" = node-a && -e "$CADDY_SERVING_HEALTH_TEST_REMOTE_BASE/fail-node-a" &&
    "$command" = *' notification-accept '* ]]; then
    printf '# tamper\n' >>"$target_root/usr/local/libexec/caddy-apprise-enqueue"
fi
PATH="$CADDY_SERVING_HEALTH_TEST_REMOTE_BASE/bin:/usr/bin:/bin" \
    CADDY_SERVING_HEALTH_TEST_NODE=$node \
    CADDY_SERVING_HEALTH_TARGET_ROOT=$target_root \
    CADDY_SERVING_HEALTH_SYSTEMCTL_COMMAND="$CADDY_SERVING_HEALTH_TEST_REMOTE_BASE/bin/systemctl" \
    CADDY_SERVING_HEALTH_SYSTEMD_TMPFILES_COMMAND="$CADDY_SERVING_HEALTH_TEST_REMOTE_BASE/bin/tmpfiles" \
    CADDY_SERVING_HEALTH_BUSCTL_COMMAND="$CADDY_SERVING_HEALTH_TEST_REMOTE_BASE/bin/busctl" \
    CADDY_SERVING_HEALTH_IP_COMMAND="$CADDY_SERVING_HEALTH_TEST_REMOTE_BASE/bin/ip" \
    /bin/bash -c "$command"
SSH
    cat >"$test_remote_base/fake-scp" <<'SCP'
#!/usr/bin/env bash
set -Eeuo pipefail
[[ "$1" = -p && "$2" = -- ]]
source=$3
target=${4#*:}
printf '%s\t%s\n' "${4%%:*}" "$target" >>"$CADDY_SERVING_HEALTH_TEST_REMOTE_BASE/scp.calls"
install -m 0600 "$source" "$target"
SCP
    chmod 0700 "$test_remote_base/bin/"* "$test_remote_base/fake-ssh" "$test_remote_base/fake-scp"
    : >"$test_remote_base/systemctl.calls"
    : >"$test_remote_base/tmpfiles.calls"
    : >"$test_remote_base/busctl.calls"
    : >"$test_remote_base/ip.calls"
    : >"$test_remote_base/ssh.calls"
    : >"$test_remote_base/scp.calls"
    ssh_command=$test_remote_base/fake-ssh
    scp_command=$test_remote_base/fake-scp
    node_a_host=test-node-a
    node_b_host=test-node-b

    : >"$test_remote_base/fail-node-a"
    if run_notification_standardization_live; then notification_status=0; else notification_status=$?; fi
    [[ "$notification_status" -ne 0 && "$notification_status" -ne 125 ]]
    notification_raw=$notification_test_root/raw/outer-reverse-rollback.txt
    notification_decision=$notification_test_root/decisions/outer-reverse-rollback.tsv
    grep -E 'notification-(install|rollback)' "$test_remote_base/ssh.calls" >"$notification_raw"
    grep -Fq $'node-a\tcd / && sudo -n /bin/bash -s -- notification-rollback' "$notification_raw"
    grep -Fq $'node-b\tcd / && sudo -n /bin/bash -s -- notification-rollback' "$notification_raw"
    write_decision outer-reverse-rollback reject "$notification_status" failed-and-restored failed-and-restored \
        "$notification_raw" "$notification_decision"

    rm -f -- "$test_remote_base/fail-node-a"
    : >"$test_remote_base/ssh.calls"
    : >"$test_remote_base/scp.calls"
    run_notification_standardization_live
    notification_raw=$notification_test_root/raw/outer-preflight.txt
    notification_decision=$notification_test_root/decisions/outer-preflight.tsv
    cat "$test_remote_base/scp.calls" "$test_remote_base/ssh.calls" \
        "$test_remote_base/busctl.calls" "$test_remote_base/ip.calls" \
        >"$notification_raw"
    notification_observed=$(wc -l <"$notification_raw")
    write_decision outer-preflight reach 0 "$notification_observed" "$notification_observed" \
        "$notification_raw" "$notification_decision"
    notification_raw=$notification_test_root/raw/outer-standby-first.txt
    notification_decision=$notification_test_root/decisions/outer-standby-first.tsv
    grep -E 'notification-(install|accept)' "$test_remote_base/ssh.calls" >"$notification_raw"
    [[ "$(sed -n '1p' "$notification_raw")" = *$'node-b\t'*notification-install* ]]
    [[ "$(sed -n '2p' "$notification_raw")" = *$'node-b\t'*notification-accept* ]]
    [[ "$(sed -n '3p' "$notification_raw")" = *$'node-a\t'*notification-install* ]]
    [[ "$(sed -n '4p' "$notification_raw")" = *$'node-a\t'*notification-accept* ]]
    write_decision outer-standby-first accept 0 node-b-then-node-a node-b-then-node-a \
        "$notification_raw" "$notification_decision"
    notification_raw=$notification_test_root/raw/outer-evidence-readback.txt
    notification_decision=$notification_test_root/decisions/outer-evidence-readback.tsv
    cat "$workstation_evidence/node-b-readback.stdout" "$workstation_evidence/node-a-readback.stdout" \
        >"$notification_raw"
    grep -Fq 'file=mutation.tsv' "$notification_raw"
    write_decision outer-evidence-readback accept 0 both-nodes both-nodes \
        "$notification_raw" "$notification_decision"
    notification_raw=$notification_test_root/raw/outer-zero-residue.txt
    notification_decision=$notification_test_root/decisions/outer-zero-residue.tsv
    printf 'node_a=%s\nnode_b=%s\n' \
        "$([[ ! -e "$node_a_payload" ]] && printf absent || printf present)" \
        "$([[ ! -e "$node_b_payload" ]] && printf absent || printf present)" >"$notification_raw"
    write_decision outer-zero-residue accept 0 absent absent "$notification_raw" "$notification_decision"
    if grep -Eq $'\t(restart|reload|stop|start) (caddy|lighttpd|pihole-FTL|unbound|keepalived)\\.service$' \
        "$test_remote_base/systemctl.calls"; then return 1; fi
    chmod -R u+rwX -- "$test_remote_base"
    rm -rf -- "$test_remote_base"
    printf '%s_notification_standardization_production_path_test_complete=true\n' "$prefix"
    printf '%s_production_path_test_complete=true\n' "$prefix"
}

production_path_test() {
    local serving_health_test_root=${CADDY_PRODUCTION_PATH_EVIDENCE_ROOT:?missing evidence root}
    local serving_health_remote_base serving_health_raw serving_health_decision serving_health_observed
    local serving_health_status serving_health_role serving_health_remote_evidence serving_health_test_id
    local serving_health_tmpfiles_line serving_health_keepalived_stop_line
    local serving_health_keepalived_line
    local serving_health_mode serving_health_variant_root serving_health_variant_evidence
    local retained_root retained_candidate retained_release_hash retained_payload_hash
    local serving_health_transaction_test_evidence

    [[ "$serving_health_test_root" = /tmp/* && -d "$serving_health_test_root" && ! -L "$serving_health_test_root" ]]
    chmod 0700 "$serving_health_test_root"
    install -d -m 0700 "$serving_health_test_root/raw" "$serving_health_test_root/decisions"
    if [[ "$operation_scope" = pihole-web-health-unit-only ]]; then
        web_health_unit_outer_production_path_test
        return
    fi
    if [[ "$operation_scope" = notification-standardization-only ]]; then
        notification_outer_production_path_test
        return
    fi
    if [[ "$operation_scope" = external-notification-attribution-read-only ]]; then
        external_attribution_outer_production_path_test
        return
    fi
    if [[ "$operation_scope" = controlled-serving-failure-exercise ]]; then
        controlled_failure_outer_production_path_test
        return
    fi
    serving_health_remote_base=$(mktemp -d /tmp/caddy-serving-health-production-path.XXXXXX)
    serving_health_test_id=${serving_health_remote_base##*.}
    test_remote_base=$serving_health_remote_base
    export CADDY_SERVING_HEALTH_TEST_REMOTE_BASE=$test_remote_base
    ssh_command=$workstation_evidence/fake-ssh
    scp_command=$workstation_evidence/fake-scp
    install -d -m 0700 "$test_remote_base/bin"
    cat >"$test_remote_base/bin/sudo" <<'SUDO'
#!/usr/bin/env bash
set -Eeuo pipefail
[[ "$1" = -n ]]
shift
export CADDY_SERVING_HEALTH_PRODUCTION_PATH_TEST=1
exec "$@"
SUDO
    cat >"$test_remote_base/bin/runuser" <<'RUNUSER'
#!/usr/bin/env bash
set -Eeuo pipefail
[[ "$1" = -u ]]
runuser_identity=$2
runuser_group=default
shift 2
if [[ "$1" = -g ]]; then
    runuser_group=$2
    shift 2
fi
[[ "$1" = -- ]]
shift
printf '%s:%s\n' "$runuser_identity" "$runuser_group" \
    >>"$CADDY_SERVING_HEALTH_TEST_REMOTE_BASE/runuser.identities"
printf 'runuser %s:%s\n' "$runuser_identity" "$runuser_group" \
    >>"$CADDY_SERVING_HEALTH_TEST_REMOTE_BASE/ordering.calls"
if [[ "${1:-}" = env && "${2:-}" = -i ]]; then
    shift 2
    exec env -i CADDY_SERVING_HEALTH_TEST_REMOTE_BASE="$CADDY_SERVING_HEALTH_TEST_REMOTE_BASE" "$@"
fi
exec "$@"
RUNUSER
    cat >"$test_remote_base/bin/keepalived" <<'KEEPALIVED'
#!/usr/bin/env bash
set -Eeuo pipefail
printf '%s\n' "$*" >>"$CADDY_SERVING_HEALTH_TEST_REMOTE_BASE/prohibited-keepalived-parser.calls"
exit 97
KEEPALIVED
    cat >"$test_remote_base/bin/unbound-checkconf" <<'UNBOUND_CHECKCONF'
#!/usr/bin/env bash
set -Eeuo pipefail
[[ $# -eq 1 && -f "$1" ]]
grep -Fq 'local-zone: "local.theama.co." static' "$1"
UNBOUND_CHECKCONF
    cat >"$test_remote_base/bin/systemctl" <<'SYSTEMCTL'
#!/usr/bin/env bash
set -Eeuo pipefail
printf '%s\n' "$*" >>"$CADDY_SERVING_HEALTH_TEST_REMOTE_BASE/systemctl.calls"
printf 'systemctl %s\n' "$*" >>"$CADDY_SERVING_HEALTH_TEST_REMOTE_BASE/ordering.calls"
state_root=${CADDY_SERVING_HEALTH_TARGET_ROOT:-$CADDY_SERVING_HEALTH_TEST_REMOTE_BASE/default-root}
state_file=$state_root/run/serving_health-keepalived-stopped
case "$1" in
    is-active)
        [[ "$2" = --quiet ]]
        if [[ "$3" = keepalived.service && -e "$state_file" ]]; then
            exit 3
        fi
        ;;
    stop)
        [[ $# -eq 2 ]]
        if [[ "$2" = keepalived.service ]]; then
            install -d -m 0755 "${state_file%/*}"
            : >"$state_file"
        fi
        ;;
    start)
        [[ $# -eq 2 ]]
        if [[ "$2" = keepalived.service ]]; then
            rm -f -- "$state_file"
            if [[ -x "$CADDY_SERVING_HEALTH_TARGET_ROOT/etc/scripts/check-dns.sh" &&
                -x "$CADDY_SERVING_HEALTH_TARGET_ROOT/usr/local/libexec/check-caddy.sh" ]]; then
                for sequence in 1 2 3; do
                    env DNS_CHECK_DIG_COMMAND="$CADDY_SERVING_HEALTH_TEST_REMOTE_BASE/bin/dig" \
                        DNS_CHECK_SYSTEMCTL_COMMAND="$CADDY_SERVING_HEALTH_TEST_REMOTE_BASE/bin/systemctl" \
                        "$CADDY_SERVING_HEALTH_TEST_REMOTE_BASE/bin/runuser" -u pi -- \
                        "$CADDY_SERVING_HEALTH_TARGET_ROOT/etc/scripts/check-dns.sh"
                    env CADDY_SERVING_HEALTH_ENVIRONMENT_FILE="$CADDY_SERVING_HEALTH_TARGET_ROOT/etc/default/caddy-ha" \
                        CADDY_SERVING_HEALTH_CURL_COMMAND="$CADDY_SERVING_HEALTH_TEST_REMOTE_BASE/bin/curl" \
                        CADDY_SERVING_HEALTH_SYSTEMCTL_COMMAND="$CADDY_SERVING_HEALTH_TEST_REMOTE_BASE/bin/systemctl" \
                        "$CADDY_SERVING_HEALTH_TEST_REMOTE_BASE/bin/runuser" -u keepalived_script \
                        -g caddy-tls -- "$CADDY_SERVING_HEALTH_TARGET_ROOT/usr/local/libexec/check-caddy.sh"
                done
            fi
            printf '%s\n' \
                'test-host systemd[1]: Starting keepalived.service - Keepalive Daemon...' \
                'test-host systemd[1]: Started keepalived.service - Keepalive Daemon.' \
                'test-host Keepalived_vrrp[100]: VRRP_Script(check-dns) considered successful on startup' \
                'test-host Keepalived_vrrp[100]: VRRP_Script(check-caddy) considered successful on startup' \
                >>"$CADDY_SERVING_HEALTH_TEST_REMOTE_BASE/keepalived.journal"
            if [[ "${CADDY_SERVING_HEALTH_TEST_DAEMON_MODE:-success}" = journal-failure ]]; then
                printf '%s\n' \
                    'test-host Keepalived_vrrp[100]: VRRP_Script(check-caddy) failed (exited with status 1)' \
                    >>"$CADDY_SERVING_HEALTH_TEST_REMOTE_BASE/keepalived.journal"
            fi
        fi
        ;;
    daemon-reload | reload | enable | disable) : ;;
    *) exit 64 ;;
esac
SYSTEMCTL
    cat >"$test_remote_base/bin/systemd-tmpfiles" <<'TMPFILES'
#!/usr/bin/env bash
set -Eeuo pipefail
[[ "$1" = --create && "$2" = "${CADDY_SERVING_HEALTH_TARGET_ROOT:?}/etc/tmpfiles.d/caddy-ha.conf" ]]
install -d -m 0755 "$CADDY_SERVING_HEALTH_TARGET_ROOT/run/caddy-serving-health"
install -d -m 0755 "$CADDY_SERVING_HEALTH_TARGET_ROOT/run/caddy-serving-health/keepalived"
printf '%s\n' "$*" >>"$CADDY_SERVING_HEALTH_TEST_REMOTE_BASE/tmpfiles.calls"
printf 'tmpfiles %s\n' "$*" >>"$CADDY_SERVING_HEALTH_TEST_REMOTE_BASE/ordering.calls"
TMPFILES
    cat >"$test_remote_base/bin/dig" <<'DIG'
#!/usr/bin/env bash
if [[ "${CADDY_SERVING_HEALTH_TEST_DIG_FAIL:-0}" = 1 ]]; then
    exit 9
fi
case " $* " in
    *' A '*) printf '10.1.0.55\n' ;;
    *' AAAA '*) printf 'fd36:5aa8:6971:1::55\n' ;;
    *) exit 64 ;;
esac
DIG
    cat >"$test_remote_base/bin/curl" <<'CURL'
#!/usr/bin/env bash
case "${CADDY_SERVING_HEALTH_TEST_CURL_MODE:-success}" in
    failure) exit 7 ;;
    timeout | signal) /usr/bin/sleep 0.20 ;;
    success) : ;;
    *) exit 64 ;;
esac
printf '204\n'
CURL
    cat >"$test_remote_base/bin/ss" <<'SS'
#!/usr/bin/env bash
printf 'LISTEN 0 4096 10.1.0.53:443 0.0.0.0:*\n'
printf 'LISTEN 0 4096 [fd36:5aa8:6971:1::53]:443 [::]:*\n'
printf 'LISTEN 0 4096 10.1.0.54:443 0.0.0.0:*\n'
printf 'LISTEN 0 4096 [fd36:5aa8:6971:1::54]:443 [::]:*\n'
SS
    cat >"$test_remote_base/bin/journalctl" <<'JOURNALCTL'
#!/usr/bin/env bash
set -Eeuo pipefail
case " $* " in
    *' --show-cursor '*) printf '%s\n' '-- cursor: s=serving_health-production-path' ;;
    *' --after-cursor '*)
        if [[ -s "$CADDY_SERVING_HEALTH_TEST_REMOTE_BASE/keepalived.journal" ]]; then
            cat "$CADDY_SERVING_HEALTH_TEST_REMOTE_BASE/keepalived.journal"
        else
            printf '%s\n' 'test-host caddy.service: serving_health production-path event'
        fi
        ;;
    *) exit 64 ;;
esac
JOURNALCTL
    cat >"$test_remote_base/bin/sleep" <<'SLEEP'
#!/usr/bin/env bash
set -Eeuo pipefail
[[ $# -eq 1 && "$1" =~ ^[0-9]+([.][0-9]+)?$ ]]
/usr/bin/sleep 0.02
SLEEP
    cat >"$ssh_command" <<'SSH'
#!/usr/bin/env bash
set -Eeuo pipefail
host=$1
shift
command="$*"
printf '%s\t%s\n' "$host" "$command" >>"$CADDY_SERVING_HEALTH_TEST_REMOTE_BASE/ssh.calls"
PATH="$CADDY_SERVING_HEALTH_TEST_REMOTE_BASE/bin:/usr/bin:/bin" /bin/bash -c "$command"
SSH
    cat >"$scp_command" <<'SCP'
#!/usr/bin/env bash
set -Eeuo pipefail
[[ "$1" = -p && "$2" = -- ]]
source=$3
target=${4#*:}
printf '%s\t%s\n' "$source" "$target" >>"$CADDY_SERVING_HEALTH_TEST_REMOTE_BASE/scp.calls"
install -o "$(id -un)" -g "$(id -gn)" -m 0600 "$source" "$target"
SCP
    chmod 0700 "$ssh_command" "$scp_command" "$test_remote_base/bin/"*
    export CADDY_SERVING_HEALTH_SLEEP_COMMAND=$test_remote_base/bin/sleep
    printf 'NODE_FQDN=pihole0.local.theama.co\nNODE_IPV4=10.1.0.53\nNODE_IPV6=fd36:5aa8:6971:1::53\n' \
        >"$test_remote_base/environment-node-a"
    printf 'NODE_FQDN=pihole00.local.theama.co\nNODE_IPV4=10.1.0.54\nNODE_IPV6=fd36:5aa8:6971:1::54\n' \
        >"$test_remote_base/environment-node-b"
    node_a_host=test-node-a
    node_b_host=test-node-b
    node_a_payload=/tmp/caddy-serving-health-test-$serving_health_test_id-node-a
    node_b_payload=/tmp/caddy-serving-health-test-$serving_health_test_id-node-b
    node_a_archive=$node_a_payload.tar
    node_b_archive=$node_b_payload.tar
    node_a_evidence=$node_a_payload/evidence
    node_b_evidence=$node_b_payload/evidence
    build_payload
    write_remote_programs
    upload_payload node-a "$node_a_host" "$node_a_payload" "$node_a_archive"
    upload_payload node-b "$node_b_host" "$node_b_payload" "$node_b_archive"
    retained_root=$test_remote_base/retained
    retained_candidate=$retained_root/incoming/node-a/action17p-node-a-to-node-b-bootstrap
    install -d -m 0700 "$retained_candidate" \
        "$retained_root/outgoing" "$retained_root/quarantine" "$retained_root/releases"
    printf 'payload\n' >"$retained_candidate/Caddyfile"
    printf '%s  Caddyfile\n' "$(sha256sum "$retained_candidate/Caddyfile" | awk '{ print $1 }')" \
        >"$retained_candidate/manifest.sha256"
    printf '%s\n' \
        '{"revision":"action17p-node-a-to-node-b-bootstrap","source_node":"node-a"}' \
        >"$retained_candidate/release-manifest.json"
    chmod 0500 "$retained_candidate"
    retained_release_hash=$(sha256sum "$retained_candidate/release-manifest.json" | awk '{ print $1 }')
    retained_payload_hash=$(sha256sum "$retained_candidate/manifest.sha256" | awk '{ print $1 }')
    CADDY_SERVING_HEALTH_INCOMING_ROOT=$retained_root/incoming \
        CADDY_SERVING_HEALTH_OUTGOING_ROOT=$retained_root/outgoing \
        CADDY_SERVING_HEALTH_QUARANTINE_ROOT=$retained_root/quarantine \
        CADDY_SERVING_HEALTH_RELEASES_ROOT=$retained_root/releases \
        CADDY_SERVING_HEALTH_RETAINED_RELEASE_MANIFEST_SHA256=$retained_release_hash \
        CADDY_SERVING_HEALTH_RETAINED_PAYLOAD_MANIFEST_SHA256=$retained_payload_hash \
        remote_transaction node-b-retained-check-producer "$node_b_host" retained-check \
        node-b "$node_b_payload" "$node_b_evidence"
    [[ -d "$retained_candidate" ]]
    CADDY_SERVING_HEALTH_ENVIRONMENT_FILE=$test_remote_base/environment-node-b \
        CADDY_SERVING_HEALTH_UNBOUND_CHECKCONF_COMMAND=$test_remote_base/bin/unbound-checkconf \
        CADDY_SERVING_HEALTH_RUNUSER_COMMAND=$test_remote_base/bin/runuser \
        CADDY_SERVING_HEALTH_SYSTEMCTL_COMMAND=$test_remote_base/bin/systemctl \
        CADDY_SERVING_HEALTH_DNS_DIG_COMMAND=$test_remote_base/bin/dig \
        CADDY_SERVING_HEALTH_CURL_COMMAND=$test_remote_base/bin/curl \
        CADDY_SERVING_HEALTH_SS_COMMAND=$test_remote_base/bin/ss \
        remote_transaction node-b-candidate-producer "$node_b_host" candidate-check \
        node-b "$node_b_payload" "$node_b_evidence"
    if [[ -e "$test_remote_base/prohibited-keepalived-parser.calls" ]]; then
        printf '%s_check_keepalived_parser_not_invoked=false\n' "$prefix" >&2
        return 1
    fi
    printf '%s_check_keepalived_parser_not_invoked=true\n' "$prefix"
    CADDY_SERVING_HEALTH_JOURNALCTL_COMMAND=$test_remote_base/bin/journalctl \
        remote_transaction node-a-journal-cursor-producer "$node_a_host" journal-cursor \
        node-a "$node_a_payload" "$node_a_evidence"
    CADDY_SERVING_HEALTH_JOURNALCTL_COMMAND=$test_remote_base/bin/journalctl \
        remote_transaction node-b-journal-cursor-producer "$node_b_host" journal-cursor \
        node-b "$node_b_payload" "$node_b_evidence"
    CADDY_SERVING_HEALTH_JOURNALCTL_COMMAND=$test_remote_base/bin/journalctl \
        remote_transaction node-a-journal-capture-producer "$node_a_host" journal-capture \
        node-a "$node_a_payload" "$node_a_evidence"
    CADDY_SERVING_HEALTH_JOURNALCTL_COMMAND=$test_remote_base/bin/journalctl \
        remote_transaction node-b-journal-capture-producer "$node_b_host" journal-capture \
        node-b "$node_b_payload" "$node_b_evidence"
    install -d -m 0700 "$test_remote_base/node-a-root" "$test_remote_base/node-b-root"
    install -d -m 0755 "$test_remote_base/node-a-root/etc/default" \
        "$test_remote_base/node-b-root/etc/default"
    install -m 0640 "$test_remote_base/environment-node-a" \
        "$test_remote_base/node-a-root/etc/default/caddy-ha"
    install -m 0640 "$test_remote_base/environment-node-b" \
        "$test_remote_base/node-b-root/etc/default/caddy-ha"
    install -d -m 0755 "$test_remote_base/node-b-root/usr/local/libexec"
    install -m 0755 "$repository_root/Caddy/scripts/prepare-lighttpd-config.sh" \
        "$test_remote_base/node-b-root/usr/local/libexec/prepare-lighttpd-config.sh"
    : >"$test_remote_base/ordering.calls"
    CADDY_SERVING_HEALTH_TARGET_ROOT=$test_remote_base/node-b-root \
        CADDY_SERVING_HEALTH_SYSTEMCTL_COMMAND=$test_remote_base/bin/systemctl \
        CADDY_SERVING_HEALTH_JOURNALCTL_COMMAND=$test_remote_base/bin/journalctl \
        CADDY_SERVING_HEALTH_SYSTEMD_TMPFILES_COMMAND=$test_remote_base/bin/systemd-tmpfiles \
        CADDY_SERVING_HEALTH_RUNUSER_COMMAND=$test_remote_base/bin/runuser \
        CADDY_SERVING_HEALTH_DNS_DIG_COMMAND=$test_remote_base/bin/dig \
        CADDY_SERVING_HEALTH_CURL_COMMAND=$test_remote_base/bin/curl \
        CADDY_SERVING_HEALTH_SS_COMMAND=$test_remote_base/bin/ss \
        CADDY_SERVING_HEALTH_UNBOUND_CHECKCONF_COMMAND=$test_remote_base/bin/unbound-checkconf \
        remote_transaction node-b-install-producer "$node_b_host" install node-b \
        "$node_b_payload" "$node_b_evidence"
    serving_health_raw=$serving_health_test_root/raw/keepalived-daemon-owned-acceptance.txt
    serving_health_decision=$serving_health_test_root/decisions/keepalived-daemon-owned-acceptance.tsv
    install -m 0600 "$test_remote_base/ordering.calls" "$serving_health_raw"
    serving_health_tmpfiles_line=$(grep -n '^tmpfiles --create ' "$serving_health_raw" | cut -d: -f1)
    serving_health_keepalived_stop_line=$(grep -n '^systemctl stop keepalived.service$' \
        "$serving_health_raw" | cut -d: -f1)
    serving_health_keepalived_line=$(grep -n '^systemctl start keepalived.service$' \
        "$serving_health_raw" | cut -d: -f1)
    [[ "$serving_health_keepalived_stop_line" -lt "$serving_health_tmpfiles_line" &&
        "$serving_health_tmpfiles_line" -lt "$serving_health_keepalived_line" ]]
    [[ "$(grep -c '^runuser pi:default$' "$serving_health_raw")" -eq 3 ]]
    [[ "$(grep -c '^runuser keepalived_script:caddy-tls$' "$serving_health_raw")" -eq 3 ]]
    grep -Fxq 'serving_health_deployment_check_keepalived_daemon_dns_success=true' \
        "$workstation_evidence/node-b-install-producer.stdout"
    grep -Fxq 'serving_health_deployment_check_keepalived_daemon_proxy_success=true' \
        "$workstation_evidence/node-b-install-producer.stdout"
    [[ ! -e "$test_remote_base/node-b-root/run/caddy-serving-health/dns" ]]
    [[ ! -e "$test_remote_base/node-b-root/run/caddy-serving-health/proxy" ]]
    write_decision keepalived-daemon-owned-acceptance accept 0 \
        stop-install-start-three-real-helper-cycles \
        stop-install-start-three-real-helper-cycles \
        "$serving_health_raw" "$serving_health_decision"
    serving_health_transaction_test_evidence=$serving_health_test_root/transaction-through-outer
    install -d -m 0700 "$serving_health_transaction_test_evidence"
    CADDY_PRODUCTION_PATH_EVIDENCE_ROOT=$serving_health_transaction_test_evidence \
        CADDY_SERVING_HEALTH_TEST_REPOSITORY_ROOT=$repository_root \
        remote_transaction node-a-post-promote-production-path "$node_a_host" \
        --production-path-test
    CADDY_SERVING_HEALTH_TARGET_ROOT=$test_remote_base/node-a-root \
        CADDY_SERVING_HEALTH_SYSTEMCTL_COMMAND=$test_remote_base/bin/systemctl \
        CADDY_SERVING_HEALTH_JOURNALCTL_COMMAND=$test_remote_base/bin/journalctl \
        CADDY_SERVING_HEALTH_SYSTEMD_TMPFILES_COMMAND=$test_remote_base/bin/systemd-tmpfiles \
        CADDY_SERVING_HEALTH_RUNUSER_COMMAND=$test_remote_base/bin/runuser \
        CADDY_SERVING_HEALTH_DNS_DIG_COMMAND=$test_remote_base/bin/dig \
        CADDY_SERVING_HEALTH_CURL_COMMAND=$test_remote_base/bin/curl \
        CADDY_SERVING_HEALTH_SS_COMMAND=$test_remote_base/bin/ss \
        CADDY_SERVING_HEALTH_UNBOUND_CHECKCONF_COMMAND=$test_remote_base/bin/unbound-checkconf \
        remote_transaction node-a-install-producer "$node_a_host" install node-a \
        "$node_a_payload" "$node_a_evidence"
    CADDY_SERVING_HEALTH_TARGET_ROOT=$test_remote_base/node-a-root \
        CADDY_SERVING_HEALTH_SYSTEMCTL_COMMAND=$test_remote_base/bin/systemctl \
        CADDY_SERVING_HEALTH_UNBOUND_CHECKCONF_COMMAND=$test_remote_base/bin/unbound-checkconf \
        remote_transaction node-a-rollback-producer "$node_a_host" rollback node-a \
        "$node_a_payload" "$node_a_evidence"
    CADDY_SERVING_HEALTH_TARGET_ROOT=$test_remote_base/node-b-root \
        CADDY_SERVING_HEALTH_SYSTEMCTL_COMMAND=$test_remote_base/bin/systemctl \
        CADDY_SERVING_HEALTH_UNBOUND_CHECKCONF_COMMAND=$test_remote_base/bin/unbound-checkconf \
        remote_transaction node-b-rollback-producer "$node_b_host" rollback node-b \
        "$node_b_payload" "$node_b_evidence"
    [[ "$(find "$test_remote_base/node-a-root" -type f -printf '%P\n' | LC_ALL=C sort)" = etc/default/caddy-ha ]]
    [[ "$(find "$test_remote_base/node-b-root" -type f -printf '%P\n' | LC_ALL=C sort)" = $'etc/default/caddy-ha\nusr/local/libexec/prepare-lighttpd-config.sh' ]]
    [[ "$(sha256sum "$test_remote_base/node-b-root/usr/local/libexec/prepare-lighttpd-config.sh" | awk '{ print $1 }')" = ce9a78aa487ce55c6fbba553b238160687852361d81c9b37179e4def8f83166f ]]

    serving_health_mode=journal-failure
    serving_health_variant_root=$test_remote_base/rejection-$serving_health_mode-root
    serving_health_variant_evidence=$node_b_payload/evidence-$serving_health_mode
    install -d -m 0700 "$serving_health_variant_root" "$serving_health_variant_evidence"
    install -d -m 0755 "$serving_health_variant_root/etc/default" \
        "$serving_health_variant_root/usr/local/libexec"
    install -m 0640 "$test_remote_base/environment-node-b" \
        "$serving_health_variant_root/etc/default/caddy-ha"
    install -m 0755 "$repository_root/Caddy/scripts/prepare-lighttpd-config.sh" \
        "$serving_health_variant_root/usr/local/libexec/prepare-lighttpd-config.sh"
    : >"$test_remote_base/keepalived.journal"
    if CADDY_SERVING_HEALTH_TEST_DAEMON_MODE=$serving_health_mode \
        CADDY_SERVING_HEALTH_TARGET_ROOT=$serving_health_variant_root \
        CADDY_SERVING_HEALTH_SYSTEMCTL_COMMAND=$test_remote_base/bin/systemctl \
        CADDY_SERVING_HEALTH_JOURNALCTL_COMMAND=$test_remote_base/bin/journalctl \
        CADDY_SERVING_HEALTH_SYSTEMD_TMPFILES_COMMAND=$test_remote_base/bin/systemd-tmpfiles \
        CADDY_SERVING_HEALTH_RUNUSER_COMMAND=$test_remote_base/bin/runuser \
        CADDY_SERVING_HEALTH_DNS_DIG_COMMAND=$test_remote_base/bin/dig \
        CADDY_SERVING_HEALTH_CURL_COMMAND=$test_remote_base/bin/curl \
        CADDY_SERVING_HEALTH_SS_COMMAND=$test_remote_base/bin/ss \
        CADDY_SERVING_HEALTH_UNBOUND_CHECKCONF_COMMAND=$test_remote_base/bin/unbound-checkconf \
        remote_transaction "daemon-$serving_health_mode-rejection-producer" \
        "$node_b_host" install node-b "$node_b_payload" \
        "$serving_health_variant_evidence"; then
        serving_health_status=0
    else
        serving_health_status=$?
    fi
    [[ "$serving_health_status" -ne 0 ]]
    serving_health_raw=$serving_health_test_root/raw/daemon-$serving_health_mode-rejection.txt
    serving_health_decision=$serving_health_test_root/decisions/daemon-$serving_health_mode-rejection.tsv
    {
        cat "$workstation_evidence/daemon-$serving_health_mode-rejection-producer.stdout"
        cat "$workstation_evidence/daemon-$serving_health_mode-rejection-producer.stderr"
        cat "$test_remote_base/keepalived.journal"
    } >"$serving_health_raw"
    write_decision "daemon-$serving_health_mode-rejection" reject \
        "$serving_health_status" accepted rejected "$serving_health_raw" "$serving_health_decision"
    CADDY_SERVING_HEALTH_TARGET_ROOT=$serving_health_variant_root \
        CADDY_SERVING_HEALTH_SYSTEMCTL_COMMAND=$test_remote_base/bin/systemctl \
        CADDY_SERVING_HEALTH_UNBOUND_CHECKCONF_COMMAND=$test_remote_base/bin/unbound-checkconf \
        remote_transaction "daemon-$serving_health_mode-rollback-producer" \
        "$node_b_host" rollback node-b "$node_b_payload" \
        "$serving_health_variant_evidence"
    [[ "$(find "$serving_health_variant_root" -type f -printf '%P\n' | LC_ALL=C sort)" = $'etc/default/caddy-ha\nusr/local/libexec/prepare-lighttpd-config.sh' ]]
    remote_transaction node-a-evidence-producer "$node_a_host" evidence-probe \
        node-a "$node_a_payload" "$node_a_evidence"
    remote_transaction node-b-evidence-producer "$node_b_host" evidence-probe \
        node-b "$node_b_payload" "$node_b_evidence"

    serving_health_raw=$serving_health_test_root/raw/outer-preflight.txt
    serving_health_decision=$serving_health_test_root/decisions/outer-preflight.tsv
    cat "$test_remote_base/ssh.calls" "$test_remote_base/scp.calls" \
        "$test_remote_base/runuser.identities" "$test_remote_base/systemctl.calls" \
        >"$serving_health_raw"
    serving_health_observed=$(wc -l <"$serving_health_raw")
    write_decision outer-preflight reach 0 "$serving_health_observed" \
        "$serving_health_observed" "$serving_health_raw" "$serving_health_decision"

    for serving_health_role in node-a node-b; do
        if [[ "$serving_health_role" = node-a ]]; then
            serving_health_remote_evidence=$node_a_evidence
        else
            serving_health_remote_evidence=$node_b_evidence
        fi
        serving_health_raw=$serving_health_test_root/raw/evidence-readback-$serving_health_role-success.txt
        serving_health_decision=$serving_health_test_root/decisions/evidence-readback-$serving_health_role-success.tsv
        ssh_stream "test-$serving_health_role" "$readback_program" \
            "$serving_health_remote_evidence" >"$serving_health_raw"
        serving_health_observed=$(sha256sum "$serving_health_raw" | awk '{ print $1 }')
        write_decision "evidence-readback-$serving_health_role-success" accept 0 \
            "$serving_health_observed" "$serving_health_observed" "$serving_health_raw" "$serving_health_decision"

        serving_health_raw=$serving_health_test_root/raw/evidence-readback-$serving_health_role-failure.txt
        serving_health_decision=$serving_health_test_root/decisions/evidence-readback-$serving_health_role-failure.tsv
        if ssh_stream "test-$serving_health_role" "$readback_program" \
            "$serving_health_remote_evidence-absent" >"$serving_health_raw" 2>&1; then
            serving_health_status=0
        else
            serving_health_status=$?
        fi
        printf 'exit_status=%s\n' "$serving_health_status" >>"$serving_health_raw"
        write_decision "evidence-readback-$serving_health_role-failure" reject \
            "$serving_health_status" present absent "$serving_health_raw" "$serving_health_decision"
    done
    cleanup_remote node-a "$node_a_host" "$node_a_payload" "$node_a_archive"
    cleanup_remote node-b "$node_b_host" "$node_b_payload" "$node_b_archive"
    chmod -R u+rwX -- "$serving_health_remote_base"
    rm -rf -- "$serving_health_remote_base"
    printf '%s_production_path_test_complete=true\n' "$prefix"
}

[[ $# -le 1 ]] || {
    usage
    exit 64
}
readonly invocation_mode=${1:-live}
[[ "$invocation_mode" = live || "$invocation_mode" = --production-path-test ]] || {
    usage
    exit 64
}

repository_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
readonly repository_root
workspace_root=${repository_root%/homelab-server-configs}
readonly workspace_root
transaction=$repository_root/Caddy/scripts/apply-serving-health-deployment.sh
readonly transaction
operation_spec=$repository_root/Caddy/manifests/serving-health-operation.yaml
readonly operation_spec
regular_file "$transaction"
regular_file "$operation_spec"
[[ "$(sha256sum "$transaction" | awk '{ print $1 }')" = "$transaction_sha256" ]]
[[ "$(sha256sum "$operation_spec" | awk '{ print $1 }')" = "$operation_sha256" ]]
if [[ "${CADDY_CONTROLLED_EXERCISE_CONTRACT_ONLY:-0}" = 1 ]]; then
    operation_scope=controlled-serving-failure-exercise
else
    operation_scope=$(sed -n 's/^scope: //p' "$operation_spec")
fi
readonly operation_scope
[[ "$operation_scope" =~ ^(pihole-web-health-unit-only|notification-standardization-only|external-notification-attribution-read-only|controlled-serving-failure-exercise|full-serving-health)$ ]]

if [[ "$invocation_mode" = --production-path-test ]]; then
    workstation_evidence=$(mktemp -d /tmp/caddy-serving-health-outer-test.XXXXXX)
else
    workstation_evidence=$(mktemp -d /tmp/caddy-ssh-evidence-serving_health.XXXXXX)
fi
readonly workstation_evidence
chmod 0700 "$workstation_evidence"
payload_stage=$workstation_evidence/payload
payload_archive=$workstation_evidence/serving-health-payload.tar
prepare_program=$workstation_evidence/remote-prepare.sh
accept_program=$workstation_evidence/remote-accept.sh
disposition_program=$workstation_evidence/remote-disposition.sh
readback_program=$workstation_evidence/remote-readback.sh
external_accept_program=$workstation_evidence/external-accept.sh
external_readback_program=$workstation_evidence/external-readback.sh
external_cleanup_program=$workstation_evidence/external-cleanup.sh
readonly payload_stage payload_archive prepare_program accept_program disposition_program readback_program
readonly external_accept_program external_readback_program external_cleanup_program
run_id=$(date -u +%Y%m%dT%H%M%SZ)-$$
readonly run_id
node_a_payload=/tmp/caddy-serving-health-$run_id-node-a
node_b_payload=/tmp/caddy-serving-health-$run_id-node-b
node_a_archive=$node_a_payload.tar
node_b_archive=$node_b_payload.tar
node_a_evidence=$node_a_payload/evidence
node_b_evidence=$node_b_payload/evidence
ssh_command=/usr/bin/ssh
scp_command=/usr/bin/scp

build_payload
write_remote_programs
if [[ "$invocation_mode" = --production-path-test ]]; then
    production_path_test
else
    run_live
fi
printf 'evidence_directory=%s\n' "$workstation_evidence"
