#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_20e_b
readonly inspector_sha256=d983cf111b54d8e62a25b55f62c5e2e74423b42fc8a2cfc1de8e4dfb95b1881a
readonly maximum_stream_bytes=2097152
readonly maximum_stream_lines=8192
script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
readonly caddy_root=${script_directory%/scripts}
readonly inspector=$script_directory/inspect-node-b-runtime-shadow-metadata-action20e-b.sh
readonly collision_checker=$caddy_root/tests/check-shell-readonly-local-collisions-v2.sh
readonly ssh_binary=${CADDY_ACTION20EB_SSH_BINARY:-/usr/bin/ssh}

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }
line_count() { awk 'END { print NR }' "$1"; }
safe_stream() {
    local inspected_path=$1

    [[ "$(wc -c <"$inspected_path")" -le "$maximum_stream_bytes" ]] || return 1
    [[ "$(line_count "$inspected_path")" -le "$maximum_stream_lines" ]] || return 1
    ! LC_ALL=C grep -n '[^[:print:][:space:]]' "$inspected_path" >/dev/null || return 1
    ! grep -Eqi \
        'BEGIN [A-Z ]*PRIVATE KEY|CADDY_TLS_PRIVATE_KEY_PEM|PRIVATE_KEY=|DOPPLER_TOKEN|Authorization:[[:space:]]*Bearer' \
        "$inspected_path"
}
emit_stream_metadata() {
    local emitted_label=$1
    local emitted_path=$2

    printf '%s_%s_bytes=%s\n' "$prefix" "$emitted_label" "$(wc -c <"$emitted_path")"
    printf '%s_%s_lines=%s\n' "$prefix" "$emitted_label" "$(line_count "$emitted_path")"
    printf '%s_%s_sha256=%s\n' "$prefix" "$emitted_label" "$(file_hash "$emitted_path")"
}
working_directory_approved() {
    case "$PWD" in
        /home/aaron/code/homelab-server-configs) return 0 ;;
        /workspace/homelab-server-configs)
            [[ "${CADDY_VALIDATION_CONTAINER:-}" = 1 ]]
            ;;
        *) return 1 ;;
    esac
}
require_one() {
    local expected_line=$1
    local inspected_transcript=$2

    [[ "$(grep -Fxc "$expected_line" "$inspected_transcript")" -eq 1 ]]
}
verify_sources() {
    [[ -f "$inspector" && ! -L "$inspector" ]] || return 1
    [[ "$(file_hash "$inspector")" = "$inspector_sha256" ]] || return 1
    /bin/bash -n "$inspector" || return 1
    shellcheck "$inspector" || return 1
    /bin/bash "$collision_checker" "$inspector" >/dev/null || return 1
    /bin/bash "$inspector" --self-test >/dev/null || return 1
}
validate_transcript() {
    local error_path=$1
    local output_path=$2
    local observed_remote_status=$3
    local contract_root
    local expected_count
    local observed_count
    local reported_count
    local reported_failed
    local failed_count
    local first_failure
    local before_hash
    local after_hash
    local classification

    # conditional-validator-explicit-failures-begin
    [[ ! -s "$error_path" ]] || return 97
    contract_root=$(mktemp -d /tmp/caddy-action20e-b-contract.XXXXXX) || return 97
    /bin/bash "$inspector" --expected-assertions | LC_ALL=C sort \
        >"$contract_root/expected" || {
        rm -rf -- "$contract_root"
        return 97
    }
    sed -n "s/^${prefix}_assertion_\([a-z0-9_]*\)=\(true\|false\)$/\1/p" \
        "$output_path" | LC_ALL=C sort >"$contract_root/observed"
    expected_count=$(wc -l <"$contract_root/expected") || {
        rm -rf -- "$contract_root"
        return 97
    }
    observed_count=$(wc -l <"$contract_root/observed") || {
        rm -rf -- "$contract_root"
        return 97
    }
    [[ "$expected_count" -gt 0 ]] || { # conditional-validator-requires-return 97
        rm -rf -- "$contract_root"
        return 97 # conditional-validator-requires-return
    }
    [[ "$expected_count" -eq "$(LC_ALL=C sort -u "$contract_root/expected" | wc -l)" ]] || { # conditional-validator-requires-return 97
        rm -rf -- "$contract_root"
        return 97 # conditional-validator-requires-return
    }
    [[ "$observed_count" -eq "$expected_count" ]] || { # conditional-validator-requires-return 97
        rm -rf -- "$contract_root"
        return 97 # conditional-validator-requires-return
    }
    [[ "$observed_count" -eq "$(LC_ALL=C sort -u "$contract_root/observed" | wc -l)" ]] || { # conditional-validator-requires-return 97
        rm -rf -- "$contract_root"
        return 97 # conditional-validator-requires-return
    }
    cmp -s "$contract_root/expected" "$contract_root/observed" || { # conditional-validator-requires-return 97
        rm -rf -- "$contract_root"
        return 97 # conditional-validator-requires-return
    }
    rm -rf -- "$contract_root"

    reported_count=$(sed -n "s/^${prefix}_assertion_count=//p" "$output_path") || return 97
    reported_failed=$(sed -n "s/^${prefix}_failed_assertion_count=//p" "$output_path") || return 97
    first_failure=$(sed -n "s/^${prefix}_first_failure=//p" "$output_path") || return 97
    failed_count=$(grep -Ec "^${prefix}_assertion_[a-z0-9_]+=false$" "$output_path" || true)
    [[ "$reported_count" =~ ^[0-9]+$ ]] || return 97
    [[ "$reported_count" -eq "$expected_count" ]] || return 97
    [[ "$reported_failed" =~ ^[0-9]+$ ]] || return 97
    [[ "$reported_failed" -eq "$failed_count" ]] || return 97
    before_hash=$(sed -n "s/^${prefix}_value_before_state_sha256=//p" "$output_path") || return 97
    after_hash=$(sed -n "s/^${prefix}_value_after_state_sha256=//p" "$output_path") || return 97
    [[ "$before_hash" =~ ^[0-9a-f]{64}$ ]] || return 97
    [[ "$after_hash" = "$before_hash" ]] || return 97
    classification=$(sed -n "s/^${prefix}_value_reproduction_classification=//p" "$output_path") || return 97
    [[ "$classification" = intermediate_parents_default_0755 ]] || return 97
    require_one "${prefix}_value_expected_shadow_root_metadata=root:root:700" "$output_path" || return 97
    require_one "${prefix}_value_observed_shadow_root_symbolic=root:root:755" "$output_path" || return 97
    require_one "${prefix}_value_observed_shadow_etc_symbolic=root:root:755" "$output_path" || return 97
    require_one "${prefix}_value_observed_shadow_tmpfiles_symbolic=root:root:700" "$output_path" || return 97
    require_one "${prefix}_node_a_contacted=false" "$output_path" || return 97
    require_one "${prefix}_systemd_tmpfiles_invoked=false" "$output_path" || return 97
    require_one "${prefix}_transient_filesystem_activity=true" "$output_path" || return 97
    require_one "${prefix}_persistent_filesystem_mutations=false" "$output_path" || return 97
    require_one "${prefix}_service_mutations=false" "$output_path" || return 97
    require_one "${prefix}_keepalived_service_mutations=false" "$output_path" || return 97
    require_one "${prefix}_notifier_invoked=false" "$output_path" || return 97
    require_one "${prefix}_vrrp_mutations=false" "$output_path" || return 97
    require_one "${prefix}_vip_mutations=false" "$output_path" || return 97
    require_one "${prefix}_remote_complete=true" "$output_path" || return 97
    [[ "$failed_count" -eq 0 ]] || return 1
    [[ "$first_failure" = none ]] || return 97
    [[ "$observed_remote_status" -eq 0 ]] || return 97
    # conditional-validator-explicit-failures-end
    return 0
}
write_contract_fixture() {
    local assertion_label
    local expected_count
    local state_hash=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa

    expected_count=$(/bin/bash "$inspector" --expected-assertions | wc -l)
    while IFS= read -r assertion_label; do
        printf '%s_assertion_%s=true\n' "$prefix" "$assertion_label"
    done < <(/bin/bash "$inspector" --expected-assertions)
    printf '%s\n' \
        "${prefix}_value_before_state_sha256=$state_hash" \
        "${prefix}_value_after_state_sha256=$state_hash" \
        "${prefix}_value_expected_shadow_root_metadata=root:root:700" \
        "${prefix}_value_observed_shadow_root_symbolic=root:root:755" \
        "${prefix}_value_observed_shadow_root_numeric=0:0:755" \
        "${prefix}_value_observed_shadow_etc_symbolic=root:root:755" \
        "${prefix}_value_observed_shadow_etc_numeric=0:0:755" \
        "${prefix}_value_observed_shadow_tmpfiles_symbolic=root:root:700" \
        "${prefix}_value_observed_shadow_tmpfiles_numeric=0:0:700" \
        "${prefix}_value_reproduction_classification=intermediate_parents_default_0755" \
        "${prefix}_assertion_count=$expected_count" \
        "${prefix}_failed_assertion_count=0" \
        "${prefix}_first_failure=none" \
        "${prefix}_node_a_contacted=false" \
        "${prefix}_systemd_tmpfiles_invoked=false" \
        "${prefix}_transient_filesystem_activity=true" \
        "${prefix}_persistent_filesystem_mutations=false" \
        "${prefix}_service_mutations=false" \
        "${prefix}_keepalived_service_mutations=false" \
        "${prefix}_notifier_invoked=false" \
        "${prefix}_vrrp_mutations=false" \
        "${prefix}_vip_mutations=false" \
        "${prefix}_remote_complete=true"
}

case "${1:-}" in
    --self-test | --source-test)
        [[ $# -eq 1 ]] || exit 64
        verify_sources
        printf '%s_runner_%s_complete=true\n' "$prefix" "${1#--}"
        exit 0
        ;;
    --contract-test)
        [[ $# -eq 1 ]] || exit 64
        verify_sources
        contract_test_root=$(mktemp -d /tmp/caddy-action20e-b-runner-contract.XXXXXX)
        readonly contract_test_root
        trap 'rm -rf -- "$contract_test_root"' EXIT
        : >"$contract_test_root/empty.err"
        write_contract_fixture >"$contract_test_root/valid.out"
        validate_transcript "$contract_test_root/empty.err" "$contract_test_root/valid.out" 0
        sed '/^action_20e_b_assertion_identity_root=/d' "$contract_test_root/valid.out" \
            >"$contract_test_root/missing.out"
        if validate_transcript "$contract_test_root/empty.err" "$contract_test_root/missing.out" 0; then
            exit 1
        fi
        cp "$contract_test_root/valid.out" "$contract_test_root/duplicate.out"
        printf '%s_assertion_identity_root=true\n' "$prefix" \
            >>"$contract_test_root/duplicate.out"
        if validate_transcript "$contract_test_root/empty.err" "$contract_test_root/duplicate.out" 0; then
            exit 1
        fi
        sed 's/intermediate_parents_default_0755/unexpected/' \
            "$contract_test_root/valid.out" >"$contract_test_root/unexpected.out"
        if validate_transcript "$contract_test_root/empty.err" "$contract_test_root/unexpected.out" 0; then
            exit 1
        fi
        printf '%s_runner_contract_test_complete=true\n' "$prefix"
        exit 0
        ;;
    "") [[ $# -eq 0 ]] || exit 64 ;;
    *)
        printf 'Usage: %s [--self-test|--source-test|--contract-test]\n' "${0##*/}" >&2
        exit 64
        ;;
esac

verify_sources
working_directory_approved
work_directory=$(mktemp -d /tmp/caddy-action20e-b-runner.XXXXXX)
readonly work_directory
cleanup() {
    # shellcheck disable=SC2317
    rm -rf -- "$work_directory"
}
trap cleanup EXIT
readonly remote_stdout=$work_directory/remote.stdout
readonly remote_stderr=$work_directory/remote.stderr
: >"$remote_stdout"
: >"$remote_stderr"
chmod 0600 "$remote_stdout" "$remote_stderr"
remote_status=0
if [[ "${CADDY_ACTION20EB_INTERCEPTED_TEST:-}" = 1 ]]; then
    "$ssh_binary" -T -o BatchMode=yes -o IdentitiesOnly=no \
        -o StrictHostKeyChecking=yes -o HostKeyAlias=pihole00.local.theama.co \
        pi@10.1.0.54 'cd / && sudo -n /bin/bash -s --' <"$inspector" \
        >"$remote_stdout" 2>"$remote_stderr" || remote_status=$?
else
    [[ -z "${CADDY_ACTION20EB_SSH_BINARY:-}" ]]
    /usr/bin/ssh -T -o BatchMode=yes -o IdentitiesOnly=no \
        -o StrictHostKeyChecking=yes -o HostKeyAlias=pihole00.local.theama.co \
        pi@10.1.0.54 'cd / && sudo -n /bin/bash -s --' <"$inspector" \
        >"$remote_stdout" 2>"$remote_stderr" || remote_status=$?
fi
readonly remote_status
emit_stream_metadata remote_stdout "$remote_stdout"
emit_stream_metadata remote_stderr "$remote_stderr"
if safe_stream "$remote_stdout" && safe_stream "$remote_stderr"; then
    printf '%s_remote_stream_classification=bounded_safe\n' "$prefix"
    printf '%s_remote_stdout_begin\n' "$prefix"
    cat "$remote_stdout"
    printf '%s_remote_stdout_end\n' "$prefix"
    if [[ -s "$remote_stderr" ]]; then
        printf '%s_remote_stderr_begin\n' "$prefix" >&2
        cat "$remote_stderr" >&2
        printf '%s_remote_stderr_end\n' "$prefix" >&2
    else
        printf '%s_remote_stderr_content_secured=empty\n' "$prefix"
    fi
else
    printf '%s_remote_stream_classification=unsafe_retained\n' "$prefix" >&2
    trap - EXIT
    printf '%s_protected_evidence=%s\n' "$prefix" "$work_directory" >&2
    exit 97
fi
validation_status=0
validate_transcript "$remote_stderr" "$remote_stdout" "$remote_status" || validation_status=$?
readonly validation_status
printf '%s_remote_status=%s\n' "$prefix" "$remote_status"
printf '%s_validation_status=%s\n' "$prefix" "$validation_status"
if [[ "$validation_status" -eq 97 ]]; then
    trap - EXIT
    printf '%s_protected_evidence=%s\n' "$prefix" "$work_directory" >&2
    exit 97
fi
rm -rf -- "$work_directory"
trap - EXIT
printf '%s_runner_cleanup_complete=true\n' "$prefix"
exit "$validation_status"
