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
workspace_root=$(cd -- "$caddy_root/../.." && pwd)
readonly workspace_root
readonly driver="$script_dir/apply-node-a-dns-nss-correction-action17n-reset-retry.sh"
readonly driver_sha256=94c1ea0cf40cda26fa28130c1167f6f00f73957c9ed7430a8e8ec1510f7ef755
readonly historical_driver="$script_dir/apply-node-a-dns-nss-correction-action17n-retry.sh"
readonly historical_driver_sha256=0d56be5b31f141d7b6ab4d92164450d66675dbd9fe05f12a0903644915a91620
readonly historical_runner="$script_dir/run-node-a-dns-nss-correction-action17n-retry.sh"
readonly historical_runner_sha256=0b05f20f33babb1a8acca8f8ad095ffc0dd0c88dfbd1dfcfe81e67972b6eeb23
readonly historical_regression="$caddy_root/tests/action17n-retry-node-a-dns-nss-correction-regression.sh"
readonly historical_regression_sha256=9869fd512b1eb7a5656c5416c1d6cfc5098b15529dfb22d6dfbde8e959d81847
readonly source_local_zone="$workspace_root/homelab-dns/Unbound/configs/pihole0-local-zone.conf"
readonly source_local_zone_sha256=fdd771afc7069e9bb5c08367798f454b36bd5fbc2be0be4b0cd0b251ca01218b
readonly candidate_local_zone_sha256=c70f709789223f91835f0f21c397f577d1e2bb24005a5defbf46055fb411dbb4
readonly accepted_local_zone_sha256=8a7d1c6d2235e6f37a98dfd3e10165b49968fcc5f3e898ce0b359f70bc0456d1
readonly host_alias=pihole0.local.theama.co
readonly host_address=10.1.0.53
readonly -a readiness_keys=(
    direct_unbound_peer_aaaa
    direct_unbound_node_a_aaaa
    direct_unbound_peer_ptr6
    local_pihole_peer_aaaa
    local_pihole_node_a_aaaa
    local_pihole_peer_ptr6
)

file_hash() {
    sha256sum "$1" | awk '{ print $1 }'
}

verify_source() {
    [[ -f "$driver" && ! -L "$driver" ]]
    [[ "$(file_hash "$driver")" == "$driver_sha256" ]]
    [[ -f "$historical_driver" && ! -L "$historical_driver" ]]
    [[ "$(file_hash "$historical_driver")" == "$historical_driver_sha256" ]]
    [[ -f "$historical_runner" && ! -L "$historical_runner" ]]
    [[ "$(file_hash "$historical_runner")" == "$historical_runner_sha256" ]]
    [[ -f "$historical_regression" && ! -L "$historical_regression" ]]
    [[ "$(file_hash "$historical_regression")" == "$historical_regression_sha256" ]]
    [[ -f "$source_local_zone" && ! -L "$source_local_zone" ]]
    [[ "$(file_hash "$source_local_zone")" == "$source_local_zone_sha256" ]]
    git -C "$workspace_root/homelab-dns" check-ignore -q \
        Unbound/configs/pihole0-local-zone.conf
    if git -C "$workspace_root/homelab-dns" ls-files --error-unmatch \
        Unbound/configs/pihole0-local-zone.conf >/dev/null 2>&1; then
        return 1
    fi
    bash -n "$driver" "$historical_driver" "$historical_runner" \
        "$historical_regression"
}

render_candidate() {
    local rendered_path=$1

    awk '
        /homeassistant[.]local[.]theama[.]co[.].*IN A / { removed_a++; next }
        /local-data-ptr: "10[.]1[.]2[.]120 homeassistant[.]local[.]theama[.]co[.]"/ {
            removed_ptr++
            next
        }
        { print }
        END {
            if (removed_a != 1 || removed_ptr != 1) {
                exit 42
            }
        }
    ' "$source_local_zone" >"$rendered_path"
    [[ "$(file_hash "$rendered_path")" == "$candidate_local_zone_sha256" ]]
    [[ "$(grep -Ec 'homeassistant[.]local[.]theama[.]co' \
        "$rendered_path" || true)" -eq 0 ]]
}

verify_exact_six_record_advance() {
    local candidate_path=$1
    local reconstructed_path=$2

    awk '
        /pihole[.]local[.]theama[.]co[.].*IN AAAA fd36:5aa8:6971:1::55/ {
            removed++
            next
        }
        /pihole0[.]local[.]theama[.]co[.].*IN AAAA fd36:5aa8:6971:1::53/ {
            removed++
            next
        }
        /pihole00[.]local[.]theama[.]co[.].*IN AAAA fd36:5aa8:6971:1::54/ {
            removed++
            next
        }
        /local-data-ptr: "fd36:5aa8:6971:1::55 pihole[.]local[.]theama[.]co[.]"/ {
            removed++
            next
        }
        /local-data-ptr: "fd36:5aa8:6971:1::53 pihole0[.]local[.]theama[.]co[.]"/ {
            removed++
            next
        }
        /local-data-ptr: "fd36:5aa8:6971:1::54 pihole00[.]local[.]theama[.]co[.]"/ {
            removed++
            next
        }
        { print }
        END {
            if (removed != 6) {
                exit 43
            }
        }
    ' "$candidate_path" >"$reconstructed_path"
    [[ "$(file_hash "$reconstructed_path")" == "$accepted_local_zone_sha256" ]]
}

validate_success_transcript() {
    local validation_transcript=$1
    local validation_key
    local validation_assertion_count
    local validation_unique_count

    grep -Fqx 'action_17n_reset_retry_acceptance=true' "$validation_transcript"
    grep -Fqx 'action_17n_reset_retry_manifest_action=17n-reset-retry' \
        "$validation_transcript"
    grep -Fqx 'action_17n_reset_retry_resolv_conf_mutation=false' \
        "$validation_transcript"
    grep -Fqx 'action_17n_reset_retry_peer_connections=false' \
        "$validation_transcript"
    grep -Fqx 'action_17n_reset_retry_synchronization_executed=false' \
        "$validation_transcript"
    grep -Fqx 'action_17n_reset_retry_pihole_cache_reset=true' \
        "$validation_transcript"
    grep -Fqx 'action_17n_reset_retry_service_restart=true' \
        "$validation_transcript"
    for reset_check in \
        pihole_restartdns pihole_ftl_active_after_reset \
        pihole_ftl_pid_after_reset_nonzero \
        pihole_ftl_pid_changed_after_reset \
        pihole_ftl_restarts_after_reset_numeric \
        pihole_ftl_active_at_acceptance \
        pihole_ftl_pid_stable_after_reset \
        pihole_ftl_restarts_stable_after_reset; do
        grep -Fqx "action_17n_reset_retry_check_${reset_check}=true" \
            "$validation_transcript"
    done
    [[ "$(grep -Ec '^action_17n_reset_retry_check_[a-z0-9_]+=false$' \
        "$validation_transcript" || true)" -eq 0 ]]

    validation_assertion_count=$(
        grep -Ec '^action_17n_reset_retry_check_[a-z0-9_]+=(true|false)$' \
            "$validation_transcript" || true
    )
    validation_unique_count=$(
        sed -n \
            's/^\(action_17n_reset_retry_check_[a-z0-9_]*\)=\(true\|false\)$/\1/p' \
            "$validation_transcript" |
            LC_ALL=C sort -u |
            wc -l
    )
    [[ "$validation_assertion_count" -eq "$validation_unique_count" ]]

    for validation_key in "${readiness_keys[@]}"; do
        grep -Fqx \
            "action_17n_reset_retry_check_readiness_${validation_key}_command_status=true" \
            "$validation_transcript"
        grep -Fqx \
            "action_17n_reset_retry_check_readiness_${validation_key}_answer_safe=true" \
            "$validation_transcript"
        grep -Fqx \
            "action_17n_reset_retry_check_readiness_${validation_key}_answer_exact=true" \
            "$validation_transcript"
        [[ "$(grep -Ec \
            "^action_17n_reset_retry_value_readiness_${validation_key}_answer=[A-Za-z0-9:.,_-]+$" \
            "$validation_transcript")" -eq 1 ]]
        [[ "$(grep -Ec \
            "^action_17n_reset_retry_value_readiness_${validation_key}_iteration=([1-9]|1[0-9]|20)$" \
            "$validation_transcript")" -eq 1 ]]
    done

    if grep -Eq \
        '^action_17n_reset_retry_(check|value)_[^=]+=.*[^A-Za-z0-9:.,_/-].*$' \
        "$validation_transcript"; then
        return 1
    fi
}

self_test() (
    local self_test_dir
    local self_test_candidate

    verify_source
    self_test_dir=$(mktemp -d)
    self_test_candidate="$self_test_dir/pihole-local-zone.conf"
    trap 'rm -rf -- "$self_test_dir"' EXIT
    render_candidate "$self_test_candidate"
    verify_exact_six_record_advance \
        "$self_test_candidate" "$self_test_dir/reconstructed-live.conf"
    "$driver" --self-test >/dev/null
    printf 'action_17n_reset_retry_runner_self_test_complete=true\n'
)

contract_test() {
    local contract_key

    grep -Fq "readonly host_alias=pihole0.local.theama.co" "$0"
    grep -Fq "readonly host_address=10.1.0.53" "$0"
    grep -Fq "sudo -n /bin/bash -c 'cd / &&" "$0"
    grep -Fq "printf 'action=17n-reset-retry" "$driver"
    grep -Fq 'run_check pihole_restartdns perform_pihole_reset' "$driver"
    grep -Fq 'rollback_record_status pihole_restartdns' "$driver"
    if grep -Fq "printf 'action=17m" "$driver"; then
        return 1
    fi
    grep -Fq 'action_17n_reset_retry_acceptance=true' "$driver"
    grep -Fq 'action_17n_reset_retry_resolv_conf_mutation=false' "$driver"
    grep -Fq '# DNS_READINESS_BLOCK_BEGIN' "$driver"
    grep -Fq '# DNS_READINESS_BLOCK_END' "$driver"
    for contract_key in "${readiness_keys[@]}"; do
        grep -Fq "$contract_key" "$driver"
    done
    if grep -Fq 'bounded_dns_readiness' "$driver"; then
        return 1
    fi
    if grep -Eq '(^|[[:space:]])(rsync|scp|sftp)([[:space:]]|$)' \
        "$driver"; then
        return 1
    fi
    printf 'action_17n_reset_retry_runner_contract_test_complete=true\n'
}

case "${1:-}" in
    --self-test)
        [[ $# -eq 1 ]]
        self_test
        exit 0
        ;;
    --source-test)
        [[ $# -eq 1 ]]
        verify_source
        printf 'action_17n_reset_retry_runner_source_test_complete=true\n'
        exit 0
        ;;
    --contract-test)
        [[ $# -eq 1 ]]
        contract_test
        exit 0
        ;;
    "") ;;
    *)
        printf 'Usage: %s [--self-test|--source-test|--contract-test]\n' \
            "${0##*/}" >&2
        exit 2
        ;;
esac

verify_source
work_dir=$(mktemp -d)
readonly work_dir
candidate="$work_dir/pihole-local-zone.conf"
archive="$work_dir/action17n-reset-retry.tar"
transcript="$work_dir/transcript"
readonly candidate archive transcript
cleanup() {
    # shellcheck disable=SC2317
    rm -rf -- "$work_dir"
}
trap cleanup EXIT

render_candidate "$candidate"
verify_exact_six_record_advance \
    "$candidate" "$work_dir/reconstructed-live.conf"
chmod 0600 "$candidate"
tar -C "$work_dir" -cf "$archive" \
    -C "$script_dir" apply-node-a-dns-nss-correction-action17n-reset-retry.sh \
    -C "$script_dir" apply-node-a-dns-nss-correction-action17n-retry.sh \
    -C "$work_dir" pihole-local-zone.conf

set +e
ssh -T \
    -o BatchMode=yes \
    -o ConnectTimeout=5 \
    -o HostKeyAlias="$host_alias" \
    -o StrictHostKeyChecking=yes \
    "pi@$host_address" \
    "sudo -n /bin/bash -c 'cd / && \
remote_stage=\$(mktemp -d /run/caddy-action17n-reset-retry.XXXXXX) && \
trap '\\''rm -rf -- \"\$remote_stage\"'\\'' EXIT && \
tar -C \"\$remote_stage\" -xf - && \
chown root:root \"\$remote_stage\"/* && \
chmod 0700 \"\$remote_stage\" && \
chmod 0700 \"\$remote_stage/apply-node-a-dns-nss-correction-action17n-reset-retry.sh\" && \
chmod 0600 \"\$remote_stage/apply-node-a-dns-nss-correction-action17n-retry.sh\" && \
chmod 0600 \"\$remote_stage/pihole-local-zone.conf\" && \
/bin/bash \"\$remote_stage/apply-node-a-dns-nss-correction-action17n-reset-retry.sh\" \
--candidate \"\$remote_stage/pihole-local-zone.conf\"'" \
    <"$archive" >"$transcript" 2>&1
ssh_status=$?
set -e

if [[ "$ssh_status" -eq 0 ]] &&
    validate_success_transcript "$transcript"; then
    printf 'action_17n_reset_retry_ssh_status=0\n'
    printf 'action_17n_reset_retry_runner_acceptance=true\n'
    exit 0
fi

sed -n '1,320p' "$transcript" >&2
printf 'action_17n_reset_retry_ssh_status=%s\n' "$ssh_status" >&2
if grep -Fqx 'action_17n_reset_retry_rollback_complete=true' "$transcript"; then
    printf 'action_17n_reset_retry_runner_rollback_complete=true\n' >&2
elif grep -Fqx 'manual_intervention_required=true' "$transcript"; then
    printf 'action_17n_reset_retry_runner_manual_intervention_required=true\n' >&2
    exit 125
fi
printf 'action_17n_reset_retry_runner_acceptance=false\n' >&2
exit 1
