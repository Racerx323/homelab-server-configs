#!/usr/bin/env bash
# shellcheck disable=SC2016

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_20d_retry10_d_retry_builder
readonly source_candidate_sha256=d1dd8f030fe0a03742ff9c5e0458302cea81ff65a256203f9c07ab5ff022d810
readonly source_installer_sha256=ade3794ce506be9df2b6117715e33395b98bcd61bfb4dbfd7ed34570e00ee468
readonly source_runner_sha256=48b3790c24c9dc35be79abf519110cea0145ee5787ed017ca6493314a61f9c25

script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
readonly source_candidate=$script_directory/check-caddy-instrumented-action20d-retry10-d.sh
readonly source_installer=$script_directory/install-node-a-caddy-health-instrumentation-action20d-retry10-d.sh
readonly source_runner=$script_directory/run-node-a-caddy-health-instrumentation-action20d-retry10-d.sh

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }
record_check() {
    local action20d_d_retry_builder_label=$1

    shift
    if "$@"; then
        printf '%s_check_%s=true\n' "$prefix" "$action20d_d_retry_builder_label"
        return 0
    fi
    printf '%s_check_%s=false\n' "$prefix" "$action20d_d_retry_builder_label" >&2
    return 1
}
write_stager() {
    local action20d_d_retry_stager=$1

    cat >"$action20d_d_retry_stager" <<'STAGER'
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

    [[ -d "$stage_path" && ! -L "$stage_path" ]] || return 1
    [[ "$(stat -c '%U:%G:%a' "$stage_path")" = \
        "$expected_owner:$expected_group:710" ]] || return 1
    [[ -f "$stage_path/$candidate_name" && ! -L "$stage_path/$candidate_name" ]] || return 1
    [[ "$(stat -c '%U:%G:%a' "$stage_path/$candidate_name")" = \
        "$expected_owner:$expected_group:750" ]] || return 1
    [[ "$(find "$stage_path" -mindepth 1 -maxdepth 1 -printf '.\n' | wc -l)" -eq 1 ]] || return 1
}
apply_candidate_stage() {
    local source_path=$1
    local stage_path=$2
    local expected_owner=$3
    local expected_group=$4

    [[ -f "$source_path" && ! -L "$source_path" ]] || return 1
    [[ ! -e "$stage_path" ]] || return 1
    install -d -o "$expected_owner" -g "$expected_group" -m 0710 "$stage_path" || return 1
    install -o "$expected_owner" -g "$expected_group" -m 0750 \
        "$source_path" "$stage_path/$candidate_name" || return 1
    validate_candidate_stage "$stage_path" "$expected_owner" "$expected_group"
}

case "${1:-}" in
    --apply)
        [[ $# -eq 5 ]] || exit 64
        apply_candidate_stage "$2" "$3" "$4" "$5"
        ;;
    --validate)
        [[ $# -eq 4 ]] || exit 64
        validate_candidate_stage "$2" "$3" "$4"
        ;;
    *)
        printf 'Usage: %s --apply SOURCE STAGE OWNER GROUP | --validate STAGE OWNER GROUP\n' \
            "${0##*/}" >&2
        exit 64
        ;;
esac
STAGER
    chmod 0755 "$action20d_d_retry_stager"
}
transform_installer() {
    sed \
        -e 's/action_20d_retry10_d/action_20d_retry10_d_retry/g' \
        -e 's/action20d-retry10-d/action20d-retry10-d-retry/g' \
        -e 's/check-caddy-instrumented-action20d-retry10-d-retry\.sh/check-caddy-instrumented-action20d-retry10-d.sh/g' \
        -e '/record_check stage_directory_metadata/{n;s/root:root:700/root:caddy-tls:710/;}' \
        -e '/record_check candidate_metadata/{n;s/root:root:700/root:caddy-tls:750/;}' \
        "$source_installer"
}
transform_runner() {
    local action20d_d_retry_installer_hash=$1
    local action20d_d_retry_stager_hash=$2

    sed \
        -e 's/action_20d_retry10_d/action_20d_retry10_d_retry/g' \
        -e 's/action20d-retry10-d/action20d-retry10-d-retry/g' \
        -e 's/check-caddy-instrumented-action20d-retry10-d-retry\.sh/check-caddy-instrumented-action20d-retry10-d.sh/g' \
        -e "s/ade3794ce506be9df2b6117715e33395b98bcd61bfb4dbfd7ed34570e00ee468/$action20d_d_retry_installer_hash/g" \
        -e "/readonly installer_sha256=/a readonly stager_sha256=$action20d_d_retry_stager_hash" \
        -e '/readonly installer=/{a\
readonly stager=$script_directory/stage-node-a-caddy-health-instrumentation-action20d-retry10-d-retry.sh
}' \
        -e '/verify_source "$installer_sha256" "$installer" || return 1/a\
    verify_source "$stager_sha256" "$stager" || return 1
' \
        -e '/check-caddy-instrumented-action20d-retry10-d\.sh \\/i\
    stage-node-a-caddy-health-instrumentation-action20d-retry10-d-retry.sh \\
' \
        -e '/chmod 0700 "$bundle_stage\/payload" "$bundle_stage\/payload"\/\*/a\
            '\''/bin/bash "$bundle_stage/payload/stage-node-a-caddy-health-instrumentation-action20d-retry10-d-retry.sh" --apply "$bundle_stage/payload/check-caddy-instrumented-action20d-retry10-d.sh" "$bundle_stage/candidate" root caddy-tls'\'' \\
' \
        -e 's|--stage "$bundle_stage/payload"|--stage "$bundle_stage/candidate"|' \
        "$source_runner"
}
build() {
    local action20d_d_retry_output_root=$1
    local action20d_d_retry_candidate=$action20d_d_retry_output_root/check-caddy-instrumented-action20d-retry10-d.sh
    local action20d_d_retry_installer=$action20d_d_retry_output_root/install-node-a-caddy-health-instrumentation-action20d-retry10-d-retry.sh
    local action20d_d_retry_runner=$action20d_d_retry_output_root/run-node-a-caddy-health-instrumentation-action20d-retry10-d-retry.sh
    local action20d_d_retry_stager=$action20d_d_retry_output_root/stage-node-a-caddy-health-instrumentation-action20d-retry10-d-retry.sh
    local action20d_d_retry_installer_hash
    local action20d_d_retry_stager_hash

    install -d -m 0700 "$action20d_d_retry_output_root"
    install -m 0755 "$source_candidate" "$action20d_d_retry_candidate"
    write_stager "$action20d_d_retry_stager"
    transform_installer >"$action20d_d_retry_installer"
    chmod 0755 "$action20d_d_retry_installer"
    action20d_d_retry_installer_hash=$(file_hash "$action20d_d_retry_installer")
    action20d_d_retry_stager_hash=$(file_hash "$action20d_d_retry_stager")
    transform_runner "$action20d_d_retry_installer_hash" \
        "$action20d_d_retry_stager_hash" >"$action20d_d_retry_runner"
    chmod 0755 "$action20d_d_retry_runner"
    record_check candidate_hash test \
        "$(file_hash "$action20d_d_retry_candidate")" = "$source_candidate_sha256"
    record_check installer_syntax /bin/bash -n "$action20d_d_retry_installer"
    record_check stager_syntax /bin/bash -n "$action20d_d_retry_stager"
    record_check runner_syntax /bin/bash -n "$action20d_d_retry_runner"
    record_check installer_candidate_stage_metadata grep -Fq \
        '"$(stat -c '\''%U:%G:%a'\'' "$stage_directory")" = root:caddy-tls:710' \
        "$action20d_d_retry_installer"
    record_check installer_candidate_metadata grep -Fq \
        '"$(stat -c '\''%U:%G:%a'\'' "$action20d_d_candidate")" = root:caddy-tls:750' \
        "$action20d_d_retry_installer"
    record_check production_stager_call grep -Fq -- \
        '--apply "$bundle_stage/payload/check-caddy-instrumented-action20d-retry10-d.sh" "$bundle_stage/candidate" root caddy-tls' \
        "$action20d_d_retry_runner"
    record_check protected_payload_owner grep -Fq \
        'chown -R root:root "$bundle_stage/payload"' \
        "$action20d_d_retry_runner"
    record_check protected_payload_mode grep -Fq \
        'chmod 0700 "$bundle_stage/payload" "$bundle_stage/payload"/*' \
        "$action20d_d_retry_runner"
    printf '%s_installer_sha256=%s\n' "$prefix" "$action20d_d_retry_installer_hash"
    printf '%s_stager_sha256=%s\n' "$prefix" "$action20d_d_retry_stager_hash"
    printf '%s_runner_sha256=%s\n' "$prefix" "$(file_hash "$action20d_d_retry_runner")"
    printf '%s_complete=true\n' "$prefix"
}

case "${1:-}" in
    --output)
        [[ $# -eq 2 ]] || exit 64
        record_check source_candidate_hash test "$(file_hash "$source_candidate")" = "$source_candidate_sha256"
        record_check source_installer_hash test "$(file_hash "$source_installer")" = "$source_installer_sha256"
        record_check source_runner_hash test "$(file_hash "$source_runner")" = "$source_runner_sha256"
        build "$2"
        ;;
    --self-test)
        [[ $# -eq 1 ]] || exit 64
        action20d_d_retry_test_root=$(mktemp -d /tmp/caddy-action20d-retry10-d-retry-builder.XXXXXX)
        trap 'rm -rf -- "$action20d_d_retry_test_root"' EXIT
        build "$action20d_d_retry_test_root"
        ;;
    *)
        printf 'Usage: %s --output DIRECTORY|--self-test\n' "${0##*/}" >&2
        exit 64
        ;;
esac
