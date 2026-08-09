#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH
readonly PATH

readonly prefix=action_23d_focused_validation
readonly builder_sha256=c7f12484c0b022583c4573728f60bea87e1fb94cc7679d569acf3fdc51adb644
readonly driver_sha256=dd2f8ee4ebb3d4077622059cdb658c98353796c95b83e4df44e53701702cc0ef
readonly outer_sha256=cb0f6c291e889eaa33c64c7af1bb56bab09fb35b4e80e442f18d3f01001e9488
readonly regression_sha256=803a80c9476302c34d95e8c263016a172129cc5e7c89ca77783613ecf8c3049b
readonly manifest_sha256=063607fde0728eb82a1aeb1eac970ac1a43cd09ba0c002075a31980e47a9e18a

test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
caddy_root=${test_directory%/tests}
readonly caddy_root
repository_root=${caddy_root%/Caddy}
readonly repository_root
readonly builder=$caddy_root/scripts/build-node-b-pihole-ptr-policy-action23d.sh
readonly driver=$caddy_root/scripts/apply-node-b-pihole-ptr-policy-action23d.sh
readonly outer=$caddy_root/scripts/run-node-b-pihole-ptr-policy-action23d-outer.sh
readonly regression=$test_directory/action23d-node-b-pihole-ptr-policy-regression.sh
readonly focused=$test_directory/action23d-focused-validation.sh
readonly manifest=$caddy_root/manifests/dns-action23d-pihole-ptr-policy.yaml

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }
record_check() {
    local action23d_focused_label=$1

    shift
    if "$@" >/dev/null; then
        printf '%s_check_%s=true\n' "$prefix" "$action23d_focused_label"
        return 0
    fi
    printf '%s_check_%s=false\n' "$prefix" "$action23d_focused_label" >&2
    return 1
}
yaml_check() {
    # conditional-validator-explicit-failures-begin
    if command -v yamllint >/dev/null; then
        yamllint -s "$manifest" || return 1
        return 0
    fi
    [[ "${CADDY_VALIDATION_CONTAINER:-}" == 1 ]] || return 1
    grep -Fqx -- '---' "$manifest" || return 1
    grep -Fqx 'action: 23d' "$manifest" || return 1
    grep -Fqx 'status: defined' "$manifest" || return 1
    grep -Fqx '  rerun_permitted: false' "$manifest" || return 1
    grep -Fqx '  ftl_owner: pihole' "$manifest" || return 1
    grep -Fqx '  ftl_group: root' "$manifest" || return 1
    grep -Fqx '  ftl_mode: "0664"' "$manifest" || return 1
    grep -Fqx '  old_line: PIHOLE_PTR=HOSTNAMEFQDN' "$manifest" || return 1
    grep -Fqx '  new_line: PIHOLE_PTR=NONE' "$manifest" || return 1
    grep -Fqx '  required_domain_line: domain=local.theama.co' "$manifest" || return 1
    grep -Fqx '  definition_only: true' "$manifest" || return 1
    grep -Fqx '  node_contact_authorized: false' "$manifest" || return 1
    grep -Fqx '  live_mutation_authorized: false' "$manifest" || return 1
    # conditional-validator-explicit-failures-end
}
reproducible_generation() {
    local action23d_focused_output_root
    local action23d_focused_builder_stdout

    action23d_focused_output_root=$(mktemp -d /tmp/caddy-action23d-build.XXXXXX) || return 1
    action23d_focused_builder_stdout=$action23d_focused_output_root/builder.stdout
    # conditional-validator-explicit-failures-begin
    /bin/bash "$builder" --output-root "$action23d_focused_output_root" \
        >"$action23d_focused_builder_stdout" || {
        rm -rf -- "$action23d_focused_output_root"
        return 1
    }
    grep -Fqx 'action_23d_builder_complete=true' "$action23d_focused_builder_stdout" || {
        rm -rf -- "$action23d_focused_output_root"
        return 1
    }
    if [[ "$(file_hash "$action23d_focused_output_root/apply-node-b-pihole-ptr-policy-action23d.sh")" != "$driver_sha256" ]]; then
        rm -rf -- "$action23d_focused_output_root"
        return 1
    fi
    if [[ "$(file_hash "$action23d_focused_output_root/run-node-b-pihole-ptr-policy-action23d-outer.sh")" != "$outer_sha256" ]]; then
        rm -rf -- "$action23d_focused_output_root"
        return 1
    fi
    if [[ "$(file_hash "$action23d_focused_output_root/action23d-node-b-pihole-ptr-policy-regression.sh")" != "$regression_sha256" ]]; then
        rm -rf -- "$action23d_focused_output_root"
        return 1
    fi
    rm -rf -- "$action23d_focused_output_root" || return 1
    # conditional-validator-explicit-failures-end
}

record_check builder_hash test "$(file_hash "$builder")" = "$builder_sha256"
record_check driver_hash test "$(file_hash "$driver")" = "$driver_sha256"
record_check outer_hash test "$(file_hash "$outer")" = "$outer_sha256"
record_check regression_hash test "$(file_hash "$regression")" = "$regression_sha256"
record_check manifest_hash test "$(file_hash "$manifest")" = "$manifest_sha256"
record_check syntax /bin/bash -n "$builder" "$driver" "$outer" "$regression" "$focused"
record_check shellcheck shellcheck "$builder" "$driver" "$outer" "$regression" "$focused"
record_check canonical_format /bin/bash "$test_directory/shfmt-canonical.sh" --check \
    "$builder" "$driver" "$outer" "$regression" "$focused"
record_check yaml yaml_check
record_check reproducible_generation reproducible_generation
record_check regression /bin/bash "$regression"
record_check collision_policy /bin/bash \
    "$test_directory/check-shell-readonly-local-collisions-v2.sh" \
    "$builder" "$driver" "$outer" "$regression" "$focused"
record_check conditional_policy /bin/bash \
    "$test_directory/conditional-validator-errexit-policy-regression.sh"
record_check output_evidence_policy /bin/bash \
    "$test_directory/transaction-output-evidence-policy-regression.sh"
record_check scalar_grep_policy /bin/bash \
    "$test_directory/multifile-grep-count-policy.sh" --check \
    "$builder" "$driver" "$outer" "$regression" "$focused"
record_check portable_awk_policy /bin/bash \
    "$test_directory/portable-awk-policy.sh" --check \
    "$builder" "$driver" "$outer" "$regression" "$focused"
record_check remote_cwd_policy /bin/bash \
    "$test_directory/remote-streamed-bash-cwd-policy.sh" --check "$outer"
record_check source_context /bin/bash \
    "$test_directory/run-source-test-in-context.sh" --runner "$outer"
record_check accepted_live_hash_policy /bin/bash \
    "$test_directory/accepted-live-hash-policy.sh" --check
record_check executable_policy /bin/bash \
    "$test_directory/executable-wrapper-policy-regression.sh"

for action23d_focused_entrypoint in "$builder" "$driver" "$outer" "$regression" "$focused"; do
    record_check "index_mode_$(basename "$action23d_focused_entrypoint" | tr '.-' '__')" \
        test "$(git -C "$repository_root" ls-files --stage -- \
            "Caddy/${action23d_focused_entrypoint#"$caddy_root/"}" | awk '{ print $1 }')" = 100755
done

printf '%s_node_a_contacted=false\n' "$prefix"
printf '%s_node_b_contacted=false\n' "$prefix"
printf '%s_live_mutation=false\n' "$prefix"
printf '%s_action_23c_rerun=false\n' "$prefix"
printf '%s_action_23d_executed=false\n' "$prefix"
printf '%s_complete_suite_bypassed=true\n' "$prefix"
printf '%s_complete=true\n' "$prefix"
