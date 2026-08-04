#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_19d_a
readonly derivation_sha256=f128432030f4fce0be7d2ab71a24fd70f9a966cbd14113b7b5cde02ccabb4f89
readonly rendered_inspector_sha256=ca6eac99ab383bc02cfb8e9f8468532011324a5d9dcd1b893ca5ac624600ccc5
readonly rendered_runner_sha256=83f01bb634a17c9b9d283aaf7d304055a79f623cf5bf6fed38a2fb2f5cf9e2fa
readonly base_derivation_sha256=7ba7ca096db09c48b57c32ae62bf300b3aa16aa6b6f8d4cf033d83624395dd1b
readonly base_regression_sha256=daa584d9af999fe7bfd839dde58f190b75a44b1e9b445f7132369e3406b980fc
readonly expected_assertion_count=86

test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
readonly caddy_root=${test_directory%/tests}
readonly derivation="$caddy_root/scripts/derive-node-a-keepalived-helper-postinstall-action19d-a.sh"
readonly base_derivation="$caddy_root/scripts/derive-node-b-keepalived-helper-postinstall-action19b-b.sh"
readonly base_inspector="$caddy_root/scripts/inspect-node-b-keepalived-helper-prerequisite-action19a-a.sh"
readonly base_runner="$caddy_root/scripts/run-node-b-keepalived-helper-prerequisite-action19a-a.sh"
readonly base_regression="$test_directory/action19b-b-node-b-keepalived-helper-postinstall-regression.sh"
readonly collision_checker="$test_directory/check-shell-readonly-local-collisions-v2.sh"
readonly inner_collision_checker="$test_directory/check-shell-readonly-local-collisions.sh"
readonly conditional_policy="$test_directory/conditional-validator-errexit-policy-regression.sh"

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }

require_gate() {
    local gate_label=$1

    shift
    if "$@"; then
        printf '%s_regression_%s=true\n' "$prefix" "$gate_label"
        return 0
    fi
    printf '%s_regression_%s=false\n' "$prefix" "$gate_label" >&2
    return 1
}

render_reference_regression() {
    local output_path=$1

    sed \
        -e 's/action_19b_b/action_19d_a/g' \
        -e 's/action19b-b/action19d-a/g' \
        -e 's/ACTION19BB/ACTION19DA/g' \
        -e 's/CADDY_ACTION19BB/CADDY_ACTION19DA/g' \
        -e 's/node_b_postinstall/node_a_postinstall/g' \
        -e 's/node-b-keepalived-helper-postinstall-action19b-b/node-a-keepalived-helper-postinstall-action19d-a/g' \
        -e 's/inspect-node-b-keepalived-helper-postinstall-action19b-b/inspect-node-a-keepalived-helper-postinstall-action19d-a/g' \
        -e 's/run-node-b-keepalived-helper-postinstall-action19b-b/run-node-a-keepalived-helper-postinstall-action19d-a/g' \
        -e 's/derive-node-b-keepalived-helper-postinstall-action19b-b/derive-node-a-keepalived-helper-postinstall-action19d-a/g' \
        -e 's/inspect-node-b-keepalived-helper-postinstall-action19d-a/inspect-node-a-keepalived-helper-postinstall-action19d-a/g' \
        -e 's/run-node-b-keepalived-helper-postinstall-action19d-a/run-node-a-keepalived-helper-postinstall-action19d-a/g' \
        -e 's/derive-node-b-keepalived-helper-postinstall-action19d-a/derive-node-a-keepalived-helper-postinstall-action19d-a/g' \
        -e "s/7ba7ca096db09c48b57c32ae62bf300b3aa16aa6b6f8d4cf033d83624395dd1b/$derivation_sha256/g" \
        -e "s/74b4fbafc25850dace3b0057a7b74a3464936425869952ac21113c11e2652250/$rendered_inspector_sha256/g" \
        -e "s/8c24121c3e8a1f4f8719b6445228c690745671217bc54bd6e7c12c866869c34f/$rendered_runner_sha256/g" \
        -e 's/pihole00\.local\.theama\.co/pihole0.local.theama.co/g' \
        "$base_regression" >"$output_path"
    chmod 0755 "$output_path"
    if grep -Eq 'action_19b_b|action19b|node-b|node_b|pihole00\.' \
        "$output_path"; then
        return 1
    fi
}

write_dynamic_collision_fixture() {
    local output_path=$1

    # shellcheck disable=SC2016
    printf '%s\n' \
        '#!/usr/bin/env bash' \
        'readonly collision_value=outer' \
        'collision_function() {' \
        '    local collision_value=inner' \
        '    printf "%s\\n" "$collision_value"' \
        '}' \
        'collision_function' >"$output_path"
    chmod 0755 "$output_path"
}

write_invalid_summary_ssh() {
    local output_path=$1

    # shellcheck disable=SC2016
    printf '%s\n' \
        '#!/usr/bin/env bash' \
        'set -Eeuo pipefail' \
        'capture=$(mktemp /tmp/caddy-action19d-a-invalid-summary.XXXXXX)' \
        'trap '\''rm -f -- "$capture"'\'' EXIT' \
        'status=0' \
        '/bin/bash -s >"$capture" 2>/dev/null || status=$?' \
        'sed -e '\''s/^action_19d_a_failed_assertion_count=.*/action_19d_a_failed_assertion_count=0/'\'' -e '\''s/^action_19d_a_first_failure=.*/action_19d_a_first_failure=none/'\'' "$capture"' \
        'exit 0' >"$output_path"
    chmod 0755 "$output_path"
}

run_invalid_summary_case() {
    local rendered_runner=$1
    local case_root=$2
    local case_runner=$case_root/Caddy/scripts/${rendered_runner##*/}
    local case_status=0

    install -d -m 0700 "$case_root/Caddy/scripts" "$case_root/Caddy/tests" \
        "$case_root/bin"
    install -m 0755 "$rendered_runner" \
        "$case_root/Caddy/scripts/"
    install -m 0755 "$inspector" \
        "$case_root/Caddy/scripts/inspect-node-a-keepalived-helper-postinstall-action19d-a.sh"
    install -m 0755 "$collision_checker" "$inner_collision_checker" \
        "$case_root/Caddy/tests/"
    write_invalid_summary_ssh "$case_root/bin/ssh"
    (
        cd -- "${caddy_root%/Caddy}"
        CADDY_ACTION19DA_SSH_BINARY="$case_root/bin/ssh" \
            CADDY_ACTION19DA_INTERCEPTED_TEST=1 \
            /bin/bash "$case_runner"
    ) >"$case_root/runner.out" 2>"$case_root/runner.err" ||
        case_status=$?
    if [[ "$case_status" -ne 97 ]] ||
        ! grep -Fxq action_19d_a_runner_contract_valid=false \
            "$case_root/runner.err" ||
        [[ "$(awk 'END { print NR }' "$case_root/runner.err")" -ne 1 ]] ||
        ! grep -Eq '^action_19d_a_assertion_[a-z0-9_]+=false$' \
            "$case_root/runner.out" ||
        ! grep -Eq '^action_19d_a_assertion_[a-z0-9_]+=true$' \
            "$case_root/runner.out" ||
        ! grep -Fxq action_19d_a_failed_assertion_count=0 \
            "$case_root/runner.out" ||
        ! grep -Fxq action_19d_a_first_failure=none \
            "$case_root/runner.out"; then
        printf '%s_regression_invalid_summary_status=%s\n' \
            "$prefix" "$case_status" >&2
        printf '%s_regression_invalid_summary_stdout_lines=%s\n' \
            "$prefix" "$(awk 'END { print NR }' "$case_root/runner.out")" >&2
        printf '%s_regression_invalid_summary_stderr_lines=%s\n' \
            "$prefix" "$(awk 'END { print NR }' "$case_root/runner.err")" >&2
        printf '%s_regression_invalid_summary_stderr_begin\n' "$prefix" >&2
        sed -n '1,20p' "$case_root/runner.err" >&2
        printf '%s_regression_invalid_summary_stderr_end\n' "$prefix" >&2
        printf '%s_regression_invalid_summary_summary_begin\n' "$prefix" >&2
        grep -E '^action_19d_a_(assertion_[a-z0-9_]+|assertion_count|failed_assertion_count|first_failure|runner_contract_valid|runner_acceptance)=' \
            "$case_root/runner.out" >&2 || true
        printf '%s_regression_invalid_summary_summary_end\n' "$prefix" >&2
        return 1
    fi
    [[ "$case_status" -eq 97 ]] || return 1
    grep -Fxq action_19d_a_runner_contract_valid=false \
        "$case_root/runner.err" || return 1
    [[ "$(awk 'END { print NR }' "$case_root/runner.err")" -eq 1 ]] ||
        return 1
    grep -Eq '^action_19d_a_assertion_[a-z0-9_]+=false$' \
        "$case_root/runner.out" || return 1
    grep -Eq '^action_19d_a_assertion_[a-z0-9_]+=true$' \
        "$case_root/runner.out" || return 1
    grep -Fxq action_19d_a_failed_assertion_count=0 \
        "$case_root/runner.out" || return 1
    grep -Fxq action_19d_a_first_failure=none \
        "$case_root/runner.out"
}

regression_root=$(mktemp -d /tmp/caddy-action19d-a-regression.XXXXXX)
readonly regression_root
trap 'rm -rf -- "$regression_root"' EXIT
readonly rendered_root=$regression_root/rendered/Caddy
readonly rendered_scripts=$rendered_root/scripts
readonly reference_root=$regression_root/reference/Caddy
install -d -m 0700 "$rendered_scripts" "$reference_root/scripts" \
    "$rendered_root/tests" "$reference_root/tests"
install -m 0755 "$collision_checker" "$inner_collision_checker" \
    "$rendered_root/tests/"
/bin/bash "$derivation" --output-directory "$rendered_scripts"
readonly inspector=$rendered_scripts/inspect-node-a-keepalived-helper-postinstall-action19d-a.sh
readonly runner=$rendered_scripts/run-node-a-keepalived-helper-postinstall-action19d-a.sh
readonly reference_regression=$reference_root/tests/action19d-a-node-a-keepalived-helper-postinstall-regression.sh
render_reference_regression "$reference_regression"
install -m 0755 "$derivation" "$base_derivation" "$base_inspector" \
    "$base_runner" \
    "$reference_root/scripts/"
install -m 0755 "$collision_checker" "$inner_collision_checker" \
    "$reference_root/tests/"

require_gate derivation_hash_exact test "$(file_hash "$derivation")" = \
    "$derivation_sha256"
require_gate base_derivation_hash_exact test \
    "$(file_hash "$base_derivation")" = "$base_derivation_sha256"
require_gate base_regression_hash_exact test \
    "$(file_hash "$base_regression")" = "$base_regression_sha256"
require_gate inspector_hash_exact test "$(file_hash "$inspector")" = \
    "$rendered_inspector_sha256"
require_gate runner_hash_exact test "$(file_hash "$runner")" = \
    "$rendered_runner_sha256"
require_gate shell_syntax bash -n "$derivation" "$inspector" "$runner" \
    "$reference_regression"
require_gate shellcheck shellcheck "$derivation" "$inspector" "$runner" \
    "$reference_regression"
require_gate readonly_local_collision_absent \
    "$collision_checker" "$0" "$derivation" "$inspector" "$runner" \
    "$reference_regression"
require_gate conditional_validator_policy "$conditional_policy" >/dev/null
require_gate derivation_self_test /bin/bash "$derivation" --self-test
require_gate inspector_self_test /bin/bash "$inspector" --self-test
require_gate runner_self_test /bin/bash "$runner" --self-test
require_gate runner_contract_test /bin/bash "$runner" --contract-test
require_gate assertion_count_exact test \
    "$(/bin/bash "$inspector" --expected-assertions | wc -l)" -eq \
    "$expected_assertion_count"
require_gate assertion_labels_unique test \
    "$(/bin/bash "$inspector" --expected-assertions | sort -u | wc -l)" \
    -eq "$expected_assertion_count"

write_dynamic_collision_fixture "$regression_root/dynamic-collision.sh"
if "$collision_checker" "$regression_root/dynamic-collision.sh" \
    >"$regression_root/collision.out" 2>"$regression_root/collision.err"; then
    printf '%s_regression_dynamic_collision_rejected=false\n' "$prefix" >&2
    exit 1
fi
printf '%s_regression_dynamic_collision_rejected=true\n' "$prefix"

require_gate early_invalid_later_valid_rejected \
    run_invalid_summary_case "$runner" "$regression_root/invalid-summary"

if [[ "${CADDY_VALIDATION_CONTAINER:-}" = 1 ]]; then
    require_gate container_projection_root test "$caddy_root" = \
        /workspace/homelab-server-configs/Caddy
    printf '%s_regression_reference_production_path=host_authoritative\n' \
        "$prefix"
else
    require_gate transformed_reference_regression \
        env CADDY_ACTION19DA_INTERCEPTED_TEST=1 \
        /bin/bash "$reference_regression"
fi

printf '%s_false_negative_valid_contract_accepted=true\n' "$prefix"
printf '%s_false_negative_semantic_mismatch_preserved=true\n' "$prefix"
printf '%s_false_positive_early_invalid_later_valid_rejected=true\n' "$prefix"
printf '%s_false_positive_dynamic_collision_rejected=true\n' "$prefix"
printf '%s_production_path_network_contact=false\n' "$prefix"
printf '%s_node_a_postinstall_regression_complete=true\n' "$prefix"
