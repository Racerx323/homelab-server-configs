#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH
readonly PATH

readonly prefix=action_23m_focused_validation
readonly driver_sha256=b7ca5f324b00b431cce86a800594f353dd0e2d46a70140fc875dac95ae3eea42
readonly outer_sha256=de36b74860647d130338a3475b3d163215293e2396604095ca725949fecd11b7
readonly regression_sha256=f3a06ec943bad6fdf7778568b0550708814da69eb87419dcab6c42802eaeda9a
readonly action_manifest_sha256=e9b257acd25d51d2477c2675452e4e3e4efcb09fcde6e8132340c3180ac3c055
readonly source_sha256=bcb145b39d8eadc187d9a2cb546d486c439602c05b0a77f2b7bcc82f4b0f5aad
readonly candidate_sha256=fa9f4850386ab1328f323c7c88bd9fa9ad0d5a84994b3066b6874deb5beb569c

test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
caddy_root=${test_directory%/tests}
readonly caddy_root
repository_root=${caddy_root%/Caddy}
readonly repository_root
workspace_root=${repository_root%/homelab-server-configs}
readonly workspace_root
readonly driver="$caddy_root/scripts/apply-node-a-unbound-srv-records-action23m.sh"
readonly outer="$caddy_root/scripts/run-node-a-unbound-srv-records-action23m-outer.sh"
readonly regression="$test_directory/action23m-node-a-unbound-srv-records-regression.sh"
readonly focused="$test_directory/action23m-focused-validation.sh"
readonly action_manifest="$caddy_root/manifests/dns-action23m-srv-records.yaml"
readonly source_local_zone="$workspace_root/homelab-dns/Unbound/configs/pihole0-local-zone.conf"
readonly source_primary="$workspace_root/homelab-dns/Unbound/configs/pihole0.conf"

file_hash() {
    sha256sum "$1" | awk '{ print $1 }'
}

record_check() {
    local action23m_focused_label=$1

    shift
    if "$@" >/dev/null; then
        printf '%s_check_%s=true\n' "$prefix" "$action23m_focused_label"
        return 0
    fi
    printf '%s_check_%s=false\n' "$prefix" "$action23m_focused_label" >&2
    return 1
}

native_parser_check() (
    local action23m_parser_dir
    local action23m_parser_candidate
    local action23m_parser_root

    if ! command -v unbound-checkconf >/dev/null; then
        [[ -z "${CADDY_VALIDATION_CONTAINER:-}" ]]
        printf '%s_native_parser_deferred_to_container=true\n' "$prefix"
        return 0
    fi
    action23m_parser_dir=$(mktemp -d)
    trap 'rm -rf -- "$action23m_parser_dir"' EXIT
    action23m_parser_candidate="$action23m_parser_dir/pihole-local-zone.conf"
    action23m_parser_root="$action23m_parser_dir/unbound.conf"
    awk '
        /homeassistant[.]local[.]theama[.]co[.].*IN A / { removed_a++; next }
        /local-data-ptr: "10[.]1[.]2[.]120 homeassistant[.]local[.]theama[.]co[.]"/ {
            removed_ptr++
            next
        }
        $0 == "    local-data: \"pihole-admin.local.theama.co. IN A 10.1.0.56\"" {
            if (!inserted_caddy_forward) {
                print
                print "    local-data: \"proxy.local.theama.co. IN A 10.1.0.56\""
                print "    local-data: \"pihole-admin.local.theama.co. IN AAAA fd36:5aa8:6971:1::56\""
                print "    local-data: \"proxy.local.theama.co. IN AAAA fd36:5aa8:6971:1::56\""
                inserted_caddy_forward++
            }
            next
        }
        $0 == "    local-data: \"proxy.local.theama.co. IN A 10.1.0.56\"" { next }
        $0 == "    local-data: \"pihole-admin.local.theama.co. IN AAAA fd36:5aa8:6971:1::56\"" { next }
        $0 == "    local-data: \"proxy.local.theama.co. IN AAAA fd36:5aa8:6971:1::56\"" { next }
        { print }
        END {
            if (removed_a != 1 || removed_ptr != 1 || inserted_caddy_forward != 1) { exit 42 }
        }
    ' "$source_local_zone" >"$action23m_parser_candidate"
    [[ "$(file_hash "$action23m_parser_candidate")" == "$candidate_sha256" ]]
    {
        printf 'include-toplevel: "%s"\n' "$source_primary"
        printf 'include-toplevel: "%s"\n' "$action23m_parser_candidate"
    } >"$action23m_parser_root"
    unbound-checkconf "$action23m_parser_root" >/dev/null
)

yaml_check() {
    if command -v yamllint >/dev/null; then
        yamllint -s "$action_manifest"
        return 0
    fi
    [[ "${CADDY_VALIDATION_CONTAINER:-}" == 1 ]] || return 1
    grep -Fqx -- '---' "$action_manifest" || return 1
    grep -Fqx 'action: 23m' "$action_manifest" || return 1
    grep -Fqx 'status: defined' "$action_manifest" || return 1
    grep -Fqx 'successor_of: 23k' "$action_manifest" || return 1
    grep -Fqx 'immutable_predecessor_must_not_run: true' "$action_manifest" || return 1
    grep -Fqx 'record_family: SRV' "$action_manifest" || return 1
    grep -Fqx '  definition_only: true' "$action_manifest" || return 1
    grep -Fqx '  node_contact_authorized: false' "$action_manifest" || return 1
    grep -Fqx '  live_mutation_authorized: false' "$action_manifest" || return 1
}

record_check driver_hash test "$(file_hash "$driver")" = "$driver_sha256"
record_check outer_hash test "$(file_hash "$outer")" = "$outer_sha256"
record_check regression_hash test "$(file_hash "$regression")" = "$regression_sha256"
record_check action_manifest_hash test \
    "$(file_hash "$action_manifest")" = "$action_manifest_sha256"
record_check source_hash test "$(file_hash "$source_local_zone")" = "$source_sha256"
record_check syntax /bin/bash -n "$driver" "$outer" "$regression" "$focused"
record_check shellcheck shellcheck "$driver" "$outer" "$regression" "$focused"
record_check canonical_format /bin/bash "$test_directory/shfmt-canonical.sh" --check \
    "$driver" "$outer" "$regression" "$focused"
record_check yaml yaml_check
record_check source_contract /bin/bash "$test_directory/run-source-test-in-context.sh" \
    --runner "$outer"
record_check native_parser native_parser_check
record_check regression /bin/bash "$regression"
record_check collision_policy /bin/bash \
    "$test_directory/check-shell-readonly-local-collisions-v2.sh" \
    "$driver" "$outer" "$regression" "$focused"
record_check conditional_policy /bin/bash \
    "$test_directory/conditional-validator-errexit-policy-regression.sh"
record_check output_evidence_policy /bin/bash \
    "$test_directory/transaction-output-evidence-policy-regression.sh"
record_check scalar_grep_policy /bin/bash \
    "$test_directory/multifile-grep-count-policy.sh" --check \
    "$driver" "$outer" "$regression" "$focused"
record_check portable_awk_policy /bin/bash \
    "$test_directory/portable-awk-policy.sh" --check \
    "$driver" "$outer" "$regression" "$focused"
record_check remote_cwd_policy /bin/bash \
    "$test_directory/remote-streamed-bash-cwd-policy.sh" --check "$outer"
record_check labeled_dns_policy /bin/bash \
    "$test_directory/labeled-dns-readiness-policy-regression.sh" \
    --production-test
record_check transcript_contract_policy /bin/bash \
    "$test_directory/transcript-contract-ratchet-policy-regression.sh"
record_check accepted_live_hash_policy /bin/bash \
    "$test_directory/accepted-live-hash-policy.sh" --check
record_check outer_gate_policy /bin/bash \
    "$test_directory/outer-local-gate-label-policy-regression.sh" \
    --runner "$outer"
record_check outer_gate_inventory_unique test \
    "$("$outer" --expected-local-gates | wc -l)" -eq \
    "$("$outer" --expected-local-gates | LC_ALL=C sort -u | wc -l)"

for action23m_focused_entrypoint in "$driver" "$outer" "$regression" "$focused"; do
    record_check "executable_index_$(basename "$action23m_focused_entrypoint" | tr '.-' '__')" \
        test "$(git ls-files --stage -- \
            "Caddy/${action23m_focused_entrypoint#"$caddy_root/"}" | awk '{ print $1 }')" = 100755
done

printf '%s_node_a_contacted=false\n' "$prefix"
printf '%s_node_b_contacted=false\n' "$prefix"
printf '%s_dns_configuration_mutation=false\n' "$prefix"
printf '%s_unbound_reload=false\n' "$prefix"
printf '%s_pihole_cache_reset=false\n' "$prefix"
printf '%s_action_23a_rerun=false\n' "$prefix"
printf '%s_action_23h_rerun=false\n' "$prefix"
printf '%s_action_23i_rerun=false\n' "$prefix"
printf '%s_action_23j_rerun=false\n' "$prefix"
printf '%s_action_23k_rerun=false\n' "$prefix"
printf '%s_action_23l_rerun=false\n' "$prefix"
printf '%s_action_executed=false\n' "$prefix"
printf '%s_complete_suite_bypassed=true\n' "$prefix"
printf '%s_complete=true\n' "$prefix"
