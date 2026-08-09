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
readonly outer="$caddy_root/scripts/run-node-a-unbound-a-records-action23g-outer.sh"
readonly driver="$caddy_root/scripts/apply-node-a-unbound-a-records-action23g.sh"
readonly collision_policy="$script_dir/check-shell-readonly-local-collisions-v2.sh"

require_true() {
    local action23g_regression_label=$1

    shift
    if "$@"; then
        printf 'action_23g_regression_%s=true\n' "$action23g_regression_label"
    else
        printf 'action_23g_regression_%s=false\n' "$action23g_regression_label" >&2
        return 1
    fi
}

run_collision_policy() {
    "$collision_policy" "$0" "$outer" "$driver" >/dev/null
}

run_transport_case() {
    local action23g_case_mode=$1
    local action23g_case_status_expected=$2
    local action23g_case_acceptance_expected=$3
    local action23g_case_dir
    local action23g_case_stdout
    local action23g_case_stderr
    local action23g_case_status

    action23g_case_dir=$(mktemp -d)
    action23g_case_stdout="$action23g_case_dir/stdout"
    action23g_case_stderr="$action23g_case_dir/stderr"
    set +e
    ACTION23G_TEST_SSH_BIN="$fake_ssh" \
        ACTION23G_FIXTURE_MODE="$action23g_case_mode" \
        ACTION23G_FIXTURE_DRIVER="$driver" \
        ACTION23G_FIXTURE_LOG="$action23g_case_dir/fake-ssh.log" \
        /bin/bash "$outer" --transport-test \
        >"$action23g_case_stdout" 2>"$action23g_case_stderr"
    action23g_case_status=$?
    set -e

    [[ "$action23g_case_status" -eq "$action23g_case_status_expected" ]]
    grep -Fqx 'fake_ssh_archive_candidate_hash=true' \
        "$action23g_case_dir/fake-ssh.log"
    grep -Fqx 'fake_ssh_remote_boundary=true' \
        "$action23g_case_dir/fake-ssh.log"
    if [[ "$action23g_case_acceptance_expected" == true ]]; then
        grep -Fqx 'action_23g_outer_acceptance=true' "$action23g_case_stdout"
        grep -Fqx 'action_23g_outer_stdout_classification=bounded_safe' \
            "$action23g_case_stdout"
        grep -Fqx 'action_23g_outer_stderr_classification=bounded_safe' \
            "$action23g_case_stdout"
        [[ ! -s "$action23g_case_stderr" ]]
    else
        if grep -Fqx 'action_23g_outer_acceptance=true' "$action23g_case_stdout"; then
            return 1
        fi
        grep -Fqx 'action_23g_outer_acceptance=false' "$action23g_case_stderr"
    fi
    rm -rf -- "$action23g_case_dir"
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
    'if action23g_probe_output=$(run_dns_probe_command' "$driver"
require_true readiness_probe_no_errexit_toggle test \
    "$(sed -n '/^capture_dns_probe() {/,/^}/p' "$driver" | grep -Ec 'set [+-]e' || true)" -eq 0
require_true candidate_parser_label_visible grep -Fq \
    'run_check candidate_parser validate_shadow_parser' "$driver"
# This is an intentional literal production-source contract.
# shellcheck disable=SC2016
require_true candidate_parser_redirect_internal grep -Fq \
    'unbound-checkconf "$action23g_parser_root" >/dev/null' "$driver"
require_true accepted_ftl_hash_pinned grep -Fqx \
    'readonly accepted_pihole_ftl_sha256=c77de6654c575e12fa1661f8ec901de67d9a623c3e9b965d4e32b550c132a7aa' \
    "$driver"
require_true accepted_ptr_policy_pinned grep -Fq \
    "grep -Fxc 'PIHOLE_PTR=NONE'" "$driver"
require_true rejected_ptr_policy_pinned grep -Fq \
    "grep -Fxc 'PIHOLE_PTR=HOSTNAMEFQDN'" "$driver"
require_true accepted_domain_hash_pinned grep -Fqx \
    'readonly accepted_pihole_domain_sha256=a8305acbc27a9133d6e68e8b1a0fe9a462a975919233d71866d54b2e98810f96' \
    "$driver"
require_true predecessor_driver_invocation_absent test \
    "$(grep -Ec 'apply-node-a-unbound-a-records-action23b|run-node-a-unbound-a-records-action23b' \
        "$driver" || true)" -eq 0
require_true predecessor_outer_invocation_absent test \
    "$(grep -Ec 'apply-node-a-unbound-a-records-action23b|run-node-a-unbound-a-records-action23b' \
        "$outer" || true)" -eq 0

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

readonly fixture_mode=${ACTION23G_FIXTURE_MODE:?}
readonly fixture_driver=${ACTION23G_FIXTURE_DRIVER:?}
readonly fixture_log=${ACTION23G_FIXTURE_LOG:?}
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
        sed '/^action_23g_check_uid_is_root=true$/d' "$contract"
        ;;
    duplicate_label)
        cat "$contract"
        printf 'action_23g_check_uid_is_root=true\n'
        ;;
    false_label)
        sed 's/^action_23g_check_uid_is_root=true$/action_23g_check_uid_is_root=false/' \
            "$contract"
        ;;
    wrong_ftl_hash)
        sed 's/^action_23g_pihole_ftl_sha256=.*/action_23g_pihole_ftl_sha256=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/' \
            "$contract"
        ;;
    wrong_domain_hash)
        sed 's/^action_23g_pihole_domain_sha256=.*/action_23g_pihole_domain_sha256=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb/' \
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
require_true wrong_ftl_hash_rejected run_transport_case wrong_ftl_hash 1 false
require_true wrong_domain_hash_rejected run_transport_case wrong_domain_hash 1 false
require_true stderr_rejected run_transport_case stderr 1 false
require_true nonzero_rejected run_transport_case nonzero 1 false

printf 'action_23g_regression_node_contact=false\n'
printf 'action_23g_regression_live_mutation=false\n'
printf 'action_23g_regression_complete=true\n'
