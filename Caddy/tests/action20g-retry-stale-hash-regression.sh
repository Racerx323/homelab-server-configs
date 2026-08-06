#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_20g_retry_regression
readonly retry_builder_sha256=dfbd052e6e71747e16a7018301740cac3b0db5c04b69b7bc85095e0faf684b8b
readonly source_builder_sha256=b23a75e6bd1b17803f79d2824065c58c7ed7f1b350593d50f6c86469e69929c3
readonly correction_builder_sha256=8171bf8bf9cc881f4939c1589fbae181f95be110c56c4bee596125d1e5f86c5b
readonly retry_probe_sha256=0b0176222c78dad4726c4094f0378b6edb1bc22e6ec2011b2ebebd616ed9626d
readonly retry_runner_sha256=55e465174151ddc40b577fc806079c48c0bcc70ea0e65b89d3f33552ce4f3f3e
readonly source_probe_sha256=aa86451cea27a257ff9b14ca10e774a6189e4859df3fcf9bb1449f889bff54e2
readonly source_runner_sha256=5c7d5b9c3732371b6b3e0b5422b7e1772f723887103f168d827fe1c95cac50a8
readonly correction_installer_sha256=1961680f2591a988af5203744947455080903ce29e8317cfe678d95dffe78b6c
readonly correction_runner_sha256=88398dccf48209f63b5765d47886970269668fc486f3573f13ebabce192146ec
readonly node_a_health_sha256=d1dd8f030fe0a03742ff9c5e0458302cea81ff65a256203f9c07ab5ff022d810
readonly node_b_health_sha256=9bf531ab7cbb047f8f09ce5956b597d5c8b6ede397c166f0b040e2e92fe8bbab

test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
readonly caddy_root=${test_directory%/tests}
readonly retry_builder=$caddy_root/scripts/build-action20g-retry-baseline.sh
readonly source_builder=$caddy_root/scripts/build-dual-node-caddy-postactivation-action20d-retry10-a-retry.sh
readonly correction_builder=$caddy_root/scripts/build-node-b-caddy-health-group-action20g.sh
readonly hash_policy=$test_directory/accepted-live-hash-policy.sh
readonly hash_policy_regression=$test_directory/accepted-live-hash-policy-regression.sh

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }
record_check() {
    local action20g_retry_regression_label=$1

    shift
    if "$@"; then
        printf '%s_check_%s=true\n' "$prefix" "$action20g_retry_regression_label"
        return 0
    fi
    printf '%s_check_%s=false\n' "$prefix" "$action20g_retry_regression_label" >&2
    return 1
}
probe_delta_exact() {
    local action20g_retry_normalized=$regression_root/probe.normalized

    awk -v node_a_hash="$node_a_health_sha256" -v node_b_hash="$node_b_health_sha256" '
        $0 == "readonly prefix=action_20g_retry_baseline_probe" {
            print "readonly prefix=action_20d_retry10_a_retry_probe"
            next
        }
        $0 == "case \"${2:-}\" in" {
            getline first
            getline second
            getline third
            getline fourth
            if (first == "    node-a) readonly health_sha256=" node_a_hash " ;;" &&
                second == "    node-b) readonly health_sha256=" node_b_hash " ;;" &&
                third == "    *) readonly health_sha256=invalid ;;" &&
                fourth == "esac") {
                print "readonly health_sha256=" node_b_hash
                next
            }
            print $0
            print first
            print second
            print third
            print fourth
            next
        }
        { print }
    ' "$retry_probe" >"$action20g_retry_normalized"
    cmp -s "$source_probe" "$action20g_retry_normalized"
}
runner_delta_exact() {
    local action20g_retry_normalized=$regression_root/runner.normalized

    sed -e 's/action_20g_retry_baseline/action_20d_retry10_a_retry/g' \
        -e 's/inspect-dual-node-caddy-postactivation-action20g-retry\.sh/inspect-dual-node-caddy-postactivation-action20d-retry10-a.sh/g' \
        -e "s/readonly probe_sha256=$retry_probe_sha256/readonly probe_sha256=$source_probe_sha256/" \
        "$retry_runner" >"$action20g_retry_normalized"
    cmp -s "$source_runner" "$action20g_retry_normalized"
}

regression_root=$(mktemp -d /tmp/caddy-action20g-retry-regression.XXXXXX)
readonly regression_root
trap 'rm -rf -- "$regression_root"' EXIT
readonly source_root=$regression_root/source
readonly retry_root=$regression_root/retry
readonly correction_root=$regression_root/correction
install -d -m 0700 "$source_root" "$retry_root" "$correction_root"
/bin/bash "$source_builder" --output "$source_root" >"$regression_root/source.stdout"
/bin/bash "$retry_builder" --output "$retry_root" >"$regression_root/retry.stdout"
/bin/bash "$correction_builder" --output "$correction_root" >"$regression_root/correction.stdout"
readonly source_probe=$source_root/inspect-dual-node-caddy-postactivation-action20d-retry10-a.sh
readonly source_runner=$source_root/run-dual-node-caddy-postactivation-action20d-retry10-a.sh
readonly retry_probe=$retry_root/inspect-dual-node-caddy-postactivation-action20g-retry.sh
readonly retry_runner=$retry_root/run-dual-node-caddy-postactivation-action20g-retry.sh
readonly correction_installer=$correction_root/install-node-b-caddy-health-group-action20g.sh
readonly correction_runner=$correction_root/run-node-b-caddy-health-group-correction-action20g.sh

record_check retry_builder_hash test "$(file_hash "$retry_builder")" = "$retry_builder_sha256"
record_check source_builder_hash test "$(file_hash "$source_builder")" = "$source_builder_sha256"
record_check correction_builder_hash test "$(file_hash "$correction_builder")" = "$correction_builder_sha256"
record_check source_probe_hash test "$(file_hash "$source_probe")" = "$source_probe_sha256"
record_check source_runner_hash test "$(file_hash "$source_runner")" = "$source_runner_sha256"
record_check retry_probe_hash test "$(file_hash "$retry_probe")" = "$retry_probe_sha256"
record_check retry_runner_hash test "$(file_hash "$retry_runner")" = "$retry_runner_sha256"
record_check correction_installer_unchanged test "$(file_hash "$correction_installer")" = "$correction_installer_sha256"
record_check correction_runner_unchanged test "$(file_hash "$correction_runner")" = "$correction_runner_sha256"
record_check node_a_hash_exact grep -Fqx \
    "    node-a) readonly health_sha256=$node_a_health_sha256 ;;" "$retry_probe"
record_check node_b_hash_exact grep -Fqx \
    "    node-b) readonly health_sha256=$node_b_health_sha256 ;;" "$retry_probe"
record_check probe_delta_only_health_and_labels probe_delta_exact
record_check runner_delta_only_probe_reference_and_labels runner_delta_exact
record_check retry_probe_self_test /bin/bash "$retry_probe" --self-test
record_check retry_runner_self_test /bin/bash "$retry_runner" --self-test
record_check retry_runner_contract_test /bin/bash "$retry_runner" --contract-test
record_check accepted_live_policy /bin/bash "$hash_policy" --check
record_check accepted_live_policy_regression /bin/bash "$hash_policy_regression"
printf '%s_false_positive_controls=true\n' "$prefix"
printf '%s_false_negative_controls=true\n' "$prefix"
printf '%s_complete=true\n' "$prefix"
