#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
caddy_root=$(cd -- "$test_directory/.." && pwd)
readonly caddy_root
readonly derivation="$caddy_root/scripts/derive-node-b-action17u-postrepair-acceptance-action17u-c.sh"
readonly historical_inspector="$caddy_root/scripts/inspect-node-b-stderr-safe-finalizer-postinstall-action17u-a.sh"
readonly historical_runner="$caddy_root/scripts/run-node-b-stderr-safe-finalizer-postinstall-action17u-a.sh"
readonly expected_inspector_sha256=d579c51913ab6fc664550f8f966ed49fac50fd37c6c22890a1d04097018806c5
readonly expected_runner_sha256=07e07a07c84a1d7b80792ff8f86bf420d4f323b51baf88fab424c49d93efc644

cleanup_directory=

cleanup_test_directory() {
    local cleanup_status=$?

    trap - EXIT
    if [[ -n "$cleanup_directory" && -d "$cleanup_directory" ]]; then
        rm -rf -- "$cleanup_directory"
    fi
    exit "$cleanup_status"
}

file_hash() {
    sha256sum "$1" | awk '{ print $1 }'
}

render_tree() {
    local render_root=$1
    local render_scripts="$render_root/Caddy/scripts"
    local render_tests="$render_root/Caddy/tests"

    install -d -m 0700 "$render_scripts" "$render_tests"
    "$derivation" --render-inspector "$historical_inspector" \
        >"$render_scripts/inspect-node-b-action17u-postrepair-acceptance-action17u-c.sh"
    "$derivation" --render-runner "$historical_runner" \
        >"$render_scripts/run-node-b-action17u-postrepair-acceptance-action17u-c.sh"
    install -m 0755 -- "$test_directory/check-shell-readonly-local-collisions.sh" \
        "$render_tests/check-shell-readonly-local-collisions.sh"
    chmod 0755 "$render_scripts/"*
    [[ "$(file_hash "$render_scripts/inspect-node-b-action17u-postrepair-acceptance-action17u-c.sh")" == "$expected_inspector_sha256" ]]
    [[ "$(file_hash "$render_scripts/run-node-b-action17u-postrepair-acceptance-action17u-c.sh")" == "$expected_runner_sha256" ]]
}

write_fake_ssh() {
    local fake_ssh=$1

    # Variables are evaluated only by the intercepted production process.
    # shellcheck disable=SC2016
    printf '%s\n' \
        '#!/usr/bin/env bash' \
        'set -Eeuo pipefail' \
        'cat >"$ACTION17UC_STDIN"' \
        'printf "%s\n" "$@" >"$ACTION17UC_ARGUMENTS"' \
        '[[ "$(sha256sum "$ACTION17UC_STDIN" | awk '\''{ print $1 }'\'')" == "$ACTION17UC_INSPECTOR_HASH" ]]' \
        'cat -- "$ACTION17UC_STDOUT"' \
        'cat -- "$ACTION17UC_STDERR" >&2' \
        'exit "$ACTION17UC_STATUS"' >"$fake_ssh"
    chmod 0755 "$fake_ssh"
}

make_fixture() {
    local inspector=$1
    local fixture=$2
    local fixture_label fixture_count=0
    local fixture_hash=1111111111111111111111111111111111111111111111111111111111111111

    {
        while IFS= read -r fixture_label; do
            printf 'action_17u_c_assertion_%s=true\n' "$fixture_label"
            fixture_count=$((fixture_count + 1))
        done < <("$inspector" --expected-checks)
        printf '%s\n' \
            "action_17u_c_assertion_count=$fixture_count" \
            action_17u_c_failed_assertion_count=0 action_17u_c_first_failure=none \
            action_17u_c_value_finalizer_sha256=15d858774a17369f31261f7f94bea72d575f269fdb3e8e991534f66dd4f4902d \
            action_17u_c_value_backup_path=/var/backups/caddy-ha/action17u-node-b-stderr-safe-finalizer.N9uEhC \
            action_17u_c_value_expected_backup_manifest_sha256=a992c2ff9bdfde76770ddae910dedfc2a8bbdf6ad25de909ec5cbeacda31d70b \
            action_17u_c_value_observed_backup_manifest_sha256=a992c2ff9bdfde76770ddae910dedfc2a8bbdf6ad25de909ec5cbeacda31d70b \
            action_17u_c_value_payload_sha256=3635265ef2ad9d6a0a88b9b972fa329d97655d3b4c9df56a1b491952bf1f8f6e \
            action_17u_c_value_manifest_sha256=f4dc87dab7075c4b20ed2acafb4969b757534bad49f5b47c85de4474d17175c8 \
            "action_17u_c_value_before_state_sha256=$fixture_hash" \
            "action_17u_c_value_after_state_sha256=$fixture_hash" \
            action_17u_c_finalizer_invoked=false action_17u_c_release_mutated=false \
            action_17u_c_marker_mutated=false action_17u_c_service_mutations=false \
            action_17u_c_lsyncd_reconciliation_activation=false \
            action_17u_c_filesystem_mutations=false action_17u_c_persistent_mutations=false \
            action_17u_c_node_b_read_only_postrepair_complete=true
    } >"$fixture"
}

production_test() {
    local production_root scripts_root rendered_inspector rendered_runner fake_bin
    local valid_status mismatch_status malformed_status retained_evidence

    cleanup_directory=$(mktemp -d /tmp/caddy-action17u-c-regression.XXXXXX)
    trap cleanup_test_directory EXIT
    production_root="$cleanup_directory/production"
    fake_bin="$cleanup_directory/bin"
    install -d -m 0700 "$fake_bin"
    render_tree "$production_root"
    scripts_root="$production_root/Caddy/scripts"
    rendered_inspector="$scripts_root/inspect-node-b-action17u-postrepair-acceptance-action17u-c.sh"
    rendered_runner="$scripts_root/run-node-b-action17u-postrepair-acceptance-action17u-c.sh"
    sed -i "s|^PATH=/usr/bin:/bin$|PATH=$fake_bin:/usr/bin:/bin|" "$rendered_runner"
    write_fake_ssh "$fake_bin/ssh"
    make_fixture "$rendered_inspector" "$cleanup_directory/valid"
    : >"$cleanup_directory/empty"

    valid_status=0
    (
        cd /home/aaron/code/homelab-server-configs
        ACTION17UC_ARGUMENTS="$cleanup_directory/valid.arguments" \
            ACTION17UC_INSPECTOR_HASH="$expected_inspector_sha256" \
            ACTION17UC_STATUS=0 ACTION17UC_STDERR="$cleanup_directory/empty" \
            ACTION17UC_STDIN="$cleanup_directory/valid.stdin" \
            ACTION17UC_STDOUT="$cleanup_directory/valid" "$rendered_runner"
    ) >"$cleanup_directory/valid.outer" 2>"$cleanup_directory/valid.error" || valid_status=$?
    [[ "$valid_status" -eq 0 ]]
    grep -Fxq action_17u_c_runner_acceptance=true "$cleanup_directory/valid.outer"
    grep -Fxq action_17u_c_assertion_repair_stage_count_zero=true "$cleanup_directory/valid.outer"
    grep -Fxq 'cd / && sudo -n /bin/bash -s --' "$cleanup_directory/valid.arguments"

    sed 's/action_17u_c_assertion_repair_stage_count_zero=true/action_17u_c_assertion_repair_stage_count_zero=false/; s/action_17u_c_failed_assertion_count=0/action_17u_c_failed_assertion_count=1/; s/action_17u_c_first_failure=none/action_17u_c_first_failure=repair_stage_count_zero/; /action_17u_c_node_b_read_only_postrepair_complete=true/d' \
        "$cleanup_directory/valid" >"$cleanup_directory/mismatch"
    mismatch_status=0
    (
        cd /home/aaron/code/homelab-server-configs
        ACTION17UC_ARGUMENTS="$cleanup_directory/mismatch.arguments" \
            ACTION17UC_INSPECTOR_HASH="$expected_inspector_sha256" \
            ACTION17UC_STATUS=1 ACTION17UC_STDERR="$cleanup_directory/empty" \
            ACTION17UC_STDIN="$cleanup_directory/mismatch.stdin" \
            ACTION17UC_STDOUT="$cleanup_directory/mismatch" "$rendered_runner"
    ) >"$cleanup_directory/mismatch.outer" 2>"$cleanup_directory/mismatch.error" || mismatch_status=$?
    [[ "$mismatch_status" -eq 1 ]]
    grep -Fxq action_17u_c_runner_acceptance=semantic_mismatch "$cleanup_directory/mismatch.outer"

    cp -- "$cleanup_directory/valid" "$cleanup_directory/malformed"
    printf 'action_17u_c_assertion_identity_root=true\n' >>"$cleanup_directory/malformed"
    malformed_status=0
    (
        cd /home/aaron/code/homelab-server-configs
        ACTION17UC_ARGUMENTS="$cleanup_directory/malformed.arguments" \
            ACTION17UC_INSPECTOR_HASH="$expected_inspector_sha256" \
            ACTION17UC_STATUS=0 ACTION17UC_STDERR="$cleanup_directory/empty" \
            ACTION17UC_STDIN="$cleanup_directory/malformed.stdin" \
            ACTION17UC_STDOUT="$cleanup_directory/malformed" "$rendered_runner"
    ) >"$cleanup_directory/malformed.outer" 2>"$cleanup_directory/malformed.error" || malformed_status=$?
    [[ "$malformed_status" -eq 97 ]]
    grep -Fxq action_17u_c_runner_acceptance=false "$cleanup_directory/malformed.error"
    retained_evidence=$(sed -n 's/^action_17u_c_evidence_retained=//p' \
        "$cleanup_directory/malformed.error")
    [[ "$retained_evidence" == /tmp/caddy-action17u-c-runner.* ]]
    [[ -d "$retained_evidence" && ! -L "$retained_evidence" ]]
    [[ "$(stat -c '%U:%G:%a' "$retained_evidence")" == aaron:aaron:700 ]]
    [[ -f "$retained_evidence/node-b.out" && -f "$retained_evidence/node-b.err" ]]
    rm -rf -- "$retained_evidence"

    [[ -z "$(find /tmp -mindepth 1 -maxdepth 1 -type d -name 'caddy-action17u-c-runner.*' -print -quit)" ]]
    printf 'action_17u_c_valid_production_path_accepted=true\n'
    printf 'action_17u_c_semantic_mismatch_preserved=true\n'
    printf 'action_17u_c_malformed_evidence_rejected=true\n'
    printf 'action_17u_c_malformed_evidence_retention_validated=true\n'
    printf 'action_17u_c_production_path_network_contact=false\n'
    rm -rf -- "$cleanup_directory"
    cleanup_directory=
    trap - EXIT
}

container_projection_test() {
    local projection_root projection_inspector projection_runner

    cleanup_directory=$(mktemp -d /tmp/caddy-action17u-c-container.XXXXXX)
    trap cleanup_test_directory EXIT
    projection_root="$cleanup_directory/production"
    render_tree "$projection_root"
    projection_inspector="$projection_root/Caddy/scripts/inspect-node-b-action17u-postrepair-acceptance-action17u-c.sh"
    projection_runner="$projection_root/Caddy/scripts/run-node-b-action17u-postrepair-acceptance-action17u-c.sh"
    [[ "$("$projection_inspector" --expected-checks | wc -l)" -eq 72 ]]
    [[ "$("$projection_inspector" --expected-checks | sort -u | wc -l)" -eq 72 ]]
    grep -Fxq repair_stage_count_zero < <("$projection_inspector" --expected-checks)
    grep -Fq "record_command repair_stage_count_zero" "$projection_inspector"
    "$projection_inspector" --self-test >/dev/null
    "$projection_runner" --contract-test >/dev/null
    printf 'action_17u_c_container_projection_validated=true\n'
    printf 'action_17u_c_container_network_contact=false\n'
    rm -rf -- "$cleanup_directory"
    cleanup_directory=
    trap - EXIT
}

case "${1:-}" in
    --self-test)
        [[ $# -eq 1 ]]
        bash -n "$derivation" "$historical_inspector" "$historical_runner"
        printf 'action_17u_c_regression_self_test_complete=true\n'
        ;;
    --production-test | "")
        [[ $# -le 1 ]]
        if [[ "${CADDY_VALIDATION_CONTAINER:-}" == 1 ]]; then
            container_projection_test
        else
            production_test
        fi
        ;;
    *)
        printf 'Usage: %s [--self-test|--production-test]\n' "${0##*/}" >&2
        exit 64
        ;;
esac
