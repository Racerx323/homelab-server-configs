#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_19e
readonly derivation_sha256=0453ed18dd4b6fe2c987bf2150cc4aca8e32792fea70b8f1470e8561c49203b5
readonly regression_sha256=513d9c6dbb1d80336f268713f66f3ffd024575ac6c71d18ce637693dfdad5526
readonly installer_sha256=8aa4eb3d6753b6028b196d623a98e48e2f3a0eb161825e3f1087d17c29608512
readonly runner_sha256=c332c6cc3b1afb0858dcf83f25dd0443882885a1d21d0fd194bf13a9df6a7ebb
readonly renderer_sha256=d7fa1c57a4d74edd966b78cf66d79e534f49c09a7265c2ad326f00018fa4c1c2
readonly environment_template_sha256=bbd5ff898e49b70e4d3dbac247c5ea11b762035404f5b58e2928d3dd5dc03679
readonly keepalived_template_sha256=ebc60650edd4cb384000604b402ce1e99153b50d505c7e13289b6b33d7abdd09
readonly lsyncd_template_sha256=5091566ae9f8165d502305ce08dad75cf1c78b417eca3dbd1dca8efa7eff105a
readonly manifest_sha256=ee58ae3d2af19c6b5fd45b8c87d9c4866450d1a2d737c277c26442db36ebcfd0
readonly collision_checker_sha256=ba1e769a3d00b5884421a8860f820e2dc8a3d8074837dab930630407f047886f
readonly conditional_policy_sha256=68cd687916f9d8be78f50af7a410d376f457ca74ab906a8e459795de6c495455
readonly transcript_policy_sha256=99e0040d785e70a4f2e8d1796f8c6bf29675593d1ae5d13e54d9ac2dceebe44c
readonly output_policy_sha256=84873a1ad3ee1745fe445f179f6a002c2ccee5b147b93cc3db0d6f17d54d4441
readonly maximum_stream_bytes=1048576
readonly maximum_stream_lines=4096

script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
readonly caddy_root=${script_directory%/scripts}
readonly derivation="$script_directory/derive-node-a-keepalived-fragment-action19e.sh"
readonly regression="$caddy_root/tests/action19e-node-a-keepalived-fragment-definition-regression.sh"
readonly renderer="$script_directory/render-node-config.sh"
readonly environment_template="$caddy_root/templates/caddy-ha.env.in"
readonly keepalived_template="$caddy_root/templates/keepalived-caddy-ha.conf.in"
readonly lsyncd_template="$caddy_root/templates/lsyncd-caddy.lua.in"
readonly manifest="$caddy_root/manifests/deployment.yaml"
readonly collision_checker="$caddy_root/tests/check-shell-readonly-local-collisions-v2.sh"
readonly conditional_policy="$caddy_root/tests/conditional-validator-errexit-policy-regression.sh"
readonly transcript_policy="$caddy_root/tests/transcript-contract-ratchet-policy-regression.sh"
readonly output_policy="$caddy_root/tests/transaction-output-evidence-policy-regression.sh"

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }
line_count() { awk 'END { print NR }' "$1"; }

require_source() {
    local expected_hash=$1
    local expected_mode=$2
    local source_path=$3
    local expected_identity

    expected_identity="$(id -un):$(id -gn):$expected_mode"
    [[ -f "$source_path" && ! -L "$source_path" ]] || return 1
    [[ "$(stat -c '%U:%G:%a' "$source_path")" = "$expected_identity" ]] ||
        return 1
    [[ "$(file_hash "$source_path")" = "$expected_hash" ]] || return 1
}

verify_sources() {
    require_source "$derivation_sha256" 755 "$derivation" || return 1
    require_source "$regression_sha256" 755 "$regression" || return 1
    require_source "$renderer_sha256" 755 "$renderer" || return 1
    require_source "$environment_template_sha256" 644 \
        "$environment_template" || return 1
    require_source "$keepalived_template_sha256" 644 \
        "$keepalived_template" || return 1
    require_source "$lsyncd_template_sha256" 644 "$lsyncd_template" || return 1
    require_source "$manifest_sha256" 644 "$manifest" || return 1
    require_source "$collision_checker_sha256" 755 "$collision_checker" ||
        return 1
    require_source "$conditional_policy_sha256" 755 "$conditional_policy" ||
        return 1
    require_source "$transcript_policy_sha256" 755 "$transcript_policy" ||
        return 1
    require_source "$output_policy_sha256" 755 "$output_policy" || return 1
    bash -n "$derivation" "$regression" "$renderer" || return 1
    shellcheck "$derivation" "$regression" "$renderer" || return 1
    "$collision_checker" "$0" "$derivation" "$regression" "$renderer" \
        "$conditional_policy" "$transcript_policy" "$output_policy" \
        >/dev/null || return 1
}

render_stage() {
    local stage_root=$1
    local stage_caddy=$stage_root/Caddy
    local stage_scripts=$stage_caddy/scripts
    local stage_tests=$stage_caddy/tests
    local stage_templates=$stage_caddy/templates
    local stage_manifests=$stage_caddy/manifests
    local staged_installer=$stage_scripts/install-node-a-keepalived-fragment-action19e.sh
    local staged_runner=$stage_scripts/run-node-a-keepalived-fragment-install-action19e.sh

    install -d -m 0700 "$stage_scripts" "$stage_tests" "$stage_templates" \
        "$stage_manifests" || return 1
    install -m 0755 "$renderer" "$stage_scripts/" || return 1
    install -m 0755 "$collision_checker" "$stage_tests/" || return 1
    install -m 0644 "$environment_template" "$keepalived_template" \
        "$lsyncd_template" "$stage_templates/" || return 1
    install -m 0644 "$manifest" "$stage_manifests/" || return 1
    /bin/bash "$derivation" --output-directory "$stage_scripts" || return 1
    [[ "$(file_hash "$staged_installer")" = "$installer_sha256" ]] || return 1
    [[ "$(file_hash "$staged_runner")" = "$runner_sha256" ]] || return 1
    bash -n "$staged_installer" "$staged_runner" || return 1
    shellcheck "$staged_installer" "$staged_runner" || return 1
    "$collision_checker" "$staged_installer" "$staged_runner" >/dev/null ||
        return 1
    /bin/bash "$staged_installer" --self-test >/dev/null || return 1
    [[ "$(/bin/bash "$staged_installer" --expected-checks | wc -l)" -eq 154 ]] ||
        return 1
    /bin/bash "$staged_runner" --self-test >/dev/null || return 1
    /bin/bash "$staged_runner" --contract-test >/dev/null || return 1
    printf '%s\n' "$staged_runner"
}

run_local_gates() {
    local gate_root=$1

    verify_sources || return 1
    /bin/bash "$derivation" --self-test >/dev/null || return 1
    /bin/bash "$conditional_policy" >/dev/null || return 1
    /bin/bash "$transcript_policy" >/dev/null || return 1
    /bin/bash "$output_policy" >/dev/null || return 1
    /bin/bash "$regression" >/dev/null || return 1
    render_stage "$gate_root" >/dev/null || return 1
}

safe_stream() {
    local stream_path=$1

    [[ "$(wc -c <"$stream_path")" -le "$maximum_stream_bytes" ]] || return 1
    [[ "$(line_count "$stream_path")" -le "$maximum_stream_lines" ]] ||
        return 1
    ! LC_ALL=C grep -n '[^[:print:][:space:]]' "$stream_path" >/dev/null ||
        return 1
    ! grep -Eqi \
        'BEGIN [A-Z ]*PRIVATE KEY|CADDY_TLS_PRIVATE_KEY_PEM|PRIVATE_KEY=|DOPPLER_TOKEN|Authorization:[[:space:]]*Bearer' \
        "$stream_path"
}

emit_stream_metadata() {
    local stream_name=$1
    local stream_path=$2

    printf '%s_%s_bytes=%s\n' "$prefix" "$stream_name" \
        "$(wc -c <"$stream_path")"
    printf '%s_%s_lines=%s\n' "$prefix" "$stream_name" \
        "$(line_count "$stream_path")"
    printf '%s_%s_sha256=%s\n' "$prefix" "$stream_name" \
        "$(file_hash "$stream_path")"
}

case "${1:-}" in
    --self-test | --source-test | --contract-test)
        [[ $# -eq 1 ]] || exit 64
        test_root=$(mktemp -d /tmp/caddy-action19e-outer-test.XXXXXX)
        readonly test_root
        trap 'rm -rf -- "$test_root"' EXIT
        run_local_gates "$test_root"
        printf '%s_outer_%s_complete=true\n' "$prefix" "${1#--}"
        exit 0
        ;;
    "")
        [[ $# -eq 0 ]] || exit 64
        ;;
    *)
        printf 'Usage: %s [--self-test|--source-test|--contract-test]\n' \
            "${0##*/}" >&2
        exit 64
        ;;
esac

verify_sources
[[ "$PWD" = /home/aaron/code/homelab-server-configs ]]
[[ -z "${CADDY_ACTION19E_SSH_BINARY:-}" ]]
[[ -z "${CADDY_ACTION19E_INTERCEPTED_TEST:-}" ]]
work_directory=$(mktemp -d /tmp/caddy-action19e-outer.XXXXXX)
readonly work_directory
cleanup() {
    # shellcheck disable=SC2317
    rm -rf -- "$work_directory"
}
trap cleanup EXIT
run_local_gates "$work_directory/local"
rendered_runner=$(render_stage "$work_directory/live")
readonly rendered_runner
readonly stdout_path=$work_directory/inner.stdout
readonly stderr_path=$work_directory/inner.stderr
: >"$stdout_path"
: >"$stderr_path"
chmod 0600 "$stdout_path" "$stderr_path"

inner_status=0
/bin/bash "$rendered_runner" >"$stdout_path" 2>"$stderr_path" ||
    inner_status=$?
readonly inner_status
emit_stream_metadata inner_stdout "$stdout_path"
emit_stream_metadata inner_stderr "$stderr_path"
if safe_stream "$stdout_path" && safe_stream "$stderr_path"; then
    printf '%s_inner_stream_classification=bounded_safe\n' "$prefix"
    printf '%s_inner_stdout_begin\n' "$prefix"
    cat "$stdout_path"
    printf '%s_inner_stdout_end\n' "$prefix"
    if [[ -s "$stderr_path" ]]; then
        printf '%s_inner_stderr_begin\n' "$prefix" >&2
        cat "$stderr_path" >&2
        printf '%s_inner_stderr_end\n' "$prefix" >&2
    else
        printf '%s_inner_stderr_content_secured=empty\n' "$prefix"
    fi
else
    printf '%s_inner_stream_classification=unsafe_retained\n' "$prefix" >&2
    trap - EXIT
    printf '%s_protected_evidence=%s\n' "$prefix" "$work_directory" >&2
    exit 97
fi
printf '%s_inner_status=%s\n' "$prefix" "$inner_status"
rm -rf -- "$work_directory"
trap - EXIT
printf '%s_outer_cleanup_complete=true\n' "$prefix"
exit "$inner_status"
