#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly derivation_sha256=7ba7ca096db09c48b57c32ae62bf300b3aa16aa6b6f8d4cf033d83624395dd1b
readonly rendered_inspector_sha256=74b4fbafc25850dace3b0057a7b74a3464936425869952ac21113c11e2652250
readonly rendered_runner_sha256=8c24121c3e8a1f4f8719b6445228c690745671217bc54bd6e7c12c866869c34f
readonly expected_assertion_count=86

test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
readonly caddy_root=${test_directory%/tests}
readonly derivation="$caddy_root/scripts/derive-node-b-keepalived-helper-postinstall-action19b-b.sh"
readonly collision_checker="$test_directory/check-shell-readonly-local-collisions-v2.sh"
readonly inner_collision_checker="$test_directory/check-shell-readonly-local-collisions.sh"

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }

require_gate() {
    local gate_label=$1

    shift
    if "$@"; then
        printf 'action_19b_b_regression_%s=true\n' "$gate_label"
        return 0
    fi
    printf 'action_19b_b_regression_%s=false\n' "$gate_label" >&2
    return 1
}

label_alignment_valid() {
    local inspector_path=$1
    local alignment_root
    local expected_path
    local observed_path

    alignment_root=$(mktemp -d /tmp/caddy-action19b-b-labels.XXXXXX)
    expected_path=$alignment_root/expected
    observed_path=$alignment_root/observed
    "$inspector_path" --expected-assertions | LC_ALL=C sort >"$expected_path"
    {
        awk '/^record_command [a-z0-9_]+/ { print $2 }' "$inspector_path"
        for helper_label in certificate_helper sync_failure_helper \
            reconcile_helper sync_health_helper; do
            printf '%s\n' \
                "${helper_label}_regular" \
                "${helper_label}_not_symlink" \
                "${helper_label}_metadata_exact" \
                "${helper_label}_hash_exact"
        done
    } | LC_ALL=C sort >"$observed_path"
    if [[ "$(wc -l <"$expected_path")" -ne "$expected_assertion_count" ||
    "$(sort -u "$expected_path" | wc -l)" -ne "$expected_assertion_count" ||
    "$(wc -l <"$observed_path")" -ne "$expected_assertion_count" ||
    "$(sort -u "$observed_path" | wc -l)" -ne "$expected_assertion_count" ]] ||
        ! cmp -s "$expected_path" "$observed_path"; then
        rm -rf -- "$alignment_root"
        return 1
    fi
    rm -rf -- "$alignment_root"
}

static_read_only_policy() {
    local inspector_path=$1
    local runner_path=$2

    if grep -Eq \
        'systemctl[[:space:]]+(start|stop|restart|reload|enable|disable|mask|unmask|daemon-reload|reset-failed)' \
        "$inspector_path" "$runner_path"; then
        return 1
    fi
    if grep -Eq \
        '(^|[[:space:]])(rsync|scp|sftp|install|mv)([[:space:]]|$)' \
        "$inspector_path" "$runner_path"; then
        return 1
    fi
    grep -Fq 'record_command health_hash_exact' "$inspector_path" || return 1
    grep -Fq 'record_command notification_hash_exact' "$inspector_path" ||
        return 1
    grep -Fq 'record_command backup_manifest_content_exact' \
        "$inspector_path" || return 1
    grep -Fq 'record_command state_unchanged' "$inspector_path" || return 1
    grep -Fq "printf '%s_helper_execution=false" "$inspector_path" ||
        return 1
    grep -Fq "printf '%s_persistent_mutations=false" "$inspector_path" ||
        return 1
    grep -Fq "'cd / && sudo -n /bin/bash -s --'" "$runner_path"
}

write_fake_ssh() {
    local fake_ssh_path=$1

    cat >"$fake_ssh_path" <<'FAKE_SSH'
#!/usr/bin/env bash
set -Eeuo pipefail
printf '%s\n' "$@" >"$ACTION19BB_SSH_ARGUMENTS"
capture=$(mktemp /tmp/caddy-action19b-b-fake-ssh.XXXXXX)
trap 'rm -f -- "$capture"' EXIT
status=0
/bin/bash -s >"$capture" 2>/dev/null || status=$?
sed \
    -e 's/^action_19b_b_value_health_state=.*/action_19b_b_value_health_state=exact/' \
    -e 's/^action_19b_b_value_health_observed_sha256=.*/action_19b_b_value_health_observed_sha256=c3bc1c080cd148efc0a64440a2a411ec115d0ca83f8e6a66220d7bd201971414/' \
    -e 's/^action_19b_b_value_notification_state=.*/action_19b_b_value_notification_state=exact/' \
    -e 's/^action_19b_b_value_notification_observed_sha256=.*/action_19b_b_value_notification_observed_sha256=5862b494301f972d039477d4ed93a7d56156b141cba31c41ccd61d7f843321d8/' \
    "$capture"
exit "$status"
FAKE_SSH
    chmod 0755 "$fake_ssh_path"
}

run_intercepted_production_path() {
    local inspector_path=$1
    local runner_path=$2
    local case_root=$3
    local case_runner=$case_root/Caddy/scripts/${runner_path##*/}
    local case_status=0

    install -d -m 0700 "$case_root/Caddy/scripts" "$case_root/Caddy/tests" \
        "$case_root/bin"
    install -m 0755 "$inspector_path" "$runner_path" \
        "$case_root/Caddy/scripts/"
    install -m 0755 "$collision_checker" "$inner_collision_checker" \
        "$case_root/Caddy/tests/"
    write_fake_ssh "$case_root/bin/ssh"
    CADDY_ACTION19BB_SSH_BINARY="$case_root/bin/ssh" \
        CADDY_ACTION19BB_INTERCEPTED_TEST=1 \
        ACTION19BB_SSH_ARGUMENTS="$case_root/ssh.arguments" \
        "$case_runner" >"$case_root/runner.out" \
        2>"$case_root/runner.err" || case_status=$?
    if [[ "$case_status" -ne 1 || -s "$case_root/runner.err" ]] ||
        ! grep -Fxq action_19b_b_runner_acceptance=semantic_mismatch \
            "$case_root/runner.out"; then
        printf 'action_19b_b_regression_diagnostic_status=%s\n' \
            "$case_status" >&2
        printf 'action_19b_b_regression_diagnostic_stdout_lines=%s\n' \
            "$(awk 'END { print NR }' "$case_root/runner.out")" >&2
        printf 'action_19b_b_regression_diagnostic_stderr_lines=%s\n' \
            "$(awk 'END { print NR }' "$case_root/runner.err")" >&2
        printf 'action_19b_b_regression_diagnostic_acceptance_records=%s\n' \
            "$(grep -c '^action_19b_b_runner_acceptance=' \
                "$case_root/runner.out" || true)" >&2
        printf 'action_19b_b_regression_diagnostic_stderr_begin\n' >&2
        sed -n '1,20p' "$case_root/runner.err" >&2
        printf 'action_19b_b_regression_diagnostic_stderr_end\n' >&2
        printf 'action_19b_b_regression_diagnostic_summary_begin\n' >&2
        grep -E '^action_19b_b_(assertion_count|failed_assertion_count|first_failure|value_|helper_execution|filesystem_mutations|service_mutations|vrrp_mutations|vip_mutations|persistent_mutations|remote_complete)=' \
            "$case_root/runner.out" >&2 || true
        printf 'action_19b_b_regression_diagnostic_summary_end\n' >&2
    fi
    [[ "$case_status" -eq 1 ]] || return 1
    [[ ! -s "$case_root/runner.err" ]] || return 1
    grep -Fxq action_19b_b_runner_acceptance=semantic_mismatch \
        "$case_root/runner.out" || return 1
    grep -Fxq "action_19b_b_assertion_count=$expected_assertion_count" \
        "$case_root/runner.out" || return 1
    grep -Fxq action_19b_b_remote_stream_classification=bounded_safe \
        "$case_root/runner.out" || return 1
    grep -Fxq -- -T "$case_root/ssh.arguments" || return 1
    grep -Fxq HostKeyAlias=pihole00.local.theama.co \
        "$case_root/ssh.arguments" || return 1
    grep -Fq 'cd / && sudo -n /bin/bash -s --' \
        "$case_root/ssh.arguments"
}

regression_root=$(mktemp -d /tmp/caddy-action19b-b-regression.XXXXXX)
readonly regression_root
trap 'rm -rf -- "$regression_root"' EXIT
readonly rendered_root=$regression_root/Caddy/scripts
install -d -m 0700 "$rendered_root" "$regression_root/Caddy/tests"
install -m 0755 "$collision_checker" "$inner_collision_checker" \
    "$regression_root/Caddy/tests/"
"$derivation" --output-directory "$rendered_root"
readonly inspector=$rendered_root/inspect-node-b-keepalived-helper-postinstall-action19b-b.sh
readonly runner=$rendered_root/run-node-b-keepalived-helper-postinstall-action19b-b.sh

require_gate derivation_hash_exact test "$(file_hash "$derivation")" = \
    "$derivation_sha256"
require_gate inspector_hash_exact test "$(file_hash "$inspector")" = \
    "$rendered_inspector_sha256"
require_gate runner_hash_exact test "$(file_hash "$runner")" = \
    "$rendered_runner_sha256"
require_gate shell_syntax bash -n "$derivation" "$inspector" "$runner"
require_gate shellcheck shellcheck "$derivation" "$inspector" "$runner"
require_gate readonly_local_collision_absent \
    "$collision_checker" "$derivation" "$inspector" "$runner"
require_gate derivation_self_test "$derivation" --self-test
require_gate inspector_self_test "$inspector" --self-test
require_gate runner_self_test "$runner" --self-test
require_gate runner_contract_test "$runner" --contract-test
require_gate production_label_alignment label_alignment_valid "$inspector"
require_gate static_read_only_policy static_read_only_policy \
    "$inspector" "$runner"

cp -- "$inspector" "$regression_root/duplicate-label.inspector"
printf '%s\n' 'record_command health_hash_exact true' \
    >>"$regression_root/duplicate-label.inspector"
if label_alignment_valid "$regression_root/duplicate-label.inspector"; then
    printf 'action_19b_b_regression_duplicate_production_label_rejected=false\n' \
        >&2
    exit 1
fi
printf 'action_19b_b_regression_duplicate_production_label_rejected=true\n'

cp -- "$inspector" "$regression_root/missing-label.inspector"
sed -i '/^record_command backup_manifest_hash_exact /d' \
    "$regression_root/missing-label.inspector"
if label_alignment_valid "$regression_root/missing-label.inspector"; then
    printf 'action_19b_b_regression_missing_production_label_rejected=false\n' \
        >&2
    exit 1
fi
printf 'action_19b_b_regression_missing_production_label_rejected=true\n'

if [[ "${CADDY_VALIDATION_CONTAINER:-}" = 1 ]]; then
    require_gate container_projection_root test "$caddy_root" = \
        /workspace/homelab-server-configs/Caddy
    printf 'action_19b_b_regression_intercepted_production_path=host_authoritative\n'
else
    require_gate intercepted_production_semantic_mismatch \
        run_intercepted_production_path "$inspector" "$runner" \
        "$regression_root/production"
fi

printf 'action_19b_b_false_negative_valid_contract_accepted=true\n'
printf 'action_19b_b_false_negative_semantic_mismatch_preserved=true\n'
printf 'action_19b_b_false_positive_duplicate_transcript_rejected=true\n'
printf 'action_19b_b_false_positive_missing_production_label_rejected=true\n'
printf 'action_19b_b_production_path_network_contact=false\n'
printf 'action_19b_b_node_b_postinstall_regression_complete=true\n'
