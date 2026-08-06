#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_20d_c_regression
readonly probe_sha256=defff2a76889c084b9903c2012b3fe16fdb8dd581882e4acb7dd62d6f625524d
readonly runner_sha256=a492843c8439339a95cc996c437a2dfc7ce7710057940cf82b7dcde25ffad77c

test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
readonly caddy_root=${test_directory%/tests}
readonly repository_root=${caddy_root%/Caddy}
readonly probe="$caddy_root/scripts/inspect-caddy-notifier-context-action20d-c.sh"
readonly runner="$caddy_root/scripts/run-dual-node-caddy-notifier-context-action20d-c.sh"

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
write_fixture() {
    local fixture_role=$1
    local fixture_dns_count=$2
    local fixture_path=$3
    local fixture_label
    local fixture_hash=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa

    {
        while IFS= read -r fixture_label; do
            printf 'action_20d_c_probe_assertion_%s=true\n' "$fixture_label"
        done < <("$probe" --expected-assertions)
        printf '%s\n' \
            "action_20d_c_probe_value_node_role=$fixture_role" \
            'action_20d_c_probe_value_inherited_execution_user=pi' \
            'action_20d_c_probe_value_state_directory_metadata=pi:pi:750' \
            'action_20d_c_probe_value_dedupe_directory_metadata=pi:pi:750' \
            'action_20d_c_probe_value_caddy_ipv4_vip_count=0' \
            'action_20d_c_probe_value_caddy_ipv6_vip_count=0' \
            "action_20d_c_probe_value_dns_ipv4_vip_count=$fixture_dns_count" \
            "action_20d_c_probe_value_dns_ipv6_vip_count=$fixture_dns_count" \
            "action_20d_c_probe_value_before_snapshot_sha256=$fixture_hash" \
            "action_20d_c_probe_value_after_snapshot_sha256=$fixture_hash" \
            "action_20d_c_probe_assertion_count=$("$probe" --expected-assertions | wc -l)" \
            'action_20d_c_probe_failed_assertion_count=0' \
            'action_20d_c_probe_first_failure=none' \
            'action_20d_c_probe_notification_helper_invoked=false' \
            'action_20d_c_probe_filesystem_mutations=false' \
            'action_20d_c_probe_service_mutations=false' \
            'action_20d_c_probe_keepalived_mutations=false' \
            'action_20d_c_probe_vrrp_mutations=false' \
            'action_20d_c_probe_vip_mutations=false' \
            'action_20d_c_probe_network_mutations=false' \
            'action_20d_c_probe_persistent_mutations=false' \
            'action_20d_c_probe_remote_complete=true'
    } >"$fixture_path"
}
run_case() {
    local case_root=$1
    local case_corruption=$2
    local expected_status=$3
    local observed_status=0
    local fake_ssh=$case_root/fake-ssh

    install -d -m 0700 "$case_root"
    write_fixture node-a 1 "$case_root/node-a.fixture"
    write_fixture node-b 0 "$case_root/node-b.fixture"
    case "$case_corruption" in
        none) ;;
        node-a-directory-false)
            sed -i \
                's/action_20d_c_probe_assertion_state_directory_writable_as_pi=true/action_20d_c_probe_assertion_state_directory_writable_as_pi=false/; s/action_20d_c_probe_failed_assertion_count=0/action_20d_c_probe_failed_assertion_count=1/; s/action_20d_c_probe_first_failure=none/action_20d_c_probe_first_failure=state_directory_writable_as_pi/' \
                "$case_root/node-a.fixture"
            ;;
        node-b-missing-label)
            sed -i '/action_20d_c_probe_assertion_dedupe_directory_searchable_as_pi=/d' \
                "$case_root/node-b.fixture"
            ;;
        *) return 1 ;;
    esac
    cat >"$fake_ssh" <<'FAKE_SSH'
#!/usr/bin/env bash
set -Eeuo pipefail
cat >"${ACTION20DC_STDIN_CAPTURE:?}"
printf '%s\n' "$*" >>"${ACTION20DC_SSH_ARGS_CAPTURE:?}"
case "$*" in
    *pi@10.1.0.53*) cat "${ACTION20DC_NODE_A_FIXTURE:?}" ;;
    *pi@10.1.0.54*) cat "${ACTION20DC_NODE_B_FIXTURE:?}" ;;
    *) exit 64 ;;
esac
FAKE_SSH
    chmod 0700 "$fake_ssh"
    : >"$case_root/ssh.args"
    (
        cd "$repository_root" || exit 1
        CADDY_ACTION20DC_SSH_BINARY="$fake_ssh" \
            ACTION20DC_NODE_A_FIXTURE="$case_root/node-a.fixture" \
            ACTION20DC_NODE_B_FIXTURE="$case_root/node-b.fixture" \
            ACTION20DC_STDIN_CAPTURE="$case_root/stdin" \
            ACTION20DC_SSH_ARGS_CAPTURE="$case_root/ssh.args" \
            /bin/bash "$runner"
    ) >"$case_root/stdout" 2>"$case_root/stderr" || observed_status=$?
    [[ "$observed_status" -eq "$expected_status" ]] || return 1
    [[ ! -s "$case_root/stderr" ]] || return 1
    [[ "$(wc -l <"$case_root/ssh.args")" -eq 2 ]] || return 1
    grep -Fqx -- '-T -o BatchMode=yes -o IdentitiesOnly=no -o StrictHostKeyChecking=yes -o HostKeyAlias=pihole0.local.theama.co -o ConnectTimeout=10 -o ConnectionAttempts=1 -o LogLevel=ERROR pi@10.1.0.53 cd / && sudo -n /bin/bash -s -- --node node-a' "$case_root/ssh.args" || return 1
    grep -Fqx -- '-T -o BatchMode=yes -o IdentitiesOnly=no -o StrictHostKeyChecking=yes -o HostKeyAlias=pihole00.local.theama.co -o ConnectTimeout=10 -o ConnectionAttempts=1 -o LogLevel=ERROR pi@10.1.0.54 cd / && sudo -n /bin/bash -s -- --node node-b' "$case_root/ssh.args" || return 1
    cmp -s "$probe" "$case_root/stdin" || return 1
    grep -Fq 'action_20d_c_node_a_stdout_classification=bounded_safe' "$case_root/stdout" || return 1
    grep -Fq 'action_20d_c_node_b_stdout_classification=bounded_safe' "$case_root/stdout" || return 1
    grep -Fq 'action_20d_c_notification_helper_invoked=false' "$case_root/stdout" || return 1
}
source_contract() {
    [[ "$(file_hash "$probe")" = "$probe_sha256" ]] || return 1
    [[ "$(file_hash "$runner")" = "$runner_sha256" ]] || return 1
    grep -Fq 'readonly execution_user=pi' "$probe" || return 1
    grep -Fq 'readonly state_directory=/run/caddy-ha' "$probe" || return 1
    grep -Fq 'readonly dedupe_directory=/run/caddy-ha-notify' "$probe" || return 1
    # These patterns intentionally match literal variable references.
    # shellcheck disable=SC2016
    grep -Fq 'run_assertion state_directory_writable_as_pi runuser -u "$execution_user" -- test -w "$state_directory"' "$probe" || return 1
    # shellcheck disable=SC2016
    grep -Fq 'run_assertion dedupe_directory_writable_as_pi runuser -u "$execution_user" -- test -w "$dedupe_directory"' "$probe" || return 1
    # shellcheck disable=SC2016
    ! grep -Eq '^run_assertion [a-z0-9_]+ runuser .*-- "\$notification_script"' \
        "$probe" || return 1
    grep -Fq 'cd / && sudo -n /bin/bash -s -- --node ' "$runner" || return 1
}

work_directory=$(mktemp -d /tmp/caddy-action20d-c-regression.XXXXXX)
readonly work_directory
trap 'rm -rf -- "$work_directory"' EXIT
require_gate source_contract source_contract
require_gate valid_production_path run_case "$work_directory/valid" none 0
require_gate false_result_rejected_and_node_b_preserved run_case \
    "$work_directory/false-result" node-a-directory-false 1
require_gate missing_label_rejected run_case \
    "$work_directory/missing-label" node-b-missing-label 1
printf '%s_complete=true\n' "$prefix"
