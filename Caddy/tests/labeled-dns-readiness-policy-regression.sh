#!/usr/bin/env bash

set -euo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_dir
caddy_root=$(cd -- "$script_dir/.." && pwd)
readonly caddy_root
readonly inspector="$caddy_root/scripts/inspect-node-a-dns-nss-post-rollback-action17n-a.sh"
readonly historical_driver="$caddy_root/scripts/apply-node-a-dns-nss-correction-action17n.sh"
readonly historical_driver_sha256=7b24de1f46fd9fc04a0aec2819e3c0c7f728cef265720c4a1df3c93389c81990
readonly corrected_driver="$caddy_root/scripts/apply-node-a-dns-nss-correction-action17n-retry.sh"
readonly agent_policy="$caddy_root/../AGENTS.md"

file_hash() {
    sha256sum "$1" | awk '{ print $1 }'
}

extract_readiness_block() {
    local extraction_source=$1

    sed -n \
        '/^# BEGIN LABELED DNS READINESS$/,/^# END LABELED DNS READINESS$/p' \
        "$extraction_source"
}

run_policy_regression() {
    local readiness_block
    local corrected_readiness_block
    local probe_labels
    local corrected_probe_key
    local -a corrected_probe_keys=(
        direct_unbound_peer_aaaa
        direct_unbound_node_a_aaaa
        direct_unbound_peer_ptr6
        local_pihole_peer_aaaa
        local_pihole_node_a_aaaa
        local_pihole_peer_ptr6
    )

    [[ -f "$inspector" && ! -L "$inspector" ]]
    [[ -f "$historical_driver" && ! -L "$historical_driver" ]]
    [[ "$(file_hash "$historical_driver")" == "$historical_driver_sha256" ]]
    [[ -f "$corrected_driver" && ! -L "$corrected_driver" ]]
    grep -Fq 'Every fail-closed infrastructure validator must emit one' \
        "$agent_policy"
    grep -Fq 'assertion per observable condition.' "$agent_policy"
    readiness_block=$(extract_readiness_block "$inspector")
    [[ "$(grep -Fxc '# BEGIN LABELED DNS READINESS' \
        <<<"$readiness_block")" -eq 1 ]]
    [[ "$(grep -Fxc '# END LABELED DNS READINESS' \
        <<<"$readiness_block")" -eq 1 ]]
    if grep -Eq '&&|[|][|]|^[[:space:]]*(if|while)[[:space:]]' \
        <<<"$readiness_block"; then
        printf 'Labeled DNS readiness block contains a compound predicate.\n' \
            >&2
        exit 1
    fi
    probe_labels=$(
        awk '
            /^[[:space:]]*(dns_probe|reverse_dns_probe)[[:space:]]/ {
                print $2
            }
        ' <<<"$readiness_block"
    )
    [[ "$(wc -l <<<"$probe_labels")" -eq 6 ]]
    [[ "$(LC_ALL=C sort -u <<<"$probe_labels" | wc -l)" -eq 6 ]]
    while IFS= read -r probe_label; do
        [[ "$probe_label" =~ ^[a-z0-9_]+$ ]]
    done <<<"$probe_labels"
    grep -Fq "assert_equal \"\${probe_label}_status\"" "$inspector"
    grep -Fq \
        "record_assertion \"\${probe_label}_answer_safe\" true" "$inspector"
    grep -Fq \
        "assert_equal \"\${reverse_probe_label}_status\"" "$inspector"
    grep -Fq \
        "record_assertion \"\${reverse_probe_label}_answer_safe\" true" \
        "$inspector"
    grep -Fq \
        "record_assertion \"\${file_shape_label}_regular\"" "$inspector"
    grep -Fq \
        "record_assertion \"\${file_shape_label}_not_symlink\"" "$inspector"
    grep -Fq \
        "record_assertion \"\${path_absent_label}_entry_absent\"" "$inspector"
    grep -Fq \
        "record_assertion \"\${path_absent_label}_symlink_absent\"" \
        "$inspector"
    grep -Fq "assert_equal \"state_\${state_component}_unchanged\"" \
        "$inspector"
    if grep -Fq 'assert_equal state_unchanged' "$inspector"; then
        printf 'State continuity is hidden under one aggregate label.\n' >&2
        exit 1
    fi

    corrected_readiness_block=$(
        sed -n \
            '/^# DNS_READINESS_BLOCK_BEGIN$/,/^# DNS_READINESS_BLOCK_END$/p' \
            "$corrected_driver"
    )
    [[ "$(grep -Fxc '# DNS_READINESS_BLOCK_BEGIN' \
        <<<"$corrected_readiness_block")" -eq 1 ]]
    [[ "$(grep -Fxc '# DNS_READINESS_BLOCK_END' \
        <<<"$corrected_readiness_block")" -eq 1 ]]
    for corrected_probe_key in "${corrected_probe_keys[@]}"; do
        grep -Fq "$corrected_probe_key" <<<"$corrected_readiness_block"
    done
    grep -Fq \
        "\"readiness_\${readiness_key}_command_status\"" "$corrected_driver"
    grep -Fq \
        "\"readiness_\${readiness_key}_answer_safe\"" "$corrected_driver"
    grep -Fq \
        "\"readiness_\${readiness_key}_answer_exact\"" "$corrected_driver"
    grep -Fq \
        'printf '\''action_17n_retry_value_readiness_%s_answer=%s' \
        "$corrected_driver"
    grep -Fq \
        'printf '\''action_17n_retry_value_readiness_%s_iteration=%s' \
        "$corrected_driver"
    if grep -Eq \
        'bounded_dns_readiness|query_exact|query_reverse_exact' \
        <<<"$corrected_readiness_block"; then
        printf 'Corrected retry reintroduced an aggregate DNS gate.\n' >&2
        exit 1
    fi
    [[ "$(grep -Fxc "    printf 'action=17n\\n'" \
        "$corrected_driver")" -eq 1 ]]
    [[ "$(grep -Fxc "    printf 'action=17m\\n'" \
        "$corrected_driver" || true)" -eq 0 ]]
    printf 'labeled_dns_readiness_policy_regression_complete=true\n'
}

case "${1:-}" in
    --self-test | --production-test)
        [[ $# -eq 1 ]]
        run_policy_regression
        ;;
    *)
        printf 'Usage: %s --self-test|--production-test\n' "${0##*/}" >&2
        exit 2
        ;;
esac
