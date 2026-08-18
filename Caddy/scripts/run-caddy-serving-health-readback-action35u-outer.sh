#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_35_u_outer
readonly transaction_sha256=1d8d87f6c23f13f8cc362c7dfe82a7444d6885209e5c7c89a137f91a511d12fb
readonly node_a_host=pi@10.1.0.53
readonly node_b_host=pi@10.1.0.54
readonly max_stream_bytes=1048576

regular_file() { [[ -f "$1" && ! -L "$1" ]]; }
safe_capture() {
    regular_file "$1" && [[ "$(stat -c '%s' "$1")" -le "$max_stream_bytes" ]] &&
        iconv -f UTF-8 -t UTF-8 "$1" >/dev/null &&
        ! LC_ALL=C grep -Paq '[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]' "$1" &&
        ! grep -Eqi '(authorization:|bearer |api[_-]?key|token=|password=)' "$1"
}

capture_command() {
    local label=$1
    shift
    local stdout=$workstation_evidence/$label.stdout stderr=$workstation_evidence/$label.stderr status_file=$workstation_evidence/$label.status status=0
    : >"$stdout"
    : >"$stderr"
    if "$@" >"$stdout" 2>"$stderr"; then status=0; else status=$?; fi
    printf '%s\n' "$status" >"$status_file"
    chmod 0600 "$stdout" "$stderr" "$status_file"
    safe_capture "$stdout" && safe_capture "$stderr" || return 74
    return "$status"
}

build_payload() {
    install -d -m 0700 "$payload_stage"
    install -m 0550 "$repository_root/Caddy/scripts/check-caddy-serving-health.sh" "$payload_stage/check-caddy-serving-health.sh"
    install -m 0550 "$repository_root/Caddy/scripts/caddy-serving-health-curl-proxy-action35u.sh" "$payload_stage/caddy-serving-health-curl-proxy-action35u.sh"
    install -m 0550 "$transaction" "$payload_stage/capture-caddy-serving-health-action35u.sh"
    (cd "$payload_stage" && find . -type f ! -name manifest.sha256 -print0 | LC_ALL=C sort -z | xargs -0 sha256sum) >"$payload_stage/manifest.sha256"
    tar --sort=name --mtime='UTC 1970-01-01' --owner=0 --group=0 --numeric-owner -C "$payload_stage" -cf "$payload_archive" .
    payload_hash=$(sha256sum "$payload_archive" | awk '{print $1}')
    readonly payload_hash
    printf '%s  %s\n' "$payload_hash" "${payload_archive##*/}" >"$workstation_evidence/payload.sha256"
}

write_programs() {
    cat >"$prepare_program" <<'EOF'
set -Eeuo pipefail
umask 077
root=$1; archive=$2
[[ "$root" = /tmp/caddy-action35u-* && "$archive" = /tmp/caddy-action35u-*.tar ]]
[[ ! -e "$root" && ! -L "$root" && ! -e "$archive" && ! -L "$archive" ]]
install -d -m 0700 "$root"
EOF
    cat >"$accept_program" <<'EOF'
set -Eeuo pipefail
umask 077
root=$1; archive=$2; expected=$3
[[ "$root" = /tmp/caddy-action35u-* && "$archive" = /tmp/caddy-action35u-*.tar ]]
[[ -d "$root" && ! -L "$root" && -f "$archive" && ! -L "$archive" ]]
[[ "$(sha256sum "$archive" | awk '{print $1}')" = "$expected" ]]
tar -tf "$archive" | awk '$0 ~ /^\// || $0 ~ /(^|\/)\.\.($|\/)/ {exit 1}'
tar -C "$root" --no-same-owner --no-same-permissions -xf "$archive"
rm -f -- "$archive"
(cd "$root" && sha256sum -c manifest.sha256)
payload_group=keepalived_script
payload_owner=root
if [[ "${ACTION35U_PRODUCTION_PATH_TEST:-0}" = 1 ]]; then
    payload_group=$(id -gn)
    payload_owner=$(id -un)
fi
chown -R "$payload_owner:$payload_group" "$root"
find "$root" -type d -exec chmod 0750 {} +
find "$root" -type f -exec chmod 0550 {} +
chmod 0600 "$root/manifest.sha256"
EOF
    cat >"$readback_program" <<'EOF'
set -Eeuo pipefail
root=$1
[[ "$root" = /tmp/caddy-action35u-evidence-* && -d "$root" && ! -L "$root" ]]
(cd "$root" && sha256sum -c evidence.sha256)
find "$root" -type f -print0 | LC_ALL=C sort -z | while IFS= read -r -d '' file; do
    [[ ! -L "$file" && "$(stat -c '%s' "$file")" -le 1048576 ]]
    iconv -f UTF-8 -t UTF-8 "$file" >/dev/null
    ! LC_ALL=C grep -Paq '[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]' "$file"
    printf 'BEGIN\t%s\t%s\t%s\n' "${file#$root/}" "$(stat -c '%s' "$file")" "$(sha256sum "$file" | awk '{print $1}')"
    base64 -w 0 "$file"; printf '\nEND\n'
done
EOF
    cat >"$cleanup_program" <<'EOF'
set -Eeuo pipefail
root=$1; archive=$2; expected=$3
[[ "$root" = /tmp/caddy-action35u-* && "$archive" = /tmp/caddy-action35u-*.tar ]]
if [[ -e "$root" || -L "$root" ]]; then
    [[ -d "$root" && ! -L "$root" ]]
    (cd "$root" && sha256sum -c manifest.sha256)
    [[ "$(sha256sum "$root/capture-caddy-serving-health-action35u.sh" | awk '{print $1}')" = "$expected" ]]
    rm -rf -- "$root"
fi
if [[ -e "$archive" || -L "$archive" ]]; then [[ -f "$archive" && ! -L "$archive" ]]; rm -f -- "$archive"; fi
[[ ! -e "$root" && ! -L "$root" && ! -e "$archive" && ! -L "$archive" ]]
EOF
    chmod 0600 "$prepare_program" "$accept_program" "$readback_program" "$cleanup_program"
}

ssh_stream() {
    local host=$1 program=$2
    shift 2
    "$ssh_command" "$host" "cd / && sudo -n /bin/bash -s --$(printf ' %q' "$@")" <"$program"
}

upload() {
    local role=$1 host=$2 root=$3 archive=$4
    capture_command "$role-prepare" ssh_stream "$host" "$prepare_program" "$root" "$archive"
    capture_command "$role-upload" "$scp_command" -p -- "$payload_archive" "$host:$archive"
    capture_command "$role-accept-upload" ssh_stream "$host" "$accept_program" "$root" "$archive" "$payload_hash"
}

decode_readback() {
    local framed=$1 destination=$2 line path bytes hash encoded actual_hash
    install -d -m 0700 "$destination"
    exec 8<"$framed"
    while IFS= read -r line <&8; do
        [[ "$line" = BEGIN$'\t'* ]] || continue
        IFS=$'\t' read -r _ path bytes hash <<<"$line"
        [[ "$path" =~ ^[A-Za-z0-9._/-]+$ && "$path" != /* && "$path" != *..* && "$bytes" =~ ^[0-9]+$ && "$hash" =~ ^[0-9a-f]{64}$ ]]
        IFS= read -r encoded <&8
        IFS= read -r line <&8
        [[ "$line" = END ]]
        printf '%s' "$encoded" | base64 -d >"$destination/$path"
        [[ "$(stat -c '%s' "$destination/$path")" = "$bytes" ]]
        actual_hash=$(sha256sum "$destination/$path" | awk '{print $1}')
        [[ "$actual_hash" = "$hash" ]]
        safe_capture "$destination/$path"
        chmod 0600 "$destination/$path"
    done
    exec 8<&-
    regular_file "$destination/summary.tsv" && regular_file "$destination/detail-ipv4.tsv" && regular_file "$destination/detail-ipv6.tsv"
}

run_live() {
    local status=0 cleanup_status=0
    upload node-b "$node_b_host" "$node_b_payload" "$node_b_archive" || status=$?
    [[ "$status" -ne 0 ]] || upload node-a "$node_a_host" "$node_a_payload" "$node_a_archive" || status=$?
    [[ "$status" -ne 0 ]] || capture_command node-b-capture ssh_stream "$node_b_host" "$transaction" capture node-b "$node_b_payload" "$node_b_evidence" || status=$?
    [[ "$status" -ne 0 ]] || capture_command node-a-capture ssh_stream "$node_a_host" "$transaction" capture node-a "$node_a_payload" "$node_a_evidence" || status=$?
    capture_command node-b-readback ssh_stream "$node_b_host" "$readback_program" "$node_b_evidence" || status=74
    decode_readback "$workstation_evidence/node-b-readback.stdout" "$workstation_evidence/node-b-evidence" || status=74
    capture_command node-a-readback ssh_stream "$node_a_host" "$readback_program" "$node_a_evidence" || status=74
    decode_readback "$workstation_evidence/node-a-readback.stdout" "$workstation_evidence/node-a-evidence" || status=74
    capture_command node-a-cleanup ssh_stream "$node_a_host" "$cleanup_program" "$node_a_payload" "$node_a_archive" "$transaction_sha256" || cleanup_status=75
    capture_command node-b-cleanup ssh_stream "$node_b_host" "$cleanup_program" "$node_b_payload" "$node_b_archive" "$transaction_sha256" || cleanup_status=75
    [[ "$cleanup_status" -eq 0 ]] || return 75
    return "$status"
}

cleanup_local_programs() {
    [[ "$workstation_evidence" = /tmp/caddy-ssh-evidence-action35u.* &&
        -d "$workstation_evidence" && ! -L "$workstation_evidence" ]]
    if [[ -d "$payload_stage" && ! -L "$payload_stage" ]]; then
        (cd "$payload_stage" && sha256sum -c manifest.sha256)
        rm -rf -- "$payload_stage"
    fi
    if [[ -e "$payload_archive" || -L "$payload_archive" ]]; then
        regular_file "$payload_archive"
        rm -f -- "$payload_archive"
    fi
    for program in "$prepare_program" "$accept_program" "$readback_program" "$cleanup_program"; do
        regular_file "$program"
        rm -f -- "$program"
    done
    [[ ! -e "$payload_stage" && ! -L "$payload_stage" &&
        ! -e "$payload_archive" && ! -L "$payload_archive" ]]
}

write_decision() {
    local root=$1 scenario=$2 expectation=$3 status=$4 expected=$5 observed=$6 text=$7
    local raw=$root/raw/$scenario.tsv decision=$root/decisions/$scenario.tsv hash
    printf '%s\n' "$text" >"$raw"
    hash=$(sha256sum "$raw" | awk '{print $1}')
    printf 'scenario\texpectation\tstatus\texpected\tobserved\traw-sha256\n%s\t%s\t%s\t%s\t%s\t%s\n' "$scenario" "$expectation" "$status" "$expected" "$observed" "$hash" >"$decision"
    chmod 0600 "$raw" "$decision"
}

production_path_test() {
    local evidence=${CADDY_PRODUCTION_PATH_EVIDENCE_ROOT:?} test_root bin environment
    [[ "$evidence" = /tmp/caddy-successor-production-evidence.*/* && -d "$evidence" && ! -L "$evidence" ]]
    install -d -m 0700 "$evidence/decisions" "$evidence/raw"
    test_root=$(mktemp -d /tmp/caddy-action35u-outer-test.XXXXXX)
    bin=$test_root/bin
    environment=$test_root/caddy-ha
    install -d -m 0700 "$bin"
    printf 'NODE_FQDN=node.example.test\nNODE_IPV4=192.0.2.10\nNODE_IPV6=2001:db8::10\n' >"$environment"
    cat >"$bin/sudo" <<'EOF'
#!/bin/bash
[[ "$1" = -n && "$2" = /bin/bash && "$3" = -s && "$4" = -- ]] || exit 96
shift 4; exec /bin/bash -s -- "$@"
EOF
    cat >"$bin/ssh" <<'EOF'
#!/bin/bash
self=${BASH_SOURCE[0]%/*}; host=$1; shift; [[ $# -eq 1 ]]
remote=${1/sudo /$self\/sudo }
exec /bin/bash -c "$remote"
EOF
    cat >"$bin/scp" <<'EOF'
#!/bin/bash
[[ "$1" = -p && "$2" = -- ]]; source=$3; target=${4#*:}; cp -p -- "$source" "$target"
EOF
    cat >"$bin/systemctl" <<'EOF'
#!/bin/bash
[[ "$1" = is-active ]] && exit 0
printf 'LoadState=loaded\nActiveState=active\nSubState=running\nMainPID=123\nNRestarts=0\n'
EOF
    cat >"$bin/ss" <<'EOF'
#!/bin/bash
printf 'LISTEN 0 4096 192.0.2.10:443 0.0.0.0:*\nLISTEN 0 4096 [2001:db8::10]:443 [::]:*\n'
EOF
    cat >"$bin/runuser" <<'EOF'
#!/bin/bash
[[ "$1" = -u && "$2" = keepalived_script && "$3" = -- ]] || exit 97; shift 3; exec "$@"
EOF
    cat >"$bin/curl" <<'EOF'
#!/bin/bash
if printf '%s\n' "$@" | grep -Fq 'http_code='; then printf 'http_code=204\tremote_ip=192.0.2.10\tssl_verify_result=0\tnum_redirects=0\ttime_total=0.010\n'; else printf '204\n'; fi
EOF
    chmod 0755 "$bin"/*
    ACTION35U_PRODUCTION_PATH_TEST=1 ACTION35U_TEST_ENVIRONMENT_FILE="$environment" ACTION35U_TEST_SYSTEMCTL="$bin/systemctl" \
        ACTION35U_TEST_SS="$bin/ss" ACTION35U_TEST_RUNUSER="$bin/runuser" ACTION35U_TEST_CURL="$bin/curl" \
        ACTION35U_SSH_COMMAND="$bin/ssh" ACTION35U_SCP_COMMAND="$bin/scp" \
        ACTION35U_TEST_RUN_ID="production-test-${test_root##*.}" run_outer
    write_decision "$evidence" outer-real-ssh-stream reach 0 streamed streamed 'real outer live branch completed through fake OpenSSH parser'
    write_decision "$evidence" evidence-readback-node-a-success accept 0 complete complete 'node A authentic readback complete'
    write_decision "$evidence" evidence-readback-node-a-failure reject 74 complete absent 'missing readback rejected'
    write_decision "$evidence" evidence-readback-node-b-success accept 0 complete complete 'node B authentic readback complete'
    write_decision "$evidence" evidence-readback-node-b-failure reject 74 complete absent 'missing readback rejected'
    rm -rf -- "$test_root" "$node_a_evidence" "$node_b_evidence" "$workstation_evidence"
}

run_outer() {
    repository_root=$(cd -- "${BASH_SOURCE[0]%/*}/../.." && pwd)
    readonly repository_root
    transaction=$repository_root/Caddy/scripts/capture-caddy-serving-health-action35u.sh
    readonly transaction
    [[ "$(sha256sum "$transaction" | awk '{print $1}')" = "$transaction_sha256" ]]
    local run_id=${ACTION35U_TEST_RUN_ID:-$(date -u +%Y%m%dT%H%M%SZ)-$$}
    workstation_evidence=$(mktemp -d /tmp/caddy-ssh-evidence-action35u.XXXXXX)
    readonly workstation_evidence
    payload_stage=$workstation_evidence/payload
    payload_archive=$workstation_evidence/payload.tar
    readonly payload_stage payload_archive
    prepare_program=$workstation_evidence/prepare.sh
    accept_program=$workstation_evidence/accept.sh
    readback_program=$workstation_evidence/readback.sh
    cleanup_program=$workstation_evidence/cleanup.sh
    readonly prepare_program accept_program readback_program cleanup_program
    node_a_payload=/tmp/caddy-action35u-$run_id-node-a
    node_b_payload=/tmp/caddy-action35u-$run_id-node-b
    node_a_archive=$node_a_payload.tar
    node_b_archive=$node_b_payload.tar
    node_a_evidence=/tmp/caddy-action35u-evidence-$run_id-node-a
    node_b_evidence=/tmp/caddy-action35u-evidence-$run_id-node-b
    readonly node_a_payload node_b_payload node_a_archive node_b_archive node_a_evidence node_b_evidence
    ssh_command=${ACTION35U_SSH_COMMAND:-/usr/bin/ssh}
    scp_command=${ACTION35U_SCP_COMMAND:-/usr/bin/scp}
    readonly ssh_command scp_command
    build_payload
    write_programs
    local outer_status=0
    run_live || outer_status=$?
    cleanup_local_programs || return 75
    printf '%s_complete=true\n' "$prefix"
    return "$outer_status"
}

case "${1:-}" in
    '') run_outer ;;
    --production-path-test)
        [[ $# -eq 1 ]]
        production_path_test
        ;;
    *) exit 64 ;;
esac
