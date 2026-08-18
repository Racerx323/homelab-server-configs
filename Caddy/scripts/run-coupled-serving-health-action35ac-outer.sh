#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_35_ac_outer
readonly transaction_sha256=f1407806d7697b15a33146bb64fc9cd0ad0dab0244887c65a9767443949d279e
node_a_host=pi@10.1.0.53
node_b_host=pi@10.1.0.54
readonly max_stream_bytes=1048576

usage() {
    printf 'Usage: %s [--production-path-test]\n' "${0##*/}" >&2
}

regular_file() {
    [[ -f "$1" && ! -L "$1" ]]
}

safe_capture() {
    local action35ac_path=$1

    regular_file "$action35ac_path"
    [[ "$(stat -c '%s' "$action35ac_path")" -le "$max_stream_bytes" ]]
    iconv -f UTF-8 -t UTF-8 "$action35ac_path" >/dev/null
    ! LC_ALL=C grep -Paq '[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]' "$action35ac_path"
}

capture() {
    local action35ac_label=$1
    shift
    local action35ac_stdout=$workstation_evidence/$action35ac_label.stdout
    local action35ac_stderr=$workstation_evidence/$action35ac_label.stderr
    local action35ac_status=$workstation_evidence/$action35ac_label.status
    local action35ac_rc=0

    : >"$action35ac_stdout"
    : >"$action35ac_stderr"
    if "$@" >"$action35ac_stdout" 2>"$action35ac_stderr"; then
        action35ac_rc=0
    else
        action35ac_rc=$?
    fi
    printf '%s\n' "$action35ac_rc" >"$action35ac_status"
    chmod 0600 "$action35ac_stdout" "$action35ac_stderr" "$action35ac_status"
    safe_capture "$action35ac_stdout"
    safe_capture "$action35ac_stderr"
    return "$action35ac_rc"
}

build_payload() {
    local action35ac_repository action35ac_source action35ac_target action35ac_mode
    local action35ac_hash action35ac_lifecycle action35ac_source_path action35ac_destination

    install -d -m 0700 "$payload_stage/manifests" "$payload_stage/repositories"
    install -m 0600 "$repository_root/Caddy/manifests/serving-health-production.tsv" \
        "$payload_stage/manifests/serving-health-production.tsv"
    install -m 0600 "$repository_root/Caddy/manifests/production-artifacts.tsv" \
        "$payload_stage/manifests/production-artifacts.tsv"
    install -m 0600 "$repository_root/Caddy/manifests/action35ac-node-b-quarantine.tsv" \
        "$payload_stage/manifests/action35ac-node-b-quarantine.tsv"
    while IFS=$'\t' read -r action35ac_repository action35ac_source action35ac_target \
        action35ac_mode action35ac_hash action35ac_lifecycle; do
        [[ "$action35ac_repository" = '# repository' ]] && continue
        [[ "$action35ac_mode" =~ ^0[0-7]{3}$ && "$action35ac_lifecycle" = production-candidate ]]
        [[ "$action35ac_target" = /* ]]
        action35ac_source_path=${workspace_root}/$action35ac_repository/$action35ac_source
        regular_file "$action35ac_source_path"
        [[ "$(sha256sum "$action35ac_source_path" | awk '{ print $1 }')" = "$action35ac_hash" ]]
        action35ac_destination=$payload_stage/repositories/$action35ac_repository/$action35ac_source
        install -d -m 0700 "$(dirname -- "$action35ac_destination")"
        install -m 0600 "$action35ac_source_path" "$action35ac_destination"
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
case "$remote_root" in /tmp/caddy-action35ac-*) ;; *) exit 64 ;; esac
case "$archive" in /tmp/caddy-action35ac-*.tar) ;; *) exit 64 ;; esac
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
case "$remote_root" in /tmp/caddy-action35ac-*) ;; *) exit 64 ;; esac
case "$archive" in /tmp/caddy-action35ac-*.tar) ;; *) exit 64 ;; esac
[[ -d "$remote_root" && ! -L "$remote_root" ]]
[[ -f "$archive" && ! -L "$archive" ]]
expected_metadata=pi:pi:600
if [[ "${ACTION35AC_PRODUCTION_PATH_TEST:-0}" = 1 ]]; then
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
case "$remote_root" in /tmp/caddy-action35ac-*) ;; *) exit 64 ;; esac
case "$archive" in /tmp/caddy-action35ac-*.tar) ;; *) exit 64 ;; esac
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
case "$evidence_root" in /tmp/caddy-action35ac-*) ;; *) exit 64 ;; esac
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
    chmod 0600 "$prepare_program" "$accept_program" "$disposition_program" \
        "$readback_program"
}

ssh_stream() {
    local action35ac_host=$1
    local action35ac_program=$2
    shift 2
    "$ssh_command" "$action35ac_host" \
        "cd / && sudo -n /bin/bash -s --$(printf ' %q' "$@")" <"$action35ac_program"
}

upload_payload() {
    local action35ac_role=$1
    local action35ac_host=$2
    local action35ac_remote_root=$3
    local action35ac_remote_archive=$4
    local action35ac_hash

    action35ac_hash=$(awk '{ print $1 }' "$workstation_evidence/payload.sha256")
    capture "$action35ac_role-upload-prepare" ssh_stream "$action35ac_host" \
        "$prepare_program" "$action35ac_remote_root" "$action35ac_remote_archive"
    capture "$action35ac_role-upload-copy" "$scp_command" -p -- \
        "$payload_archive" "$action35ac_host:$action35ac_remote_archive"
    capture "$action35ac_role-upload-accept" ssh_stream "$action35ac_host" \
        "$accept_program" "$action35ac_remote_root" "$action35ac_remote_archive" \
        "$action35ac_hash"
}

remote_transaction() {
    local action35ac_label=$1
    local action35ac_host=$2
    shift 2

    capture "$action35ac_label" ssh_stream "$action35ac_host" "$transaction" "$@"
}

readback() {
    local action35ac_role=$1
    local action35ac_host=$2
    local action35ac_remote_evidence=$3

    capture "$action35ac_role-readback" ssh_stream "$action35ac_host" \
        "$readback_program" "$action35ac_remote_evidence"
}

cleanup_remote() {
    local action35ac_role=$1
    local action35ac_host=$2
    local action35ac_remote_root=$3
    local action35ac_remote_archive=$4

    capture "$action35ac_role-disposition" ssh_stream "$action35ac_host" \
        "$disposition_program" "$action35ac_remote_root" "$action35ac_remote_archive"
}

run_live() {
    local action35ac_node_b_mutated=false
    local action35ac_node_a_mutated=false
    local action35ac_failure=0
    local action35ac_phase_status=0

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
        action35ac_phase_status=$?
        readback node-a-failure "$node_a_host" "$node_a_evidence" || :
        readback node-b-failure "$node_b_host" "$node_b_evidence" || :
        cleanup_remote node-a "$node_a_host" "$node_a_payload" "$node_a_archive" || :
        cleanup_remote node-b "$node_b_host" "$node_b_payload" "$node_b_archive" || :
        return "$action35ac_phase_status"
    fi

    action35ac_node_b_mutated=true
    if remote_transaction node-b-retained-disposition "$node_b_host" \
        retained-disposition node-b "$node_b_payload" "$node_b_evidence"; then
        :
    else
        action35ac_failure=$?
    fi
    if [[ "$action35ac_failure" -eq 0 ]]; then
        if remote_transaction node-b-install "$node_b_host" install node-b \
            "$node_b_payload" "$node_b_evidence"; then
            :
        else
            action35ac_failure=$?
        fi
    fi
    if [[ "$action35ac_failure" -eq 0 ]]; then
        if remote_transaction node-b-accept "$node_b_host" accept node-b \
            "$node_b_payload" "$node_b_evidence"; then
            :
        else
            action35ac_failure=$?
        fi
    fi
    if [[ "$action35ac_failure" -eq 0 ]]; then
        if remote_transaction node-b-ownership "$node_b_host" ownership node-b \
            "$node_b_payload" "$node_b_evidence"; then
            :
        else
            action35ac_failure=$?
        fi
    fi
    if [[ "$action35ac_failure" -eq 0 ]]; then
        action35ac_node_a_mutated=true
        if remote_transaction node-a-quarantine-disposition "$node_a_host" \
            node-a-quarantine-disposition node-a "$node_a_payload" "$node_a_evidence"; then
            :
        else
            action35ac_failure=$?
        fi
    fi
    if [[ "$action35ac_failure" -eq 0 ]]; then
        if remote_transaction node-a-promote "$node_a_host" promote node-a \
            "$node_a_payload" "$node_a_evidence"; then
            :
        else
            action35ac_failure=$?
        fi
    fi
    if [[ "$action35ac_failure" -eq 0 ]]; then
        if remote_transaction node-a-post-promote-candidate-check "$node_a_host" \
            candidate-check node-a "$node_a_payload" "$node_a_evidence"; then
            :
        else
            action35ac_failure=$?
        fi
    fi
    if [[ "$action35ac_failure" -eq 0 ]]; then
        if remote_transaction node-a-install "$node_a_host" install node-a \
            "$node_a_payload" "$node_a_evidence"; then
            :
        else
            action35ac_failure=$?
        fi
    fi
    if [[ "$action35ac_failure" -eq 0 ]]; then
        if remote_transaction node-a-accept "$node_a_host" accept node-a \
            "$node_a_payload" "$node_a_evidence"; then
            :
        else
            action35ac_failure=$?
        fi
    fi
    if [[ "$action35ac_failure" -eq 0 ]]; then
        if remote_transaction node-a-ownership "$node_a_host" ownership node-a \
            "$node_a_payload" "$node_a_evidence"; then
            :
        else
            action35ac_failure=$?
        fi
    fi
    if [[ "$action35ac_failure" -eq 0 ]]; then
        if remote_transaction node-b-ownership-final "$node_b_host" ownership node-b \
            "$node_b_payload" "$node_b_evidence"; then
            :
        else
            action35ac_failure=$?
        fi
    fi
    if [[ "$action35ac_failure" -eq 0 ]]; then
        if remote_transaction node-a-consume-outbound "$node_a_host" consume node-a \
            "$node_a_payload" "$node_a_evidence"; then
            :
        else
            action35ac_failure=$?
        fi
    fi
    if [[ "$action35ac_failure" -eq 0 ]]; then
        if remote_transaction node-a-final-residue "$node_a_host" final-residue node-a \
            "$node_a_payload" "$node_a_evidence" &&
            remote_transaction node-b-final-residue "$node_b_host" final-residue node-b \
                "$node_b_payload" "$node_b_evidence"; then
            :
        else
            action35ac_failure=$?
        fi
    fi

    if ! remote_transaction node-a-journal-capture "$node_a_host" journal-capture node-a \
        "$node_a_payload" "$node_a_evidence"; then
        [[ "$action35ac_failure" -ne 0 ]] || action35ac_failure=1
    fi
    if ! remote_transaction node-b-journal-capture "$node_b_host" journal-capture node-b \
        "$node_b_payload" "$node_b_evidence"; then
        [[ "$action35ac_failure" -ne 0 ]] || action35ac_failure=1
    fi

    if ! remote_transaction node-a-sampler-stop "$node_a_host" sampler-stop node-a \
        "$node_a_payload" "$node_a_evidence"; then
        [[ "$action35ac_failure" -ne 0 ]] || action35ac_failure=1
    fi
    if ! remote_transaction node-b-sampler-stop "$node_b_host" sampler-stop node-b \
        "$node_b_payload" "$node_b_evidence"; then
        [[ "$action35ac_failure" -ne 0 ]] || action35ac_failure=1
    fi
    if ! readback node-a "$node_a_host" "$node_a_evidence"; then
        [[ "$action35ac_failure" -ne 0 ]] || action35ac_failure=1
    fi
    if ! readback node-b "$node_b_host" "$node_b_evidence"; then
        [[ "$action35ac_failure" -ne 0 ]] || action35ac_failure=1
    fi

    if [[ "$action35ac_failure" -ne 0 ]]; then
        if [[ "$action35ac_node_a_mutated" = true ]]; then
            remote_transaction node-a-rollback "$node_a_host" rollback node-a \
                "$node_a_payload" "$node_a_evidence" || exit 125
        fi
        if [[ "$action35ac_node_b_mutated" = true ]]; then
            remote_transaction node-b-rollback "$node_b_host" rollback node-b \
                "$node_b_payload" "$node_b_evidence" || exit 125
        fi
        readback node-a-rollback "$node_a_host" "$node_a_evidence" || exit 125
        readback node-b-rollback "$node_b_host" "$node_b_evidence" || exit 125
        cleanup_remote node-a "$node_a_host" "$node_a_payload" "$node_a_archive" || exit 125
        cleanup_remote node-b "$node_b_host" "$node_b_payload" "$node_b_archive" || exit 125
        return "$action35ac_failure"
    fi

    cleanup_remote node-a "$node_a_host" "$node_a_payload" "$node_a_archive"
    cleanup_remote node-b "$node_b_host" "$node_b_payload" "$node_b_archive"
}

write_decision() {
    local action35ac_scenario=$1
    local action35ac_expectation=$2
    local action35ac_status=$3
    local action35ac_expected=$4
    local action35ac_observed=$5
    local action35ac_raw=$6
    local action35ac_decision=$7
    local action35ac_raw_hash

    action35ac_raw_hash=$(sha256sum "$action35ac_raw" | awk '{ print $1 }')
    printf 'scenario\texpectation\tstatus\texpected\tobserved\traw-sha256\n%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$action35ac_scenario" "$action35ac_expectation" "$action35ac_status" \
        "$action35ac_expected" "$action35ac_observed" "$action35ac_raw_hash" \
        >"$action35ac_decision"
    chmod 0600 "$action35ac_raw" "$action35ac_decision"
}

production_path_test() {
    local action35ac_test_root=${CADDY_PRODUCTION_PATH_EVIDENCE_ROOT:?missing evidence root}
    local action35ac_remote_base action35ac_raw action35ac_decision action35ac_observed
    local action35ac_status action35ac_role action35ac_remote_evidence action35ac_test_id
    local action35ac_tmpfiles_line action35ac_keepalived_stop_line
    local action35ac_keepalived_line
    local action35ac_mode action35ac_variant_root action35ac_variant_evidence
    local retained_root retained_candidate retained_release_hash retained_payload_hash
    local action35ac_transaction_test_evidence

    [[ "$action35ac_test_root" = /tmp/* && -d "$action35ac_test_root" && ! -L "$action35ac_test_root" ]]
    chmod 0700 "$action35ac_test_root"
    install -d -m 0700 "$action35ac_test_root/raw" "$action35ac_test_root/decisions"
    action35ac_remote_base=$(mktemp -d /tmp/caddy-action35ac-production-path.XXXXXX)
    action35ac_test_id=${action35ac_remote_base##*.}
    test_remote_base=$action35ac_remote_base
    export ACTION35AC_TEST_REMOTE_BASE=$test_remote_base
    ssh_command=$workstation_evidence/fake-ssh
    scp_command=$workstation_evidence/fake-scp
    install -d -m 0700 "$test_remote_base/bin"
    cat >"$test_remote_base/bin/sudo" <<'SUDO'
#!/usr/bin/env bash
set -Eeuo pipefail
[[ "$1" = -n ]]
shift
export ACTION35AC_PRODUCTION_PATH_TEST=1
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
    >>"$ACTION35AC_TEST_REMOTE_BASE/runuser.identities"
printf 'runuser %s:%s\n' "$runuser_identity" "$runuser_group" \
    >>"$ACTION35AC_TEST_REMOTE_BASE/ordering.calls"
if [[ "${1:-}" = env && "${2:-}" = -i ]]; then
    shift 2
    exec env -i ACTION35AC_TEST_REMOTE_BASE="$ACTION35AC_TEST_REMOTE_BASE" "$@"
fi
exec "$@"
RUNUSER
    cat >"$test_remote_base/bin/keepalived" <<'KEEPALIVED'
#!/usr/bin/env bash
set -Eeuo pipefail
printf '%s\n' "$*" >>"$ACTION35AC_TEST_REMOTE_BASE/prohibited-keepalived-parser.calls"
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
printf '%s\n' "$*" >>"$ACTION35AC_TEST_REMOTE_BASE/systemctl.calls"
printf 'systemctl %s\n' "$*" >>"$ACTION35AC_TEST_REMOTE_BASE/ordering.calls"
state_root=${ACTION35AC_TARGET_ROOT:-$ACTION35AC_TEST_REMOTE_BASE/default-root}
state_file=$state_root/run/action35ac-keepalived-stopped
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
            printf '%s\n' \
                'test-host systemd[1]: Starting keepalived.service - Keepalive Daemon...' \
                'test-host systemd[1]: Started keepalived.service - Keepalive Daemon.' \
                'test-host Keepalived_vrrp[100]: VRRP_Script(check-dns) considered successful on startup' \
                'test-host Keepalived_vrrp[100]: VRRP_Script(check-caddy) considered successful on startup' \
                >>"$ACTION35AC_TEST_REMOTE_BASE/keepalived.journal"
            if [[ "${ACTION35AC_TEST_DAEMON_MODE:-success}" = journal-failure ]]; then
                printf '%s\n' \
                    'test-host Keepalived_vrrp[100]: VRRP_Script(check-caddy) failed (exited with status 1)' \
                    >>"$ACTION35AC_TEST_REMOTE_BASE/keepalived.journal"
            fi
            if [[ -x "$ACTION35AC_TARGET_ROOT/etc/scripts/check-dns.sh" &&
                -x "$ACTION35AC_TARGET_ROOT/usr/local/libexec/check-caddy.sh" ]]; then
                /usr/bin/setsid -f "$ACTION35AC_TEST_REMOTE_BASE/bin/keepalived-daemon-producer"
            fi
        fi
        ;;
    daemon-reload | reload | enable | disable) : ;;
    *) exit 64 ;;
esac
SYSTEMCTL
    cat >"$test_remote_base/bin/keepalived-daemon-producer" <<'KEEPALIVED_DAEMON'
#!/usr/bin/env bash
set -Eeuo pipefail
mode=${ACTION35AC_TEST_DAEMON_MODE:-success}
cycles=5
[[ "$mode" != stale ]] || cycles=1
for ((sequence = 1; sequence <= cycles; sequence++)); do
    dns_fail=0
    caddy_mode=success
    [[ "$mode" != dns-intermittent || "$sequence" -ne 3 ]] || dns_fail=1
    [[ "$mode" != caddy-intermittent || "$sequence" -ne 3 ]] || caddy_mode=failure
    [[ "$mode" != timeout || "$sequence" -ne 1 ]] || caddy_mode=timeout
    [[ "$mode" != signal || "$sequence" -ne 1 ]] || caddy_mode=signal
    if ! env DNS_CHECK_STATUS_FILE="$ACTION35AC_TARGET_ROOT/run/caddy-serving-health/dns/status" \
        DNS_CHECK_DIG_COMMAND="$ACTION35AC_TEST_REMOTE_BASE/bin/dig" \
        DNS_CHECK_SYSTEMCTL_COMMAND="$ACTION35AC_TEST_REMOTE_BASE/bin/systemctl" \
        ACTION35AC_TEST_DIG_FAIL="$dns_fail" \
        "$ACTION35AC_TEST_REMOTE_BASE/bin/runuser" -u pi -- \
        "$ACTION35AC_TARGET_ROOT/etc/scripts/check-dns.sh" \
        >>"$ACTION35AC_TEST_REMOTE_BASE/daemon-dns.stdout" \
        2>>"$ACTION35AC_TEST_REMOTE_BASE/daemon-dns.stderr"; then
        printf '%s\n' \
            'test-host Keepalived_vrrp[100]: VRRP_Script(check-dns) failed (exited with status 1)' \
            >>"$ACTION35AC_TEST_REMOTE_BASE/keepalived.journal"
        exit 1
    fi
    caddy_status=0
    if [[ "$caddy_mode" = timeout || "$caddy_mode" = signal ]]; then
        env CADDY_SERVING_HEALTH_STATUS_FILE="$ACTION35AC_TARGET_ROOT/run/caddy-serving-health/proxy/status" \
            CADDY_SERVING_HEALTH_ENVIRONMENT_FILE="$ACTION35AC_TARGET_ROOT/etc/default/caddy-ha" \
            CADDY_SERVING_HEALTH_CURL_COMMAND="$ACTION35AC_TEST_REMOTE_BASE/bin/curl" \
            CADDY_SERVING_HEALTH_SS_COMMAND="$ACTION35AC_TEST_REMOTE_BASE/bin/ss" \
            CADDY_SERVING_HEALTH_SYSTEMCTL_COMMAND="$ACTION35AC_TEST_REMOTE_BASE/bin/systemctl" \
            ACTION35AC_TEST_CURL_MODE="$caddy_mode" \
            /usr/bin/timeout --preserve-status \
            --signal="$([[ "$caddy_mode" = signal ]] && printf KILL || printf TERM)" \
            --kill-after=0.05 0.05 \
            "$ACTION35AC_TEST_REMOTE_BASE/bin/runuser" -u keepalived_script \
            -g caddy-tls -- "$ACTION35AC_TARGET_ROOT/usr/local/libexec/check-caddy.sh" \
            >>"$ACTION35AC_TEST_REMOTE_BASE/daemon-caddy.stdout" \
            2>>"$ACTION35AC_TEST_REMOTE_BASE/daemon-caddy.stderr" || caddy_status=$?
    else
        env CADDY_SERVING_HEALTH_STATUS_FILE="$ACTION35AC_TARGET_ROOT/run/caddy-serving-health/proxy/status" \
            CADDY_SERVING_HEALTH_ENVIRONMENT_FILE="$ACTION35AC_TARGET_ROOT/etc/default/caddy-ha" \
            CADDY_SERVING_HEALTH_CURL_COMMAND="$ACTION35AC_TEST_REMOTE_BASE/bin/curl" \
            CADDY_SERVING_HEALTH_SS_COMMAND="$ACTION35AC_TEST_REMOTE_BASE/bin/ss" \
            CADDY_SERVING_HEALTH_SYSTEMCTL_COMMAND="$ACTION35AC_TEST_REMOTE_BASE/bin/systemctl" \
            ACTION35AC_TEST_CURL_MODE="$caddy_mode" \
            "$ACTION35AC_TEST_REMOTE_BASE/bin/runuser" -u keepalived_script \
            -g caddy-tls -- "$ACTION35AC_TARGET_ROOT/usr/local/libexec/check-caddy.sh" \
            >>"$ACTION35AC_TEST_REMOTE_BASE/daemon-caddy.stdout" \
            2>>"$ACTION35AC_TEST_REMOTE_BASE/daemon-caddy.stderr" || caddy_status=$?
    fi
    if [[ "$caddy_status" -ne 0 ]]; then
        if [[ "$caddy_status" -eq 143 ]]; then
            printf '%s\n' \
                'test-host Keepalived_vrrp[100]: VRRP_Script(check-caddy) timed out' \
                >>"$ACTION35AC_TEST_REMOTE_BASE/keepalived.journal"
        elif [[ "$caddy_status" -eq 137 ]]; then
            printf '%s\n' \
                'test-host Keepalived_vrrp[100]: VRRP_Script(check-caddy) terminated by signal 9' \
                >>"$ACTION35AC_TEST_REMOTE_BASE/keepalived.journal"
        else
            printf '%s\n' \
                'test-host Keepalived_vrrp[100]: VRRP_Script(check-caddy) failed (exited with status 1)' \
                >>"$ACTION35AC_TEST_REMOTE_BASE/keepalived.journal"
        fi
        exit 1
    fi
    /usr/bin/sleep 0.08
done
KEEPALIVED_DAEMON
    cat >"$test_remote_base/bin/systemd-tmpfiles" <<'TMPFILES'
#!/usr/bin/env bash
set -Eeuo pipefail
[[ "$1" = --create && "$2" = "${ACTION35AC_TARGET_ROOT:?}/etc/tmpfiles.d/caddy-ha.conf" ]]
install -d -m 0755 "$ACTION35AC_TARGET_ROOT/run/caddy-serving-health"
install -d -m 0755 "$ACTION35AC_TARGET_ROOT/run/caddy-serving-health/dns"
install -d -m 0755 "$ACTION35AC_TARGET_ROOT/run/caddy-serving-health/proxy"
install -d -m 0755 "$ACTION35AC_TARGET_ROOT/run/caddy-serving-health/keepalived"
printf '%s\n' "$*" >>"$ACTION35AC_TEST_REMOTE_BASE/tmpfiles.calls"
printf 'tmpfiles %s\n' "$*" >>"$ACTION35AC_TEST_REMOTE_BASE/ordering.calls"
TMPFILES
    cat >"$test_remote_base/bin/dig" <<'DIG'
#!/usr/bin/env bash
if [[ "${ACTION35AC_TEST_DIG_FAIL:-0}" = 1 ]]; then
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
case "${ACTION35AC_TEST_CURL_MODE:-success}" in
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
    *' --show-cursor '*) printf '%s\n' '-- cursor: s=action35ac-production-path' ;;
    *' --after-cursor '*)
        if [[ -s "$ACTION35AC_TEST_REMOTE_BASE/keepalived.journal" ]]; then
            cat "$ACTION35AC_TEST_REMOTE_BASE/keepalived.journal"
        else
            printf '%s\n' 'test-host caddy.service: action35ac production-path event'
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
printf '%s\t%s\n' "$host" "$command" >>"$ACTION35AC_TEST_REMOTE_BASE/ssh.calls"
PATH="$ACTION35AC_TEST_REMOTE_BASE/bin:/usr/bin:/bin" /bin/bash -c "$command"
SSH
    cat >"$scp_command" <<'SCP'
#!/usr/bin/env bash
set -Eeuo pipefail
[[ "$1" = -p && "$2" = -- ]]
source=$3
target=${4#*:}
printf '%s\t%s\n' "$source" "$target" >>"$ACTION35AC_TEST_REMOTE_BASE/scp.calls"
install -o "$(id -un)" -g "$(id -gn)" -m 0600 "$source" "$target"
SCP
    chmod 0700 "$ssh_command" "$scp_command" "$test_remote_base/bin/"*
    export ACTION35AC_SLEEP_COMMAND=$test_remote_base/bin/sleep
    printf 'NODE_FQDN=pihole0.local.theama.co\nNODE_IPV4=10.1.0.53\nNODE_IPV6=fd36:5aa8:6971:1::53\n' \
        >"$test_remote_base/environment-node-a"
    printf 'NODE_FQDN=pihole00.local.theama.co\nNODE_IPV4=10.1.0.54\nNODE_IPV6=fd36:5aa8:6971:1::54\n' \
        >"$test_remote_base/environment-node-b"
    node_a_host=test-node-a
    node_b_host=test-node-b
    node_a_payload=/tmp/caddy-action35ac-test-$action35ac_test_id-node-a
    node_b_payload=/tmp/caddy-action35ac-test-$action35ac_test_id-node-b
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
    ACTION35AC_INCOMING_ROOT=$retained_root/incoming \
        ACTION35AC_OUTGOING_ROOT=$retained_root/outgoing \
        ACTION35AC_QUARANTINE_ROOT=$retained_root/quarantine \
        ACTION35AC_RELEASES_ROOT=$retained_root/releases \
        ACTION35AC_RETAINED_RELEASE_MANIFEST_SHA256=$retained_release_hash \
        ACTION35AC_RETAINED_PAYLOAD_MANIFEST_SHA256=$retained_payload_hash \
        remote_transaction node-b-retained-check-producer "$node_b_host" retained-check \
        node-b "$node_b_payload" "$node_b_evidence"
    [[ -d "$retained_candidate" ]]
    ACTION35AC_ENVIRONMENT_FILE=$test_remote_base/environment-node-b \
        ACTION35AC_UNBOUND_CHECKCONF_COMMAND=$test_remote_base/bin/unbound-checkconf \
        ACTION35AC_RUNUSER_COMMAND=$test_remote_base/bin/runuser \
        ACTION35AC_SYSTEMCTL_COMMAND=$test_remote_base/bin/systemctl \
        ACTION35AC_DNS_DIG_COMMAND=$test_remote_base/bin/dig \
        ACTION35AC_CURL_COMMAND=$test_remote_base/bin/curl \
        ACTION35AC_SS_COMMAND=$test_remote_base/bin/ss \
        remote_transaction node-b-candidate-producer "$node_b_host" candidate-check \
        node-b "$node_b_payload" "$node_b_evidence"
    if [[ -e "$test_remote_base/prohibited-keepalived-parser.calls" ]]; then
        printf '%s_check_keepalived_parser_not_invoked=false\n' "$prefix" >&2
        return 1
    fi
    printf '%s_check_keepalived_parser_not_invoked=true\n' "$prefix"
    ACTION35AC_JOURNALCTL_COMMAND=$test_remote_base/bin/journalctl \
        remote_transaction node-a-journal-cursor-producer "$node_a_host" journal-cursor \
        node-a "$node_a_payload" "$node_a_evidence"
    ACTION35AC_JOURNALCTL_COMMAND=$test_remote_base/bin/journalctl \
        remote_transaction node-b-journal-cursor-producer "$node_b_host" journal-cursor \
        node-b "$node_b_payload" "$node_b_evidence"
    ACTION35AC_JOURNALCTL_COMMAND=$test_remote_base/bin/journalctl \
        remote_transaction node-a-journal-capture-producer "$node_a_host" journal-capture \
        node-a "$node_a_payload" "$node_a_evidence"
    ACTION35AC_JOURNALCTL_COMMAND=$test_remote_base/bin/journalctl \
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
    ACTION35AC_TARGET_ROOT=$test_remote_base/node-b-root \
        ACTION35AC_SYSTEMCTL_COMMAND=$test_remote_base/bin/systemctl \
        ACTION35AC_JOURNALCTL_COMMAND=$test_remote_base/bin/journalctl \
        ACTION35AC_SYSTEMD_TMPFILES_COMMAND=$test_remote_base/bin/systemd-tmpfiles \
        ACTION35AC_RUNUSER_COMMAND=$test_remote_base/bin/runuser \
        ACTION35AC_DNS_DIG_COMMAND=$test_remote_base/bin/dig \
        ACTION35AC_CURL_COMMAND=$test_remote_base/bin/curl \
        ACTION35AC_SS_COMMAND=$test_remote_base/bin/ss \
        ACTION35AC_UNBOUND_CHECKCONF_COMMAND=$test_remote_base/bin/unbound-checkconf \
        remote_transaction node-b-install-producer "$node_b_host" install node-b \
        "$node_b_payload" "$node_b_evidence"
    action35ac_raw=$action35ac_test_root/raw/keepalived-daemon-owned-acceptance.txt
    action35ac_decision=$action35ac_test_root/decisions/keepalived-daemon-owned-acceptance.tsv
    install -m 0600 "$test_remote_base/ordering.calls" "$action35ac_raw"
    action35ac_tmpfiles_line=$(grep -n '^tmpfiles --create ' "$action35ac_raw" | cut -d: -f1)
    action35ac_keepalived_stop_line=$(grep -n '^systemctl stop keepalived.service$' \
        "$action35ac_raw" | cut -d: -f1)
    action35ac_keepalived_line=$(grep -n '^systemctl start keepalived.service$' \
        "$action35ac_raw" | cut -d: -f1)
    [[ "$action35ac_keepalived_stop_line" -lt "$action35ac_tmpfiles_line" &&
        "$action35ac_tmpfiles_line" -lt "$action35ac_keepalived_line" ]]
    [[ "$(grep -c '^runuser pi:default$' "$action35ac_raw")" -eq 5 ]]
    [[ "$(grep -c '^runuser keepalived_script:caddy-tls$' "$action35ac_raw")" -eq 5 ]]
    grep -Fxq 'action_35_ac_check_keepalived_daemon_dns_transition_count=true' \
        "$workstation_evidence/node-b-install-producer.stdout"
    grep -Fxq 'action_35_ac_check_keepalived_daemon_proxy_transition_count=true' \
        "$workstation_evidence/node-b-install-producer.stdout"
    grep -Fxq 'result=healthy' \
        "$test_remote_base/node-b-root/run/caddy-serving-health/dns/status"
    grep -Fxq 'result=healthy' \
        "$test_remote_base/node-b-root/run/caddy-serving-health/proxy/status"
    write_decision keepalived-daemon-owned-acceptance accept 0 \
        stop-install-start-five-daemon-transitions \
        stop-install-start-five-daemon-transitions \
        "$action35ac_raw" "$action35ac_decision"
    action35ac_transaction_test_evidence=$action35ac_test_root/transaction-through-outer
    install -d -m 0700 "$action35ac_transaction_test_evidence"
    CADDY_PRODUCTION_PATH_EVIDENCE_ROOT=$action35ac_transaction_test_evidence \
        ACTION35AC_TEST_REPOSITORY_ROOT=$repository_root \
        remote_transaction node-a-post-promote-production-path "$node_a_host" \
        --production-path-test
    ACTION35AC_TARGET_ROOT=$test_remote_base/node-a-root \
        ACTION35AC_SYSTEMCTL_COMMAND=$test_remote_base/bin/systemctl \
        ACTION35AC_JOURNALCTL_COMMAND=$test_remote_base/bin/journalctl \
        ACTION35AC_SYSTEMD_TMPFILES_COMMAND=$test_remote_base/bin/systemd-tmpfiles \
        ACTION35AC_RUNUSER_COMMAND=$test_remote_base/bin/runuser \
        ACTION35AC_DNS_DIG_COMMAND=$test_remote_base/bin/dig \
        ACTION35AC_CURL_COMMAND=$test_remote_base/bin/curl \
        ACTION35AC_SS_COMMAND=$test_remote_base/bin/ss \
        ACTION35AC_UNBOUND_CHECKCONF_COMMAND=$test_remote_base/bin/unbound-checkconf \
        remote_transaction node-a-install-producer "$node_a_host" install node-a \
        "$node_a_payload" "$node_a_evidence"
    ACTION35AC_TARGET_ROOT=$test_remote_base/node-a-root \
        ACTION35AC_SYSTEMCTL_COMMAND=$test_remote_base/bin/systemctl \
        ACTION35AC_UNBOUND_CHECKCONF_COMMAND=$test_remote_base/bin/unbound-checkconf \
        remote_transaction node-a-rollback-producer "$node_a_host" rollback node-a \
        "$node_a_payload" "$node_a_evidence"
    ACTION35AC_TARGET_ROOT=$test_remote_base/node-b-root \
        ACTION35AC_SYSTEMCTL_COMMAND=$test_remote_base/bin/systemctl \
        ACTION35AC_UNBOUND_CHECKCONF_COMMAND=$test_remote_base/bin/unbound-checkconf \
        remote_transaction node-b-rollback-producer "$node_b_host" rollback node-b \
        "$node_b_payload" "$node_b_evidence"
    [[ "$(find "$test_remote_base/node-a-root" -type f -printf '%P\n' | LC_ALL=C sort)" = etc/default/caddy-ha ]]
    [[ "$(find "$test_remote_base/node-b-root" -type f -printf '%P\n' | LC_ALL=C sort)" = $'etc/default/caddy-ha\nusr/local/libexec/prepare-lighttpd-config.sh' ]]
    [[ "$(sha256sum "$test_remote_base/node-b-root/usr/local/libexec/prepare-lighttpd-config.sh" | awk '{ print $1 }')" = ce9a78aa487ce55c6fbba553b238160687852361d81c9b37179e4def8f83166f ]]

    for action35ac_mode in dns-intermittent caddy-intermittent stale journal-failure timeout signal; do
        action35ac_variant_root=$test_remote_base/rejection-$action35ac_mode-root
        action35ac_variant_evidence=$node_b_payload/evidence-$action35ac_mode
        install -d -m 0700 "$action35ac_variant_root" "$action35ac_variant_evidence"
        install -d -m 0755 "$action35ac_variant_root/etc/default" \
            "$action35ac_variant_root/usr/local/libexec"
        install -m 0640 "$test_remote_base/environment-node-b" \
            "$action35ac_variant_root/etc/default/caddy-ha"
        install -m 0755 "$repository_root/Caddy/scripts/prepare-lighttpd-config.sh" \
            "$action35ac_variant_root/usr/local/libexec/prepare-lighttpd-config.sh"
        : >"$test_remote_base/keepalived.journal"
        if ACTION35AC_TEST_DAEMON_MODE=$action35ac_mode \
            ACTION35AC_TARGET_ROOT=$action35ac_variant_root \
            ACTION35AC_SYSTEMCTL_COMMAND=$test_remote_base/bin/systemctl \
            ACTION35AC_JOURNALCTL_COMMAND=$test_remote_base/bin/journalctl \
            ACTION35AC_SYSTEMD_TMPFILES_COMMAND=$test_remote_base/bin/systemd-tmpfiles \
            ACTION35AC_RUNUSER_COMMAND=$test_remote_base/bin/runuser \
            ACTION35AC_DNS_DIG_COMMAND=$test_remote_base/bin/dig \
            ACTION35AC_CURL_COMMAND=$test_remote_base/bin/curl \
            ACTION35AC_SS_COMMAND=$test_remote_base/bin/ss \
            ACTION35AC_UNBOUND_CHECKCONF_COMMAND=$test_remote_base/bin/unbound-checkconf \
            remote_transaction "daemon-$action35ac_mode-rejection-producer" \
            "$node_b_host" install node-b "$node_b_payload" \
            "$action35ac_variant_evidence"; then
            action35ac_status=0
        else
            action35ac_status=$?
        fi
        [[ "$action35ac_status" -ne 0 ]]
        action35ac_raw=$action35ac_test_root/raw/daemon-$action35ac_mode-rejection.txt
        action35ac_decision=$action35ac_test_root/decisions/daemon-$action35ac_mode-rejection.tsv
        {
            cat "$workstation_evidence/daemon-$action35ac_mode-rejection-producer.stdout"
            cat "$workstation_evidence/daemon-$action35ac_mode-rejection-producer.stderr"
            cat "$test_remote_base/keepalived.journal"
            find "$action35ac_variant_evidence" -maxdepth 1 -type f \
                -name '*status-record' -exec sh -c 'printf "file=%s\n" "$1"; cat "$1"' sh {} \;
        } >"$action35ac_raw"
        write_decision "daemon-$action35ac_mode-rejection" reject \
            "$action35ac_status" accepted rejected "$action35ac_raw" "$action35ac_decision"
        ACTION35AC_TARGET_ROOT=$action35ac_variant_root \
            ACTION35AC_SYSTEMCTL_COMMAND=$test_remote_base/bin/systemctl \
            ACTION35AC_UNBOUND_CHECKCONF_COMMAND=$test_remote_base/bin/unbound-checkconf \
            remote_transaction "daemon-$action35ac_mode-rollback-producer" \
            "$node_b_host" rollback node-b "$node_b_payload" \
            "$action35ac_variant_evidence"
        [[ "$(find "$action35ac_variant_root" -type f -printf '%P\n' | LC_ALL=C sort)" = $'etc/default/caddy-ha\nusr/local/libexec/prepare-lighttpd-config.sh' ]]
    done
    remote_transaction node-a-evidence-producer "$node_a_host" evidence-probe \
        node-a "$node_a_payload" "$node_a_evidence"
    remote_transaction node-b-evidence-producer "$node_b_host" evidence-probe \
        node-b "$node_b_payload" "$node_b_evidence"

    action35ac_raw=$action35ac_test_root/raw/outer-preflight.txt
    action35ac_decision=$action35ac_test_root/decisions/outer-preflight.tsv
    cat "$test_remote_base/ssh.calls" "$test_remote_base/scp.calls" \
        "$test_remote_base/runuser.identities" "$test_remote_base/systemctl.calls" \
        >"$action35ac_raw"
    action35ac_observed=$(wc -l <"$action35ac_raw")
    write_decision outer-preflight reach 0 "$action35ac_observed" \
        "$action35ac_observed" "$action35ac_raw" "$action35ac_decision"

    for action35ac_role in node-a node-b; do
        if [[ "$action35ac_role" = node-a ]]; then
            action35ac_remote_evidence=$node_a_evidence
        else
            action35ac_remote_evidence=$node_b_evidence
        fi
        action35ac_raw=$action35ac_test_root/raw/evidence-readback-$action35ac_role-success.txt
        action35ac_decision=$action35ac_test_root/decisions/evidence-readback-$action35ac_role-success.tsv
        ssh_stream "test-$action35ac_role" "$readback_program" \
            "$action35ac_remote_evidence" >"$action35ac_raw"
        action35ac_observed=$(sha256sum "$action35ac_raw" | awk '{ print $1 }')
        write_decision "evidence-readback-$action35ac_role-success" accept 0 \
            "$action35ac_observed" "$action35ac_observed" "$action35ac_raw" "$action35ac_decision"

        action35ac_raw=$action35ac_test_root/raw/evidence-readback-$action35ac_role-failure.txt
        action35ac_decision=$action35ac_test_root/decisions/evidence-readback-$action35ac_role-failure.tsv
        if ssh_stream "test-$action35ac_role" "$readback_program" \
            "$action35ac_remote_evidence-absent" >"$action35ac_raw" 2>&1; then
            action35ac_status=0
        else
            action35ac_status=$?
        fi
        write_decision "evidence-readback-$action35ac_role-failure" reject \
            "$action35ac_status" present absent "$action35ac_raw" "$action35ac_decision"
    done
    cleanup_remote node-a "$node_a_host" "$node_a_payload" "$node_a_archive"
    cleanup_remote node-b "$node_b_host" "$node_b_payload" "$node_b_archive"
    chmod -R u+rwX -- "$action35ac_remote_base"
    rm -rf -- "$action35ac_remote_base"
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
transaction=$repository_root/Caddy/scripts/apply-coupled-serving-health-action35ac.sh
readonly transaction
regular_file "$transaction"
[[ "$(sha256sum "$transaction" | awk '{ print $1 }')" = "$transaction_sha256" ]]

if [[ "$invocation_mode" = --production-path-test ]]; then
    workstation_evidence=$(mktemp -d /tmp/caddy-action35ac-outer-test.XXXXXX)
else
    workstation_evidence=$(mktemp -d /tmp/caddy-ssh-evidence-action35ac.XXXXXX)
fi
readonly workstation_evidence
chmod 0700 "$workstation_evidence"
payload_stage=$workstation_evidence/payload
payload_archive=$workstation_evidence/action35ac-payload.tar
prepare_program=$workstation_evidence/remote-prepare.sh
accept_program=$workstation_evidence/remote-accept.sh
disposition_program=$workstation_evidence/remote-disposition.sh
readback_program=$workstation_evidence/remote-readback.sh
readonly payload_stage payload_archive prepare_program accept_program disposition_program readback_program
run_id=$(date -u +%Y%m%dT%H%M%SZ)-$$
readonly run_id
node_a_payload=/tmp/caddy-action35ac-$run_id-node-a
node_b_payload=/tmp/caddy-action35ac-$run_id-node-b
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
