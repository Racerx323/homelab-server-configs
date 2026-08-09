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
readonly driver="$script_dir/apply-node-b-unbound-aaaa-records-action23h.sh"
readonly driver_sha256=4cd1b10d4782dfce4fe32540ddce4eff807685f8b8756fcd435a2cb4086ff179
readonly action_manifest="$caddy_root/manifests/dns-action23h-aaaa-records.yaml"
readonly action_manifest_sha256=8675cb330cbd47508b6457feb8d64374e46d60562ed9b7c085cd9c3a76bc34b6
readonly dns_manifest="$caddy_root/manifests/dns-records.yaml"
readonly dns_manifest_sha256=809c3734dccafc743ced9db81c03db94d1bf9f6918de68b6cc38383a204ebf22
readonly regression="$caddy_root/tests/action23h-node-b-unbound-aaaa-records-regression.sh"
readonly regression_sha256=91dd75a850a4a9e4e0ddbcb95dbabdb4cb9ebef622c66e7cbc388f53074d853c
readonly accepted_live_hash_policy="$caddy_root/tests/accepted-live-hash-policy.sh"
readonly accepted_live_hash_policy_sha256=ddd0bac4ed05db2b8a082c3df21e5e1b8a439ad5c7d60e74b09ee0aa99629174
readonly source_local_zone="$workspace_root/homelab-dns/Unbound/configs/pihole0-local-zone.conf"
readonly source_local_zone_sha256=e3518865f5503e852f79b4e0a602b55526d7e4e35739d1395f5a4d3feb3bd74f
readonly accepted_local_zone_sha256=b0c6549c1ac5825de7c50e60e5c825cddb51f5d75056f0fd37c196d670886160
readonly candidate_local_zone_sha256=7d018a7f3d96961de78bb523176f30e5128d04d9810a3db534d73639e2958c39
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
        accepted_live_policy_regular accepted_live_hash_policy_hash \
        accepted_live_hash_policy_check \
        source_regular source_hash source_ignored source_untracked \
        source_admin_a_exact source_proxy_a_exact \
        source_homeassistant_a_exact source_homeassistant_ptr_exact \
        candidate_hash candidate_homeassistant_absent \
        candidate_admin_aaaa_exact candidate_proxy_aaaa_exact \
        candidate_caddy_ptr_absent \
        candidate_caddy_srv_absent candidate_exact_live_parent \
        driver_syntax driver_shellcheck driver_self_test \
        driver_expected_labels_nonempty driver_expected_labels_unique
}

gate_pass() {
    local action23h_gate_label=$1

    printf 'action_23h_outer_gate_%s=true\n' "$action23h_gate_label"
}

require_gate() {
    local action23h_gate_label=$1

    shift
    if "$@"; then
        gate_pass "$action23h_gate_label"
    else
        printf 'action_23h_outer_gate_%s=false\n' "$action23h_gate_label" >&2
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
    local action23h_render_path=$1

    awk '
        /homeassistant[.]local[.]theama[.]co[.].*IN A / { removed_a++; next }
        /local-data-ptr: "10[.]1[.]2[.]120 homeassistant[.]local[.]theama[.]co[.]"/ {
            removed_ptr++
            next
        }
        {
            print
            if ($0 == "    local-data: \"proxy.local.theama.co. IN A 10.1.0.56\"") {
                print "    local-data: \"pihole-admin.local.theama.co. IN AAAA fd36:5aa8:6971:1::56\""
                print "    local-data: \"proxy.local.theama.co. IN AAAA fd36:5aa8:6971:1::56\""
                added_aaaa++
            }
        }
        END {
            if (removed_a != 1 || removed_ptr != 1 || added_aaaa != 1) { exit 42 }
        }
    ' "$source_local_zone" >"$action23h_render_path"
}

reconstruct_live_parent() {
    local action23h_candidate_path=$1
    local action23h_parent_path=$2

    awk '
        { line[NR] = $0 }
        END {
            for (line_number = 1; line_number <= NR; line_number++) {
                if (line[line_number] == "    local-data: \"pihole-admin.local.theama.co. IN AAAA fd36:5aa8:6971:1::56\"" &&
                    line[line_number + 1] == "    local-data: \"proxy.local.theama.co. IN AAAA fd36:5aa8:6971:1::56\"") {
                    line_number += 1
                    removed_aaaa++
                    continue
                }
                print line[line_number]
            }
            if (removed_aaaa != 1) { exit 43 }
        }
    ' "$action23h_candidate_path" >"$action23h_parent_path"
}

verify_source_and_candidate() {
    local action23h_verify_dir
    local action23h_verify_candidate
    local action23h_verify_parent

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

    action23h_verify_dir=$(mktemp -d)
    action23h_verify_candidate="$action23h_verify_dir/pihole-local-zone.conf"
    action23h_verify_parent="$action23h_verify_dir/live-parent.conf"
    render_candidate "$action23h_verify_candidate" || return 1
    reconstruct_live_parent \
        "$action23h_verify_candidate" "$action23h_verify_parent" || return 1
    require_gate candidate_hash has_hash \
        "$action23h_verify_candidate" "$candidate_local_zone_sha256" || return 1
    require_gate candidate_homeassistant_absent test \
        "$(grep -Fc 'homeassistant.local.theama.co' \
            "$action23h_verify_candidate" || true)" -eq 0 || return 1
    require_gate candidate_admin_aaaa_exact test \
        "$(grep -Fxc '    local-data: "pihole-admin.local.theama.co. IN AAAA fd36:5aa8:6971:1::56"' \
            "$action23h_verify_candidate" || true)" -eq 1 || return 1
    require_gate candidate_proxy_aaaa_exact test \
        "$(grep -Fxc '    local-data: "proxy.local.theama.co. IN AAAA fd36:5aa8:6971:1::56"' \
            "$action23h_verify_candidate" || true)" -eq 1 || return 1
    require_gate candidate_caddy_ptr_absent test \
        "$(grep -Ec 'local-data-ptr: "(10[.]1[.]0[.]56|fd36:5aa8:6971:1::56) ' \
            "$action23h_verify_candidate" || true)" -eq 0 || return 1
    require_gate candidate_caddy_srv_absent test \
        "$(grep -Fc '_https._tcp.proxy.local.theama.co.' \
            "$action23h_verify_candidate" || true)" -eq 0 || return 1
    require_gate candidate_exact_live_parent has_hash \
        "$action23h_verify_parent" "$accepted_local_zone_sha256" || return 1
    rm -rf -- "$action23h_verify_dir" || return 1
    # conditional-validator-explicit-failures-end
}

verify_expected_labels() {
    local action23h_labels
    local action23h_label_count
    local action23h_unique_count

    action23h_labels=$("$driver" --expected-labels)
    action23h_label_count=$(printf '%s\n' "$action23h_labels" | sed '/^$/d' | wc -l)
    action23h_unique_count=$(printf '%s\n' "$action23h_labels" | sed '/^$/d' |
        LC_ALL=C sort -u | wc -l)
    require_gate driver_expected_labels_nonempty test \
        "$action23h_label_count" -gt 0 || return 1
    require_gate driver_expected_labels_unique test \
        "$action23h_label_count" -eq "$action23h_unique_count" || return 1
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
    require_gate accepted_live_policy_regular is_regular "$accepted_live_hash_policy" || return 1
    require_gate accepted_live_hash_policy_hash has_hash \
        "$accepted_live_hash_policy" "$accepted_live_hash_policy_sha256" || return 1
    require_gate accepted_live_hash_policy_check /bin/bash \
        "$accepted_live_hash_policy" --check || return 1
    verify_source_and_candidate || return 1
    require_gate driver_syntax bash -n "$driver" || return 1
    require_gate driver_shellcheck shellcheck "$driver" || return 1
    require_gate driver_self_test "$driver" --self-test || return 1
    verify_expected_labels || return 1
    # conditional-validator-explicit-failures-end
}

capture_is_safe() {
    local action23h_capture_path=$1
    local action23h_capture_bytes=$2
    local action23h_capture_lines=$3

    [[ "$action23h_capture_bytes" -le "$max_capture_bytes" ]] || return 1
    [[ "$action23h_capture_lines" -le "$max_capture_lines" ]] || return 1
    if LC_ALL=C grep -Eq '[^[:print:][:space:]]' "$action23h_capture_path"; then
        return 1
    fi
    if grep -Eqi 'PRIVATE KEY|Authorization:|api[_-]?key|token=' \
        "$action23h_capture_path"; then
        return 1
    fi
}

emit_capture() {
    local action23h_capture_label=$1
    local action23h_capture_path=$2
    local action23h_capture_bytes
    local action23h_capture_lines
    local action23h_capture_hash

    action23h_capture_bytes=$(wc -c <"$action23h_capture_path")
    action23h_capture_lines=$(wc -l <"$action23h_capture_path")
    action23h_capture_hash=$(file_hash "$action23h_capture_path")
    printf 'action_23h_outer_%s_bytes=%s\n' \
        "$action23h_capture_label" "$action23h_capture_bytes"
    printf 'action_23h_outer_%s_lines=%s\n' \
        "$action23h_capture_label" "$action23h_capture_lines"
    printf 'action_23h_outer_%s_sha256=%s\n' \
        "$action23h_capture_label" "$action23h_capture_hash"
    if capture_is_safe "$action23h_capture_path" \
        "$action23h_capture_bytes" "$action23h_capture_lines"; then
        printf 'action_23h_outer_%s_classification=bounded_safe\n' \
            "$action23h_capture_label"
        if [[ "$action23h_capture_bytes" -eq 0 ]]; then
            printf 'action_23h_outer_%s_content=empty\n' "$action23h_capture_label"
        else
            printf 'action_23h_outer_%s_begin\n' "$action23h_capture_label"
            sed -n '1,2000p' "$action23h_capture_path"
            printf 'action_23h_outer_%s_end\n' "$action23h_capture_label"
        fi
        return 0
    fi
    printf 'action_23h_outer_%s_classification=unsafe_or_unbounded\n' \
        "$action23h_capture_label"
    return 1
}

validate_success_transcript() {
    local action23h_transcript=$1
    local action23h_expected_file=$2
    local action23h_actual_file=$3
    local action23h_actual_count
    local action23h_unique_count
    local action23h_false_count

    action23h_false_count=$(grep -Ec \
        '^action_23h_check_[a-z0-9_]+=false$' "$action23h_transcript" || true)

    # conditional-validator-explicit-failures-begin
    "$driver" --expected-labels | LC_ALL=C sort >"$action23h_expected_file" || return 1
    sed -n 's/^action_23h_check_\([a-z0-9_]*\)=\(true\|false\)$/\1/p' \
        "$action23h_transcript" | LC_ALL=C sort >"$action23h_actual_file" || return 1
    action23h_actual_count=$(wc -l <"$action23h_actual_file")
    action23h_unique_count=$(LC_ALL=C sort -u "$action23h_actual_file" | wc -l)
    [[ "$action23h_actual_count" -eq "$action23h_unique_count" ]] || return 1
    cmp -s "$action23h_expected_file" "$action23h_actual_file" || return 1
    [[ "$action23h_false_count" -eq 0 ]] || return 1
    [[ "$(grep -Fxc 'action_23h_acceptance=true' "$action23h_transcript")" -eq 1 ]] || return 1
    [[ "$(grep -Fxc 'action_23h_manifest_action=23h' "$action23h_transcript")" -eq 1 ]] || return 1
    [[ "$(grep -Fxc 'action_23h_record_family=AAAA' "$action23h_transcript")" -eq 1 ]] || return 1
    [[ "$(grep -Fxc 'action_23h_pihole_ftl_sha256=c77de6654c575e12fa1661f8ec901de67d9a623c3e9b965d4e32b550c132a7aa' "$action23h_transcript")" -eq 1 ]] || return 1
    [[ "$(grep -Fxc 'action_23h_pihole_domain_sha256=a8305acbc27a9133d6e68e8b1a0fe9a462a975919233d71866d54b2e98810f96' "$action23h_transcript")" -eq 1 ]] || return 1
    [[ "$(grep -Fxc 'action_23h_pihole_cache_reset=true' "$action23h_transcript")" -eq 1 ]] || return 1
    [[ "$(grep -Fxc 'action_23h_unbound_reload=true' "$action23h_transcript")" -eq 1 ]] || return 1
    [[ "$(grep -Fxc 'action_23h_peer_ssh=false' "$action23h_transcript")" -eq 1 ]] || return 1
    [[ "$(grep -Fxc 'action_23h_synchronization_executed=false' "$action23h_transcript")" -eq 1 ]] || return 1
    # conditional-validator-explicit-failures-end
}

self_test() {
    run_local_gates
    printf 'action_23h_outer_regression_skipped_for_self_test=true\n'
    printf 'action_23h_outer_node_contact=false\n'
    printf 'action_23h_outer_self_test_complete=true\n'
}

contract_test() {
    grep -Fq 'cd / && sudo -n /bin/bash -c' "$0"
    # The contract is intentionally matched as literal remote-shell text.
    # shellcheck disable=SC2016
    grep -Fq '/bin/bash "$remote_stage/apply-node-b-unbound-aaaa-records-action23h.sh"' "$0"
    grep -Fq 'validate_success_transcript' "$0"
    grep -Fq 'action_23h_outer_stdout_classification' "$0"
    grep -Fq 'action_23h_outer_stderr_classification' "$0"
    if grep -Eq '(^|[[:space:]])(rsync|scp|sftp)([[:space:]]|$)' "$0"; then
        return 1
    fi
    printf 'action_23h_outer_contract_test_complete=true\n'
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
        printf 'action_23h_outer_source_test_complete=true\n'
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
    printf 'action_23h_outer_regression=true\n'
else
    printf 'action_23h_outer_regression_skipped_for_transport_test=true\n'
fi

work_dir=$(mktemp -d)
readonly work_dir
candidate="$work_dir/pihole-local-zone.conf"
archive="$work_dir/action23h.tar"
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
    apply-node-b-unbound-aaaa-records-action23h.sh \
    -C "$work_dir" pihole-local-zone.conf

ssh_bin=ssh
if [[ "$transport_test" == true ]]; then
    ssh_bin=${ACTION23H_TEST_SSH_BIN:?ACTION23H_TEST_SSH_BIN is required}
fi
readonly ssh_bin

set +e
"$ssh_bin" -T \
    -o BatchMode=yes \
    -o ConnectTimeout=5 \
    -o HostKeyAlias="$host_alias" \
    -o StrictHostKeyChecking=yes \
    "pi@$host_address" \
    "cd / && sudo -n /bin/bash -c 'remote_stage=\$(mktemp -d /run/caddy-action23h.XXXXXX) && trap '\''rm -rf -- \"\$remote_stage\"'\'' EXIT && tar -C \"\$remote_stage\" -xf - && chown root:root \"\$remote_stage\"/* && chmod 0700 \"\$remote_stage\" && chmod 0700 \"\$remote_stage/apply-node-b-unbound-aaaa-records-action23h.sh\" && chmod 0600 \"\$remote_stage/pihole-local-zone.conf\" && /bin/bash \"\$remote_stage/apply-node-b-unbound-aaaa-records-action23h.sh\" --candidate \"\$remote_stage/pihole-local-zone.conf\"'" \
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
    printf 'action_23h_outer_protected_evidence_path=%s\n' "$work_dir" >&2
    exit 1
fi

if [[ "$ssh_status" -eq 0 ]] &&
    validate_success_transcript \
        "$stdout_capture" "$expected_labels" "$actual_labels" &&
    [[ ! -s "$stderr_capture" ]]; then
    printf 'action_23h_outer_ssh_status=0\n'
    printf 'action_23h_outer_node_b_contacted=true\n'
    printf 'action_23h_outer_dns_configuration_mutation=true\n'
    printf 'action_23h_outer_unbound_reload=true\n'
    printf 'action_23h_outer_pihole_cache_reset=true\n'
    printf 'action_23h_outer_acceptance=true\n'
    exit 0
fi

printf 'action_23h_outer_ssh_status=%s\n' "$ssh_status" >&2
if grep -Fqx 'manual_intervention_required=true' "$stderr_capture"; then
    printf 'action_23h_outer_manual_intervention_required=true\n' >&2
    exit 125
fi
if grep -Fqx 'action_23h_rollback_complete=true' "$stderr_capture"; then
    printf 'action_23h_outer_rollback_complete=true\n' >&2
fi
printf 'action_23h_outer_acceptance=false\n' >&2
exit 1
