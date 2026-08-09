#!/usr/bin/env bash
# shellcheck disable=SC2317

set -Eeu -o pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_dir
caddy_root=$(cd -- "$script_dir/.." && pwd)
readonly caddy_root
workspace_root=$(cd -- "$caddy_root/../.." && pwd)
readonly workspace_root
readonly driver="$script_dir/apply-node-b-unbound-a-records-action23a.sh"
readonly driver_sha256=6b12a7fabfa0edf18fdc571032d8ba4be17aeae38abfd2702b4ee5f776d83505
readonly action_manifest="$caddy_root/manifests/dns-action23a-a-records.yaml"
readonly action_manifest_sha256=85c1d7419505fa6809fea107cfa72827e94aa6960975f368d9f9d645a523bd86
readonly dns_manifest="$caddy_root/manifests/dns-records.yaml"
readonly dns_manifest_sha256=809c3734dccafc743ced9db81c03db94d1bf9f6918de68b6cc38383a204ebf22
readonly regression="$caddy_root/tests/action23a-node-b-unbound-a-records-regression.sh"
readonly regression_sha256=4ad80f9f7605ad04ac24bac9214d7c8653251f7480f741008bbcbcf29f6b28c8
readonly source_local_zone="$workspace_root/homelab-dns/Unbound/configs/pihole0-local-zone.conf"
readonly source_local_zone_sha256=e3518865f5503e852f79b4e0a602b55526d7e4e35739d1395f5a4d3feb3bd74f
readonly accepted_local_zone_sha256=c70f709789223f91835f0f21c397f577d1e2bb24005a5defbf46055fb411dbb4
readonly candidate_local_zone_sha256=b0c6549c1ac5825de7c50e60e5c825cddb51f5d75056f0fd37c196d670886160
readonly host_alias=pihole00.local.theama.co
readonly host_address=10.1.0.54
readonly max_capture_bytes=131072
readonly max_capture_lines=2000

file_hash() {
    sha256sum "$1" | awk '{ print $1 }'
}

emit_expected_local_gates() {
    printf '%s\n' \
        working_directory \
        driver_regular driver_executable driver_hash \
        action_manifest_regular action_manifest_hash \
        dns_manifest_regular dns_manifest_hash \
        regression_regular regression_executable regression_hash \
        source_regular source_hash source_ignored source_untracked \
        source_admin_a_exact source_proxy_a_exact \
        source_homeassistant_a_exact source_homeassistant_ptr_exact \
        candidate_hash candidate_homeassistant_absent \
        candidate_caddy_aaaa_absent candidate_caddy_ptr_absent \
        candidate_caddy_srv_absent candidate_exact_live_parent \
        driver_syntax driver_shellcheck driver_self_test \
        driver_expected_labels_nonempty driver_expected_labels_unique
}

gate_pass() {
    local action23a_gate_label=$1

    printf 'action_23a_outer_gate_%s=true\n' "$action23a_gate_label"
}

require_gate() {
    local action23a_gate_label=$1

    shift
    if "$@"; then
        gate_pass "$action23a_gate_label"
    else
        printf 'action_23a_outer_gate_%s=false\n' "$action23a_gate_label" >&2
        return 1
    fi
}

is_regular() {
    [[ -f "$1" && ! -L "$1" ]]
}

has_hash() {
    [[ "$(file_hash "$1")" == "$2" ]]
}

source_is_ignored() {
    git -C "$workspace_root/homelab-dns" check-ignore -q \
        Unbound/configs/pihole0-local-zone.conf
}

source_is_untracked() {
    if git -C "$workspace_root/homelab-dns" ls-files --error-unmatch \
        Unbound/configs/pihole0-local-zone.conf >/dev/null 2>&1; then
        return 1
    fi
}

render_candidate() {
    local action23a_render_path=$1

    awk '
        /homeassistant[.]local[.]theama[.]co[.].*IN A / { removed_a++; next }
        /local-data-ptr: "10[.]1[.]2[.]120 homeassistant[.]local[.]theama[.]co[.]"/ {
            removed_ptr++
            next
        }
        { print }
        END {
            if (removed_a != 1 || removed_ptr != 1) { exit 42 }
        }
    ' "$source_local_zone" >"$action23a_render_path"
}

reconstruct_live_parent() {
    local action23a_candidate_path=$1
    local action23a_parent_path=$2

    awk '
        { line[NR] = $0 }
        END {
            for (line_number = 1; line_number <= NR; line_number++) {
                if (line[line_number] == "" &&
                    line[line_number + 1] == "    # Caddy/keepalived HA records" &&
                    line[line_number + 2] == "    local-data: \"pihole-admin.local.theama.co. IN A 10.1.0.56\"" &&
                    line[line_number + 3] == "    local-data: \"proxy.local.theama.co. IN A 10.1.0.56\"") {
                    line_number += 3
                    removed++
                    continue
                }
                print line[line_number]
            }
            if (removed != 1) { exit 43 }
        }
    ' "$action23a_candidate_path" >"$action23a_parent_path"
}

verify_source_and_candidate() {
    local action23a_verify_dir
    local action23a_verify_candidate
    local action23a_verify_parent

    # conditional-validator-explicit-failures-begin
    require_gate source_regular is_regular "$source_local_zone" || return 1
    require_gate source_hash has_hash \
        "$source_local_zone" "$source_local_zone_sha256" || return 1
    require_gate source_ignored source_is_ignored || return 1
    require_gate source_untracked source_is_untracked || return 1
    require_gate source_admin_a_exact test \
        "$(grep -Fxc '    local-data: "pihole-admin.local.theama.co. IN A 10.1.0.56"' \
            "$source_local_zone" || true)" -eq 1 || return 1
    require_gate source_proxy_a_exact test \
        "$(grep -Fxc '    local-data: "proxy.local.theama.co. IN A 10.1.0.56"' \
            "$source_local_zone" || true)" -eq 1 || return 1
    require_gate source_homeassistant_a_exact test \
        "$(grep -Fc 'homeassistant.local.theama.co. IN A 10.1.2.120' \
            "$source_local_zone" || true)" -eq 1 || return 1
    require_gate source_homeassistant_ptr_exact test \
        "$(grep -Fc '10.1.2.120 homeassistant.local.theama.co.' \
            "$source_local_zone" || true)" -eq 1 || return 1

    action23a_verify_dir=$(mktemp -d)
    action23a_verify_candidate="$action23a_verify_dir/pihole-local-zone.conf"
    action23a_verify_parent="$action23a_verify_dir/live-parent.conf"
    render_candidate "$action23a_verify_candidate" || return 1
    reconstruct_live_parent \
        "$action23a_verify_candidate" "$action23a_verify_parent" || return 1
    require_gate candidate_hash has_hash \
        "$action23a_verify_candidate" "$candidate_local_zone_sha256" || return 1
    require_gate candidate_homeassistant_absent test \
        "$(grep -Fc 'homeassistant.local.theama.co' \
            "$action23a_verify_candidate" || true)" -eq 0 || return 1
    require_gate candidate_caddy_aaaa_absent test \
        "$(grep -Ec '(pihole-admin|proxy)[.]local[.]theama[.]co[.].* IN AAAA ' \
            "$action23a_verify_candidate" || true)" -eq 0 || return 1
    require_gate candidate_caddy_ptr_absent test \
        "$(grep -Ec 'local-data-ptr: "(10[.]1[.]0[.]56|fd36:5aa8:6971:1::56) ' \
            "$action23a_verify_candidate" || true)" -eq 0 || return 1
    require_gate candidate_caddy_srv_absent test \
        "$(grep -Fc '_https._tcp.proxy.local.theama.co.' \
            "$action23a_verify_candidate" || true)" -eq 0 || return 1
    require_gate candidate_exact_live_parent has_hash \
        "$action23a_verify_parent" "$accepted_local_zone_sha256" || return 1
    rm -rf -- "$action23a_verify_dir" || return 1
    # conditional-validator-explicit-failures-end
}

verify_expected_labels() {
    local action23a_labels
    local action23a_label_count
    local action23a_unique_count

    action23a_labels=$("$driver" --expected-labels)
    action23a_label_count=$(printf '%s\n' "$action23a_labels" | sed '/^$/d' | wc -l)
    action23a_unique_count=$(printf '%s\n' "$action23a_labels" | sed '/^$/d' |
        LC_ALL=C sort -u | wc -l)
    require_gate driver_expected_labels_nonempty test \
        "$action23a_label_count" -gt 0 || return 1
    require_gate driver_expected_labels_unique test \
        "$action23a_label_count" -eq "$action23a_unique_count" || return 1
}

run_local_gates() {
    # conditional-validator-explicit-failures-begin
    require_gate working_directory test "$PWD" = "$workspace_root/homelab-server-configs" || return 1
    require_gate driver_regular is_regular "$driver" || return 1
    require_gate driver_executable test -x "$driver" || return 1
    require_gate driver_hash has_hash "$driver" "$driver_sha256" || return 1
    require_gate action_manifest_regular is_regular "$action_manifest" || return 1
    require_gate action_manifest_hash has_hash \
        "$action_manifest" "$action_manifest_sha256" || return 1
    require_gate dns_manifest_regular is_regular "$dns_manifest" || return 1
    require_gate dns_manifest_hash has_hash \
        "$dns_manifest" "$dns_manifest_sha256" || return 1
    require_gate regression_regular is_regular "$regression" || return 1
    require_gate regression_executable test -x "$regression" || return 1
    require_gate regression_hash has_hash "$regression" "$regression_sha256" || return 1
    verify_source_and_candidate || return 1
    require_gate driver_syntax bash -n "$driver" || return 1
    require_gate driver_shellcheck shellcheck "$driver" || return 1
    require_gate driver_self_test "$driver" --self-test || return 1
    verify_expected_labels || return 1
    # conditional-validator-explicit-failures-end
}

capture_is_safe() {
    local action23a_capture_path=$1
    local action23a_capture_bytes=$2
    local action23a_capture_lines=$3

    [[ "$action23a_capture_bytes" -le "$max_capture_bytes" ]] || return 1
    [[ "$action23a_capture_lines" -le "$max_capture_lines" ]] || return 1
    if LC_ALL=C grep -Eq '[^[:print:][:space:]]' "$action23a_capture_path"; then
        return 1
    fi
    if grep -Eqi 'PRIVATE KEY|Authorization:|api[_-]?key|token=' \
        "$action23a_capture_path"; then
        return 1
    fi
}

emit_capture() {
    local action23a_capture_label=$1
    local action23a_capture_path=$2
    local action23a_capture_bytes
    local action23a_capture_lines
    local action23a_capture_hash

    action23a_capture_bytes=$(wc -c <"$action23a_capture_path")
    action23a_capture_lines=$(wc -l <"$action23a_capture_path")
    action23a_capture_hash=$(file_hash "$action23a_capture_path")
    printf 'action_23a_outer_%s_bytes=%s\n' \
        "$action23a_capture_label" "$action23a_capture_bytes"
    printf 'action_23a_outer_%s_lines=%s\n' \
        "$action23a_capture_label" "$action23a_capture_lines"
    printf 'action_23a_outer_%s_sha256=%s\n' \
        "$action23a_capture_label" "$action23a_capture_hash"
    if capture_is_safe "$action23a_capture_path" \
        "$action23a_capture_bytes" "$action23a_capture_lines"; then
        printf 'action_23a_outer_%s_classification=bounded_safe\n' \
            "$action23a_capture_label"
        if [[ "$action23a_capture_bytes" -eq 0 ]]; then
            printf 'action_23a_outer_%s_content=empty\n' "$action23a_capture_label"
        else
            printf 'action_23a_outer_%s_begin\n' "$action23a_capture_label"
            sed -n '1,2000p' "$action23a_capture_path"
            printf 'action_23a_outer_%s_end\n' "$action23a_capture_label"
        fi
        return 0
    fi
    printf 'action_23a_outer_%s_classification=unsafe_or_unbounded\n' \
        "$action23a_capture_label"
    return 1
}

validate_success_transcript() {
    local action23a_transcript=$1
    local action23a_expected_file=$2
    local action23a_actual_file=$3
    local action23a_actual_count
    local action23a_unique_count
    local action23a_false_count

    action23a_false_count=$(grep -Ec \
        '^action_23a_check_[a-z0-9_]+=false$' "$action23a_transcript" || true)

    # conditional-validator-explicit-failures-begin
    "$driver" --expected-labels | LC_ALL=C sort >"$action23a_expected_file" || return 1
    sed -n 's/^action_23a_check_\([a-z0-9_]*\)=\(true\|false\)$/\1/p' \
        "$action23a_transcript" | LC_ALL=C sort >"$action23a_actual_file" || return 1
    action23a_actual_count=$(wc -l <"$action23a_actual_file")
    action23a_unique_count=$(LC_ALL=C sort -u "$action23a_actual_file" | wc -l)
    [[ "$action23a_actual_count" -eq "$action23a_unique_count" ]] || return 1
    cmp -s "$action23a_expected_file" "$action23a_actual_file" || return 1
    [[ "$action23a_false_count" -eq 0 ]] || return 1
    [[ "$(grep -Fxc 'action_23a_acceptance=true' "$action23a_transcript")" -eq 1 ]] || return 1
    [[ "$(grep -Fxc 'action_23a_manifest_action=23a' "$action23a_transcript")" -eq 1 ]] || return 1
    [[ "$(grep -Fxc 'action_23a_record_family=A' "$action23a_transcript")" -eq 1 ]] || return 1
    [[ "$(grep -Fxc 'action_23a_pihole_cache_reset=true' "$action23a_transcript")" -eq 1 ]] || return 1
    [[ "$(grep -Fxc 'action_23a_unbound_reload=true' "$action23a_transcript")" -eq 1 ]] || return 1
    [[ "$(grep -Fxc 'action_23a_peer_ssh=false' "$action23a_transcript")" -eq 1 ]] || return 1
    [[ "$(grep -Fxc 'action_23a_synchronization_executed=false' "$action23a_transcript")" -eq 1 ]] || return 1
    # conditional-validator-explicit-failures-end
}

self_test() {
    run_local_gates
    printf 'action_23a_outer_regression_skipped_for_self_test=true\n'
    printf 'action_23a_outer_node_contact=false\n'
    printf 'action_23a_outer_self_test_complete=true\n'
}

contract_test() {
    grep -Fq 'cd / && sudo -n /bin/bash -c' "$0"
    # The contract is intentionally matched as literal remote-shell text.
    # shellcheck disable=SC2016
    grep -Fq '/bin/bash "$remote_stage/apply-node-b-unbound-a-records-action23a.sh"' "$0"
    grep -Fq 'validate_success_transcript' "$0"
    grep -Fq 'action_23a_outer_stdout_classification' "$0"
    grep -Fq 'action_23a_outer_stderr_classification' "$0"
    if grep -Eq '(^|[[:space:]])(rsync|scp|sftp)([[:space:]]|$)' "$0"; then
        return 1
    fi
    printf 'action_23a_outer_contract_test_complete=true\n'
}

case "${1:-}" in
    --self-test)
        [[ $# -eq 1 ]]
        self_test
        exit 0
        ;;
    --source-test)
        [[ $# -eq 1 ]]
        verify_source_and_candidate
        printf 'action_23a_outer_source_test_complete=true\n'
        exit 0
        ;;
    --contract-test)
        [[ $# -eq 1 ]]
        contract_test
        exit 0
        ;;
    --expected-local-gates)
        [[ $# -eq 1 ]]
        emit_expected_local_gates
        exit 0
        ;;
    --transport-test)
        [[ $# -eq 1 ]]
        transport_test=true
        ;;
    "")
        [[ $# -eq 0 ]]
        transport_test=false
        ;;
    *)
        printf 'Usage: %s [--self-test|--source-test|--contract-test|--expected-local-gates|--transport-test]\n' \
            "${0##*/}" >&2
        exit 2
        ;;
esac
readonly transport_test

run_local_gates
if [[ "$transport_test" == false ]]; then
    "$regression"
    printf 'action_23a_outer_regression=true\n'
else
    printf 'action_23a_outer_regression_skipped_for_transport_test=true\n'
fi

work_dir=$(mktemp -d)
readonly work_dir
candidate="$work_dir/pihole-local-zone.conf"
archive="$work_dir/action23a.tar"
stdout_capture="$work_dir/stdout"
stderr_capture="$work_dir/stderr"
expected_labels="$work_dir/expected-labels"
actual_labels="$work_dir/actual-labels"
readonly candidate archive stdout_capture stderr_capture expected_labels actual_labels
retain_evidence=false
cleanup() {
    if [[ "$retain_evidence" == false ]]; then
        rm -rf -- "$work_dir"
    fi
}
trap cleanup EXIT

render_candidate "$candidate"
chmod 0600 "$candidate"
tar -C "$script_dir" -cf "$archive" \
    apply-node-b-unbound-a-records-action23a.sh \
    -C "$work_dir" pihole-local-zone.conf

ssh_bin=ssh
if [[ "$transport_test" == true ]]; then
    ssh_bin=${ACTION23A_TEST_SSH_BIN:?ACTION23A_TEST_SSH_BIN is required}
fi
readonly ssh_bin

set +e
"$ssh_bin" -T \
    -o BatchMode=yes \
    -o ConnectTimeout=5 \
    -o HostKeyAlias="$host_alias" \
    -o StrictHostKeyChecking=yes \
    "pi@$host_address" \
    "cd / && sudo -n /bin/bash -c 'remote_stage=\$(mktemp -d /run/caddy-action23a.XXXXXX) && trap '\''rm -rf -- \"\$remote_stage\"'\'' EXIT && tar -C \"\$remote_stage\" -xf - && chown root:root \"\$remote_stage\"/* && chmod 0700 \"\$remote_stage\" && chmod 0700 \"\$remote_stage/apply-node-b-unbound-a-records-action23a.sh\" && chmod 0600 \"\$remote_stage/pihole-local-zone.conf\" && /bin/bash \"\$remote_stage/apply-node-b-unbound-a-records-action23a.sh\" --candidate \"\$remote_stage/pihole-local-zone.conf\"'" \
    <"$archive" >"$stdout_capture" 2>"$stderr_capture"
ssh_status=$?
set -e
readonly ssh_status

stdout_safe=true
stderr_safe=true
emit_capture stdout "$stdout_capture" || stdout_safe=false
emit_capture stderr "$stderr_capture" || stderr_safe=false
if [[ "$stdout_safe" != true || "$stderr_safe" != true ]]; then
    retain_evidence=true
    printf 'action_23a_outer_protected_evidence_path=%s\n' "$work_dir" >&2
    exit 1
fi

if [[ "$ssh_status" -eq 0 ]] &&
    validate_success_transcript \
        "$stdout_capture" "$expected_labels" "$actual_labels" &&
    [[ ! -s "$stderr_capture" ]]; then
    printf 'action_23a_outer_ssh_status=0\n'
    printf 'action_23a_outer_node_b_contacted=true\n'
    printf 'action_23a_outer_dns_configuration_mutation=true\n'
    printf 'action_23a_outer_unbound_reload=true\n'
    printf 'action_23a_outer_pihole_cache_reset=true\n'
    printf 'action_23a_outer_acceptance=true\n'
    exit 0
fi

printf 'action_23a_outer_ssh_status=%s\n' "$ssh_status" >&2
if grep -Fqx 'manual_intervention_required=true' "$stderr_capture"; then
    printf 'action_23a_outer_manual_intervention_required=true\n' >&2
    exit 125
fi
if grep -Fqx 'action_23a_rollback_complete=true' "$stderr_capture"; then
    printf 'action_23a_outer_rollback_complete=true\n' >&2
fi
printf 'action_23a_outer_acceptance=false\n' >&2
exit 1
