#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_20f_regression
script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
readonly caddy_root=${script_directory%/tests}
readonly old_template=$caddy_root/templates/keepalived-caddy-ha.conf.in
readonly new_template=$caddy_root/templates/keepalived-caddy-ha-v2.conf.in
readonly installer=$caddy_root/scripts/install-node-a-caddy-health-group-action20f.sh
readonly runner=$caddy_root/scripts/run-node-a-caddy-health-group-correction-action20f.sh
readonly collision_checker=$script_directory/check-shell-readonly-local-collisions-v2.sh

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }
require_gate() {
    local action20f_regression_label=$1

    shift
    if "$@"; then
        printf '%s_%s=true\n' "$prefix" "$action20f_regression_label"
        return 0
    fi
    printf '%s_%s=false\n' "$prefix" "$action20f_regression_label" >&2
    return 1
}
templates_differ_only_by_group() {
    local action20f_regression_root

    action20f_regression_root=$(mktemp -d /tmp/caddy-action20f-template.XXXXXX) || return 1
    sed 's/user keepalived_script caddy-tls/user keepalived_script/' \
        "$new_template" >"$action20f_regression_root/normalized" || return 1
    cmp -s "$old_template" "$action20f_regression_root/normalized" || return 1
    rm -rf -- "$action20f_regression_root"
}
installer_contract_exact() {
    grep -Fq 'user keepalived_script caddy-tls' "$installer" || return 1
    # Dollar-prefixed tokens are matched as literal source text.
    # shellcheck disable=SC2016
    grep -Fq -- '--regid "$action20f_tls_gid" --clear-groups' "$installer" || return 1
    grep -Fq 'environment_metadata' "$installer" || return 1
    grep -Fq 'root:caddy-tls:640' "$installer" || return 1
    grep -Fq 'candidate_context_environment_access' "$installer" || return 1
    grep -Fq 'candidate_context_fullchain_access' "$installer" || return 1
    grep -Fq 'candidate_context_private_key_access' "$installer" || return 1
    grep -Fq 'candidate_context_caddy_validate' "$installer" || return 1
    grep -Fq 'candidate_context_curl' "$installer" || return 1
    grep -Fq 'candidate_context_full_helper' "$installer" || return 1
    grep -Fq 'installed_context_environment_access' "$installer" || return 1
    grep -Fq 'installed_context_full_helper' "$installer" || return 1
    grep -Fq 'keepalived_reloaded=false' "$installer" || return 1
    grep -Fq 'vrrp_transition_requested=false' "$installer" || return 1
    grep -Fq 'vip_mutations=false' "$installer" || return 1
    grep -Fq 'node_b_contacted=false' "$installer" || return 1
    grep -Fq 'action20f-node-a-health-group.XXXXXX' "$installer" || return 1
}
forbidden_activation_absent() {
    ! grep -Eq \
        'systemctl[[:space:]]+(reload|restart|start|stop|enable|disable)|keepalived[[:space:]]+--|ip[[:space:]].*address[[:space:]]+(add|delete|del|replace)' \
        "$installer" "$runner" || return 1
}
ssh() {
    local action20f_intercept_mode=${ACTION20F_INTERCEPT_MODE:-valid}

    cat >/dev/null
    printf 'ssh\n' >>"$ACTION20F_INTERCEPT_COUNT"
    case "$action20f_intercept_mode" in
        valid)
            /bin/bash "$ACTION20F_TEST_INSTALLER" --success-fixture
            ;;
        missing)
            /bin/bash "$ACTION20F_TEST_INSTALLER" --success-fixture |
                sed '/^action_20f_check_identity_root=true$/d'
            ;;
        duplicate)
            /bin/bash "$ACTION20F_TEST_INSTALLER" --success-fixture
            printf 'action_20f_check_identity_root=true\n'
            ;;
        false)
            /bin/bash "$ACTION20F_TEST_INSTALLER" --success-fixture |
                sed 's/^action_20f_check_identity_root=true$/action_20f_check_identity_root=false/'
            ;;
        *) return 64 ;;
    esac
}
export -f ssh

case "${1:-}" in
    --self-test)
        [[ $# -eq 1 ]] || exit 64
        require_gate template_hash_exact test \
            "$(file_hash "$new_template")" = af384fc989eaf6581579ace9f09477d23c6612618fb8eca194c37db890992779
        require_gate installer_hash_exact test \
            "$(file_hash "$installer")" = 186dc4cc62e96bf2387e84fb4714618ebd57d31535181d17e46e1a69e76e59d0
        require_gate runner_hash_exact test \
            "$(file_hash "$runner")" = f5aca1865ce91f6c80c46f807aa3517e3f37b92715f9b41ff48ec49bc491779b
        require_gate sources_syntax /bin/bash -n "$installer" "$runner" "$0"
        require_gate sources_shellcheck shellcheck "$installer" "$runner" "$0"
        require_gate collision_policy /bin/bash "$collision_checker" \
            "$installer" "$runner" "$0"
        require_gate exact_template_delta templates_differ_only_by_group
        require_gate installer_contract installer_contract_exact
        require_gate forbidden_activation_absent forbidden_activation_absent
        require_gate exact_check_count test \
            "$(/bin/bash "$installer" --expected-checks | wc -l)" -eq 94
        require_gate exact_check_labels_unique test \
            "$(/bin/bash "$installer" --expected-checks | LC_ALL=C sort -u | wc -l)" -eq 94
        require_gate installer_self_test /bin/bash "$installer" --self-test
        require_gate runner_self_test /bin/bash "$runner" --self-test
        require_gate runner_contract_test /bin/bash "$runner" --contract-test
        printf '%s_self_test_complete=true\n' "$prefix"
        exit 0
        ;;
    "") [[ $# -eq 0 ]] || exit 64 ;;
    *)
        printf 'Usage: %s [--self-test]\n' "${0##*/}" >&2
        exit 64
        ;;
esac

work_directory=$(mktemp -d /tmp/caddy-action20f-regression.XXXXXX)
readonly work_directory
trap 'rm -rf -- "$work_directory"' EXIT
export ACTION20F_TEST_INSTALLER=$installer
export ACTION20F_INTERCEPT_COUNT=$work_directory/ssh.count
: >"$ACTION20F_INTERCEPT_COUNT"

valid_status=0
CADDY_ACTION20F_SSH_BINARY=ssh ACTION20F_INTERCEPT_MODE=valid \
    /bin/bash "$runner" >"$work_directory/valid.stdout" \
    2>"$work_directory/valid.stderr" || valid_status=$?
require_gate valid_production_path_status_zero test "$valid_status" -eq 0
require_gate valid_production_path_stderr_empty test ! -s "$work_directory/valid.stderr"
require_gate valid_production_path_accepted grep -Fxq \
    'action_20f_remote_status=0' "$work_directory/valid.stdout"

for negative_mode in missing duplicate false; do
    negative_status=0
    CADDY_ACTION20F_SSH_BINARY=ssh ACTION20F_INTERCEPT_MODE=$negative_mode \
        /bin/bash "$runner" >"$work_directory/$negative_mode.stdout" \
        2>"$work_directory/$negative_mode.stderr" || negative_status=$?
    require_gate "false_positive_${negative_mode}_rejected" test \
        "$negative_status" -ne 0
done
require_gate false_negative_valid_contract_accepted test "$valid_status" -eq 0
require_gate intercepted_ssh_count_exact test \
    "$(wc -l <"$ACTION20F_INTERCEPT_COUNT")" -eq 4
printf '%s_node_contact=false\n' "$prefix"
printf '%s_complete=true\n' "$prefix"
