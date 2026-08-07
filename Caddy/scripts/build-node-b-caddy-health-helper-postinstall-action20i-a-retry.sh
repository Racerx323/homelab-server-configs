#!/usr/bin/env bash
# shellcheck disable=SC2016

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_20i_a_retry_builder
readonly source_builder_sha256=ac2e2fd0b285f546fda67996383cb8b8236d20a484cd3b8f98a97c58ee37c479
readonly source_inspector_sha256=e8ed164d0c0372bbd9d1a1c389c435b89e42411b76b68a9e9c185886a4c045c2
readonly source_runner_sha256=1a57bac9d064c99876405a7584b5ec4bcbf3376011a87ff53bea420a9a050c1a
readonly source_regression_sha256=b68bc965d3b8ecf2ac7cd454ee4bcd114688f15da54162e6bc1545554529706a
readonly expected_health_sha256=5cb42ba05b36fecd0c0cf5bc649741661b847e8f8dce94a19288d21874d87fb3
readonly node_b_uid=992
readonly node_b_tls_gid=990
readonly rejected_node_a_uid=993
readonly rejected_node_a_tls_gid=991

script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
readonly source_builder=$script_directory/build-node-b-caddy-health-helper-postinstall-action20i-a.sh

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }
record_check() {
    local action20i_a_retry_builder_label=$1

    shift
    if "$@"; then
        printf '%s_check_%s=true\n' "$prefix" "$action20i_a_retry_builder_label"
        return 0
    fi
    printf '%s_check_%s=false\n' "$prefix" \
        "$action20i_a_retry_builder_label" >&2
    return 1
}
render_regression() {
    local action20i_a_retry_builder_input=$1
    local action20i_a_retry_builder_output=$2

    awk '
        /^work_root=\$\(mktemp/ {
            print "identity_contract() {"
            print "    local action20i_a_retry_identity_source=$1"
            print ""
            print "    grep -Fqx '\''run_assertion keepalived_script_uid_exact test \"$script_uid\" = 992'\'' \"$action20i_a_retry_identity_source\" || return 1"
            print "    grep -Fqx '\''run_assertion caddy_tls_gid_exact test \"$tls_gid\" = 990'\'' \"$action20i_a_retry_identity_source\" || return 1"
            print "    [[ \"$(grep -Fxc '\''run_assertion keepalived_script_uid_exact test \"$script_uid\" = 993'\'' \"$action20i_a_retry_identity_source\" || true)\" -eq 0 ]] || return 1"
            print "    [[ \"$(grep -Fxc '\''run_assertion caddy_tls_gid_exact test \"$tls_gid\" = 991'\'' \"$action20i_a_retry_identity_source\" || true)\" -eq 0 ]] || return 1"
            print "}"
            print "identity_contract_rejected() { ! identity_contract \"$1\"; }"
            print ""
        }
        /^printf '\''%s_false_positive_controls=true/ {
            print "record_check node_b_identity_contract identity_contract \"$inspector\""
            print "uid_fixture=$work_root/node-a-uid-inspector"
            print "sed '\''s/\"$script_uid\" = 992/\"$script_uid\" = 993/'\'' \"$inspector\" >\"$uid_fixture\""
            print "record_check node_a_uid_rejected identity_contract_rejected \"$uid_fixture\""
            print "gid_fixture=$work_root/node-a-gid-inspector"
            print "sed '\''s/\"$tls_gid\" = 990/\"$tls_gid\" = 991/'\'' \"$inspector\" >\"$gid_fixture\""
            print "record_check node_a_gid_rejected identity_contract_rejected \"$gid_fixture\""
        }
        { print }
    ' "$action20i_a_retry_builder_input" >"$action20i_a_retry_builder_output"
}
build() (
    local action20i_a_retry_builder_output_root=$1
    local action20i_a_retry_builder_source_root=$action20i_a_retry_builder_output_root/source
    local action20i_a_retry_builder_inspector=$action20i_a_retry_builder_output_root/scripts/inspect-node-b-caddy-health-helper-postinstall-action20i-a-retry.sh
    local action20i_a_retry_builder_runner_common=$action20i_a_retry_builder_output_root/runner.common
    local action20i_a_retry_builder_runner=$action20i_a_retry_builder_output_root/scripts/run-node-b-caddy-health-helper-postinstall-action20i-a-retry.sh
    local action20i_a_retry_builder_regression_common=$action20i_a_retry_builder_output_root/regression.common
    local action20i_a_retry_builder_regression_stage=$action20i_a_retry_builder_output_root/regression.stage
    local action20i_a_retry_builder_regression=$action20i_a_retry_builder_output_root/tests/action20i-a-retry-postinstall-regression.sh
    local action20i_a_retry_builder_inspector_hash
    local action20i_a_retry_builder_runner_hash

    install -d -m 0700 "$action20i_a_retry_builder_output_root" \
        "$action20i_a_retry_builder_output_root/scripts" \
        "$action20i_a_retry_builder_output_root/tests"
    record_check source_builder_hash test "$(file_hash "$source_builder")" = \
        "$source_builder_sha256" || return 1
    /bin/bash "$source_builder" --output \
        "$action20i_a_retry_builder_source_root" >/dev/null || return 1
    record_check source_inspector_hash test \
        "$(file_hash "$action20i_a_retry_builder_source_root/scripts/inspect-node-b-caddy-health-helper-postinstall-action20i-a.sh")" = \
        "$source_inspector_sha256" || return 1
    record_check source_runner_hash test \
        "$(file_hash "$action20i_a_retry_builder_source_root/scripts/run-node-b-caddy-health-helper-postinstall-action20i-a.sh")" = \
        "$source_runner_sha256" || return 1
    record_check source_regression_hash test \
        "$(file_hash "$action20i_a_retry_builder_source_root/tests/action20i-a-postinstall-regression.sh")" = \
        "$source_regression_sha256" || return 1

    sed \
        -e 's/action_20i_a/action_20i_a_retry/g' \
        -e 's/action20i-a/action20i-a-retry/g' \
        -e "s/\"\$script_uid\" = $rejected_node_a_uid/\"\$script_uid\" = $node_b_uid/" \
        -e "s/\"\$tls_gid\" = $rejected_node_a_tls_gid/\"\$tls_gid\" = $node_b_tls_gid/" \
        "$action20i_a_retry_builder_source_root/scripts/inspect-node-b-caddy-health-helper-postinstall-action20i-a.sh" \
        >"$action20i_a_retry_builder_inspector"
    chmod 0755 "$action20i_a_retry_builder_inspector"
    action20i_a_retry_builder_inspector_hash=$(file_hash \
        "$action20i_a_retry_builder_inspector")

    sed \
        -e 's/action_20i_a/action_20i_a_retry/g' \
        -e 's/action20i-a/action20i-a-retry/g' \
        -e 's/inspect-node-b-caddy-health-helper-postinstall-action20i-a\.sh/inspect-node-b-caddy-health-helper-postinstall-action20i-a-retry.sh/g' \
        -e "s/$source_inspector_sha256/$action20i_a_retry_builder_inspector_hash/g" \
        "$action20i_a_retry_builder_source_root/scripts/run-node-b-caddy-health-helper-postinstall-action20i-a.sh" \
        >"$action20i_a_retry_builder_runner_common"
    mv "$action20i_a_retry_builder_runner_common" \
        "$action20i_a_retry_builder_runner"
    chmod 0755 "$action20i_a_retry_builder_runner"
    action20i_a_retry_builder_runner_hash=$(file_hash \
        "$action20i_a_retry_builder_runner")

    sed \
        -e 's/action_20i_a/action_20i_a_retry/g' \
        -e 's/action20i-a/action20i-a-retry/g' \
        -e 's/inspect-node-b-caddy-health-helper-postinstall-action20i-a\.sh/inspect-node-b-caddy-health-helper-postinstall-action20i-a-retry.sh/g' \
        -e 's/run-node-b-caddy-health-helper-postinstall-action20i-a\.sh/run-node-b-caddy-health-helper-postinstall-action20i-a-retry.sh/g' \
        -e "s/$source_inspector_sha256/$action20i_a_retry_builder_inspector_hash/g" \
        "$action20i_a_retry_builder_source_root/tests/action20i-a-postinstall-regression.sh" \
        >"$action20i_a_retry_builder_regression_common"
    render_regression "$action20i_a_retry_builder_regression_common" \
        "$action20i_a_retry_builder_regression_stage"
    mv "$action20i_a_retry_builder_regression_stage" \
        "$action20i_a_retry_builder_regression"
    chmod 0755 "$action20i_a_retry_builder_regression"
    rm -rf -- "$action20i_a_retry_builder_source_root" \
        "$action20i_a_retry_builder_regression_common"

    record_check inspector_syntax /bin/bash -n \
        "$action20i_a_retry_builder_inspector" || return 1
    record_check runner_syntax /bin/bash -n \
        "$action20i_a_retry_builder_runner" || return 1
    record_check regression_syntax /bin/bash -n \
        "$action20i_a_retry_builder_regression" || return 1
    record_check node_b_uid_exact grep -Fqx \
        'run_assertion keepalived_script_uid_exact test "$script_uid" = 992' \
        "$action20i_a_retry_builder_inspector" || return 1
    record_check node_b_gid_exact grep -Fqx \
        'run_assertion caddy_tls_gid_exact test "$tls_gid" = 990' \
        "$action20i_a_retry_builder_inspector" || return 1
    record_check accepted_health_hash_propagated grep -Fqx \
        "readonly expected_health_sha256=$expected_health_sha256" \
        "$action20i_a_retry_builder_inspector" || return 1
    record_check node_a_uid_absent test \
        "$(grep -Fxc 'run_assertion keepalived_script_uid_exact test "$script_uid" = 993' \
            "$action20i_a_retry_builder_inspector" || true)" -eq 0 || return 1
    record_check node_a_gid_absent test \
        "$(grep -Fxc 'run_assertion caddy_tls_gid_exact test "$tls_gid" = 991' \
            "$action20i_a_retry_builder_inspector" || true)" -eq 0 || return 1
    /bin/bash "$action20i_a_retry_builder_inspector" --self-test >/dev/null || return 1
    /bin/bash "$action20i_a_retry_builder_runner" --self-test >/dev/null || return 1
    /bin/bash "$action20i_a_retry_builder_regression" >/dev/null || return 1
    printf '%s_inspector_sha256=%s\n' "$prefix" \
        "$action20i_a_retry_builder_inspector_hash"
    printf '%s_runner_sha256=%s\n' "$prefix" \
        "$action20i_a_retry_builder_runner_hash"
    printf '%s_regression_sha256=%s\n' "$prefix" \
        "$(file_hash "$action20i_a_retry_builder_regression")"
    printf '%s_complete=true\n' "$prefix"
)

case "${1:-}" in
    --output)
        [[ $# -eq 2 ]] || exit 64
        build "$2"
        ;;
    --self-test)
        [[ $# -eq 1 ]] || exit 64
        test_root=$(mktemp -d /tmp/caddy-action20i-a-retry-builder.XXXXXX)
        readonly test_root
        trap 'rm -rf -- "$test_root"' EXIT
        build "$test_root/output"
        ;;
    *)
        printf 'Usage: %s --output DIRECTORY|--self-test\n' "${0##*/}" >&2
        exit 64
        ;;
esac
