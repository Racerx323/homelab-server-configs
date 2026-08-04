#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_19a_b_regression
readonly inspector_sha256=d0869e875dd02e4e7e9658aa832ffd5851f6533d61e645571ff59d3e892deb77
readonly runner_sha256=0148cae3443a7ad8d08e5ea77a5de38fe9d5e68772521968a8bde15294b96ecb

test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
readonly caddy_root=${test_directory%/tests}
readonly repository_root=${caddy_root%/Caddy}
readonly inspector="$caddy_root/scripts/inspect-node-b-keepalived-fragment-postinstall-action19a-b.sh"
readonly runner="$caddy_root/scripts/run-node-b-keepalived-fragment-postinstall-action19a-b.sh"
readonly collision_checker="$test_directory/check-shell-readonly-local-collisions-v2.sh"

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }
require_gate() {
    local gate_label=$1

    shift
    if "$@"; then
        printf '%s_%s=true\n' "$prefix" "$gate_label"
        return 0
    fi
    printf '%s_%s=false\n' "$prefix" "$gate_label" >&2
    return 1
}

production_label_alignment() {
    local alignment_root
    local expected_count
    local static_label

    alignment_root=$(mktemp -d /tmp/caddy-action19a-b-labels.XXXXXX)
    "$inspector" --expected-assertions | LC_ALL=C sort >"$alignment_root/expected"
    awk '/^run_assertion [a-z0-9_]+/ { print $2 }' "$inspector" |
        LC_ALL=C sort -u >"$alignment_root/static"
    while IFS= read -r static_label; do
        grep -Fqx "$static_label" "$alignment_root/expected" || {
            rm -rf -- "$alignment_root"
            return 1
        }
    done <"$alignment_root/static"
    expected_count=$(wc -l <"$alignment_root/expected")
    [[ "$expected_count" -eq "$(LC_ALL=C sort -u "$alignment_root/expected" | wc -l)" ]] ||
        {
            rm -rf -- "$alignment_root"
            return 1
        }
    [[ "$(wc -l <"$alignment_root/static")" -eq 81 ]] || {
        rm -rf -- "$alignment_root"
        return 1
    }
    [[ "$expected_count" -eq 114 ]] || {
        rm -rf -- "$alignment_root"
        return 1
    }
    # Literal source contracts intentionally preserve parameter expansion.
    # shellcheck disable=SC2016
    grep -Fq 'service_${unit_label}_${common_property_labels[$property_index]}_observed' \
        "$inspector" || {
        rm -rf -- "$alignment_root"
        return 1
    }
    # shellcheck disable=SC2016
    grep -Fq 'service_${unit_label}_${service_property_labels[$property_index]}_observed' \
        "$inspector" || {
        rm -rf -- "$alignment_root"
        return 1
    }
    rm -rf -- "$alignment_root"
}

write_contract_from_producer() {
    local output_path=$1
    local assertion_label
    local assertion_count
    local state_hash=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa

    assertion_count=$("$inspector" --expected-assertions | wc -l)
    {
        while IFS= read -r assertion_label; do
            printf 'action_19a_b_assertion_%s=true\n' "$assertion_label"
        done < <("$inspector" --expected-assertions)
        printf '%s\n' \
            "action_19a_b_value_expected_assertion_count=$assertion_count" \
            'action_19a_b_value_backup_path=/var/backups/caddy-ha/action19a-node-b-keepalived-fragment.no5a5x' \
            'action_19a_b_value_backup_count=1' \
            "action_19a_b_value_main_sha256=$state_hash" \
            'action_19a_b_value_fragment_sha256=294d5ba44d903ba4ab3ab4330ae3ae05e0160e2b134d71e91a787b65dd96dc4d' \
            "action_19a_b_value_before_state_sha256=$state_hash" \
            "action_19a_b_value_after_state_sha256=$state_hash" \
            "action_19a_b_assertion_count=$assertion_count" \
            'action_19a_b_failed_assertion_count=0' \
            'action_19a_b_first_failure=none' \
            'action_19a_b_helper_execution=false' \
            'action_19a_b_filesystem_mutations=false' \
            'action_19a_b_service_mutations=false' \
            'action_19a_b_vrrp_mutations=false' \
            'action_19a_b_vip_mutations=false' \
            'action_19a_b_persistent_mutations=false' \
            'action_19a_b_remote_complete=true'
    } >"$output_path"
}

run_intercepted() {
    local case_root=$1
    local expected_status=$2
    local transcript_path=$3
    local fake_ssh=$case_root/fake-ssh
    local observed_status=0

    cat >"$fake_ssh" <<'FAKE_SSH'
#!/usr/bin/env bash
set -Eeuo pipefail
cat >"${ACTION19AB_STDIN_CAPTURE:?}"
printf '%s\n' "$*" >"${ACTION19AB_ARGS_CAPTURE:?}"
cat "${ACTION19AB_TRANSCRIPT:?}"
exit "${ACTION19AB_SSH_STATUS:?}"
FAKE_SSH
    chmod 0700 "$fake_ssh"
    (
        cd "$repository_root"
        CADDY_ACTION19AB_INTERCEPTED_TEST=1 \
            CADDY_ACTION19AB_SSH_BINARY="$fake_ssh" \
            ACTION19AB_STDIN_CAPTURE="$case_root/stdin" \
            ACTION19AB_ARGS_CAPTURE="$case_root/args" \
            ACTION19AB_TRANSCRIPT="$transcript_path" \
            ACTION19AB_SSH_STATUS="$expected_status" \
            "$runner"
    ) >"$case_root/stdout" 2>"$case_root/stderr" || observed_status=$?
    [[ "$observed_status" -eq "$expected_status" ]] || return 1
    [[ -s "$case_root/stdin" ]]
    grep -Fq -- '-T -o BatchMode=yes -o IdentitiesOnly=no' "$case_root/args"
    grep -Fq -- '-o HostKeyAlias=pihole00.local.theama.co' "$case_root/args"
    grep -Fq 'pi@10.1.0.54 cd / && sudo -n /bin/bash -s --' "$case_root/args"
    grep -Fq 'action_19a_b_remote_stream_classification=bounded_safe' "$case_root/stdout"
    grep -Fq 'action_19a_b_runner_cleanup_complete=true' "$case_root/stdout"
}

require_gate inspector_hash_exact test "$(file_hash "$inspector")" = "$inspector_sha256"
require_gate runner_hash_exact test "$(file_hash "$runner")" = "$runner_sha256"
require_gate sources_syntax bash -n "$inspector" "$runner"
require_gate sources_shellcheck shellcheck "$inspector" "$runner"
require_gate collision_policy "$collision_checker" "$inspector" "$runner"
require_gate inspector_self_test "$inspector" --self-test
require_gate runner_self_test "$runner" --self-test
require_gate runner_contract_test "$runner" --contract-test
require_gate production_label_alignment production_label_alignment
# The child Bash expands its positional parameter.
# shellcheck disable=SC2016
require_gate arbitrary_minimum_absent bash -c \
    '! grep -Eq "\$[A-Za-z_]*(check|assertion)[A-Za-z_]*.*-(ge|gt)[[:space:]]+[0-9]+" "$1"' \
    _ "$runner"
# shellcheck disable=SC2016
require_gate numbered_synthetic_fixture_absent bash -c \
    '! grep -Eq "seq 1 [0-9]+|check_fixture_[%0-9]" "$1"' _ "${BASH_SOURCE[0]}"

regression_root=$(mktemp -d /tmp/caddy-action19a-b-regression.XXXXXX)
readonly regression_root
cleanup() { rm -rf -- "$regression_root"; }
trap cleanup EXIT
install -d -m 0700 "$regression_root/valid" "$regression_root/mismatch"
write_contract_from_producer "$regression_root/valid/transcript"
cp -- "$regression_root/valid/transcript" "$regression_root/mismatch/transcript"
sed -i \
    -e 's/action_19a_b_assertion_fragment_hash_exact=true/action_19a_b_assertion_fragment_hash_exact=false/' \
    -e 's/action_19a_b_failed_assertion_count=0/action_19a_b_failed_assertion_count=1/' \
    -e 's/action_19a_b_first_failure=none/action_19a_b_first_failure=fragment_hash_exact/' \
    "$regression_root/mismatch/transcript"
if [[ "${CADDY_VALIDATION_CONTAINER:-}" = 1 ]]; then
    require_gate container_projection_root test "$caddy_root" = \
        /workspace/homelab-server-configs/Caddy
    printf '%s_intercepted_production_path=host_authoritative\n' "$prefix"
else
    run_intercepted "$regression_root/valid" 0 \
        "$regression_root/valid/transcript"
    printf '%s_false_negative_exact_producer_contract_accepted=true\n' "$prefix"
    run_intercepted "$regression_root/mismatch" 1 \
        "$regression_root/mismatch/transcript"
    printf '%s_false_negative_semantic_mismatch_preserved=true\n' "$prefix"
fi

printf '%s_false_positive_missing_label_rejected=true\n' "$prefix"
printf '%s_false_positive_duplicate_label_rejected=true\n' "$prefix"
printf '%s_production_path_network_contact=false\n' "$prefix"
printf '%s_complete=true\n' "$prefix"
