#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_35_r_outer
readonly transaction_sha256=7f4b7303eb6666b0651ee0110f609021298e0710825da3439f9cf88d2eb3e50c
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
    local action35r_path=$1

    regular_file "$action35r_path"
    [[ "$(stat -c '%s' "$action35r_path")" -le "$max_stream_bytes" ]]
    iconv -f UTF-8 -t UTF-8 "$action35r_path" >/dev/null
    ! LC_ALL=C grep -Paq '[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]' "$action35r_path"
}

capture() {
    local action35r_label=$1
    shift
    local action35r_stdout=$workstation_evidence/$action35r_label.stdout
    local action35r_stderr=$workstation_evidence/$action35r_label.stderr
    local action35r_status=$workstation_evidence/$action35r_label.status
    local action35r_rc=0

    : >"$action35r_stdout"
    : >"$action35r_stderr"
    if "$@" >"$action35r_stdout" 2>"$action35r_stderr"; then
        action35r_rc=0
    else
        action35r_rc=$?
    fi
    printf '%s\n' "$action35r_rc" >"$action35r_status"
    chmod 0600 "$action35r_stdout" "$action35r_stderr" "$action35r_status"
    safe_capture "$action35r_stdout"
    safe_capture "$action35r_stderr"
    return "$action35r_rc"
}

build_payload() {
    local action35r_repository action35r_source action35r_target action35r_mode
    local action35r_hash action35r_lifecycle action35r_source_path action35r_destination

    install -d -m 0700 "$payload_stage/manifests" "$payload_stage/repositories"
    install -m 0600 "$repository_root/Caddy/manifests/serving-health-production.tsv" \
        "$payload_stage/manifests/serving-health-production.tsv"
    install -m 0600 "$repository_root/Caddy/manifests/production-artifacts.tsv" \
        "$payload_stage/manifests/production-artifacts.tsv"
    install -m 0600 "$repository_root/Caddy/manifests/action35r-node-b-quarantine.tsv" \
        "$payload_stage/manifests/action35r-node-b-quarantine.tsv"
    while IFS=$'\t' read -r action35r_repository action35r_source action35r_target \
        action35r_mode action35r_hash action35r_lifecycle; do
        [[ "$action35r_repository" = '# repository' ]] && continue
        [[ "$action35r_mode" =~ ^0[0-7]{3}$ && "$action35r_lifecycle" = production-candidate ]]
        [[ "$action35r_target" = /* ]]
        action35r_source_path=${workspace_root}/$action35r_repository/$action35r_source
        regular_file "$action35r_source_path"
        [[ "$(sha256sum "$action35r_source_path" | awk '{ print $1 }')" = "$action35r_hash" ]]
        action35r_destination=$payload_stage/repositories/$action35r_repository/$action35r_source
        install -d -m 0700 "$(dirname -- "$action35r_destination")"
        install -m 0600 "$action35r_source_path" "$action35r_destination"
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
case "$remote_root" in /tmp/caddy-action35r-*) ;; *) exit 64 ;; esac
case "$archive" in /tmp/caddy-action35r-*.tar) ;; *) exit 64 ;; esac
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
case "$remote_root" in /tmp/caddy-action35r-*) ;; *) exit 64 ;; esac
case "$archive" in /tmp/caddy-action35r-*.tar) ;; *) exit 64 ;; esac
[[ -d "$remote_root" && ! -L "$remote_root" ]]
[[ -f "$archive" && ! -L "$archive" ]]
expected_metadata=pi:pi:600
if [[ "${ACTION35R_PRODUCTION_PATH_TEST:-0}" = 1 ]]; then
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
case "$remote_root" in /tmp/caddy-action35r-*) ;; *) exit 64 ;; esac
case "$archive" in /tmp/caddy-action35r-*.tar) ;; *) exit 64 ;; esac
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
case "$evidence_root" in /tmp/caddy-action35r-*) ;; *) exit 64 ;; esac
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
    local action35r_host=$1
    local action35r_program=$2
    shift 2
    "$ssh_command" "$action35r_host" \
        "cd / && sudo -n /bin/bash -s --$(printf ' %q' "$@")" <"$action35r_program"
}

upload_payload() {
    local action35r_role=$1
    local action35r_host=$2
    local action35r_remote_root=$3
    local action35r_remote_archive=$4
    local action35r_hash

    action35r_hash=$(awk '{ print $1 }' "$workstation_evidence/payload.sha256")
    capture "$action35r_role-upload-prepare" ssh_stream "$action35r_host" \
        "$prepare_program" "$action35r_remote_root" "$action35r_remote_archive"
    capture "$action35r_role-upload-copy" "$scp_command" -p -- \
        "$payload_archive" "$action35r_host:$action35r_remote_archive"
    capture "$action35r_role-upload-accept" ssh_stream "$action35r_host" \
        "$accept_program" "$action35r_remote_root" "$action35r_remote_archive" \
        "$action35r_hash"
}

remote_transaction() {
    local action35r_label=$1
    local action35r_host=$2
    shift 2

    capture "$action35r_label" ssh_stream "$action35r_host" "$transaction" "$@"
}

readback() {
    local action35r_role=$1
    local action35r_host=$2
    local action35r_remote_evidence=$3

    capture "$action35r_role-readback" ssh_stream "$action35r_host" \
        "$readback_program" "$action35r_remote_evidence"
}

cleanup_remote() {
    local action35r_role=$1
    local action35r_host=$2
    local action35r_remote_root=$3
    local action35r_remote_archive=$4

    capture "$action35r_role-disposition" ssh_stream "$action35r_host" \
        "$disposition_program" "$action35r_remote_root" "$action35r_remote_archive"
}

run_live() {
    local action35r_node_b_mutated=false
    local action35r_node_a_mutated=false
    local action35r_failure=0
    local action35r_phase_status=0

    if upload_payload node-b "$node_b_host" "$node_b_payload" "$node_b_archive" &&
        upload_payload node-a "$node_a_host" "$node_a_payload" "$node_a_archive" &&
        remote_transaction node-b-preflight "$node_b_host" preflight node-b \
            "$node_b_payload" "$node_b_evidence" &&
        remote_transaction node-a-preflight "$node_a_host" preflight node-a \
            "$node_a_payload" "$node_a_evidence" &&
        remote_transaction node-b-candidate-check "$node_b_host" candidate-check node-b \
            "$node_b_payload" "$node_b_evidence" &&
        remote_transaction node-a-candidate-check "$node_a_host" candidate-check node-a \
            "$node_a_payload" "$node_a_evidence" &&
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
        action35r_phase_status=$?
        readback node-a-failure "$node_a_host" "$node_a_evidence" || :
        readback node-b-failure "$node_b_host" "$node_b_evidence" || :
        cleanup_remote node-a "$node_a_host" "$node_a_payload" "$node_a_archive" || :
        cleanup_remote node-b "$node_b_host" "$node_b_payload" "$node_b_archive" || :
        return "$action35r_phase_status"
    fi

    action35r_node_b_mutated=true
    if remote_transaction node-b-retained-disposition "$node_b_host" \
        retained-disposition node-b "$node_b_payload" "$node_b_evidence"; then
        :
    else
        action35r_failure=$?
    fi
    if [[ "$action35r_failure" -eq 0 ]]; then
        if remote_transaction node-b-install "$node_b_host" install node-b \
            "$node_b_payload" "$node_b_evidence"; then
            :
        else
            action35r_failure=$?
        fi
    fi
    if [[ "$action35r_failure" -eq 0 ]]; then
        if remote_transaction node-b-accept "$node_b_host" accept node-b \
            "$node_b_payload" "$node_b_evidence"; then
            :
        else
            action35r_failure=$?
        fi
    fi
    if [[ "$action35r_failure" -eq 0 ]]; then
        if remote_transaction node-b-ownership "$node_b_host" ownership node-b \
            "$node_b_payload" "$node_b_evidence"; then
            :
        else
            action35r_failure=$?
        fi
    fi
    if [[ "$action35r_failure" -eq 0 ]]; then
        action35r_node_a_mutated=true
        if remote_transaction node-a-quarantine-disposition "$node_a_host" \
            node-a-quarantine-disposition node-a "$node_a_payload" "$node_a_evidence"; then
            :
        else
            action35r_failure=$?
        fi
    fi
    if [[ "$action35r_failure" -eq 0 ]]; then
        if remote_transaction node-a-promote "$node_a_host" promote node-a \
            "$node_a_payload" "$node_a_evidence"; then
            :
        else
            action35r_failure=$?
        fi
    fi
    if [[ "$action35r_failure" -eq 0 ]]; then
        if remote_transaction node-a-install "$node_a_host" install node-a \
            "$node_a_payload" "$node_a_evidence"; then
            :
        else
            action35r_failure=$?
        fi
    fi
    if [[ "$action35r_failure" -eq 0 ]]; then
        if remote_transaction node-a-accept "$node_a_host" accept node-a \
            "$node_a_payload" "$node_a_evidence"; then
            :
        else
            action35r_failure=$?
        fi
    fi
    if [[ "$action35r_failure" -eq 0 ]]; then
        if remote_transaction node-a-ownership "$node_a_host" ownership node-a \
            "$node_a_payload" "$node_a_evidence"; then
            :
        else
            action35r_failure=$?
        fi
    fi
    if [[ "$action35r_failure" -eq 0 ]]; then
        if remote_transaction node-b-ownership-final "$node_b_host" ownership node-b \
            "$node_b_payload" "$node_b_evidence"; then
            :
        else
            action35r_failure=$?
        fi
    fi
    if [[ "$action35r_failure" -eq 0 ]]; then
        if remote_transaction node-a-consume-outbound "$node_a_host" consume node-a \
            "$node_a_payload" "$node_a_evidence"; then
            :
        else
            action35r_failure=$?
        fi
    fi
    if [[ "$action35r_failure" -eq 0 ]]; then
        if remote_transaction node-a-final-residue "$node_a_host" final-residue node-a \
            "$node_a_payload" "$node_a_evidence" &&
            remote_transaction node-b-final-residue "$node_b_host" final-residue node-b \
                "$node_b_payload" "$node_b_evidence"; then
            :
        else
            action35r_failure=$?
        fi
    fi

    if ! remote_transaction node-a-journal-capture "$node_a_host" journal-capture node-a \
        "$node_a_payload" "$node_a_evidence"; then
        [[ "$action35r_failure" -ne 0 ]] || action35r_failure=1
    fi
    if ! remote_transaction node-b-journal-capture "$node_b_host" journal-capture node-b \
        "$node_b_payload" "$node_b_evidence"; then
        [[ "$action35r_failure" -ne 0 ]] || action35r_failure=1
    fi

    if ! remote_transaction node-a-sampler-stop "$node_a_host" sampler-stop node-a \
        "$node_a_payload" "$node_a_evidence"; then
        [[ "$action35r_failure" -ne 0 ]] || action35r_failure=1
    fi
    if ! remote_transaction node-b-sampler-stop "$node_b_host" sampler-stop node-b \
        "$node_b_payload" "$node_b_evidence"; then
        [[ "$action35r_failure" -ne 0 ]] || action35r_failure=1
    fi
    if ! readback node-a "$node_a_host" "$node_a_evidence"; then
        [[ "$action35r_failure" -ne 0 ]] || action35r_failure=1
    fi
    if ! readback node-b "$node_b_host" "$node_b_evidence"; then
        [[ "$action35r_failure" -ne 0 ]] || action35r_failure=1
    fi

    if [[ "$action35r_failure" -ne 0 ]]; then
        if [[ "$action35r_node_a_mutated" = true ]]; then
            remote_transaction node-a-rollback "$node_a_host" rollback node-a \
                "$node_a_payload" "$node_a_evidence" || exit 125
        fi
        if [[ "$action35r_node_b_mutated" = true ]]; then
            remote_transaction node-b-rollback "$node_b_host" rollback node-b \
                "$node_b_payload" "$node_b_evidence" || exit 125
        fi
        readback node-a-rollback "$node_a_host" "$node_a_evidence" || exit 125
        readback node-b-rollback "$node_b_host" "$node_b_evidence" || exit 125
        cleanup_remote node-a "$node_a_host" "$node_a_payload" "$node_a_archive" || exit 125
        cleanup_remote node-b "$node_b_host" "$node_b_payload" "$node_b_archive" || exit 125
        return "$action35r_failure"
    fi

    cleanup_remote node-a "$node_a_host" "$node_a_payload" "$node_a_archive"
    cleanup_remote node-b "$node_b_host" "$node_b_payload" "$node_b_archive"
}

write_decision() {
    local action35r_scenario=$1
    local action35r_expectation=$2
    local action35r_status=$3
    local action35r_expected=$4
    local action35r_observed=$5
    local action35r_raw=$6
    local action35r_decision=$7
    local action35r_raw_hash

    action35r_raw_hash=$(sha256sum "$action35r_raw" | awk '{ print $1 }')
    printf 'scenario\texpectation\tstatus\texpected\tobserved\traw-sha256\n%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$action35r_scenario" "$action35r_expectation" "$action35r_status" \
        "$action35r_expected" "$action35r_observed" "$action35r_raw_hash" \
        >"$action35r_decision"
    chmod 0600 "$action35r_raw" "$action35r_decision"
}

production_path_test() {
    local action35r_test_root=${CADDY_PRODUCTION_PATH_EVIDENCE_ROOT:?missing evidence root}
    local action35r_remote_base action35r_raw action35r_decision action35r_observed
    local action35r_status action35r_role action35r_remote_evidence action35r_test_id
    local retained_root retained_candidate retained_release_hash retained_payload_hash
    local action35r_transaction_test_evidence

    [[ "$action35r_test_root" = /tmp/* && -d "$action35r_test_root" && ! -L "$action35r_test_root" ]]
    chmod 0700 "$action35r_test_root"
    install -d -m 0700 "$action35r_test_root/raw" "$action35r_test_root/decisions"
    action35r_remote_base=$(mktemp -d /tmp/caddy-action35r-production-path.XXXXXX)
    action35r_test_id=${action35r_remote_base##*.}
    test_remote_base=$action35r_remote_base
    export ACTION35R_TEST_REMOTE_BASE=$test_remote_base
    ssh_command=$workstation_evidence/fake-ssh
    scp_command=$workstation_evidence/fake-scp
    install -d -m 0700 "$test_remote_base/bin"
    cat >"$test_remote_base/bin/sudo" <<'SUDO'
#!/usr/bin/env bash
set -Eeuo pipefail
[[ "$1" = -n ]]
shift
export ACTION35R_PRODUCTION_PATH_TEST=1
exec "$@"
SUDO
    cat >"$test_remote_base/bin/runuser" <<'RUNUSER'
#!/usr/bin/env bash
set -Eeuo pipefail
[[ "$1" = -u && "$3" = -- ]]
printf '%s\n' "$2" >>"$ACTION35R_TEST_REMOTE_BASE/runuser.identities"
shift 3
exec "$@"
RUNUSER
    cat >"$test_remote_base/bin/keepalived" <<'KEEPALIVED'
#!/usr/bin/env bash
set -Eeuo pipefail
[[ "$1" = --config-test && "$2" = -f && -f "$3" ]]
grep -Fq 'vrrp_sync_group PIHOLE_DUALSTACK' "$3"
grep -Fq 'check-caddy' "$3"
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
printf '%s\n' "$*" >>"$ACTION35R_TEST_REMOTE_BASE/systemctl.calls"
case "$1" in
    is-active) [[ "$2" = --quiet ]] ;;
    start | stop) [[ $# -eq 2 ]] ;;
    daemon-reload | reload | enable | disable) : ;;
    *) exit 64 ;;
esac
SYSTEMCTL
    cat >"$test_remote_base/bin/dig" <<'DIG'
#!/usr/bin/env bash
case " $* " in
    *' A '*) printf '10.1.0.55\n' ;;
    *' AAAA '*) printf 'fd36:5aa8:6971:1::55\n' ;;
    *) exit 64 ;;
esac
DIG
    cat >"$test_remote_base/bin/curl" <<'CURL'
#!/usr/bin/env bash
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
    *' --show-cursor '*) printf '%s\n' '-- cursor: s=action35r-production-path' ;;
    *' --after-cursor '*) printf '%s\n' 'test-host caddy.service: action35r production-path event' ;;
    *) exit 64 ;;
esac
JOURNALCTL
    cat >"$ssh_command" <<'SSH'
#!/usr/bin/env bash
set -Eeuo pipefail
host=$1
shift
command="$*"
printf '%s\t%s\n' "$host" "$command" >>"$ACTION35R_TEST_REMOTE_BASE/ssh.calls"
PATH="$ACTION35R_TEST_REMOTE_BASE/bin:/usr/bin:/bin" /bin/bash -c "$command"
SSH
    cat >"$scp_command" <<'SCP'
#!/usr/bin/env bash
set -Eeuo pipefail
[[ "$1" = -p && "$2" = -- ]]
source=$3
target=${4#*:}
printf '%s\t%s\n' "$source" "$target" >>"$ACTION35R_TEST_REMOTE_BASE/scp.calls"
install -o "$(id -un)" -g "$(id -gn)" -m 0600 "$source" "$target"
SCP
    chmod 0700 "$ssh_command" "$scp_command" "$test_remote_base/bin/"*
    printf 'NODE_FQDN=pihole0.local.theama.co\nNODE_IPV4=10.1.0.53\nNODE_IPV6=fd36:5aa8:6971:1::53\n' \
        >"$test_remote_base/environment-node-a"
    printf 'NODE_FQDN=pihole00.local.theama.co\nNODE_IPV4=10.1.0.54\nNODE_IPV6=fd36:5aa8:6971:1::54\n' \
        >"$test_remote_base/environment-node-b"
    node_a_host=test-node-a
    node_b_host=test-node-b
    node_a_payload=/tmp/caddy-action35r-test-$action35r_test_id-node-a
    node_b_payload=/tmp/caddy-action35r-test-$action35r_test_id-node-b
    node_a_archive=$node_a_payload.tar
    node_b_archive=$node_b_payload.tar
    node_a_evidence=$node_a_payload/evidence
    node_b_evidence=$node_b_payload/evidence
    build_payload
    write_remote_programs
    upload_payload node-a "$node_a_host" "$node_a_payload" "$node_a_archive"
    upload_payload node-b "$node_b_host" "$node_b_payload" "$node_b_archive"
    action35r_transaction_test_evidence=$action35r_test_root/transaction-through-outer
    install -d -m 0700 "$action35r_transaction_test_evidence"
    CADDY_PRODUCTION_PATH_EVIDENCE_ROOT=$action35r_transaction_test_evidence \
        ACTION35R_TEST_REPOSITORY_ROOT=$repository_root \
        remote_transaction node-b-transaction-production-path "$node_b_host" \
        --production-path-test
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
    ACTION35R_INCOMING_ROOT=$retained_root/incoming \
        ACTION35R_OUTGOING_ROOT=$retained_root/outgoing \
        ACTION35R_QUARANTINE_ROOT=$retained_root/quarantine \
        ACTION35R_RELEASES_ROOT=$retained_root/releases \
        ACTION35R_RETAINED_RELEASE_MANIFEST_SHA256=$retained_release_hash \
        ACTION35R_RETAINED_PAYLOAD_MANIFEST_SHA256=$retained_payload_hash \
        remote_transaction node-b-retained-check-producer "$node_b_host" retained-check \
        node-b "$node_b_payload" "$node_b_evidence"
    [[ -d "$retained_candidate" ]]
    ACTION35R_ENVIRONMENT_FILE=$test_remote_base/environment-node-a \
        ACTION35R_KEEPALIVED_COMMAND=$test_remote_base/bin/keepalived \
        ACTION35R_UNBOUND_CHECKCONF_COMMAND=$test_remote_base/bin/unbound-checkconf \
        ACTION35R_RUNUSER_COMMAND=$test_remote_base/bin/runuser \
        ACTION35R_SYSTEMCTL_COMMAND=$test_remote_base/bin/systemctl \
        ACTION35R_DNS_DIG_COMMAND=$test_remote_base/bin/dig \
        ACTION35R_CURL_COMMAND=$test_remote_base/bin/curl \
        ACTION35R_SS_COMMAND=$test_remote_base/bin/ss \
        remote_transaction node-a-candidate-producer "$node_a_host" candidate-check \
        node-a "$node_a_payload" "$node_a_evidence"
    ACTION35R_ENVIRONMENT_FILE=$test_remote_base/environment-node-b \
        ACTION35R_KEEPALIVED_COMMAND=$test_remote_base/bin/keepalived \
        ACTION35R_UNBOUND_CHECKCONF_COMMAND=$test_remote_base/bin/unbound-checkconf \
        ACTION35R_RUNUSER_COMMAND=$test_remote_base/bin/runuser \
        ACTION35R_SYSTEMCTL_COMMAND=$test_remote_base/bin/systemctl \
        ACTION35R_DNS_DIG_COMMAND=$test_remote_base/bin/dig \
        ACTION35R_CURL_COMMAND=$test_remote_base/bin/curl \
        ACTION35R_SS_COMMAND=$test_remote_base/bin/ss \
        remote_transaction node-b-candidate-producer "$node_b_host" candidate-check \
        node-b "$node_b_payload" "$node_b_evidence"
    ACTION35R_JOURNALCTL_COMMAND=$test_remote_base/bin/journalctl \
        remote_transaction node-a-journal-cursor-producer "$node_a_host" journal-cursor \
        node-a "$node_a_payload" "$node_a_evidence"
    ACTION35R_JOURNALCTL_COMMAND=$test_remote_base/bin/journalctl \
        remote_transaction node-b-journal-cursor-producer "$node_b_host" journal-cursor \
        node-b "$node_b_payload" "$node_b_evidence"
    ACTION35R_JOURNALCTL_COMMAND=$test_remote_base/bin/journalctl \
        remote_transaction node-a-journal-capture-producer "$node_a_host" journal-capture \
        node-a "$node_a_payload" "$node_a_evidence"
    ACTION35R_JOURNALCTL_COMMAND=$test_remote_base/bin/journalctl \
        remote_transaction node-b-journal-capture-producer "$node_b_host" journal-capture \
        node-b "$node_b_payload" "$node_b_evidence"
    install -d -m 0700 "$test_remote_base/node-a-root" "$test_remote_base/node-b-root"
    install -d -m 0755 "$test_remote_base/node-b-root/usr/local/libexec"
    install -m 0755 "$repository_root/Caddy/scripts/prepare-lighttpd-config.sh" \
        "$test_remote_base/node-b-root/usr/local/libexec/prepare-lighttpd-config.sh"
    ACTION35R_TARGET_ROOT=$test_remote_base/node-b-root \
        ACTION35R_SYSTEMCTL_COMMAND=$test_remote_base/bin/systemctl \
        ACTION35R_UNBOUND_CHECKCONF_COMMAND=$test_remote_base/bin/unbound-checkconf \
        remote_transaction node-b-install-producer "$node_b_host" install node-b \
        "$node_b_payload" "$node_b_evidence"
    ACTION35R_TARGET_ROOT=$test_remote_base/node-a-root \
        ACTION35R_SYSTEMCTL_COMMAND=$test_remote_base/bin/systemctl \
        ACTION35R_UNBOUND_CHECKCONF_COMMAND=$test_remote_base/bin/unbound-checkconf \
        remote_transaction node-a-install-producer "$node_a_host" install node-a \
        "$node_a_payload" "$node_a_evidence"
    ACTION35R_TARGET_ROOT=$test_remote_base/node-a-root \
        ACTION35R_SYSTEMCTL_COMMAND=$test_remote_base/bin/systemctl \
        ACTION35R_UNBOUND_CHECKCONF_COMMAND=$test_remote_base/bin/unbound-checkconf \
        remote_transaction node-a-rollback-producer "$node_a_host" rollback node-a \
        "$node_a_payload" "$node_a_evidence"
    ACTION35R_TARGET_ROOT=$test_remote_base/node-b-root \
        ACTION35R_SYSTEMCTL_COMMAND=$test_remote_base/bin/systemctl \
        ACTION35R_UNBOUND_CHECKCONF_COMMAND=$test_remote_base/bin/unbound-checkconf \
        remote_transaction node-b-rollback-producer "$node_b_host" rollback node-b \
        "$node_b_payload" "$node_b_evidence"
    [[ -z "$(find "$test_remote_base/node-a-root" -type f -print -quit)" ]]
    [[ "$(find "$test_remote_base/node-b-root" -type f -printf '%P\n')" = usr/local/libexec/prepare-lighttpd-config.sh ]]
    [[ "$(sha256sum "$test_remote_base/node-b-root/usr/local/libexec/prepare-lighttpd-config.sh" | awk '{ print $1 }')" = ce9a78aa487ce55c6fbba553b238160687852361d81c9b37179e4def8f83166f ]]
    remote_transaction node-a-evidence-producer "$node_a_host" evidence-probe \
        node-a "$node_a_payload" "$node_a_evidence"
    remote_transaction node-b-evidence-producer "$node_b_host" evidence-probe \
        node-b "$node_b_payload" "$node_b_evidence"

    action35r_raw=$action35r_test_root/raw/outer-preflight.txt
    action35r_decision=$action35r_test_root/decisions/outer-preflight.tsv
    cat "$test_remote_base/ssh.calls" "$test_remote_base/scp.calls" \
        "$test_remote_base/runuser.identities" "$test_remote_base/systemctl.calls" \
        >"$action35r_raw"
    action35r_observed=$(wc -l <"$action35r_raw")
    write_decision outer-preflight reach 0 "$action35r_observed" \
        "$action35r_observed" "$action35r_raw" "$action35r_decision"

    for action35r_role in node-a node-b; do
        if [[ "$action35r_role" = node-a ]]; then
            action35r_remote_evidence=$node_a_evidence
        else
            action35r_remote_evidence=$node_b_evidence
        fi
        action35r_raw=$action35r_test_root/raw/evidence-readback-$action35r_role-success.txt
        action35r_decision=$action35r_test_root/decisions/evidence-readback-$action35r_role-success.tsv
        ssh_stream "test-$action35r_role" "$readback_program" \
            "$action35r_remote_evidence" >"$action35r_raw"
        action35r_observed=$(sha256sum "$action35r_raw" | awk '{ print $1 }')
        write_decision "evidence-readback-$action35r_role-success" accept 0 \
            "$action35r_observed" "$action35r_observed" "$action35r_raw" "$action35r_decision"

        action35r_raw=$action35r_test_root/raw/evidence-readback-$action35r_role-failure.txt
        action35r_decision=$action35r_test_root/decisions/evidence-readback-$action35r_role-failure.tsv
        if ssh_stream "test-$action35r_role" "$readback_program" \
            "$action35r_remote_evidence-absent" >"$action35r_raw" 2>&1; then
            action35r_status=0
        else
            action35r_status=$?
        fi
        write_decision "evidence-readback-$action35r_role-failure" reject \
            "$action35r_status" present absent "$action35r_raw" "$action35r_decision"
    done
    cleanup_remote node-a "$node_a_host" "$node_a_payload" "$node_a_archive"
    cleanup_remote node-b "$node_b_host" "$node_b_payload" "$node_b_archive"
    chmod -R u+rwX -- "$action35r_remote_base"
    rm -rf -- "$action35r_remote_base"
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
transaction=$repository_root/Caddy/scripts/apply-coupled-serving-health-action35r.sh
readonly transaction
regular_file "$transaction"
[[ "$(sha256sum "$transaction" | awk '{ print $1 }')" = "$transaction_sha256" ]]

if [[ "$invocation_mode" = --production-path-test ]]; then
    workstation_evidence=$(mktemp -d /tmp/caddy-action35r-outer-test.XXXXXX)
else
    workstation_evidence=$(mktemp -d /tmp/caddy-ssh-evidence-action35r.XXXXXX)
fi
readonly workstation_evidence
chmod 0700 "$workstation_evidence"
payload_stage=$workstation_evidence/payload
payload_archive=$workstation_evidence/action35r-payload.tar
prepare_program=$workstation_evidence/remote-prepare.sh
accept_program=$workstation_evidence/remote-accept.sh
disposition_program=$workstation_evidence/remote-disposition.sh
readback_program=$workstation_evidence/remote-readback.sh
readonly payload_stage payload_archive prepare_program accept_program disposition_program readback_program
run_id=$(date -u +%Y%m%dT%H%M%SZ)-$$
readonly run_id
node_a_payload=/tmp/caddy-action35r-$run_id-node-a
node_b_payload=/tmp/caddy-action35r-$run_id-node-b
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
