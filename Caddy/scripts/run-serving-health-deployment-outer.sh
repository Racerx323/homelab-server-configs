#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=serving_health_deployment_outer
readonly transaction_sha256=88eac36e3ce093b761ab8085d83c9359c378e03e2c265880bde1bcff131e9ef0
readonly operation_sha256=dc8f2964335b73e811ce8e5bc9fdc207b5761bee3ac9c093c464b601dcc25402
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
    install -m 0600 "$repository_root/Caddy/manifests/serving-health-production.tsv" \
        "$payload_stage/manifests/serving-health-production.tsv"
    install -m 0600 "$repository_root/Caddy/manifests/production-artifacts.tsv" \
        "$payload_stage/manifests/production-artifacts.tsv"
    install -m 0600 "$repository_root/Caddy/manifests/serving-health-quarantine-baseline.tsv" \
        "$payload_stage/manifests/serving-health-quarantine-baseline.tsv"
    while IFS=$'\t' read -r serving_health_repository serving_health_source serving_health_target \
        serving_health_mode serving_health_hash serving_health_lifecycle; do
        [[ "$serving_health_repository" = '# repository' ]] && continue
        [[ "$serving_health_mode" =~ ^0[0-7]{3}$ && "$serving_health_lifecycle" = production-candidate ]]
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
    chmod 0600 "$prepare_program" "$accept_program" "$disposition_program" \
        "$readback_program"
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

cleanup_remote() {
    local serving_health_role=$1
    local serving_health_host=$2
    local serving_health_remote_root=$3
    local serving_health_remote_archive=$4

    capture "$serving_health_role-disposition" ssh_stream "$serving_health_host" \
        "$disposition_program" "$serving_health_remote_root" "$serving_health_remote_archive"
}

run_live() {
    local serving_health_node_b_mutated=false
    local serving_health_node_a_mutated=false
    local serving_health_failure=0
    local serving_health_phase_status=0
    local serving_health_target_revision=

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
readonly payload_stage payload_archive prepare_program accept_program disposition_program readback_program
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
