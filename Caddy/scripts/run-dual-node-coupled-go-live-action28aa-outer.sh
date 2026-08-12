#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

# ssh-local-evidence-contract-v1
readonly prefix=action_28aa_outer
readonly node_a_target=pi@10.1.0.53
readonly node_b_target=pi@10.1.0.54
readonly retained_revision=20260809T193432Z-6a2fab64-69e6-4cfb-a026-0a38fcae5b63
readonly maximum_stream_bytes=4194304
readonly maximum_stream_lines=32768
readonly maximum_failover_seconds=90
readonly maximum_failback_seconds=120
script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
readonly caddy_root=${script_directory%/scripts}
readonly transaction=$script_directory/transact-coupled-go-live-action28aa.sh
readonly publisher=$script_directory/publish-release-v2.sh
readonly reconciler=$script_directory/reconcile-release-v2.sh
readonly node_a_lsyncd=$caddy_root/configs/lsyncd/caddy-node-a.lua
readonly node_b_lsyncd=$caddy_root/configs/lsyncd/caddy-node-b.lua
readonly regression=$caddy_root/tests/action28aa-coupled-go-live-regression.sh
readonly manifest=$caddy_root/manifests/caddy-coupled-go-live-action28aa.yaml
readonly expected_transaction_sha256=0f8fa79168933311eae07d7062c3d744f649ac8ca457b21c5e5414f6512e0ac5
readonly expected_publisher_sha256=4a1cbeca92babe731528e4901e7164a876ab7d52a668390d311bedc11238b513
readonly expected_reconciler_sha256=7bf8bad5fa978b64e3d4a6f12ff4632a42a6c11f429e3e92e193228cc4f29918
readonly expected_node_a_lsyncd_sha256=db0dd1cc9f297052fb4d627822696c9685218f442c5a1282e62186f9e61bad6d
readonly expected_node_b_lsyncd_sha256=b9b525a2a46bab73062cfa5e2e98fab617d137887c889e092bf981504332caf1
evidence_root=${CADDY_ACTION28AA_EVIDENCE_ROOT:-/tmp/caddy-ssh-evidence/action28aa}
readonly evidence_root
ssh_binary=${CADDY_ACTION28AA_SSH_BIN:-/usr/bin/ssh}
readonly ssh_binary
run_id=
outer_root=
last_stdout=
node_b_installed=false
node_a_installed=false
node_a_relinquished=false
transaction_complete=false
availability_pid=
availability_stop=
availability_samples=
availability_stderr=
classifier_fixture_root=

file_hash() { sha256sum -- "$1" | awk '{ print $1 }'; }
line_count() { awk 'END { print NR }' "$1"; }
valid_source() {
    local action28aa_outer_expected=$1
    local action28aa_outer_source=$2

    [[ -f "$action28aa_outer_source" && ! -L "$action28aa_outer_source" ]] || return 1
    [[ "$(file_hash "$action28aa_outer_source")" = "$action28aa_outer_expected" ]]
}
working_directory_approved() {
    case "$PWD" in
        /home/aaron/code/homelab-server-configs) return 0 ;;
        /workspace/homelab-server-configs) [[ "${CADDY_VALIDATION_CONTAINER:-}" = 1 ]] ;;
        *) return 1 ;;
    esac
}
gate() {
    local action28aa_outer_label=$1

    shift
    if "$@" >/dev/null 2>&1; then
        printf '%s_gate_%s=true\n' "$prefix" "$action28aa_outer_label"
        return 0
    fi
    printf '%s_gate_%s=false\n' "$prefix" "$action28aa_outer_label" >&2
    return 1
}
safe_stream() {
    local action28aa_outer_stream=$1

    [[ "$(wc -c <"$action28aa_outer_stream")" -le "$maximum_stream_bytes" ]] || return 1
    [[ "$(line_count "$action28aa_outer_stream")" -le "$maximum_stream_lines" ]] || return 1
    iconv -f UTF-8 -t UTF-8 "$action28aa_outer_stream" >/dev/null 2>&1 || return 1
    ! LC_ALL=C.UTF-8 grep -n '[^[:print:][:space:]]' \
        "$action28aa_outer_stream" >/dev/null || return 1
    ! grep -Eqi 'BEGIN [A-Z ]*PRIVATE KEY|Authorization:[[:space:]]*Bearer|WEBPASSWORD' \
        "$action28aa_outer_stream"
}
run_stream_classifier_self_test() {
    local action28aa_outer_fixture

    classifier_fixture_root=$(mktemp -d /tmp/action28aa-outer-stream.XXXXXX)
    trap 'rm -rf -- "$classifier_fixture_root"' EXIT INT TERM
    printf 'Created symlink /etc/systemd/system/example → /etc/systemd/system/example.service.\n' \
        >"$classifier_fixture_root/utf8"
    printf 'safe\001control\n' >"$classifier_fixture_root/control"
    printf 'invalid\377utf8\n' >"$classifier_fixture_root/invalid"
    printf 'WEBPASSWORD=redacted-fixture\n' >"$classifier_fixture_root/secret"
    head -c "$((maximum_stream_bytes + 1))" /dev/zero | tr '\0' a \
        >"$classifier_fixture_root/bytes"
    awk -v count="$((maximum_stream_lines + 1))" \
        'BEGIN { for (line = 1; line <= count; line++) print "x" }' \
        >"$classifier_fixture_root/lines"
    safe_stream "$classifier_fixture_root/utf8"
    for action28aa_outer_fixture in control invalid secret bytes lines; do
        if safe_stream "$classifier_fixture_root/$action28aa_outer_fixture"; then
            return 1
        fi
    done
    printf '%s_stream_classifier_utf8_accepted=true\n' "$prefix"
    printf '%s_stream_classifier_control_rejected=true\n' "$prefix"
    printf '%s_stream_classifier_invalid_utf8_rejected=true\n' "$prefix"
    printf '%s_stream_classifier_secret_rejected=true\n' "$prefix"
    printf '%s_stream_classifier_byte_limit_rejected=true\n' "$prefix"
    printf '%s_stream_classifier_line_limit_rejected=true\n' "$prefix"
    printf '%s_stream_classifier_self_test_complete=true\n' "$prefix"
}
emit_stream() {
    local action28aa_outer_label=$1
    local action28aa_outer_stream=$2

    printf '%s_%s_bytes=%s\n' "$prefix" "$action28aa_outer_label" \
        "$(wc -c <"$action28aa_outer_stream")"
    printf '%s_%s_lines=%s\n' "$prefix" "$action28aa_outer_label" \
        "$(line_count "$action28aa_outer_stream")"
    printf '%s_%s_sha256=%s\n' "$prefix" "$action28aa_outer_label" \
        "$(file_hash "$action28aa_outer_stream")"
    if ! safe_stream "$action28aa_outer_stream"; then
        printf '%s_%s_classification=unsafe_retained\n' "$prefix" "$action28aa_outer_label" >&2
        return 97
    fi
    printf '%s_%s_classification=bounded_safe\n' "$prefix" "$action28aa_outer_label"
    if [[ -s "$action28aa_outer_stream" ]]; then
        printf '%s_%s_begin\n' "$prefix" "$action28aa_outer_label"
        cat "$action28aa_outer_stream"
        printf '%s_%s_end\n' "$prefix" "$action28aa_outer_label"
    else
        printf '%s_%s_content=empty\n' "$prefix" "$action28aa_outer_label"
    fi
}
prepare_capture_files() {
    local action28aa_outer_capture

    for action28aa_outer_capture in "$@"; do
        install -m 0600 /dev/null "$action28aa_outer_capture"
        [[ -f "$action28aa_outer_capture" && ! -L "$action28aa_outer_capture" ]]
        [[ "$(stat -c '%a' "$action28aa_outer_capture")" = 600 ]]
    done
}
validate_remote_program() {
    local action28aa_outer_program=$1

    # These are exact generated-program literals, not expressions to expand.
    # shellcheck disable=SC2016
    grep -Fq '/bin/bash "$stage/transact-coupled-go-live-action28aa.sh" --mode' \
        "$action28aa_outer_program" || return 1
    # shellcheck disable=SC2016
    ! grep -Eq '^"\$stage/transact-coupled-go-live-action28aa\.sh" --mode' \
        "$action28aa_outer_program" || return 1
    # shellcheck disable=SC2016
    grep -Fq 'chmod 0700 "$stage/transact-coupled-go-live-action28aa.sh"' \
        "$action28aa_outer_program"
}
run_local_gates() {
    gate working_directory working_directory_approved
    gate transaction_source valid_source "$expected_transaction_sha256" "$transaction"
    gate publisher_source valid_source "$expected_publisher_sha256" "$publisher"
    gate reconciler_source valid_source "$expected_reconciler_sha256" "$reconciler"
    gate node_a_lsyncd_source valid_source "$expected_node_a_lsyncd_sha256" "$node_a_lsyncd"
    gate node_b_lsyncd_source valid_source "$expected_node_b_lsyncd_sha256" "$node_b_lsyncd"
    gate syntax /bin/bash -n "$transaction" "$publisher" "$reconciler" "${BASH_SOURCE[0]}"
    gate transaction_self_test "$transaction" --self-test
    gate transaction_stream_classifier "$transaction" --stream-classifier-self-test
    gate historical_quarantine_contract "$transaction" \
        --historical-quarantine-self-test
    gate regression /bin/bash "$regression"
    gate shellcheck shellcheck "$transaction" "$publisher" "$reconciler" "$regression" "${BASH_SOURCE[0]}"
    gate canonical_format /bin/bash "$caddy_root/tests/shfmt-canonical.sh" --check \
        "$transaction" "$publisher" "$reconciler" "$regression" "${BASH_SOURCE[0]}"
    gate collision_policy /bin/bash "$caddy_root/tests/check-shell-readonly-local-collisions-v2.sh" \
        "$transaction" "$publisher" "$reconciler" "$regression" "${BASH_SOURCE[0]}"
    gate conditional_policy /bin/bash "$caddy_root/tests/conditional-validator-errexit-policy-regression.sh"
    gate multifile_grep_policy /bin/bash "$caddy_root/tests/multifile-grep-count-policy.sh" \
        --check "$transaction" "$publisher" "$reconciler" "$regression" "${BASH_SOURCE[0]}"
    gate portable_awk_policy /bin/bash "$caddy_root/tests/portable-awk-policy.sh" \
        --check "$transaction" "$publisher" "$reconciler" "$regression" "${BASH_SOURCE[0]}"
    gate remote_cwd_policy /bin/bash "$caddy_root/tests/remote-streamed-bash-cwd-precommit.sh" "${BASH_SOURCE[0]}"
    gate ssh_evidence_policy /bin/bash "$caddy_root/tests/ssh-stream-local-evidence-policy.sh" \
        --check "${BASH_SOURCE[0]}"
    gate manifest yamllint -s "$manifest"
}
write_remote() {
    local action28aa_outer_role=$1
    local action28aa_outer_mode=$2
    local action28aa_outer_revision=$3
    local action28aa_outer_source=$4
    local action28aa_outer_output=$5
    local action28aa_outer_config=$node_a_lsyncd
    local action28aa_outer_archive=$outer_root/payload.tar

    [[ "$action28aa_outer_role" = node-a ]] || action28aa_outer_config=$node_b_lsyncd
    tar -cf "$action28aa_outer_archive" -C "$script_directory" \
        transact-coupled-go-live-action28aa.sh publish-release-v2.sh reconcile-release-v2.sh
    tar -rf "$action28aa_outer_archive" -C "${action28aa_outer_config%/*}" \
        --transform='s|.*|configs/caddy.lua|' "${action28aa_outer_config##*/}"
    # The single-quoted strings are the generated remote program.
    # shellcheck disable=SC2016
    {
        printf '%s\n' '#!/usr/bin/env bash' 'set -Eeuo pipefail' 'set +x' 'umask 077' \
            'PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin' \
            'export PATH' 'cd /' \
            'stage=$(mktemp -d /run/caddy-action28aa-bundle.XXXXXX)' \
            'cleanup_stage() { rm -rf -- "$stage"; }' \
            'trap cleanup_stage EXIT INT TERM' \
            'chown root:root "$stage"' 'chmod 0700 "$stage"' \
            'install -m 0600 /dev/null "$stage/payload.tar"' \
            "base64 -d >\"\$stage/payload.tar\" <<'ACTION28Z_ARCHIVE'"
        base64 "$action28aa_outer_archive"
        printf '%s\n' 'ACTION28Z_ARCHIVE' \
            'tar -xf "$stage/payload.tar" -C "$stage" --no-same-owner --no-same-permissions' \
            'mv "$stage/configs/caddy.lua" "$stage/caddy.lua"' \
            'chmod 0700 "$stage/transact-coupled-go-live-action28aa.sh"' \
            'chmod 0600 "$stage/publish-release-v2.sh" "$stage/reconcile-release-v2.sh" "$stage/caddy.lua"'
        printf '/bin/bash "$stage/transact-coupled-go-live-action28aa.sh" --mode %q --role %q --stage "$stage" --run-id %q' \
            "$action28aa_outer_mode" "$action28aa_outer_role" "$run_id"
        [[ -z "$action28aa_outer_revision" ]] || printf ' --revision %q' "$action28aa_outer_revision"
        [[ -z "$action28aa_outer_source" ]] || printf ' --source %q' "$action28aa_outer_source"
        printf '\n'
    } >"$action28aa_outer_output"
    chmod 0600 "$action28aa_outer_output"
    validate_remote_program "$action28aa_outer_output"
}
run_phase() {
    local action28aa_outer_label=$1
    local action28aa_outer_role=$2
    local action28aa_outer_mode=$3
    local action28aa_outer_revision=${4:-}
    local action28aa_outer_source=${5:-}
    local action28aa_outer_target=$node_a_target
    local action28aa_outer_remote=$outer_root/$action28aa_outer_label.remote.sh
    local remote_stdout=$outer_root/$action28aa_outer_label.stdout
    local remote_stderr=$outer_root/$action28aa_outer_label.stderr
    local status_file=$outer_root/$action28aa_outer_label.status
    local remote_status=0

    [[ "$action28aa_outer_role" = node-a ]] || action28aa_outer_target=$node_b_target
    write_remote "$action28aa_outer_role" "$action28aa_outer_mode" \
        "$action28aa_outer_revision" "$action28aa_outer_source" "$action28aa_outer_remote"
    prepare_capture_files "$remote_stdout" "$remote_stderr" "$status_file"
    "$ssh_binary" -T -F /dev/null -o BatchMode=yes -o ClearAllForwardings=yes \
        -o ConnectTimeout=8 -o KbdInteractiveAuthentication=no \
        -o PasswordAuthentication=no -o PreferredAuthentications=publickey \
        -o ServerAliveCountMax=3 -o ServerAliveInterval=3 \
        -o StrictHostKeyChecking=yes "$action28aa_outer_target" \
        'cd / && sudo -n /bin/bash -s --' <"$action28aa_outer_remote" \
        >"$remote_stdout" 2>"$remote_stderr" || remote_status=$?
    printf '%s\n' "$remote_status" >"$status_file"
    printf '%s_phase_%s_status=%s\n' "$prefix" "$action28aa_outer_label" "$remote_status"
    printf '%s_phase_%s_status_sha256=%s\n' "$prefix" "$action28aa_outer_label" \
        "$(file_hash "$status_file")"
    emit_stream remote_stdout "$remote_stdout" || return 97
    emit_stream remote_stderr "$remote_stderr" || return 97
    last_stdout=$remote_stdout
    [[ "$remote_status" -eq 0 ]] || return 1
    grep -Fxq "action_28aa_remote_${action28aa_outer_mode}_acceptance=true" \
        "$remote_stdout"
}
start_availability() {
    local action28aa_outer_label=$1

    availability_stop=$outer_root/availability-$action28aa_outer_label.stop
    availability_samples=$outer_root/availability-$action28aa_outer_label.samples
    availability_stderr=$outer_root/availability-$action28aa_outer_label.stderr
    install -m 0600 /dev/null "$availability_samples" "$availability_stderr"
    (
        local action28aa_outer_dns4_status
        local action28aa_outer_dns6_status
        local action28aa_outer_https4_status
        local action28aa_outer_https6_status

        while [[ ! -e "$availability_stop" ]]; do
            action28aa_outer_dns4_status=0
            action28aa_outer_dns6_status=0
            action28aa_outer_https4_status=0
            action28aa_outer_https6_status=0
            dig +time=2 +tries=1 +short @10.1.0.55 \
                pihole-admin.local.theama.co A >/dev/null \
                2>>"$availability_stderr" || action28aa_outer_dns4_status=$?
            dig +time=2 +tries=1 +short @fd36:5aa8:6971:1::55 \
                pihole-admin.local.theama.co AAAA >/dev/null \
                2>>"$availability_stderr" || action28aa_outer_dns6_status=$?
            curl --fail --silent --show-error --max-time 5 \
                --resolve pihole-admin.local.theama.co:443:10.1.0.56 \
                https://pihole-admin.local.theama.co/admin/login.php \
                >/dev/null 2>>"$availability_stderr" || action28aa_outer_https4_status=$?
            curl --fail --silent --show-error --max-time 5 \
                --resolve 'pihole-admin.local.theama.co:443:[fd36:5aa8:6971:1::56]' \
                https://pihole-admin.local.theama.co/admin/login.php \
                >/dev/null 2>>"$availability_stderr" || action28aa_outer_https6_status=$?
            printf 'epoch=%s dns4_status=%s dns6_status=%s https4_status=%s https6_status=%s\n' \
                "$(date +%s)" "$action28aa_outer_dns4_status" \
                "$action28aa_outer_dns6_status" "$action28aa_outer_https4_status" \
                "$action28aa_outer_https6_status" >>"$availability_samples"
            sleep 1
        done
    ) &
    availability_pid=$!
    printf '%s_availability_%s_started=true\n' "$prefix" "$action28aa_outer_label"
}
stop_availability() {
    local action28aa_outer_label=$1

    : >"$availability_stop"
    wait "$availability_pid"
    emit_stream "availability_${action28aa_outer_label}_samples" "$availability_samples" || return 97
    emit_stream "availability_${action28aa_outer_label}_stderr" "$availability_stderr" || return 97
    gate "availability_${action28aa_outer_label}_sampled" test -s "$availability_samples" || return 1
    gate "availability_${action28aa_outer_label}_continuous" \
        test -z "$(grep -E 'status=[1-9][0-9]*' "$availability_samples" || true)"
    availability_pid=
}
recover() {
    local action28aa_outer_recovery_ok=true

    printf '%s_recovery_started=true\n' "$prefix"
    if [[ "$node_a_relinquished" = false && "$node_a_installed" = false &&
        "$node_b_installed" = false ]]; then
        printf '%s_recovery_not_required=true\n' "$prefix"
        printf '%s_recovery_proven=true\n' "$prefix"
        return 0
    fi
    if [[ -n "$availability_pid" ]]; then
        : >"$availability_stop"
        wait "$availability_pid" || :
        availability_pid=
    fi
    if [[ "$node_a_relinquished" = true ]]; then
        run_phase recovery_restore_owner node-a restore-owner || action28aa_outer_recovery_ok=false
    fi
    if [[ "$node_a_installed" = true ]]; then
        run_phase recovery_rollback_node_a node-a rollback || action28aa_outer_recovery_ok=false
    fi
    if [[ "$node_b_installed" = true ]]; then
        run_phase recovery_rollback_node_b node-b rollback || action28aa_outer_recovery_ok=false
    fi
    run_phase recovery_node_a_master node-a state '' master || action28aa_outer_recovery_ok=false
    run_phase recovery_node_b_backup node-b state '' backup || action28aa_outer_recovery_ok=false
    printf '%s_recovery_proven=%s\n' "$prefix" "$action28aa_outer_recovery_ok"
    [[ "$action28aa_outer_recovery_ok" = true ]]
}
must_phase() {
    if run_phase "$@"; then
        return 0
    fi
    printf '%s_failed_phase=%s\n' "$prefix" "$1" >&2
    if recover; then
        exit 1
    fi
    printf '%s_manual_intervention_required=true\n' "$prefix" >&2
    exit 125
}
must_post_gate() {
    if gate "$@"; then
        return 0
    fi
    printf '%s_failed_post_gate=%s\n' "$prefix" "$1" >&2
    if recover; then
        exit 1
    fi
    printf '%s_manual_intervention_required=true\n' "$prefix" >&2
    exit 125
}
must_availability() {
    if stop_availability "$1"; then
        return 0
    fi
    printf '%s_failed_availability_gate=%s\n' "$prefix" "$1" >&2
    if recover; then
        exit 1
    fi
    printf '%s_manual_intervention_required=true\n' "$prefix" >&2
    exit 125
}

if [[ "${1:-}" = --stream-classifier-self-test && $# -eq 1 ]]; then
    run_stream_classifier_self_test
    exit 0
fi

if [[ "${1:-}" = --pre-mutation-recovery-self-test && $# -eq 1 ]]; then
    recover
    printf '%s_pre_mutation_recovery_self_test_complete=true\n' "$prefix"
    exit 0
fi

if [[ "${1:-}" = --producer-self-test && $# -eq 1 ]]; then
    action28aa_outer_producer_root=$(mktemp -d /tmp/action28aa-producer-test.XXXXXX)
    readonly action28aa_outer_producer_root
    trap 'rm -rf -- "$action28aa_outer_producer_root"' EXIT INT TERM
    outer_root=$action28aa_outer_producer_root
    run_id=${outer_root##*/}
    action28aa_outer_producer_remote=$outer_root/remote.sh
    write_remote node-b preflight '' '' "$action28aa_outer_producer_remote"
    prepare_capture_files "$outer_root/stdout" "$outer_root/stderr" "$outer_root/status"
    validate_remote_program "$action28aa_outer_producer_remote"
    action28aa_outer_malformed=$outer_root/malformed.sh
    # This is an exact generated-program literal, not an expression to expand.
    # shellcheck disable=SC2016
    sed 's|/bin/bash "$stage/transact-coupled-go-live-action28aa.sh"|"$stage/transact-coupled-go-live-action28aa.sh"|' \
        "$action28aa_outer_producer_remote" >"$action28aa_outer_malformed"
    if validate_remote_program "$action28aa_outer_malformed"; then
        printf '%s_producer_malformed_rejected=false\n' "$prefix" >&2
        exit 1
    fi
    printf '%s_producer_remote_valid=true\n' "$prefix"
    printf '%s_producer_capture_files_valid=true\n' "$prefix"
    printf '%s_producer_malformed_rejected=true\n' "$prefix"
    printf '%s_producer_self_test_complete=true\n' "$prefix"
    exit 0
fi

if [[ "${1:-}" = --self-test && $# -eq 1 ]]; then
    run_local_gates
    printf '%s_self_test_complete=true\n' "$prefix"
    exit 0
fi
[[ $# -eq 0 ]] || {
    printf 'Usage: %s [--self-test|--producer-self-test|--pre-mutation-recovery-self-test|--stream-classifier-self-test]\n' \
        "${0##*/}" >&2
    exit 64
}

run_local_gates
install -d -m 0700 "$evidence_root"
outer_root=$(mktemp -d "$evidence_root/run.XXXXXX")
readonly outer_root
chmod 0700 "$outer_root"
run_id=${outer_root##*/}
readonly run_id
printf '%s_evidence_directory=%s\n' "$prefix" "$outer_root"

must_phase node_b_preflight node-b preflight
must_phase node_a_preflight node-a preflight
node_b_installed=true
must_phase node_b_install node-b install
node_a_installed=true
must_phase node_a_install node-a install
must_phase node_a_promote_retained node-a promote "$retained_revision"
must_phase node_b_promote_retained node-b promote "$retained_revision"
must_phase node_b_activate_sync node-b activate
must_phase node_a_activate_sync node-a activate
must_phase node_a_initial_release node-a accept-release "$retained_revision" node-a
must_phase node_b_initial_release node-b accept-release "$retained_revision" node-a
must_phase node_a_transition_cursor node-a journal-cursor
must_phase node_b_transition_cursor node-b journal-cursor

failover_started=$SECONDS
start_availability failover
must_phase node_a_relinquish node-a relinquish
node_a_relinquished=true
must_phase node_b_master node-b state '' master
must_phase node_a_zero_vips node-a state '' absent
failover_elapsed=$((SECONDS - failover_started))
printf '%s_failover_elapsed_seconds=%s\n' "$prefix" "$failover_elapsed"
must_post_gate failover_bounded test "$failover_elapsed" -le "$maximum_failover_seconds"
must_phase node_b_continuity node-b continuity
must_availability failover
must_phase node_b_normal_publish_rejected node-b reject-normal
must_phase node_b_emergency_publish node-b publish
emergency_revision=$(sed -n \
    's/^action_28aa_remote_publish_value_revision=\([A-Za-z0-9][A-Za-z0-9._-]*\)$/\1/p' \
    "$last_stdout")
readonly emergency_revision
must_post_gate emergency_revision_valid test -n "$emergency_revision"
must_phase node_b_promote_emergency node-b promote "$emergency_revision"
must_phase node_a_receive_emergency node-a accept-release "$emergency_revision" node-b
must_phase node_b_emergency_release node-b accept-release "$emergency_revision" node-b

failback_started=$SECONDS
start_availability failback
must_phase node_a_restore_owner node-a restore-owner
node_a_relinquished=false
must_phase node_a_master node-a state '' master
must_phase node_b_backup node-b state '' backup
failback_elapsed=$((SECONDS - failback_started))
printf '%s_failback_elapsed_seconds=%s\n' "$prefix" "$failback_elapsed"
must_post_gate failback_bounded test "$failback_elapsed" -le "$maximum_failback_seconds"
must_phase node_a_continuity node-a continuity
must_availability failback
must_phase node_a_normal_publish node-a publish
normal_revision=$(sed -n \
    's/^action_28aa_remote_publish_value_revision=\([A-Za-z0-9][A-Za-z0-9._-]*\)$/\1/p' \
    "$last_stdout")
readonly normal_revision
must_post_gate normal_revision_valid test -n "$normal_revision"
must_phase node_a_promote_normal node-a promote "$normal_revision"
must_phase node_b_receive_normal node-b accept-release "$normal_revision" node-a
must_phase node_a_normal_release node-a accept-release "$normal_revision" node-a
must_phase node_a_final_state node-a state '' master
must_phase node_b_final_state node-b state '' backup
must_phase node_a_journal_evidence node-a journal-evidence
must_phase node_b_journal_evidence node-b journal-evidence
must_phase node_a_commit node-a commit
must_phase node_b_commit node-b commit

transaction_complete=true
printf '%s_emergency_revision=%s\n' "$prefix" "$emergency_revision"
printf '%s_normal_revision=%s\n' "$prefix" "$normal_revision"
printf '%s_notifier_delivery_nonblocking=true\n' "$prefix"
printf '%s_recovery_invoked=false\n' "$prefix"
printf '%s_manual_intervention_required=false\n' "$prefix"
printf '%s_transaction_complete=%s\n' "$prefix" "$transaction_complete"
printf '%s_acceptance=true\n' "$prefix"
