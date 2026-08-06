#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_20d_retry5_a
readonly diagnostic_sha256=1f0cb96acc9f04325c943cb18b378b2a8d75cadfcaa5bb8673f2511053d27ce7
readonly regression_sha256=e94a5ca55006f63f6243ca03f0af6d55e62307ca146524dbfe9cd30ae84b77d1
readonly failed_outer_sha256=f4a0906113e30aa68f429920f369137a5ae80d9344be94c988c0f7974e7919e8
readonly collision_sha256=ba1e769a3d00b5884421a8860f820e2dc8a3d8074837dab930630407f047886f
readonly conditional_sha256=68cd687916f9d8be78f50af7a410d376f457ca74ab906a8e459795de6c495455
readonly transcript_sha256=99e0040d785e70a4f2e8d1796f8c6bf29675593d1ae5d13e54d9ac2dceebe44c
readonly output_sha256=84873a1ad3ee1745fe445f179f6a002c2ccee5b147b93cc3db0d6f17d54d4441
readonly source_context_sha256=e88131df2bdcf1f4e21c85a5fb1909532874eee145681b8014ead9d8f911967c
readonly maximum_stream_bytes=4194304
readonly maximum_stream_lines=16384
script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
readonly caddy_root=${script_directory%/scripts}
readonly diagnostic=$script_directory/diagnose-node-a-keepalived-pidfile-isolation-action20d-retry5-a.sh
readonly regression=$caddy_root/tests/action20d-retry5-a-pidfile-isolation-regression.sh
readonly failed_outer=$script_directory/run-dual-node-caddy-vrrp-activation-action20d-retry5-outer.sh
readonly collision=$caddy_root/tests/check-shell-readonly-local-collisions-v2.sh
readonly conditional=$caddy_root/tests/conditional-validator-errexit-policy-regression.sh
readonly transcript=$caddy_root/tests/transcript-contract-ratchet-policy-regression.sh
readonly output_policy=$caddy_root/tests/transaction-output-evidence-policy-regression.sh
readonly source_context=$caddy_root/tests/run-source-test-in-context.sh

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }
line_count() { awk 'END { print NR }' "$1"; }
require_gate() {
    local outer_gate_label=$1

    shift
    if "$@"; then
        printf '%s_outer_gate_%s=true\n' "$prefix" "$outer_gate_label"
        return 0
    fi
    printf '%s_outer_gate_%s=false\n' "$prefix" "$outer_gate_label" >&2
    return 1
}
# Invoked indirectly through require_gate.
# shellcheck disable=SC2317
source_exact() {
    local expected_source_hash=$1
    local inspected_source_path=$2
    local expected_source_identity

    expected_source_identity="$(id -un):$(id -gn):755"
    [[ -f "$inspected_source_path" && ! -L "$inspected_source_path" &&
        -x "$inspected_source_path" ]] || return 1
    [[ "$(stat -c '%U:%G:%a' "$inspected_source_path")" = "$expected_source_identity" ]] ||
        return 1
    [[ "$(file_hash "$inspected_source_path")" = "$expected_source_hash" ]] || return 1
    return 0
}
# shellcheck disable=SC2317
working_directory_approved() {
    case "$PWD" in
        /home/aaron/code/homelab-server-configs) return 0 ;;
        /workspace/homelab-server-configs)
            [[ "${CADDY_VALIDATION_CONTAINER:-}" = 1 ]]
            ;;
        *) return 1 ;;
    esac
}
safe_stream() {
    local inspected_stream=$1

    [[ "$(wc -c <"$inspected_stream")" -le "$maximum_stream_bytes" ]] || return 1
    [[ "$(line_count "$inspected_stream")" -le "$maximum_stream_lines" ]] || return 1
    ! LC_ALL=C grep -n '[^[:print:][:space:]]' "$inspected_stream" >/dev/null || return 1
    ! grep -Eqi \
        'BEGIN [A-Z ]*PRIVATE KEY|CADDY_TLS_PRIVATE_KEY_PEM|PRIVATE_KEY=|DOPPLER_TOKEN|Authorization:[[:space:]]*Bearer' \
        "$inspected_stream"
}
emit_stream() {
    local emitted_label=$1
    local emitted_path=$2

    printf '%s_%s_bytes=%s\n' "$prefix" "$emitted_label" "$(wc -c <"$emitted_path")"
    printf '%s_%s_lines=%s\n' "$prefix" "$emitted_label" "$(line_count "$emitted_path")"
    printf '%s_%s_sha256=%s\n' "$prefix" "$emitted_label" "$(file_hash "$emitted_path")"
    if ! safe_stream "$emitted_path"; then
        printf '%s_%s_classification=unsafe_retained\n' "$prefix" "$emitted_label" >&2
        return 97
    fi
    printf '%s_%s_classification=bounded_safe\n' "$prefix" "$emitted_label"
    if [[ -s "$emitted_path" ]]; then
        printf '%s_%s_begin\n' "$prefix" "$emitted_label"
        cat "$emitted_path"
        printf '%s_%s_end\n' "$prefix" "$emitted_label"
    else
        printf '%s_%s_content_secured=empty\n' "$prefix" "$emitted_label"
    fi
}
require_one() {
    local required_line=$1
    local inspected_transcript=$2

    [[ "$(grep -Fxc "$required_line" "$inspected_transcript")" -eq 1 ]]
}
classification_matches_status() {
    local observed_classification=$1
    local observed_status=$2

    case "$observed_status:$observed_classification" in
        0:pidfile_isolation_resolved_sigterm) return 0 ;;
        124:pidfile_isolation_timeout_term) return 0 ;;
        137:pidfile_isolation_timeout_kill) return 0 ;;
        143:pidfile_isolation_did_not_resolve_sigterm) return 0 ;;
        *)
            [[ "$observed_status" =~ ^([1-9]|[1-9][0-9]|1[01][0-9]|12[0-7])$ &&
                "$observed_classification" = config_test_error_or_command_failure ]]
            ;;
    esac
}
validate_transcript() {
    local transcript_path=$1
    local error_path=$2
    local observed_remote_status=$3
    local contract_root
    local expected_count
    local observed_count
    local reported_count
    local reported_failures
    local before_hash
    local after_hash
    local probe_status
    local probe_duration
    local probe_classification

    [[ "$observed_remote_status" -eq 0 && ! -s "$error_path" ]] || return 1
    contract_root=$(mktemp -d /tmp/caddy-action20d-retry5-a-contract.XXXXXX) || return 1
    /bin/bash "$diagnostic" --expected-assertions | LC_ALL=C sort >"$contract_root/expected" || {
        rm -rf -- "$contract_root"
        return 1
    }
    sed -n 's/^action_20d_retry5_a_probe_assertion_\([a-z0-9_]*\)=true$/\1/p' \
        "$transcript_path" | LC_ALL=C sort >"$contract_root/observed"
    expected_count=$(wc -l <"$contract_root/expected")
    observed_count=$(wc -l <"$contract_root/observed")
    if [[ "$expected_count" -ne 37 || "$observed_count" -ne "$expected_count" ]] ||
        [[ "$observed_count" -ne "$(LC_ALL=C sort -u "$contract_root/observed" | wc -l)" ]] ||
        ! cmp -s "$contract_root/expected" "$contract_root/observed" ||
        grep -Eq '^action_20d_retry5_a_probe_assertion_[a-z0-9_]+=false$' \
            "$transcript_path"; then
        rm -rf -- "$contract_root"
        return 1
    fi
    rm -rf -- "$contract_root"

    reported_count=$(sed -n 's/^action_20d_retry5_a_probe_value_assertion_count=//p' \
        "$transcript_path")
    reported_failures=$(sed -n 's/^action_20d_retry5_a_probe_value_failure_count=//p' \
        "$transcript_path")
    before_hash=$(sed -n 's/^action_20d_retry5_a_probe_value_before_snapshot_sha256=//p' \
        "$transcript_path")
    after_hash=$(sed -n 's/^action_20d_retry5_a_probe_value_after_snapshot_sha256=//p' \
        "$transcript_path")
    probe_status=$(sed -n 's/^action_20d_retry5_a_probe_value_probe_status=//p' \
        "$transcript_path")
    probe_duration=$(sed -n 's/^action_20d_retry5_a_probe_value_probe_duration_ms=//p' \
        "$transcript_path")
    probe_classification=$(sed -n 's/^action_20d_retry5_a_probe_value_probe_classification=//p' \
        "$transcript_path")
    [[ "$reported_count" = 37 && "$reported_failures" = 0 ]] || return 1
    require_one action_20d_retry5_a_probe_value_first_failure=none "$transcript_path" || return 1
    [[ "$before_hash" =~ ^[0-9a-f]{64}$ && "$after_hash" = "$before_hash" ]] || return 1
    [[ "$probe_status" =~ ^[0-9]+$ && "$probe_duration" =~ ^[0-9]+$ &&
        "$probe_duration" -le 17000 ]] || return 1
    classification_matches_status "$probe_classification" "$probe_status" || return 1
    require_one action_20d_retry5_a_probe_notification_invoked=false "$transcript_path" || return 1
    require_one action_20d_retry5_a_probe_service_mutations=false "$transcript_path" || return 1
    require_one action_20d_retry5_a_probe_keepalived_mutations=false "$transcript_path" || return 1
    require_one action_20d_retry5_a_probe_vrrp_mutations=false "$transcript_path" || return 1
    require_one action_20d_retry5_a_probe_vip_mutations=false "$transcript_path" || return 1
    require_one action_20d_retry5_a_probe_persistent_mutations=false "$transcript_path" || return 1
    require_one action_20d_retry5_a_probe_cleanup_complete=true "$transcript_path" || return 1
    require_one action_20d_retry5_a_probe_diagnostic_complete=true "$transcript_path" || return 1
    return 0
}
run_local_gates() {
    local local_gate_mode=${1:-full}

    require_gate working_directory working_directory_approved || return 1
    require_gate diagnostic_source_exact source_exact "$diagnostic_sha256" "$diagnostic" || return 1
    require_gate regression_source_exact source_exact "$regression_sha256" "$regression" || return 1
    require_gate failed_outer_immutable source_exact "$failed_outer_sha256" "$failed_outer" || return 1
    require_gate collision_source_exact source_exact "$collision_sha256" "$collision" || return 1
    require_gate conditional_source_exact source_exact "$conditional_sha256" "$conditional" || return 1
    require_gate transcript_source_exact source_exact "$transcript_sha256" "$transcript" || return 1
    require_gate output_source_exact source_exact "$output_sha256" "$output_policy" || return 1
    require_gate source_context_exact source_exact "$source_context_sha256" "$source_context" || return 1
    require_gate syntax /bin/bash -n "$diagnostic" "$regression" "$0" || return 1
    require_gate shellcheck shellcheck "$diagnostic" "$regression" "$0" || return 1
    require_gate canonical_format /bin/bash "$caddy_root/tests/shfmt-canonical.sh" \
        --check "$diagnostic" "$regression" "$0" || return 1
    require_gate collision_policy /bin/bash "$collision" "$diagnostic" "$regression" "$0" || return 1
    require_gate conditional_policy /bin/bash "$conditional" || return 1
    require_gate transcript_policy /bin/bash "$transcript" || return 1
    require_gate output_policy /bin/bash "$output_policy" || return 1
    require_gate diagnostic_self_test /bin/bash "$diagnostic" --self-test || return 1
    if [[ "$local_gate_mode" = intercepted ]]; then
        printf '%s_outer_gate_regression=true\n' "$prefix"
    else
        require_gate regression /bin/bash "$regression" || return 1
    fi
}

case "${1:-}" in
    --expected-local-gates)
        [[ $# -eq 1 ]] || exit 64
        printf '%s\n' \
            working_directory diagnostic_source_exact regression_source_exact \
            failed_outer_immutable collision_source_exact conditional_source_exact \
            transcript_source_exact output_source_exact source_context_exact syntax \
            shellcheck canonical_format collision_policy conditional_policy \
            transcript_policy output_policy diagnostic_self_test regression
        exit 0
        ;;
    --self-test | --source-test | --contract-test)
        [[ $# -eq 1 ]] || exit 64
        run_local_gates
        printf '%s_outer_%s_complete=true\n' "$prefix" "${1#--}"
        exit 0
        ;;
    --production-path-test)
        [[ $# -eq 2 ]] || exit 64
        intercepted_ssh=$2
        readonly intercepted_ssh
        ;;
    "")
        [[ $# -eq 0 ]] || exit 64
        intercepted_ssh=
        readonly intercepted_ssh
        ;;
    *)
        printf 'Usage: %s [--expected-local-gates|--self-test|--source-test|--contract-test|--production-path-test SSH]\n' \
            "${0##*/}" >&2
        exit 64
        ;;
esac

if [[ -n "$intercepted_ssh" ]]; then
    run_local_gates intercepted
else
    run_local_gates full
fi
outer_root=$(mktemp -d /tmp/caddy-action20d-retry5-a-outer.XXXXXX)
readonly outer_root
cleanup() {
    # shellcheck disable=SC2317
    rm -rf -- "$outer_root"
}
trap cleanup EXIT
readonly remote_stdout=$outer_root/remote.stdout
readonly remote_stderr=$outer_root/remote.stderr
: >"$remote_stdout"
: >"$remote_stderr"
chmod 0600 "$remote_stdout" "$remote_stderr"
remote_status=0
if [[ -n "$intercepted_ssh" ]]; then
    "$intercepted_ssh" -T -o BatchMode=yes -o IdentitiesOnly=no \
        -o StrictHostKeyChecking=yes -o HostKeyAlias=pihole0.local.theama.co \
        pi@10.1.0.53 'cd / && sudo -n /bin/bash -s -- node-a' <"$diagnostic" \
        >"$remote_stdout" 2>"$remote_stderr" || remote_status=$?
else
    /usr/bin/ssh -T -o BatchMode=yes -o IdentitiesOnly=no \
        -o StrictHostKeyChecking=yes -o HostKeyAlias=pihole0.local.theama.co \
        pi@10.1.0.53 'cd / && sudo -n /bin/bash -s -- node-a' <"$diagnostic" \
        >"$remote_stdout" 2>"$remote_stderr" || remote_status=$?
fi
readonly remote_status
emit_stream remote_stdout "$remote_stdout" || {
    trap - EXIT
    printf '%s_protected_evidence=%s\n' "$prefix" "$outer_root" >&2
    exit 97
}
emit_stream remote_stderr "$remote_stderr" || {
    trap - EXIT
    printf '%s_protected_evidence=%s\n' "$prefix" "$outer_root" >&2
    exit 97
}
printf '%s_remote_status=%s\n' "$prefix" "$remote_status"
if validate_transcript "$remote_stdout" "$remote_stderr" "$remote_status"; then
    printf '%s_transcript_accepted=true\n' "$prefix"
else
    printf '%s_transcript_accepted=false\n' "$prefix" >&2
    exit 1
fi
rm -rf -- "$outer_root"
trap - EXIT
printf '%s_outer_cleanup_complete=true\n' "$prefix"
printf '%s_outer_diagnostic_accepted=true\n' "$prefix"
