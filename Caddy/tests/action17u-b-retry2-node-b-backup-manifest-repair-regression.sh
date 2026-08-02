#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

retry2_test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly retry2_test_directory
retry2_caddy_root=$(cd -- "$retry2_test_directory/.." && pwd)
readonly retry2_caddy_root
readonly historical_transaction="$retry2_caddy_root/scripts/repair-node-b-action17u-backup-manifest-action17u-b.sh"
readonly historical_runner="$retry2_caddy_root/scripts/run-node-b-action17u-backup-manifest-repair-action17u-b-retry.sh"
readonly historical_regression="$retry2_test_directory/action17u-b-retry-node-b-backup-manifest-repair-regression.sh"
readonly correction="$retry2_caddy_root/scripts/correct-node-b-action17u-backup-manifest-hostname-action17u-b-retry2.sh"
readonly collision_checker="$retry2_test_directory/check-shell-readonly-local-collisions-v2.sh"
readonly historical_transaction_sha256=c47653c285e7e3db98ed22b163c7f741d781f9d27f6c8feb1293bb70706eb0de
readonly historical_runner_sha256=19df3282a29ec49fa35f13afdf69a7a2231cac0b8e5e3ae9d5917c71e3a678e5
readonly historical_regression_sha256=a1f95ca15de2f94d00c2982172788d9930f5fa86c8e8032364390bce15b8378a
readonly correction_sha256=842a5a2ab1f54715a8f6f0e9c5b527ff3c6c080ed7094f2677cc604b67b616b7
readonly corrected_transaction_sha256=f92ccbff329c2f6dff015bde47cc13fc3a146549faa69ca5a67619968d9df0d3
readonly corrected_inner_runner_sha256=e3390939cda6a4021701360ae6b43e4d9d77f146211d9cc8217cc0e9188aad0a

retry2_cleanup_directory=

# Preserve the exact failing production-regression boundary before cleanup.
report_retry2_regression_error() {
    local regression_error_status=$?
    local regression_error_line=${BASH_LINENO[0]:-unknown}

    printf 'action_17u_b_retry2_regression_error_line=%s\n' \
        "$regression_error_line" >&2
    printf 'action_17u_b_retry2_regression_error_status=%s\n' \
        "$regression_error_status" >&2
    return "$regression_error_status"
}
trap report_retry2_regression_error ERR

# Invoked indirectly by the EXIT trap installed immediately after mktemp.
# shellcheck disable=SC2317
cleanup_retry2_test_directory() {
    local cleanup_status=$?

    trap - EXIT
    if [[ -n "$retry2_cleanup_directory" &&
        -d "$retry2_cleanup_directory" ]]; then
        rm -rf -- "$retry2_cleanup_directory"
    fi
    exit "$cleanup_status"
}

file_hash() {
    sha256sum "$1" | awk '{ print $1 }'
}

verify_immutable_sources() {
    [[ "$(file_hash "$historical_transaction")" == "$historical_transaction_sha256" ]] || return 1
    [[ "$(file_hash "$historical_runner")" == "$historical_runner_sha256" ]] || return 1
    [[ "$(file_hash "$historical_regression")" == "$historical_regression_sha256" ]] || return 1
    [[ "$(file_hash "$correction")" == "$correction_sha256" ]] || return 1
}

write_fake_ssh() {
    local fake_ssh_path=$1

    # The quoted variables are evaluated only by the intercepted regression.
    # shellcheck disable=SC2016
    printf '%s\n' \
        '#!/usr/bin/env bash' \
        'set -Eeuo pipefail' \
        'umask 077' \
        'cat >"$ACTION17UB_RETRY2_STDIN"' \
        'printf "%s\n" "$@" >"$ACTION17UB_RETRY2_ARGUMENTS"' \
        'if [[ "$ACTION17UB_RETRY2_MODE" == fixture ]]; then' \
        '    cat -- "$ACTION17UB_RETRY2_FIXTURE_STDOUT"' \
        '    cat -- "$ACTION17UB_RETRY2_FIXTURE_STDERR" >&2' \
        '    exit "$ACTION17UB_RETRY2_FIXTURE_STATUS"' \
        'fi' \
        'awk '\''/^require_check effective_uid_root / { selected=1 } selected { print } /^require_check architecture_arm64 / { exit }'\'' "$ACTION17UB_RETRY2_STDIN" >"$ACTION17UB_RETRY2_PREFIX"' \
        '[[ "$(wc -l <"$ACTION17UB_RETRY2_PREFIX")" -eq 4 ]]' \
        'require_check() {' \
        '    local assertion_name=$1' \
        '    shift' \
        '    if "$@"; then' \
        '        printf "action_17u_b_assertion_%s=true\n" "$assertion_name"' \
        '    else' \
        '        printf "action_17u_b_assertion_%s=false\n" "$assertion_name" >&2' \
        '        return 1' \
        '    fi' \
        '}' \
        'id() { printf "0\n"; }' \
        'hostname() { printf "%s\n" "$ACTION17UB_RETRY2_HOSTNAME"; }' \
        'dpkg() { printf "arm64\n"; }' \
        'cd /' \
        'source "$ACTION17UB_RETRY2_PREFIX"' \
        'exit 1' >"$fake_ssh_path"
    chmod 0755 "$fake_ssh_path"
}

render_production_tree() {
    local render_root=$1
    local rendered_scripts="$render_root/Caddy/scripts"
    local rendered_tests="$render_root/Caddy/tests"

    install -d -m 0700 "$rendered_scripts" "$rendered_tests"
    "$correction" --render-transaction "$historical_transaction" \
        >"$rendered_scripts/${historical_transaction##*/}"
    "$correction" --render-runner "$historical_runner" \
        >"$rendered_scripts/run-node-b-action17u-backup-manifest-repair-action17u-b-retry2.sh"
    install -m 0755 -- "$collision_checker" "$rendered_tests/${collision_checker##*/}"
    chmod 0755 "$rendered_scripts/"*
    [[ "$(file_hash "$rendered_scripts/${historical_transaction##*/}")" == "$corrected_transaction_sha256" ]]
    [[ "$(file_hash "$rendered_scripts/run-node-b-action17u-backup-manifest-repair-action17u-b-retry2.sh")" == "$corrected_inner_runner_sha256" ]]
}

run_prefix_case() {
    local case_name=$1
    local case_hostname=$2
    local case_root=$3
    local case_runner=$4
    local case_status=0

    (
        cd /home/aaron/code/homelab-server-configs
        ACTION17UB_RETRY2_ARGUMENTS="$case_root/$case_name.arguments" \
            ACTION17UB_RETRY2_HOSTNAME="$case_hostname" \
            ACTION17UB_RETRY2_MODE=prefix \
            ACTION17UB_RETRY2_PREFIX="$case_root/$case_name.prefix" \
            ACTION17UB_RETRY2_STDIN="$case_root/$case_name.stdin" \
            "$case_runner"
    ) >"$case_root/$case_name.stdout" 2>"$case_root/$case_name.stderr" ||
        case_status=$?
    printf '%s\n' "$case_status"
}

production_prefix_regression() {
    local prefix_test_root
    local production_root
    local rendered_runner
    local fake_bin
    local corrected_status
    local historical_value_status

    prefix_test_root=$(mktemp -d /tmp/caddy-action17u-b-retry2-prefix.XXXXXX)
    retry2_cleanup_directory=$prefix_test_root
    trap cleanup_retry2_test_directory EXIT
    production_root="$prefix_test_root/production"
    fake_bin="$prefix_test_root/bin"
    install -d -m 0700 "$fake_bin"
    render_production_tree "$production_root"
    rendered_runner="$production_root/Caddy/scripts/run-node-b-action17u-backup-manifest-repair-action17u-b-retry2.sh"
    sed -i "s|^PATH=/usr/bin:/bin$|PATH=$fake_bin:/usr/bin:/bin|" "$rendered_runner"
    write_fake_ssh "$fake_bin/ssh"

    corrected_status=$(run_prefix_case corrected j1-svpihole00 \
        "$prefix_test_root" "$rendered_runner")
    [[ "$corrected_status" -eq 97 ]]
    grep -Fxq action_17u_b_assertion_effective_uid_root=true \
        "$prefix_test_root/corrected.stdout"
    grep -Fxq action_17u_b_assertion_working_directory_root=true \
        "$prefix_test_root/corrected.stdout"
    grep -Fxq action_17u_b_assertion_hostname_node_b=true \
        "$prefix_test_root/corrected.stdout"
    grep -Fxq action_17u_b_assertion_architecture_arm64=true \
        "$prefix_test_root/corrected.stdout"
    if grep -Eq '^action_17u_b_assertion_[a-z0-9_]+=false$' \
        "$prefix_test_root/corrected.stdout" "$prefix_test_root/corrected.stderr"; then
        return 1
    fi
    [[ "$(file_hash "$prefix_test_root/corrected.stdin")" == "$corrected_transaction_sha256" ]]
    grep -Fxq 'cd / && sudo -n /bin/bash -s --' \
        "$prefix_test_root/corrected.arguments"

    historical_value_status=$(run_prefix_case historical-value pihole00 \
        "$prefix_test_root" "$rendered_runner")
    [[ "$historical_value_status" -eq 1 ]]
    grep -Fxq action_17u_b_assertion_hostname_node_b=false \
        "$prefix_test_root/historical-value.stdout"
    if grep -Fq action_17u_b_assertion_architecture_arm64=true \
        "$prefix_test_root/historical-value.stdout"; then
        return 1
    fi

    [[ -z "$(find /tmp -mindepth 1 -maxdepth 1 -type d \
        -name 'caddy-action17u-b-retry2-runner.*' -print -quit)" ]]
    rm -rf -- "$prefix_test_root"
    retry2_cleanup_directory=
    trap - EXIT
    printf 'action_17u_b_retry2_corrected_hostname_prefix_passed=true\n'
    printf 'action_17u_b_retry2_historical_hostname_prefix_rejected=true\n'
    printf 'action_17u_b_retry2_architecture_boundary_exercised=true\n'
    printf 'action_17u_b_retry2_production_path_network_contact=false\n'
}

container_projection_regression() {
    local projection_root
    local projection_transaction
    local hostname_line
    local architecture_line

    projection_root=$(mktemp -d /tmp/caddy-action17u-b-retry2-container.XXXXXX)
    retry2_cleanup_directory=$projection_root
    trap cleanup_retry2_test_directory EXIT
    render_production_tree "$projection_root/production"
    projection_transaction="$projection_root/production/Caddy/scripts/${historical_transaction##*/}"
    # Match literal production command substitutions in the rendered source.
    # shellcheck disable=SC2016
    hostname_line=$(grep -nFx \
        'require_check hostname_node_b test "$(hostname -s)" = j1-svpihole00' \
        "$projection_transaction" | cut -d: -f1)
    # shellcheck disable=SC2016
    architecture_line=$(grep -nFx \
        'require_check architecture_arm64 test "$(dpkg --print-architecture)" = arm64' \
        "$projection_transaction" | cut -d: -f1)
    [[ "$hostname_line" =~ ^[0-9]+$ && "$architecture_line" =~ ^[0-9]+$ ]]
    [[ "$architecture_line" -eq $((hostname_line + 1)) ]]
    rm -rf -- "$projection_root"
    retry2_cleanup_directory=
    trap - EXIT
    printf 'action_17u_b_retry2_container_projection_validated=true\n'
}

if [[ "${1:-}" == --self-test && $# -eq 1 ]]; then
    verify_immutable_sources
    "$correction" --self-test >/dev/null
    printf 'action_17u_b_retry2_regression_self_test_complete=true\n'
    exit 0
elif [[ "${1:-}" == --production-test && $# -eq 1 ]]; then
    verify_immutable_sources
    "$correction" --self-test >/dev/null
    if [[ "${CADDY_VALIDATION_CONTAINER:-}" == 1 ]]; then
        container_projection_regression
    else
        production_prefix_regression
    fi
    exit 0
elif (($#)); then
    printf 'Usage: %s [--self-test|--production-test]\n' "${0##*/}" >&2
    exit 64
fi

verify_immutable_sources
"$correction" --self-test >/dev/null
if [[ "${CADDY_VALIDATION_CONTAINER:-}" == 1 ]]; then
    container_projection_regression
else
    production_prefix_regression
fi
printf 'Action 17u-b retry2 hostname correction regression passed.\n'
