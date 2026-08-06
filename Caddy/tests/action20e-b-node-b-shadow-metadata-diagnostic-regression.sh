#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
readonly caddy_root=${test_directory%/tests}
readonly inspector=$caddy_root/scripts/inspect-node-b-runtime-shadow-metadata-action20e-b.sh
readonly runner=$caddy_root/scripts/run-node-b-runtime-shadow-metadata-diagnostic-action20e-b.sh
readonly expected_inspector_sha256=d983cf111b54d8e62a25b55f62c5e2e74423b42fc8a2cfc1de8e4dfb95b1881a
readonly expected_runner_sha256=466c1d14a92b41c5e77383cc929074356470eb00e4f7f109be38af068b7936c0
readonly collision_checker=$test_directory/check-shell-readonly-local-collisions-v2.sh
readonly conditional_policy=$test_directory/conditional-validator-errexit-policy-regression.sh

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }
require_one() {
    local expected_line=$1
    local inspected_path=$2

    [[ "$(grep -Fxc "$expected_line" "$inspected_path")" -eq 1 ]]
}

regression_root=$(mktemp -d /tmp/caddy-action20e-b-regression.XXXXXX)
readonly regression_root
cleanup() {
    # shellcheck disable=SC2317
    rm -rf -- "$regression_root"
}
trap cleanup EXIT
reproduction_root=$(mktemp -d /tmp/caddy-action20e-b-reproduction.XXXXXX)
readonly reproduction_root
trap 'rm -rf -- "$regression_root" "$reproduction_root"' EXIT
readonly reproduction_stdout=$regression_root/reproduction.stdout
readonly fake_ssh=$regression_root/ssh
readonly runner_stdout=$regression_root/runner.stdout
readonly runner_stderr=$regression_root/runner.stderr

[[ "$(file_hash "$inspector")" = "$expected_inspector_sha256" ]]
[[ "$(file_hash "$runner")" = "$expected_runner_sha256" ]]
/bin/bash -n "$inspector" "$runner"
shellcheck "$inspector" "$runner"
/bin/bash "$collision_checker" "$0" "$inspector" "$runner" >/dev/null
/bin/bash "$conditional_policy" >/dev/null
/bin/bash "$inspector" --self-test >/dev/null
/bin/bash "$runner" --self-test >/dev/null
/bin/bash "$runner" --contract-test >/dev/null

/bin/bash "$inspector" --reproduction-test "$reproduction_root" \
    >"$reproduction_stdout"
current_identity=$(id -un):$(id -gn)
readonly current_identity
require_one "action_20e_b_reproduction_test_root=${current_identity}:755" \
    "$reproduction_stdout"
require_one "action_20e_b_reproduction_test_etc=${current_identity}:755" \
    "$reproduction_stdout"
require_one "action_20e_b_reproduction_test_leaf=${current_identity}:700" \
    "$reproduction_stdout"
require_one \
    'action_20e_b_reproduction_test_classification=intermediate_parents_default_0755' \
    "$reproduction_stdout"

cat >"$fake_ssh" <<'FAKE_SSH'
#!/usr/bin/env bash
set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH
readonly payload=$(mktemp /tmp/caddy-action20e-b-fake-payload.XXXXXX)
trap 'rm -f -- "$payload"' EXIT
cat >"$payload"
[[ "$(sha256sum "$payload" | awk '{ print $1 }')" = "$CADDY_ACTION20EB_INSPECTOR_SHA256" ]]
[[ " $* " == *' -T '* ]]
[[ " $* " == *' HostKeyAlias=pihole00.local.theama.co '* ]]
[[ " $* " == *' pi@10.1.0.54 '* ]]
[[ "${*: -1}" = 'cd / && sudo -n /bin/bash -s --' ]]
expected_count=$(/bin/bash "$CADDY_ACTION20EB_INSPECTOR" --expected-assertions | wc -l)
while IFS= read -r assertion_label; do
    printf 'action_20e_b_assertion_%s=true\n' "$assertion_label"
done < <(/bin/bash "$CADDY_ACTION20EB_INSPECTOR" --expected-assertions)
state_hash=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
printf '%s\n' \
    "action_20e_b_value_before_state_sha256=$state_hash" \
    "action_20e_b_value_after_state_sha256=$state_hash" \
    'action_20e_b_value_expected_shadow_root_metadata=root:root:700' \
    'action_20e_b_value_observed_shadow_root_symbolic=root:root:755' \
    'action_20e_b_value_observed_shadow_root_numeric=0:0:755' \
    'action_20e_b_value_observed_shadow_etc_symbolic=root:root:755' \
    'action_20e_b_value_observed_shadow_etc_numeric=0:0:755' \
    'action_20e_b_value_observed_shadow_tmpfiles_symbolic=root:root:700' \
    'action_20e_b_value_observed_shadow_tmpfiles_numeric=0:0:700' \
    'action_20e_b_value_reproduction_classification=intermediate_parents_default_0755' \
    "action_20e_b_assertion_count=$expected_count" \
    'action_20e_b_failed_assertion_count=0' \
    'action_20e_b_first_failure=none' \
    'action_20e_b_node_a_contacted=false' \
    'action_20e_b_systemd_tmpfiles_invoked=false' \
    'action_20e_b_transient_filesystem_activity=true' \
    'action_20e_b_persistent_filesystem_mutations=false' \
    'action_20e_b_service_mutations=false' \
    'action_20e_b_keepalived_service_mutations=false' \
    'action_20e_b_notifier_invoked=false' \
    'action_20e_b_vrrp_mutations=false' \
    'action_20e_b_vip_mutations=false' \
    'action_20e_b_remote_complete=true'
FAKE_SSH
chmod 0700 "$fake_ssh"
: >"$runner_stdout"
: >"$runner_stderr"
CADDY_ACTION20EB_INTERCEPTED_TEST=1 \
    CADDY_ACTION20EB_SSH_BINARY="$fake_ssh" \
    CADDY_ACTION20EB_INSPECTOR="$inspector" \
    CADDY_ACTION20EB_INSPECTOR_SHA256="$expected_inspector_sha256" \
    /bin/bash "$runner" >"$runner_stdout" 2>"$runner_stderr"
[[ ! -s "$runner_stderr" ]]
require_one 'action_20e_b_remote_stream_classification=bounded_safe' "$runner_stdout"
require_one 'action_20e_b_remote_status=0' "$runner_stdout"
require_one 'action_20e_b_validation_status=0' "$runner_stdout"
require_one 'action_20e_b_runner_cleanup_complete=true' "$runner_stdout"
printf 'action_20e_b_regression_complete=true\n'
