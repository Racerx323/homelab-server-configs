#!/usr/bin/env bash

set -Euo pipefail
set +x
umask 077
PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH
readonly PATH

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_dir
caddy_root=$(cd -- "$script_dir/.." && pwd)
readonly caddy_root
readonly node_a_inspector="$caddy_root/scripts/inspect-node-a-source-bound-restricted-transport-action17o.sh"
readonly node_b_inspector="$caddy_root/scripts/inspect-node-b-source-bound-restricted-transport-action17o.sh"
readonly runner="$caddy_root/scripts/run-node-a-to-node-b-source-bound-restricted-transport-action17o.sh"
readonly source_test_policy="$caddy_root/tests/run-source-test-in-context.sh"
readonly historical_retry="$caddy_root/scripts/run-node-a-source-bound-transport-action17c-c-retry.sh"
readonly historical_diagnostic="$caddy_root/scripts/run-node-a-source-bound-transport-diagnostic-action17c-c-a.sh"
readonly accepted_dns_nss_runner="$caddy_root/scripts/run-node-a-dns-nss-correction-action17n-reset-retry.sh"
readonly accepted_dns_nss_driver="$caddy_root/scripts/apply-node-a-dns-nss-correction-action17n-reset-retry.sh"
readonly node_a_inspector_sha256=f86c256a1e0af8a1e805a0329a6195e548651b28dfafbd160b98c714e5c61b7c
readonly node_b_inspector_sha256=6d5e7ee4834a58fec35e45f296b83df98963848613483405a961eda4ec301896
readonly runner_sha256=053bd8aa483ed92736aa0bbcee2232b9bf6d17de5ea937e4aea8690fd4e95c48
readonly historical_retry_sha256=5ec46ca77782160164785eefb75289e9a02f6d3262577261ce7cdcc31abbd6ab
readonly historical_diagnostic_sha256=f460262cded8b056818f27b0d82cd637627aa6440a67d6eb409325ac73c301d2
readonly accepted_dns_nss_runner_sha256=b9e2a07622bf7c401f667dfdb68bace73c086775de55fe8c0c24ba72b14b3b2e
readonly accepted_dns_nss_driver_sha256=94c1ea0cf40cda26fa28130c1167f6f00f73957c9ed7430a8e8ec1510f7ef755

file_hash() {
    sha256sum "$1" | awk '{ print $1 }'
}

assert_hash() {
    local hash_path=$1
    local hash_expected=$2

    [[ "$(file_hash "$hash_path")" == "$hash_expected" ]]
}

assert_unique_record_labels() {
    local label_source=$1
    local label_minimum=$2
    local label_file
    local label_count
    local label_unique_count

    label_file=$(mktemp /tmp/caddy-action17o-labels.XXXXXX)
    # shellcheck disable=SC2064
    trap "rm -f -- '$label_file'" RETURN
    sed -n \
        's/^[[:space:]]*record_command[[:space:]]\+\([a-z0-9_]\+\).*/\1/p' \
        "$label_source" >"$label_file"
    label_count=$(wc -l <"$label_file")
    label_unique_count=$(LC_ALL=C sort -u "$label_file" | wc -l)
    [[ "$label_count" -ge "$label_minimum" ]]
    [[ "$label_count" -eq "$label_unique_count" ]]
}

write_node_a_fixture() {
    local fixture_path=$1
    local fixture_hash=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa

    printf '%s\n' \
        action_17o_check_fixture=true \
        "action_17o_value_before_state_sha256=$fixture_hash" \
        action_17o_value_transport_probe_attempted=true \
        action_17o_value_direct_ssh_status=126 \
        action_17o_value_direct_ssh_error_class=forced_receiver_rejection \
        action_17o_value_rsync_dry_run_attempted=true \
        action_17o_value_rsync_dry_run_status=0 \
        "action_17o_value_after_state_sha256=$fixture_hash" \
        action_17o_checks_total=1 \
        action_17o_checks_passed=1 \
        action_17o_checks_failed=0 \
        action_17o_first_failure=none \
        action_17o_release_payload_transferred=false \
        action_17o_synchronization_executed=false \
        action_17o_service_mutations=false \
        action_17o_persistent_mutations=false \
        action_17o_node_a_acceptance=true >"$fixture_path"
}

write_node_b_fixture() {
    local fixture_path=$1
    local fixture_hash=$2

    printf '%s\n' \
        action_17o_node_b_check_fixture=true \
        "action_17o_node_b_value_state_sha256=$fixture_hash" \
        action_17o_node_b_checks_total=1 \
        action_17o_node_b_checks_passed=1 \
        action_17o_node_b_checks_failed=0 \
        action_17o_node_b_first_failure=none \
        action_17o_node_b_persistent_mutations=false \
        action_17o_node_b_synchronization_executed=false \
        action_17o_node_b_acceptance=true >"$fixture_path"
}

write_fake_ssh() {
    local fake_path=$1

    # shellcheck disable=SC2016
    {
        printf '%s\n' '#!/usr/bin/env bash'
        printf '%s\n' 'set -euo pipefail'
        printf '%s\n' 'printf "%s\n" "$*" >>"$ACTION17O_FAKE_SSH_LOG"'
        printf '%s\n' 'cat >/dev/null'
        printf '%s\n' 'case " $* " in'
        printf '%s\n' '    *" pi@10.1.0.53 "*)'
        printf '%s\n' '        cat "$ACTION17O_NODE_A_FIXTURE"'
        printf '%s\n' '        ;;'
        printf '%s\n' '    *" pi@10.1.0.54 "*)'
        printf '%s\n' \
            '        count=$(grep -Fc " pi@10.1.0.54 " "$ACTION17O_FAKE_SSH_LOG")'
        printf '%s\n' '        if [[ "$count" -eq 1 ]]; then'
        printf '%s\n' '            cat "$ACTION17O_NODE_B_BEFORE_FIXTURE"'
        printf '%s\n' '        else'
        printf '%s\n' '            cat "$ACTION17O_NODE_B_AFTER_FIXTURE"'
        printf '%s\n' '        fi'
        printf '%s\n' '        ;;'
        printf '%s\n' '    *)'
        printf '%s\n' '        exit 92'
        printf '%s\n' '        ;;'
        printf '%s\n' 'esac'
    } >"$fake_path"
    chmod 0755 "$fake_path"
}

prepare_production_stage() {
    local production_stage=$1
    local production_scripts="$production_stage/Caddy/scripts"
    local production_bin="$production_stage/bin"

    install -d -m 0700 "$production_scripts" "$production_bin"
    cp -- \
        "$node_a_inspector" \
        "$node_b_inspector" \
        "$historical_retry" \
        "$historical_diagnostic" \
        "$accepted_dns_nss_runner" \
        "$accepted_dns_nss_driver" \
        "$production_scripts/"
    sed \
        "s|^PATH=/usr/bin:/bin$|PATH=$production_bin:/usr/bin:/bin|" \
        "$runner" \
        >"$production_scripts/run-node-a-to-node-b-source-bound-restricted-transport-action17o.sh"
    chmod 0755 \
        "$production_scripts/run-node-a-to-node-b-source-bound-restricted-transport-action17o.sh"
    write_fake_ssh "$production_bin/ssh"
}

run_production_case() {
    local case_root=$1
    local expected_status=$2
    local expected_marker=$3
    local production_runner="$case_root/Caddy/scripts/run-node-a-to-node-b-source-bound-restricted-transport-action17o.sh"
    local production_status=0

    : >"$case_root/ssh.log"
    ACTION17O_FAKE_SSH_LOG="$case_root/ssh.log" \
        ACTION17O_NODE_A_FIXTURE="$case_root/node-a.fixture" \
        ACTION17O_NODE_B_BEFORE_FIXTURE="$case_root/node-b-before.fixture" \
        ACTION17O_NODE_B_AFTER_FIXTURE="$case_root/node-b-after.fixture" \
        "$production_runner" \
        >"$case_root/runner.out" 2>"$case_root/runner.err" ||
        production_status=$?
    [[ "$production_status" -eq "$expected_status" ]]
    grep -Fq "$expected_marker" \
        "$case_root/runner.out" "$case_root/runner.err"
    [[ "$(wc -l <"$case_root/ssh.log")" -eq 3 ]]
    [[ "$(grep -Fc ' pi@10.1.0.53 ' "$case_root/ssh.log")" -eq 1 ]]
    [[ "$(grep -Fc ' pi@10.1.0.54 ' "$case_root/ssh.log")" -eq 2 ]]
}

run_production_path_regression() {
    local production_root
    local case_name
    local case_root
    local stable_b_hash=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
    local changed_b_hash=cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc

    production_root=$(mktemp -d /tmp/caddy-action17o-production.XXXXXX)
    trap 'rm -rf -- "$production_root"' RETURN

    for case_name in success duplicate failed-rsync changed-node-b; do
        case_root="$production_root/$case_name"
        install -d -m 0700 "$case_root"
        prepare_production_stage "$case_root"
        write_node_a_fixture "$case_root/node-a.fixture"
        write_node_b_fixture "$case_root/node-b-before.fixture" "$stable_b_hash"
        write_node_b_fixture "$case_root/node-b-after.fixture" "$stable_b_hash"
    done

    printf 'action_17o_check_fixture=true\n' \
        >>"$production_root/duplicate/node-a.fixture"
    sed -i \
        's/action_17o_value_rsync_dry_run_status=0/action_17o_value_rsync_dry_run_status=1/' \
        "$production_root/failed-rsync/node-a.fixture"
    write_node_b_fixture \
        "$production_root/changed-node-b/node-b-after.fixture" \
        "$changed_b_hash"

    run_production_case \
        "$production_root/success" 0 action_17o_runner_acceptance=true
    run_production_case \
        "$production_root/duplicate" 97 \
        action_17o_node_a_transcript_valid=false
    run_production_case \
        "$production_root/failed-rsync" 97 \
        action_17o_node_a_transcript_valid=false
    run_production_case \
        "$production_root/changed-node-b" 97 \
        action_17o_node_b_state_unchanged=false

    printf 'action_17o_production_path_success_accepted=true\n'
    printf 'action_17o_production_path_duplicate_rejected=true\n'
    printf 'action_17o_production_path_failed_dry_run_rejected=true\n'
    printf 'action_17o_production_path_state_change_rejected=true\n'
    printf 'action_17o_production_path_network_contact=false\n'
}

if [[ "${1:-}" != --production-test || $# -ne 1 ]]; then
    printf 'Usage: %s --production-test\n' "${0##*/}" >&2
    exit 2
fi

assert_hash "$node_a_inspector" "$node_a_inspector_sha256"
assert_hash "$node_b_inspector" "$node_b_inspector_sha256"
assert_hash "$runner" "$runner_sha256"
assert_hash "$historical_retry" "$historical_retry_sha256"
assert_hash "$historical_diagnostic" "$historical_diagnostic_sha256"
assert_hash "$accepted_dns_nss_runner" "$accepted_dns_nss_runner_sha256"
assert_hash "$accepted_dns_nss_driver" "$accepted_dns_nss_driver_sha256"

bash -n "$node_a_inspector" "$node_b_inspector" "$runner"
shellcheck "$node_a_inspector" "$node_b_inspector" "$runner"
"$node_a_inspector" --self-test >/dev/null
"$node_a_inspector" --contract-test >/dev/null
"$node_b_inspector" --self-test >/dev/null
"$runner" --self-test >/dev/null
"$runner" --contract-test >/dev/null
"$source_test_policy" --runner "$runner" >/dev/null

assert_unique_record_labels "$node_a_inspector" 40
assert_unique_record_labels "$node_b_inspector" 30

grep -Fq 'cd / && exec /usr/sbin/runuser -u caddy-sync' "$runner"
grep -Fq "ssh -6 -n -T -vv \\" "$node_a_inspector"
grep -Fq -- "-b \"\$node_a_ipv6\"" "$node_a_inspector"
grep -Fq -- "--dry-run \\" "$node_a_inspector"
grep -Fq "\"caddy-sync@\$node_b_fqdn:/node-a/\"" "$node_a_inspector"
grep -Fq 'action_17o_release_payload_transferred=false' "$node_a_inspector"
grep -Fq 'action_17o_synchronization_executed=false' "$node_a_inspector"
grep -Fq 'action_17o_persistent_mutations=false' "$node_a_inspector"
grep -Fq 'action_17o_node_b_state_unchanged=true' "$runner"
if grep -Fq 'ACTION17O_' "$runner"; then
    printf 'Production runner contains a fixture bypass.\n' >&2
    exit 1
fi

if grep -Eq \
    'systemctl[[:space:]]+(start|stop|restart|reload|enable|disable|mask|unmask|daemon-reload|reset-failed)' \
    "$node_a_inspector" "$node_b_inspector" "$runner"; then
    printf 'Action 17o contains a service mutation.\n' >&2
    exit 1
fi
if grep -Eq \
    '^[[:space:]]*(ip|nft|iptables|ip6tables)[[:space:]]+(address[[:space:]]+(add|delete)|route[[:space:]]+(add|delete)|link[[:space:]]+set|rule[[:space:]]+(add|delete)|add|delete|replace|flush)' \
    "$node_a_inspector" "$node_b_inspector" "$runner"; then
    printf 'Action 17o contains a network mutation.\n' >&2
    exit 1
fi
if grep -Eq \
    '^[[:space:]]*(install|cp|mv|touch|chmod|chown|tee|truncate)([[:space:]]|$)' \
    "$node_a_inspector" "$node_b_inspector"; then
    printf 'Action 17o contains a persistent file mutation.\n' >&2
    exit 1
fi
if grep -Eq \
    '^[[:space:]]*rsync([[:space:]]|$)' "$node_a_inspector" &&
    ! grep -Fq -- "--dry-run \\" "$node_a_inspector"; then
    printf 'Action 17o rsync invocation is not a dry run.\n' >&2
    exit 1
fi
if grep -Eq \
    'lsyncd[[:space:]]+(-|--|/)|caddy-lsyncd\.service[[:space:]]+(start|restart)' \
    "$node_a_inspector" "$node_b_inspector" "$runner"; then
    printf 'Action 17o can start synchronization.\n' >&2
    exit 1
fi

if [[ "$(id -un)" == aaron ]]; then
    run_production_path_regression
else
    [[ "${CADDY_VALIDATION_CONTAINER:-0}" == 1 ]]
    printf 'action_17o_production_path_host_authoritative=true\n'
    printf 'action_17o_container_fixture_bypass_absent=true\n'
fi

printf 'action_17o_source_bound_restricted_transport_regression_complete=true\n'
