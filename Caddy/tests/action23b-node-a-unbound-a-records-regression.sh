#!/usr/bin/env bash

set -euo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_dir
caddy_root=$(cd -- "$script_dir/.." && pwd)
readonly caddy_root
readonly outer="$caddy_root/scripts/run-node-a-unbound-a-records-action23b-outer.sh"
readonly driver="$caddy_root/scripts/apply-node-a-unbound-a-records-action23b.sh"
readonly collision_policy="$script_dir/check-shell-readonly-local-collisions-v2.sh"

require_true() {
    local action23b_regression_label=$1

    shift
    if "$@"; then
        printf 'action_23b_regression_%s=true\n' "$action23b_regression_label"
    else
        printf 'action_23b_regression_%s=false\n' "$action23b_regression_label" >&2
        return 1
    fi
}

run_collision_policy() {
    "$collision_policy" "$0" "$outer" "$driver" >/dev/null
}

run_transport_case() {
    local action23b_case_mode=$1
    local action23b_case_status_expected=$2
    local action23b_case_acceptance_expected=$3
    local action23b_case_dir
    local action23b_case_stdout
    local action23b_case_stderr
    local action23b_case_status

    action23b_case_dir=$(mktemp -d)
    action23b_case_stdout="$action23b_case_dir/stdout"
    action23b_case_stderr="$action23b_case_dir/stderr"
    set +e
    ACTION23B_TEST_SSH_BIN="$fake_ssh" \
        ACTION23B_FIXTURE_MODE="$action23b_case_mode" \
        ACTION23B_FIXTURE_DRIVER="$driver" \
        ACTION23B_FIXTURE_LOG="$action23b_case_dir/fake-ssh.log" \
        /bin/bash "$outer" --transport-test \
        >"$action23b_case_stdout" 2>"$action23b_case_stderr"
    action23b_case_status=$?
    set -e

    [[ "$action23b_case_status" -eq "$action23b_case_status_expected" ]]
    grep -Fqx 'fake_ssh_archive_candidate_hash=true' \
        "$action23b_case_dir/fake-ssh.log"
    grep -Fqx 'fake_ssh_remote_boundary=true' \
        "$action23b_case_dir/fake-ssh.log"
    if [[ "$action23b_case_acceptance_expected" == true ]]; then
        grep -Fqx 'action_23b_outer_acceptance=true' "$action23b_case_stdout"
        grep -Fqx 'action_23b_outer_stdout_classification=bounded_safe' \
            "$action23b_case_stdout"
        grep -Fqx 'action_23b_outer_stderr_classification=bounded_safe' \
            "$action23b_case_stdout"
        [[ ! -s "$action23b_case_stderr" ]]
    else
        if grep -Fqx 'action_23b_outer_acceptance=true' "$action23b_case_stdout"; then
            return 1
        fi
        grep -Fqx 'action_23b_outer_acceptance=false' "$action23b_case_stderr"
    fi
    rm -rf -- "$action23b_case_dir"
}

require_true collision_policy run_collision_policy
require_true outer_syntax bash -n "$outer"
require_true driver_syntax bash -n "$driver"
require_true outer_contract "$outer" --contract-test
require_true driver_self_test "$driver" --self-test
require_true readiness_probe_subshell grep -Fq 'run_dns_probe_command() (' "$driver"
require_true readiness_probe_err_trap_disabled grep -Fq 'trap - ERR' "$driver"
# This is an intentional literal production-source contract.
# shellcheck disable=SC2016
require_true readiness_probe_explicit_status grep -Fq \
    'if action23b_probe_output=$(run_dns_probe_command' "$driver"
require_true readiness_probe_no_errexit_toggle test \
    "$(sed -n '/^capture_dns_probe() {/,/^}/p' "$driver" | grep -Ec 'set [+-]e' || true)" -eq 0
require_true candidate_parser_label_visible grep -Fq \
    'run_check candidate_parser validate_shadow_parser' "$driver"
# This is an intentional literal production-source contract.
# shellcheck disable=SC2016
require_true candidate_parser_redirect_internal grep -Fq \
    'unbound-checkconf "$action23b_parser_root" >/dev/null' "$driver"

fixture_root=$(mktemp -d)
readonly fixture_root
fake_ssh="$fixture_root/ssh"
readonly fake_ssh
cleanup() {
    rm -rf -- "$fixture_root"
}
trap cleanup EXIT

cat >"$fake_ssh" <<'FAKE_SSH'
#!/usr/bin/env bash
set -euo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly fixture_mode=${ACTION23B_FIXTURE_MODE:?}
readonly fixture_driver=${ACTION23B_FIXTURE_DRIVER:?}
readonly fixture_log=${ACTION23B_FIXTURE_LOG:?}
fixture_dir=$(mktemp -d)
readonly fixture_dir
trap 'rm -rf -- "$fixture_dir"' EXIT

printf 'fake_ssh_remote_boundary=%s\n' \
    "$(if [[ " $* " == *' pi@10.1.0.53 '* &&
        " $* " == *' HostKeyAlias=pihole0.local.theama.co '* &&
        " $* " == *'cd / && sudo -n /bin/bash -c'* &&
        " $* " == *'/bin/bash'* ]]; then printf true; else printf false; fi)" \
    >>"$fixture_log"
tar -C "$fixture_dir" -xf -
candidate="$fixture_dir/pihole-local-zone.conf"
printf 'fake_ssh_archive_candidate_hash=%s\n' \
    "$(if [[ "$(sha256sum "$candidate" | awk '{ print $1 }')" == \
        b0c6549c1ac5825de7c50e60e5c825cddb51f5d75056f0fd37c196d670886160 ]]; then
        printf true
    else
        printf false
    fi)" >>"$fixture_log"

contract="$fixture_dir/contract"
"$fixture_driver" --contract-transcript >"$contract"
case "$fixture_mode" in
    success)
        cat "$contract"
        ;;
    missing_label)
        sed '/^action_23b_check_uid_is_root=true$/d' "$contract"
        ;;
    duplicate_label)
        cat "$contract"
        printf 'action_23b_check_uid_is_root=true\n'
        ;;
    false_label)
        sed 's/^action_23b_check_uid_is_root=true$/action_23b_check_uid_is_root=false/' \
            "$contract"
        ;;
    stderr)
        cat "$contract"
        printf 'bounded fixture stderr\n' >&2
        ;;
    nonzero)
        cat "$contract"
        exit 1
        ;;
    *)
        exit 98
        ;;
esac
FAKE_SSH
chmod 0700 "$fake_ssh"

require_true success_transport run_transport_case success 0 true
require_true missing_label_rejected run_transport_case missing_label 1 false
require_true duplicate_label_rejected run_transport_case duplicate_label 1 false
require_true false_label_rejected run_transport_case false_label 1 false
require_true stderr_rejected run_transport_case stderr 1 false
require_true nonzero_rejected run_transport_case nonzero 1 false

printf 'action_23b_regression_node_contact=false\n'
printf 'action_23b_regression_live_mutation=false\n'
printf 'action_23b_regression_complete=true\n'
