#!/usr/bin/env bash
# shellcheck disable=SC2016

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_20d_retry10_d_retry2_builder
readonly source_builder_sha256=515fbbe96293ce9bc0ba838c2710af4bbba0b04c0f604de87f80d8ab88f0302c
readonly source_candidate_sha256=d1dd8f030fe0a03742ff9c5e0458302cea81ff65a256203f9c07ab5ff022d810
readonly source_installer_sha256=aa9a7e2a5c5506f6371553605c2f7ceb05d751c3cfd6a711844002ffb91b6f6f
readonly source_runner_sha256=22812cd547308eef303eb65326caef9e5afeb50c96d603423b8f652365251ab6
readonly source_stager_sha256=679448f7f3c58afe2d444503c4cf2ac44d6c6fa91d6880fdceed561799171cd9

script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
readonly source_builder=$script_directory/build-node-a-caddy-health-instrumentation-action20d-retry10-d-retry.sh

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }
record_check() {
    local action20d_d_retry2_builder_label=$1

    shift
    if "$@"; then
        printf '%s_check_%s=true\n' "$prefix" "$action20d_d_retry2_builder_label"
        return 0
    fi
    printf '%s_check_%s=false\n' "$prefix" "$action20d_d_retry2_builder_label" >&2
    return 1
}
write_stager() {
    local action20d_d_retry2_stager_path=$1

    cat >"$action20d_d_retry2_stager_path" <<'STAGER'
#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly candidate_name=check-caddy-instrumented-action20d-retry10-d.sh

validate_candidate_stage() {
    local stage_path=$1
    local expected_owner=$2
    local expected_group=$3
    local expected_parent=$4

    [[ "$(dirname -- "$stage_path")" = "$expected_parent" ]] || return 1
    [[ -d "$stage_path" && ! -L "$stage_path" ]] || return 1
    [[ "$(stat -c '%U:%G:%a' "$stage_path")" = \
        "$expected_owner:$expected_group:710" ]] || return 1
    [[ -f "$stage_path/$candidate_name" && ! -L "$stage_path/$candidate_name" ]] || return 1
    [[ "$(stat -c '%U:%G:%a' "$stage_path/$candidate_name")" = \
        "$expected_owner:$expected_group:750" ]] || return 1
    [[ "$(find "$stage_path" -mindepth 1 -maxdepth 1 -printf '.\n' | wc -l)" -eq 1 ]] || return 1
}
adopt_candidate_stage() {
    local source_path=$1
    local stage_path=$2
    local expected_owner=$3
    local expected_group=$4
    local expected_parent=$5
    local initial_owner=$6
    local initial_group=$7

    [[ -f "$source_path" && ! -L "$source_path" ]] || return 1
    [[ "$(dirname -- "$stage_path")" = "$expected_parent" ]] || return 1
    [[ -d "$stage_path" && ! -L "$stage_path" ]] || return 1
    [[ "$(stat -c '%U:%G:%a' "$stage_path")" = \
        "$initial_owner:$initial_group:700" ]] || return 1
    [[ "$(find "$stage_path" -mindepth 1 -maxdepth 1 -print -quit)" = "" ]] || return 1
    install -d -o "$expected_owner" -g "$expected_group" -m 0710 "$stage_path" || return 1
    install -o "$expected_owner" -g "$expected_group" -m 0750 \
        "$source_path" "$stage_path/$candidate_name" || return 1
    validate_candidate_stage "$stage_path" "$expected_owner" "$expected_group" \
        "$expected_parent"
}

case "${1:-}" in
    --adopt)
        [[ $# -eq 8 ]] || exit 64
        adopt_candidate_stage "$2" "$3" "$4" "$5" "$6" "$7" "$8"
        ;;
    --validate)
        [[ $# -eq 5 ]] || exit 64
        validate_candidate_stage "$2" "$3" "$4" "$5"
        ;;
    *)
        printf 'Usage: %s --adopt SOURCE STAGE OWNER GROUP PARENT INITIAL_OWNER INITIAL_GROUP | --validate STAGE OWNER GROUP PARENT\n' \
            "${0##*/}" >&2
        exit 64
        ;;
esac
STAGER
    chmod 0755 "$action20d_d_retry2_stager_path"
}
transform_installer() {
    local action20d_d_retry2_source_installer=$1

    sed \
        -e 's/action_20d_retry10_d_retry/action_20d_retry10_d_retry2/g' \
        -e 's/action20d-retry10-d-retry/action20d-retry10-d-retry2/g' \
        "$action20d_d_retry2_source_installer"
}
transform_runner() {
    local action20d_d_retry2_source_runner=$1
    local action20d_d_retry2_installer_hash=$2
    local action20d_d_retry2_stager_hash=$3

    sed \
        -e 's/action_20d_retry10_d_retry/action_20d_retry10_d_retry2/g' \
        -e 's/action20d-retry10-d-retry/action20d-retry10-d-retry2/g' \
        -e "s/aa9a7e2a5c5506f6371553605c2f7ceb05d751c3cfd6a711844002ffb91b6f6f/$action20d_d_retry2_installer_hash/g" \
        -e "s/679448f7f3c58afe2d444503c4cf2ac44d6c6fa91d6880fdceed561799171cd9/$action20d_d_retry2_stager_hash/g" \
        -e 's/bundle_stage/payload_stage/g' \
        -e 's|payload_stage=$(mktemp -d /run/caddy-action20d-retry10-d-retry2-stage\.XXXXXX)|payload_stage=$(mktemp -d /run/caddy-action20d-retry10-d-retry2-payload.XXXXXX)|' \
        -e 's|--apply "$payload_stage/payload/check-caddy-instrumented-action20d-retry10-d.sh" "$payload_stage/candidate" root caddy-tls|--adopt "$payload_stage/payload/check-caddy-instrumented-action20d-retry10-d.sh" "$candidate_stage" root caddy-tls /run root root|' \
        -e 's|--stage "$payload_stage/candidate"|--stage "$candidate_stage"|' \
        "$action20d_d_retry2_source_runner" | awk '
            /cleanup_payload_stage\(\) \{ rm -rf -- "\$payload_stage"; \}/ {
                print "            \047candidate_stage=\047 \\"
                print "            \047cleanup_payload_stage() { rm -rf -- \"$payload_stage\"; [[ -z \"$candidate_stage\" ]] || rm -rf -- \"$candidate_stage\"; }\047 \\"
                print "            \047trap cleanup_payload_stage EXIT\047 \\"
                print "            \047candidate_stage=$(mktemp -d /run/caddy-action20d-retry10-d-retry2-candidate.XXXXXX)\047 \\"
                next
            }
            /\047trap cleanup_payload_stage EXIT\047/ { next }
            { print }
        '
}
build() {
    local action20d_d_retry2_output_root=$1
    local action20d_d_retry2_source_root
    local action20d_d_retry2_candidate=$action20d_d_retry2_output_root/check-caddy-instrumented-action20d-retry10-d.sh
    local action20d_d_retry2_installer=$action20d_d_retry2_output_root/install-node-a-caddy-health-instrumentation-action20d-retry10-d-retry2.sh
    local action20d_d_retry2_runner=$action20d_d_retry2_output_root/run-node-a-caddy-health-instrumentation-action20d-retry10-d-retry2.sh
    local action20d_d_retry2_stager=$action20d_d_retry2_output_root/stage-node-a-caddy-health-instrumentation-action20d-retry10-d-retry2.sh
    local action20d_d_retry2_installer_hash
    local action20d_d_retry2_stager_hash

    action20d_d_retry2_source_root=$(mktemp -d \
        /tmp/caddy-action20d-retry10-d-retry2-source.XXXXXX) || return 1
    trap 'rm -rf -- "$action20d_d_retry2_source_root"; trap - RETURN' RETURN
    /bin/bash "$source_builder" --output "$action20d_d_retry2_source_root" >/dev/null || return 1
    record_check source_candidate_hash test \
        "$(file_hash "$action20d_d_retry2_source_root/check-caddy-instrumented-action20d-retry10-d.sh")" = \
        "$source_candidate_sha256" || return 1
    record_check source_installer_hash test \
        "$(file_hash "$action20d_d_retry2_source_root/install-node-a-caddy-health-instrumentation-action20d-retry10-d-retry.sh")" = \
        "$source_installer_sha256" || return 1
    record_check source_runner_hash test \
        "$(file_hash "$action20d_d_retry2_source_root/run-node-a-caddy-health-instrumentation-action20d-retry10-d-retry.sh")" = \
        "$source_runner_sha256" || return 1
    record_check source_stager_hash test \
        "$(file_hash "$action20d_d_retry2_source_root/stage-node-a-caddy-health-instrumentation-action20d-retry10-d-retry.sh")" = \
        "$source_stager_sha256" || return 1

    install -d -m 0700 "$action20d_d_retry2_output_root"
    install -m 0755 \
        "$action20d_d_retry2_source_root/check-caddy-instrumented-action20d-retry10-d.sh" \
        "$action20d_d_retry2_candidate"
    transform_installer \
        "$action20d_d_retry2_source_root/install-node-a-caddy-health-instrumentation-action20d-retry10-d-retry.sh" \
        >"$action20d_d_retry2_installer"
    chmod 0755 "$action20d_d_retry2_installer"
    write_stager "$action20d_d_retry2_stager"
    action20d_d_retry2_installer_hash=$(file_hash "$action20d_d_retry2_installer")
    action20d_d_retry2_stager_hash=$(file_hash "$action20d_d_retry2_stager")
    transform_runner \
        "$action20d_d_retry2_source_root/run-node-a-caddy-health-instrumentation-action20d-retry10-d-retry.sh" \
        "$action20d_d_retry2_installer_hash" "$action20d_d_retry2_stager_hash" \
        >"$action20d_d_retry2_runner"
    chmod 0755 "$action20d_d_retry2_runner"

    record_check candidate_hash test "$(file_hash "$action20d_d_retry2_candidate")" = \
        "$source_candidate_sha256" || return 1
    record_check installer_syntax /bin/bash -n "$action20d_d_retry2_installer" || return 1
    record_check stager_syntax /bin/bash -n "$action20d_d_retry2_stager" || return 1
    record_check runner_syntax /bin/bash -n "$action20d_d_retry2_runner" || return 1
    record_check direct_candidate_mktemp grep -Fq \
        'candidate_stage=$(mktemp -d /run/caddy-action20d-retry10-d-retry2-candidate.XXXXXX)' \
        "$action20d_d_retry2_runner" || return 1
    record_check protected_payload_mktemp grep -Fq \
        'payload_stage=$(mktemp -d /run/caddy-action20d-retry10-d-retry2-payload.XXXXXX)' \
        "$action20d_d_retry2_runner" || return 1
    record_check production_stager_call grep -Fq -- \
        '--adopt "$payload_stage/payload/check-caddy-instrumented-action20d-retry10-d.sh" "$candidate_stage" root caddy-tls /run root root' \
        "$action20d_d_retry2_runner" || return 1
    record_check installer_candidate_stage grep -Fq -- \
        '--stage "$candidate_stage"' "$action20d_d_retry2_runner" || return 1
    record_check cleanup_both_stages grep -Fq \
        '[[ -z "$candidate_stage" ]] || rm -rf -- "$candidate_stage"' \
        "$action20d_d_retry2_runner" || return 1
    printf '%s_installer_sha256=%s\n' "$prefix" "$action20d_d_retry2_installer_hash"
    printf '%s_stager_sha256=%s\n' "$prefix" "$action20d_d_retry2_stager_hash"
    printf '%s_runner_sha256=%s\n' "$prefix" "$(file_hash "$action20d_d_retry2_runner")"
    printf '%s_complete=true\n' "$prefix"
}

case "${1:-}" in
    --output)
        [[ $# -eq 2 ]] || exit 64
        record_check source_builder_hash test "$(file_hash "$source_builder")" = \
            "$source_builder_sha256"
        build "$2"
        ;;
    --self-test)
        [[ $# -eq 1 ]] || exit 64
        action20d_d_retry2_test_root=$(mktemp -d \
            /tmp/caddy-action20d-retry10-d-retry2-builder.XXXXXX)
        trap 'rm -rf -- "$action20d_d_retry2_test_root"' EXIT
        build "$action20d_d_retry2_test_root"
        ;;
    *)
        printf 'Usage: %s --output DIRECTORY|--self-test\n' "${0##*/}" >&2
        exit 64
        ;;
esac
