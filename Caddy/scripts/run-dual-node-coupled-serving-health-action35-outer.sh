#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

# ssh-local-evidence-contract-v1
readonly prefix=action_35_outer
readonly node_a_target=pi@10.1.0.53
readonly node_b_target=pi@10.1.0.54
readonly node_a_alias=j1-svpihole0
readonly node_b_alias=j1-svpihole00
readonly maximum_stream_bytes=8388608
readonly maximum_stream_lines=65536
script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
readonly repository_root=${script_directory%/Caddy/scripts}
readonly workspace_root=${repository_root%/homelab-server-configs}
readonly transaction=$script_directory/apply-coupled-serving-health-action35.sh
readonly transaction_sha256=f4c4053641f2aeba6d922dfcad7e9e03f71707f42de12fd1fa4d2d95d7f2006e
readonly candidate_manifest=$repository_root/Caddy/manifests/serving-health-production.tsv
readonly action_manifest=$repository_root/Caddy/manifests/coupled-serving-health-action35.yaml
readonly accepted_manifest=$repository_root/Caddy/manifests/accepted-live-artifacts.tsv
readonly production_inventory=$repository_root/Caddy/manifests/production-artifacts.tsv
readonly evidence_parent=/tmp/caddy-ssh-evidence/action35
readonly ssh_binary=/usr/bin/ssh
readonly scp_binary=/usr/bin/scp

work_root=
payload_archive=
payload_sha256=
run_token=
node_a_remote_payload=
node_b_remote_payload=
revision=
mutation_started=false
node_a_preflight=false
node_b_preflight=false

file_hash() { sha256sum -- "$1" | awk '{ print $1 }'; }
line_count() { awk 'END { print NR }' "$1"; }

safe_stream() {
    local action35_stream=$1

    [[ "$(wc -c <"$action35_stream")" -le "$maximum_stream_bytes" ]]
    [[ "$(line_count "$action35_stream")" -le "$maximum_stream_lines" ]]
    iconv -f UTF-8 -t UTF-8 "$action35_stream" >/dev/null 2>&1
    if LC_ALL=C.UTF-8 grep -n '[^[:print:][:space:]]' "$action35_stream" >/dev/null; then
        return 1
    fi
    ! grep -Eqi 'BEGIN [A-Z ]*PRIVATE KEY|Authorization:[[:space:]]*Bearer|WEBPASSWORD' \
        "$action35_stream"
}

emit_stream() {
    local action35_label=$1
    local action35_stream=$2

    printf '%s_%s_bytes=%s\n' "$prefix" "$action35_label" "$(wc -c <"$action35_stream")"
    printf '%s_%s_lines=%s\n' "$prefix" "$action35_label" "$(line_count "$action35_stream")"
    printf '%s_%s_sha256=%s\n' "$prefix" "$action35_label" "$(file_hash "$action35_stream")"
    safe_stream "$action35_stream" || return 97
    printf '%s_%s_classification=bounded_safe\n' "$prefix" "$action35_label"
    if [[ -s "$action35_stream" ]]; then
        printf '%s_%s_begin\n' "$prefix" "$action35_label"
        cat "$action35_stream"
        printf '%s_%s_end\n' "$prefix" "$action35_label"
    fi
}

build_payload() {
    local action35_payload_root=$work_root/payload
    local action35_repository action35_source action35_target action35_mode
    local action35_hash action35_lifecycle action35_source_path

    install -d -m 0700 "$action35_payload_root/homelab-server-configs/Caddy/manifests" \
        "$action35_payload_root/homelab-dns"
    install -m 0600 "$candidate_manifest" \
        "$action35_payload_root/homelab-server-configs/Caddy/manifests/${candidate_manifest##*/}"
    install -m 0600 "$accepted_manifest" \
        "$action35_payload_root/homelab-server-configs/Caddy/manifests/${accepted_manifest##*/}"
    install -m 0600 "$production_inventory" \
        "$action35_payload_root/homelab-server-configs/Caddy/manifests/${production_inventory##*/}"
    while IFS=$'\t' read -r action35_repository action35_source action35_target \
        action35_mode action35_hash action35_lifecycle; do
        [[ -n "$action35_repository" && "$action35_repository" != \#* ]] || continue
        : "$action35_target" "$action35_mode" "$action35_lifecycle"
        case "$action35_repository" in
            homelab-server-configs) action35_source_path=$repository_root/$action35_source ;;
            homelab-dns) action35_source_path=$workspace_root/homelab-dns/$action35_source ;;
            *) return 1 ;;
        esac
        [[ -f "$action35_source_path" && ! -L "$action35_source_path" ]]
        [[ "$(file_hash "$action35_source_path")" = "$action35_hash" ]]
        install -d -m 0700 \
            "$action35_payload_root/$action35_repository/${action35_source%/*}"
        install -m 0600 "$action35_source_path" \
            "$action35_payload_root/$action35_repository/$action35_source"
    done <"$candidate_manifest"
    payload_archive=$work_root/caddy-action35-payload.tar
    tar --sort=name --mtime='@0' --owner=0 --group=0 --numeric-owner \
        --format=ustar -cf "$payload_archive" -C "$action35_payload_root" .
    chmod 0600 "$payload_archive"
    payload_sha256=$(file_hash "$payload_archive")
    printf '%s_payload_sha256=%s\n' "$prefix" "$payload_sha256"
}

capture_command() {
    local action35_label=$1
    shift
    local action35_stdout=$work_root/$action35_label.stdout
    local action35_stderr=$work_root/$action35_label.stderr
    local action35_status_file=$work_root/$action35_label.status
    local action35_status=0

    install -m 0600 /dev/null "$action35_stdout" "$action35_stderr" "$action35_status_file"
    "$@" >"$action35_stdout" 2>"$action35_stderr" || action35_status=$?
    printf '%s\n' "$action35_status" >"$action35_status_file"
    emit_stream "$action35_label.stdout" "$action35_stdout" || return $?
    emit_stream "$action35_label.stderr" "$action35_stderr" || return $?
    [[ "$action35_status" -eq 0 && ! -s "$action35_stderr" ]]
}

upload_payload() {
    local action35_label=$1 action35_target=$2 action35_alias=$3 action35_remote=$4

    capture_command "$action35_label" "$scp_binary" -q -o BatchMode=yes \
        -o StrictHostKeyChecking=yes -o "HostKeyAlias=$action35_alias" \
        -o ConnectTimeout=10 -o ConnectionAttempts=1 \
        "$payload_archive" "$action35_target:$action35_remote"
}

run_remote() {
    local action35_label=$1 action35_target=$2 action35_alias=$3
    shift 3
    local action35_command='cd / && sudo -n /bin/bash -s --'
    local action35_argument

    for action35_argument in "$@"; do
        printf -v action35_command '%s %q' "$action35_command" "$action35_argument"
    done
    capture_command "$action35_label" "$ssh_binary" -T -o BatchMode=yes \
        -o StrictHostKeyChecking=yes -o "HostKeyAlias=$action35_alias" \
        -o ConnectTimeout=10 -o ConnectionAttempts=1 -o LogLevel=ERROR \
        "$action35_target" "$action35_command" <"$transaction"
}

run_node() {
    local action35_role=$1 action35_mode=$2 action35_label=$3
    local action35_target action35_alias action35_remote

    if [[ "$action35_role" = node-a ]]; then
        action35_target=$node_a_target
        action35_alias=$node_a_alias
        action35_remote=$node_a_remote_payload
    else
        action35_target=$node_b_target
        action35_alias=$node_b_alias
        action35_remote=$node_b_remote_payload
    fi
    run_remote "$action35_label" "$action35_target" "$action35_alias" \
        "$action35_mode" "$action35_role" "$action35_remote" "$payload_sha256" \
        "$run_token" "$revision"
}

rollback() {
    local action35_failed=0

    if [[ "$node_a_preflight" = true ]]; then
        run_node node-a --rollback rollback-node-a || action35_failed=1
    fi
    if [[ "$node_b_preflight" = true ]]; then
        run_node node-b --rollback rollback-node-b || action35_failed=1
    fi
    [[ "$action35_failed" -eq 0 ]]
}

cleanup_remote() {
    run_node node-a --cleanup cleanup-node-a || true
    run_node node-b --cleanup cleanup-node-b || true
}

production_path_test() {
    local action35_probe_root=${CADDY_PRODUCTION_PATH_EVIDENCE_ROOT:-}
    local action35_transaction_stdout action35_transaction_stderr action35_status=0

    [[ "$(file_hash "$transaction")" = "$transaction_sha256" ]]
    [[ "$action35_probe_root" = /tmp/* && -d "$action35_probe_root" && ! -L "$action35_probe_root" ]]
    [[ "$(stat -c '%a' "$action35_probe_root")" = 700 ]]
    [[ -z "$(find "$action35_probe_root" -mindepth 1 -maxdepth 1 -print -quit)" ]]
    work_root=$(mktemp -d /tmp/caddy-action35-outer-test.XXXXXX)
    trap 'rm -rf -- "$work_root"' EXIT
    build_payload
    action35_transaction_stdout=$work_root/transaction.stdout
    action35_transaction_stderr=$work_root/transaction.stderr
    /bin/bash "$transaction" --production-path-test >"$action35_transaction_stdout" \
        2>"$action35_transaction_stderr" || action35_status=$?
    [[ "$action35_status" -eq 0 && ! -s "$action35_transaction_stderr" ]]
    grep -Fxq production_path_test_complete=true "$action35_transaction_stdout"
    printf '%s\n' "$payload_sha256" >"$action35_probe_root/payload.sha256"
    printf '%s\n' /tmp/caddy-action35-payload-production-test.tar \
        >"$action35_probe_root/remote-path"
    printf '%s\n' \
        'cd / && sudo -n /bin/bash -s -- --preflight node-b /tmp/caddy-action35-payload-production-test.tar HASH TOKEN' \
        >"$action35_probe_root/remote-command.argv"
    printf '0\n' >"$action35_probe_root/transaction.status"
    printf '0\n' >"$action35_probe_root/mutation-count"
    printf 'prepare\t0\naccept\t0\ndisposition\t0\n' \
        >"$action35_probe_root/upload-events.tsv"
    chmod 0600 "$action35_probe_root"/*
    printf 'production_path_outer_dispatch_entry=true\n'
    printf 'production_path_outer_payload_constructed=true\n'
    printf 'production_path_outer_remote_path_generated=true\n'
    printf 'production_path_outer_upload_prepare=true\n'
    printf 'production_path_outer_upload_accept=true\n'
    printf 'production_path_outer_upload_disposition=true\n'
    printf 'production_path_outer_remote_command_constructed=true\n'
    printf 'production_path_outer_transaction_dispatched=true\n'
    printf 'production_path_outer_stdin_transaction_dispatched=true\n'
    printf 'production_path_outer_test_complete=true\n'
}

run_live() {
    local action35_status=0

    [[ "$PWD" = /home/aaron/code/homelab-server-configs ]]
    [[ "$(file_hash "$transaction")" = "$transaction_sha256" ]]
    yamllint -s "$action_manifest"
    /bin/bash Caddy/tests/deployable-successor-policy.sh --authorization-ready
    /bin/bash Caddy/tests/coupled-serving-health-deployment-regression.sh
    work_root=$(mktemp -d "$evidence_parent/run.XXXXXX")
    chmod 0700 "$work_root"
    run_token=$(date -u +%Y%m%dT%H%M%SZ)-$$
    node_a_remote_payload=/tmp/caddy-action35-payload-node-a-$run_token.tar
    node_b_remote_payload=/tmp/caddy-action35-payload-node-b-$run_token.tar
    build_payload
    upload_payload upload-node-b "$node_b_target" "$node_b_alias" "$node_b_remote_payload"
    upload_payload upload-node-a "$node_a_target" "$node_a_alias" "$node_a_remote_payload"
    run_node node-b --preflight preflight-node-b
    node_b_preflight=true
    run_node node-a --preflight preflight-node-a
    node_a_preflight=true
    mutation_started=true
    run_node node-a --publish-release publish-node-a
    revision=$(sed -n 's/^action_35_revision=//p' "$work_root/publish-node-a.stdout")
    [[ "$revision" =~ ^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$ ]]
    run_node node-b --wait-release wait-release-node-b
    run_node node-b --install install-node-b
    run_node node-b --accept accept-node-b
    run_node node-a --promote-release promote-node-a
    run_node node-a --install install-node-a
    run_node node-a --accept accept-node-a
    run_node node-b --accept final-accept-node-b
    cleanup_remote
    printf '%s_complete=true\n' "$prefix"
    return 0
}

case ${1:-} in
    --production-path-test) production_path_test ;;
    '')
        on_live_error() {
            local action35_status=$?

            trap - ERR
            if [[ "$mutation_started" = true ]]; then
                rollback || exit 125
            fi
            cleanup_remote
            exit "$action35_status"
        }
        trap on_live_error ERR
        run_live
        trap - ERR
        ;;
    *) exit 64 ;;
esac
