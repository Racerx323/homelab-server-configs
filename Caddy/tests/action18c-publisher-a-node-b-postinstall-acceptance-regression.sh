#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly derivation_sha256=cb0339649b2d6c12b8565bf893fab65d6d4b1adba1038c082559c0ad6c958959
readonly rendered_inspector_sha256=edecbe2e5f3821f5da01d1759d5c308ae1b0d7663343f5f0b569ae8f28f37f2b
readonly rendered_runner_sha256=57261a95a1bf8a1b2f2c34ac4acc7d47b2c5fdfa43db0a1468fae4250a0d6fa6
readonly expected_assertion_count=120

test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
readonly caddy_root=${test_directory%/tests}
readonly derivation="$caddy_root/scripts/derive-node-b-publisher-postinstall-acceptance-action18c-publisher-a.sh"
readonly collision_checker="$test_directory/check-shell-readonly-local-collisions-v2.sh"

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }

require_gate() {
    local gate_label=$1

    shift
    if "$@"; then
        printf 'action_18c_publisher_a_regression_%s=true\n' "$gate_label"
        return 0
    fi
    printf 'action_18c_publisher_a_regression_%s=false\n' "$gate_label" >&2
    return 1
}

label_alignment_valid() {
    local inspector_path=$1
    local alignment_root
    local expected_path
    local observed_path

    alignment_root=$(mktemp -d /tmp/caddy-action18c-publisher-a-labels.XXXXXX)
    expected_path="$alignment_root/expected"
    observed_path="$alignment_root/observed"
    "$inspector_path" --expected-checks | LC_ALL=C sort >"$expected_path"
    awk '/^record_command [a-z0-9_]+/ { print $2 }' "$inspector_path" |
        LC_ALL=C sort >"$observed_path"
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
        '(^|[[:space:]])(rsync|scp|sftp)([[:space:]]|$)|publish-release-v2[.]sh[[:space:]]+--' \
        "$inspector_path" "$runner_path"; then
        return 1
    fi
    grep -Fq 'record_command publisher_regular' "$inspector_path" || return 1
    grep -Fq 'record_command publisher_hash_exact' "$inspector_path" || return 1
    grep -Fq 'record_command publisher_backup_manifest_hash_exact' \
        "$inspector_path" || return 1
    grep -Fq 'record_command state_unchanged' "$inspector_path" || return 1
    grep -Fq "printf '%s_publisher_invoked=false" \
        "$inspector_path" || return 1
    grep -Fq "printf '%s_persistent_mutations=false" \
        "$inspector_path" || return 1
    grep -Fq "'cd / && sudo -n /bin/bash -s --'" "$runner_path"
}

write_fake_ssh() {
    local fake_ssh_path=$1

    # The fake executes the streamed production inspector locally. This yields
    # a real semantic-mismatch transcript without contacting a node.
    cat >"$fake_ssh_path" <<'FAKE_SSH'
#!/usr/bin/env bash
set -Eeuo pipefail
printf '%s\n' "$@" >"$ACTION18C_PUBLISHER_A_SSH_ARGUMENTS"
capture=$(mktemp /tmp/caddy-action18c-publisher-a-fake-ssh.XXXXXX)
trap 'rm -f -- "$capture"' EXIT
status=0
/bin/bash -s >"$capture" 2>/dev/null || status=$?
sed 's/^action_18c_publisher_a_value_observed_backup_manifest_sha256=$/action_18c_publisher_a_value_observed_backup_manifest_sha256=0000000000000000000000000000000000000000000000000000000000000000/' \
    "$capture"
exit "$status"
FAKE_SSH
    chmod 0755 "$fake_ssh_path"
}

run_intercepted_production_path() {
    local source_inspector=$1
    local source_runner=$2
    local case_root=$3
    local case_runner="$case_root/Caddy/scripts/${source_runner##*/}"
    local case_status=0

    install -d -m 0700 "$case_root/Caddy/scripts" "$case_root/Caddy/tests" \
        "$case_root/bin"
    install -m 0755 "$source_inspector" "$source_runner" \
        "$case_root/Caddy/scripts/"
    install -m 0755 "$test_directory/check-shell-readonly-local-collisions.sh" \
        "$case_root/Caddy/tests/"
    write_fake_ssh "$case_root/bin/ssh"
    sed -i "s|^PATH=/usr/bin:/bin$|PATH=$case_root/bin:/usr/bin:/bin|" \
        "$case_runner"
    ACTION18C_PUBLISHER_A_SSH_ARGUMENTS="$case_root/ssh.arguments" \
        "$case_runner" >"$case_root/runner.out" \
        2>"$case_root/runner.err" || case_status=$?
    if [[ "$case_status" -ne 1 || -s "$case_root/runner.err" ]] ||
        ! grep -Fxq action_18c_publisher_a_runner_acceptance=semantic_mismatch \
            "$case_root/runner.out"; then
        printf 'action_18c_publisher_a_regression_diagnostic_case_status=%s\n' \
            "$case_status" >&2
        printf 'action_18c_publisher_a_regression_diagnostic_stderr_bytes=%s\n' \
            "$(wc -c <"$case_root/runner.err")" >&2
        printf 'action_18c_publisher_a_regression_diagnostic_acceptance_records=%s\n' \
            "$(grep -c '^action_18c_publisher_a_runner_acceptance=' \
                "$case_root/runner.out" || true)" >&2
        printf 'action_18c_publisher_a_regression_diagnostic_assertion_count_records=%s\n' \
            "$(grep -c '^action_18c_publisher_a_assertion_count=' \
                "$case_root/runner.out" || true)" >&2
        printf 'action_18c_publisher_a_regression_diagnostic_stderr_begin\n' >&2
        sed -n '1,20p' "$case_root/runner.err" >&2
        printf 'action_18c_publisher_a_regression_diagnostic_stderr_end\n' >&2
    fi
    [[ "$case_status" -eq 1 ]] || return 1
    [[ ! -s "$case_root/runner.err" ]] || return 1
    grep -Fxq action_18c_publisher_a_runner_acceptance=semantic_mismatch \
        "$case_root/runner.out" || return 1
    grep -Fxq "action_18c_publisher_a_assertion_count=$expected_assertion_count" \
        "$case_root/runner.out" || return 1
    grep -Fxq action_18c_publisher_a_remote_stdout_content_secured=emitted \
        "$case_root/runner.out" || return 1
    grep -Fxq -- '-T' "$case_root/ssh.arguments" || return 1
    grep -Fxq 'HostKeyAlias=pihole00.local.theama.co' \
        "$case_root/ssh.arguments" || return 1
    grep -Fq 'cd / && sudo -n /bin/bash -s --' \
        "$case_root/ssh.arguments" || return 1
}

regression_root=$(mktemp -d /tmp/caddy-action18c-publisher-a-regression.XXXXXX)
readonly regression_root
trap 'rm -rf -- "$regression_root"' EXIT
readonly rendered_root="$regression_root/Caddy/scripts"
install -d -m 0700 "$rendered_root" "$regression_root/Caddy/tests"
install -m 0755 "$test_directory/check-shell-readonly-local-collisions.sh" \
    "$regression_root/Caddy/tests/"
"$derivation" --output-directory "$rendered_root"
readonly inspector="$rendered_root/inspect-node-b-publisher-postinstall-acceptance-action18c-publisher-a.sh"
readonly runner="$rendered_root/run-node-b-publisher-postinstall-acceptance-action18c-publisher-a.sh"

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
require_gate static_read_only_policy static_read_only_policy "$inspector" "$runner"

cp -- "$inspector" "$regression_root/duplicate-label.inspector"
printf '%s\n' 'record_command publisher_hash_exact true' \
    >>"$regression_root/duplicate-label.inspector"
if label_alignment_valid "$regression_root/duplicate-label.inspector"; then
    printf 'action_18c_publisher_a_regression_duplicate_production_label_rejected=false\n' >&2
    exit 1
fi
printf 'action_18c_publisher_a_regression_duplicate_production_label_rejected=true\n'

cp -- "$inspector" "$regression_root/missing-label.inspector"
sed -i '/^record_command publisher_master_gate /d' \
    "$regression_root/missing-label.inspector"
if label_alignment_valid "$regression_root/missing-label.inspector"; then
    printf 'action_18c_publisher_a_regression_missing_production_label_rejected=false\n' >&2
    exit 1
fi
printf 'action_18c_publisher_a_regression_missing_production_label_rejected=true\n'

if [[ "${CADDY_VALIDATION_CONTAINER:-}" = 1 ]]; then
    require_gate container_projection_root test "$caddy_root" = \
        /workspace/homelab-server-configs/Caddy
    printf 'action_18c_publisher_a_regression_intercepted_production_path=host_authoritative\n'
else
    require_gate intercepted_production_semantic_mismatch \
        run_intercepted_production_path "$inspector" "$runner" \
        "$regression_root/production"
fi

printf 'action_18c_publisher_a_false_negative_valid_contract_accepted=true\n'
printf 'action_18c_publisher_a_false_negative_semantic_mismatch_preserved=true\n'
printf 'action_18c_publisher_a_false_positive_duplicate_transcript_rejected=true\n'
printf 'action_18c_publisher_a_production_path_network_contact=false\n'
printf 'action_18c_publisher_a_node_b_postinstall_acceptance_regression_complete=true\n'
