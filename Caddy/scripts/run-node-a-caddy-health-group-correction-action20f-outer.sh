#!/usr/bin/env bash
# shellcheck disable=SC2317

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_20f
readonly template_sha256=af384fc989eaf6581579ace9f09477d23c6612618fb8eca194c37db890992779
readonly installer_sha256=186dc4cc62e96bf2387e84fb4714618ebd57d31535181d17e46e1a69e76e59d0
readonly runner_sha256=f5aca1865ce91f6c80c46f807aa3517e3f37b92715f9b41ff48ec49bc491779b
readonly regression_sha256=fdfa52ccaae8848e05146aff069401237d257680db0c4326994c694222107a64
readonly collision_sha256=ba1e769a3d00b5884421a8860f820e2dc8a3d8074837dab930630407f047886f
readonly conditional_sha256=68cd687916f9d8be78f50af7a410d376f457ca74ab906a8e459795de6c495455
readonly transcript_sha256=99e0040d785e70a4f2e8d1796f8c6bf29675593d1ae5d13e54d9ac2dceebe44c
readonly output_sha256=84873a1ad3ee1745fe445f179f6a002c2ccee5b147b93cc3db0d6f17d54d4441
readonly maximum_stream_bytes=4194304
readonly maximum_stream_lines=16384

script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
readonly caddy_root=${script_directory%/scripts}
readonly template=$caddy_root/templates/keepalived-caddy-ha-v2.conf.in
readonly installer=$script_directory/install-node-a-caddy-health-group-action20f.sh
readonly runner=$script_directory/run-node-a-caddy-health-group-correction-action20f.sh
readonly regression=$caddy_root/tests/action20f-node-a-health-group-correction-regression.sh
readonly collision=$caddy_root/tests/check-shell-readonly-local-collisions-v2.sh
readonly conditional=$caddy_root/tests/conditional-validator-errexit-policy-regression.sh
readonly transcript=$caddy_root/tests/transcript-contract-ratchet-policy-regression.sh
readonly output_evidence=$caddy_root/tests/transaction-output-evidence-policy-regression.sh

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }
line_count() { awk 'END { print NR }' "$1"; }
require_gate() {
    local action20f_outer_label=$1

    shift
    if "$@"; then
        printf '%s_outer_gate_%s=true\n' "$prefix" "$action20f_outer_label"
        return 0
    fi
    printf '%s_outer_gate_%s=false\n' "$prefix" "$action20f_outer_label" >&2
    return 1
}
source_exact() {
    local action20f_expected_hash=$1
    local action20f_expected_mode=$2
    local action20f_source_path=$3
    local action20f_expected_identity

    action20f_expected_identity="$(id -un):$(id -gn):$action20f_expected_mode"
    [[ -f "$action20f_source_path" && ! -L "$action20f_source_path" ]] || return 1
    [[ "$(stat -c '%U:%G:%a' "$action20f_source_path")" = "$action20f_expected_identity" ]] || return 1
    [[ "$(file_hash "$action20f_source_path")" = "$action20f_expected_hash" ]] || return 1
}
working_directory_approved() {
    case "$PWD" in
        /home/aaron/code/homelab-server-configs) return 0 ;;
        /workspace/homelab-server-configs)
            [[ "${CADDY_VALIDATION_CONTAINER:-}" = 1 ]]
            ;;
        *) return 1 ;;
    esac
}
safe_stream() {
    local action20f_outer_stream_path=$1

    [[ "$(wc -c <"$action20f_outer_stream_path")" -le "$maximum_stream_bytes" ]] || return 1
    [[ "$(line_count "$action20f_outer_stream_path")" -le "$maximum_stream_lines" ]] || return 1
    ! LC_ALL=C grep -n '[^[:print:][:space:]]' "$action20f_outer_stream_path" >/dev/null || return 1
    ! grep -Eqi \
        'BEGIN [A-Z ]*PRIVATE KEY|CADDY_TLS_PRIVATE_KEY_PEM|PRIVATE_KEY=|DOPPLER_TOKEN|Authorization:[[:space:]]*Bearer' \
        "$action20f_outer_stream_path" || return 1
}
emit_stream() {
    local action20f_outer_stream_name=$1
    local action20f_outer_stream_path=$2

    printf '%s_%s_bytes=%s\n' "$prefix" "$action20f_outer_stream_name" \
        "$(wc -c <"$action20f_outer_stream_path")"
    printf '%s_%s_lines=%s\n' "$prefix" "$action20f_outer_stream_name" \
        "$(line_count "$action20f_outer_stream_path")"
    printf '%s_%s_sha256=%s\n' "$prefix" "$action20f_outer_stream_name" \
        "$(file_hash "$action20f_outer_stream_path")"
    if [[ ! -s "$action20f_outer_stream_path" ]]; then
        printf '%s_%s_content_secured=empty\n' "$prefix" "$action20f_outer_stream_name"
        return 0
    fi
    printf '%s_%s_begin\n' "$prefix" "$action20f_outer_stream_name"
    cat "$action20f_outer_stream_path"
    printf '%s_%s_end\n' "$prefix" "$action20f_outer_stream_name"
}
run_local_gates() {
    require_gate template_source_exact source_exact "$template_sha256" 644 "$template" || return 1
    require_gate installer_source_exact source_exact "$installer_sha256" 755 "$installer" || return 1
    require_gate runner_source_exact source_exact "$runner_sha256" 755 "$runner" || return 1
    require_gate regression_source_exact source_exact "$regression_sha256" 755 "$regression" || return 1
    require_gate collision_source_exact source_exact "$collision_sha256" 755 "$collision" || return 1
    require_gate conditional_source_exact source_exact "$conditional_sha256" 755 "$conditional" || return 1
    require_gate transcript_source_exact source_exact "$transcript_sha256" 755 "$transcript" || return 1
    require_gate output_source_exact source_exact "$output_sha256" 755 "$output_evidence" || return 1
    require_gate sources_syntax /bin/bash -n "$installer" "$runner" "$regression" "$0" || return 1
    require_gate sources_shellcheck shellcheck "$installer" "$runner" "$regression" "$0" || return 1
    require_gate sources_canonical_format /bin/bash "$caddy_root/tests/shfmt-canonical.sh" \
        --check "$installer" "$runner" "$regression" "$0" || return 1
    require_gate collision_policy /bin/bash "$collision" "$installer" "$runner" "$regression" "$0" || return 1
    require_gate conditional_policy /bin/bash "$conditional" || return 1
    require_gate transcript_policy /bin/bash "$transcript" || return 1
    require_gate output_evidence_policy /bin/bash "$output_evidence" || return 1
    require_gate regression_self_test /bin/bash "$regression" --self-test || return 1
    require_gate regression_production_path /bin/bash "$regression" || return 1
    require_gate working_directory working_directory_approved || return 1
}

case "${1:-}" in
    --expected-local-gates)
        [[ $# -eq 1 ]] || exit 64
        printf '%s\n' \
            template_source_exact installer_source_exact runner_source_exact \
            regression_source_exact collision_source_exact conditional_source_exact \
            transcript_source_exact output_source_exact sources_syntax \
            sources_shellcheck sources_canonical_format collision_policy \
            conditional_policy transcript_policy output_evidence_policy \
            regression_self_test regression_production_path working_directory
        exit 0
        ;;
    --self-test | --source-test | --contract-test)
        [[ $# -eq 1 ]] || exit 64
        run_local_gates
        action20f_outer_test_kind=${1#--}
        action20f_outer_test_kind=${action20f_outer_test_kind//-/_}
        printf '%s_outer_%s_complete=true\n' "$prefix" "$action20f_outer_test_kind"
        exit 0
        ;;
    "") [[ $# -eq 0 ]] || exit 64 ;;
    *)
        printf 'Usage: %s [--expected-local-gates|--self-test|--source-test|--contract-test]\n' \
            "${0##*/}" >&2
        exit 64
        ;;
esac

run_local_gates
work_directory=$(mktemp -d /tmp/caddy-action20f-outer.XXXXXX)
readonly work_directory
cleanup() {
    # shellcheck disable=SC2317
    rm -rf -- "$work_directory"
}
trap cleanup EXIT
readonly stdout_path=$work_directory/runner.stdout
readonly stderr_path=$work_directory/runner.stderr
: >"$stdout_path"
: >"$stderr_path"
chmod 0600 "$stdout_path" "$stderr_path"
runner_status=0
/bin/bash "$runner" >"$stdout_path" 2>"$stderr_path" || runner_status=$?
readonly runner_status
if ! safe_stream "$stdout_path" || ! safe_stream "$stderr_path"; then
    printf '%s_outer_stream_classification=unsafe_retained\n' "$prefix" >&2
    trap - EXIT
    printf '%s_outer_protected_evidence=%s\n' "$prefix" "$work_directory" >&2
    exit 97
fi
printf '%s_outer_stream_classification=bounded_safe\n' "$prefix"
emit_stream runner_stdout "$stdout_path"
emit_stream runner_stderr "$stderr_path"
printf '%s_runner_status=%s\n' "$prefix" "$runner_status"
rm -rf -- "$work_directory"
trap - EXIT
printf '%s_outer_cleanup_complete=true\n' "$prefix"
exit "$runner_status"
