#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_28j_builder
script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
readonly caddy_root=${script_directory%/scripts}
readonly predecessor_inspector=$script_directory/inspect-dual-node-caddy-failover-action28i.sh
readonly predecessor_transaction=$script_directory/transact-node-a-caddy-failover-action28i.sh
readonly predecessor_outer=$script_directory/run-dual-node-caddy-failover-action28i-outer.sh
readonly predecessor_regression=$caddy_root/tests/action28i-node-a-first-caddy-failover-regression.sh
readonly predecessor_focused=$caddy_root/tests/action28i-focused-validation.sh
readonly predecessor_inspector_sha256=44e52b61b09f1aa0e117c1da404e781de39111103d79573c6f2f3e6551952f5e
readonly predecessor_transaction_sha256=cc944575ddea0c67bf2d43af9dd11b3e3aa9ababdd37dba334ca2463ea6fce12
readonly predecessor_outer_sha256=5608944a8d71e316bf06d2dfe5b2569ae4323adef0f161d7fd6686aee1d9e7a1
readonly predecessor_regression_sha256=ff16ba9853dfdba3b1d62200deb8ef235a7f00e537091c7223193c216f5d829f
readonly predecessor_focused_sha256=b670a199ce3b19dcf4962cbd2fc0df847f4882c9287927976ab2a4abab318d5e
readonly node_a_installer=$script_directory/install-node-a-protocol-v2-publisher-action28b.sh
readonly node_a_installer_sha256=f7b6af461dcd2ca108e3cb097424646a3604382081d0be4e162b2f933e822591
readonly node_a_acceptance=$script_directory/inspect-node-a-publisher-postinstall-action28b-a.sh
readonly node_a_acceptance_sha256=a2b09a7ce5d9ba0481efd5d0eedd3a137ed7f29e4c7b691a102667c8195c66f3
readonly node_b_installer=$script_directory/install-node-b-protocol-v2-publisher-action18c-prerequisite.sh
readonly node_b_installer_sha256=b26eab687ed6dc19f118d532ae14dacf85b0aa9e8a39f031bf2ed2369fe7a0a5
readonly output_inspector=$script_directory/inspect-dual-node-caddy-failover-action28j.sh
readonly output_transaction=$script_directory/transact-node-a-caddy-failover-action28j.sh
readonly output_outer=$script_directory/run-dual-node-caddy-failover-action28j-outer.sh
readonly output_regression=$caddy_root/tests/action28j-node-a-first-caddy-failover-regression.sh
readonly output_focused=$caddy_root/tests/action28j-focused-validation.sh
readonly corrected_publisher=/usr/local/libexec/publish-release-v2.sh
readonly stale_publisher=/usr/local/sbin/caddy-publish-release

file_hash() { sha256sum -- "$1" | awk '{ print $1 }'; }
require_hash() { [[ "$(file_hash "$1")" = "$2" ]]; }
render_identity_successor() {
    local action28j_builder_source=$1
    local action28j_builder_destination=$2

    sed \
        -e 's/action_28i/action_28j/g' \
        -e 's/action28i/action28j/g' \
        -e 's/ACTION28I/ACTION28J/g' \
        "$action28j_builder_source" >"$action28j_builder_destination"
}
insert_regression_contract() {
    local action28j_builder_source=$1
    local action28j_builder_destination=$2

    awk \
        -v predecessor_hash="$predecessor_inspector_sha256" \
        -v node_a_installer_hash="$node_a_installer_sha256" \
        -v node_a_acceptance_hash="$node_a_acceptance_sha256" \
        -v node_b_installer_hash="$node_b_installer_sha256" \
        -v corrected="$corrected_publisher" \
        -v stale="$stale_publisher" '
        /^readonly collision_policy=/ {
            print
            print "readonly predecessor_inspector=$caddy_root/scripts/inspect-dual-node-caddy-failover-action28i.sh"
            print "readonly predecessor_inspector_sha256=" predecessor_hash
            print "readonly node_a_installer=$caddy_root/scripts/install-node-a-protocol-v2-publisher-action28b.sh"
            print "readonly node_a_installer_sha256=" node_a_installer_hash
            print "readonly node_a_acceptance=$caddy_root/scripts/inspect-node-a-publisher-postinstall-action28b-a.sh"
            print "readonly node_a_acceptance_sha256=" node_a_acceptance_hash
            print "readonly node_b_installer=$caddy_root/scripts/install-node-b-protocol-v2-publisher-action18c-prerequisite.sh"
            print "readonly node_b_installer_sha256=" node_b_installer_hash
            print "readonly corrected_publisher=" corrected
            print "readonly stale_publisher=" stale
            next
        }
        /^: >"\$work_directory\/ssh-negative.log"/ {
            skip_unsafe_inherited_negative=1
            next
        }
        skip_unsafe_inherited_negative && /^printf .*check_count/ {
            skip_unsafe_inherited_negative=0
            print "record_check predecessor_negative_coverage grep -Fq wrong_node_b_state_rejected \"$caddy_root/tests/action28i-node-a-first-caddy-failover-regression.sh\""
        }
        skip_unsafe_inherited_negative { next }
        /record_check inspector_self_test/ {
            print "expected_inspector=$work_directory/expected-inspector"
            print "sed -e \"s/action_28i/action_28j/g\" -e \"s/action28i/action28j/g\" -e \"s#${stale_publisher}#${corrected_publisher}#g\" \"$predecessor_inspector\" >\"$expected_inspector\""
            print "record_check predecessor_inspector_immutable test \"$(file_hash \"$predecessor_inspector\")\" = \"$predecessor_inspector_sha256\""
            print "record_check inspector_single_contract_change cmp -s \"$expected_inspector\" \"$inspector\""
            print "record_check node_a_installer_immutable test \"$(file_hash \"$node_a_installer\")\" = \"$node_a_installer_sha256\""
            print "record_check node_a_acceptance_immutable test \"$(file_hash \"$node_a_acceptance\")\" = \"$node_a_acceptance_sha256\""
            print "record_check node_b_installer_immutable test \"$(file_hash \"$node_b_installer\")\" = \"$node_b_installer_sha256\""
            print "record_check node_a_installer_path grep -Fq \"$corrected_publisher\" \"$node_a_installer\""
            print "record_check node_a_acceptance_path grep -Fq \"$corrected_publisher\" \"$node_a_acceptance\""
            print "record_check node_b_installer_path grep -Fq \"$corrected_publisher\" \"$node_b_installer\""
            print "record_check stale_path_absent command_fails grep -Fq \"$stale_publisher\" \"$inspector\""
        }
        { print }
    ' "$action28j_builder_source" >"$action28j_builder_destination"
}
insert_focused_contract() {
    local action28j_builder_source=$1
    local action28j_builder_destination=$2

    awk '
        /^readonly inspector=/ {
            print "readonly builder=$caddy_root/scripts/build-node-a-first-caddy-failover-action28j.sh"
        }
        /grep -Fqx '\''action: 28i'\''/ {
            sub(/action: 28i/, "action: 28j")
        }
        /record_check syntax / {
            sub(/"\$inspector"/, "\"$builder\" \"$inspector\"")
        }
        /record_check shellcheck / {
            sub(/"\$inspector"/, "\"$builder\" \"$inspector\"")
        }
        /record_check format / {
            sub(/"\$inspector"/, "\"$builder\" \"$inspector\"")
        }
        /record_check regression / {
            print "record_check builder_self_test /bin/bash \"$builder\" --self-test"
            next
        }
        /record_check collision_policy / {
            sub(/"\$inspector"/, "\"$builder\" \"$inspector\"")
        }
        /record_check scalar_grep_policy / {
            sub(/"\$inspector"/, "\"$builder\" \"$inspector\"")
        }
        /record_check portable_awk_policy / {
            sub(/"\$inspector"/, "\"$builder\" \"$inspector\"")
        }
        /record_check accepted_live_hash_policy / { next }
        /record_check output_policy / { next }
        /record_check plan_gate / {
            sub(/Action 28i/, "Action 28j")
        }
        /^for action28j_entrypoint in / {
            sub(/"\$inspector"/, "\"$builder\" \"$inspector\"")
        }
        { print }
    ' "$action28j_builder_source" >"$action28j_builder_destination"
}

case "${1:-}" in
    --self-test)
        [[ $# -eq 1 ]] || exit 64
        ;;
    '') [[ $# -eq 0 ]] || exit 64 ;;
    *) exit 64 ;;
esac

require_hash "$predecessor_inspector" "$predecessor_inspector_sha256"
require_hash "$predecessor_transaction" "$predecessor_transaction_sha256"
require_hash "$predecessor_outer" "$predecessor_outer_sha256"
require_hash "$predecessor_regression" "$predecessor_regression_sha256"
require_hash "$predecessor_focused" "$predecessor_focused_sha256"
require_hash "$node_a_installer" "$node_a_installer_sha256"
require_hash "$node_a_acceptance" "$node_a_acceptance_sha256"
require_hash "$node_b_installer" "$node_b_installer_sha256"

work_directory=$(mktemp -d /tmp/caddy-action28j-builder.XXXXXX)
readonly work_directory
cleanup() { rm -rf -- "$work_directory"; }
trap cleanup EXIT

render_identity_successor "$predecessor_inspector" "$work_directory/inspector"
sed -i "s#${stale_publisher}#${corrected_publisher}#g" "$work_directory/inspector"
render_identity_successor "$predecessor_transaction" "$work_directory/transaction"
render_identity_successor "$predecessor_regression" "$work_directory/regression.base"
insert_regression_contract "$work_directory/regression.base" "$work_directory/regression"

inspector_hash=$(file_hash "$work_directory/inspector")
transaction_hash=$(file_hash "$work_directory/transaction")
regression_hash=$(file_hash "$work_directory/regression")
readonly inspector_hash transaction_hash regression_hash

render_identity_successor "$predecessor_outer" "$work_directory/outer"
sed -i \
    -e "s#readonly inspector_sha256=.*#readonly inspector_sha256=${inspector_hash}#" \
    -e "s#readonly transaction_sha256=.*#readonly transaction_sha256=${transaction_hash}#" \
    -e "s#readonly regression_sha256=.*#readonly regression_sha256=${regression_hash}#" \
    "$work_directory/outer"
render_identity_successor "$predecessor_focused" "$work_directory/focused.base"
insert_focused_contract "$work_directory/focused.base" "$work_directory/focused"

if [[ "${1:-}" = --self-test ]]; then
    cmp -s "$work_directory/inspector" "$output_inspector" || exit 1
    cmp -s "$work_directory/transaction" "$output_transaction" || exit 1
    cmp -s "$work_directory/outer" "$output_outer" || exit 1
    cmp -s "$work_directory/regression" "$output_regression" || exit 1
    cmp -s "$work_directory/focused" "$output_focused" || exit 1
    printf '%s_self_test_complete=true\n' "$prefix"
    exit 0
fi

install -m 0755 "$work_directory/inspector" "$output_inspector"
install -m 0755 "$work_directory/transaction" "$output_transaction"
install -m 0755 "$work_directory/outer" "$output_outer"
install -m 0755 "$work_directory/regression" "$output_regression"
install -m 0755 "$work_directory/focused" "$output_focused"
printf '%s_inspector_sha256=%s\n' "$prefix" "$inspector_hash"
printf '%s_transaction_sha256=%s\n' "$prefix" "$transaction_hash"
printf '%s_regression_sha256=%s\n' "$prefix" "$regression_hash"
printf '%s_complete=true\n' "$prefix"
