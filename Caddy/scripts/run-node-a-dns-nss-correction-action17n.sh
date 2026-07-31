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
readonly driver="$script_dir/apply-node-a-dns-nss-correction-action17n.sh"
readonly source_local_zone="$workspace_root/homelab-dns/Unbound/configs/pihole0-local-zone.conf"
readonly source_local_zone_sha256=fdd771afc7069e9bb5c08367798f454b36bd5fbc2be0be4b0cd0b251ca01218b
readonly candidate_local_zone_sha256=c70f709789223f91835f0f21c397f577d1e2bb24005a5defbf46055fb411dbb4
readonly accepted_local_zone_sha256=8a7d1c6d2235e6f37a98dfd3e10165b49968fcc5f3e898ce0b359f70bc0456d1
readonly host_alias=pihole0.local.theama.co
readonly host_address=10.1.0.53

file_hash() {
    sha256sum "$1" | awk '{ print $1 }'
}

verify_source() {
    [[ -f "$driver" && ! -L "$driver" ]]
    [[ -f "$source_local_zone" && ! -L "$source_local_zone" ]]
    [[ "$(file_hash "$source_local_zone")" == "$source_local_zone_sha256" ]]
    git -C "$workspace_root/homelab-dns" check-ignore -q \
        Unbound/configs/pihole0-local-zone.conf
    if git -C "$workspace_root/homelab-dns" ls-files --error-unmatch \
        Unbound/configs/pihole0-local-zone.conf >/dev/null 2>&1; then
        return 1
    fi
    bash -n "$driver"
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

self_test() {
    local test_dir
    local test_candidate

    verify_source
    test_dir=$(mktemp -d)
    test_candidate="$test_dir/pihole-local-zone.conf"
    trap 'rm -rf -- "$test_dir"' RETURN
    render_candidate "$test_candidate"
    verify_exact_six_record_advance \
        "$test_candidate" "$test_dir/reconstructed-live.conf"
    "$driver" --self-test >/dev/null
    printf 'action_17n_runner_self_test_complete=true\n'
}

contract_test() {
    grep -Fq "readonly host_alias=pihole0.local.theama.co" "$0"
    grep -Fq "readonly host_address=10.1.0.53" "$0"
    grep -Fq "sudo -n /bin/bash -c 'cd / &&" "$0"
    grep -Fq 'action_17n_acceptance=true' "$driver"
    grep -Fq 'action_17n_resolv_conf_mutation=false' "$driver"
    if grep -Eq '(^|[[:space:]])(rsync|scp|sftp)([[:space:]]|$)' "$driver"; then
        return 1
    fi
    printf 'action_17n_runner_contract_test_complete=true\n'
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
        printf 'action_17n_runner_source_test_complete=true\n'
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
archive="$work_dir/action17n.tar"
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
    -C "$script_dir" apply-node-a-dns-nss-correction-action17n.sh \
    -C "$work_dir" pihole-local-zone.conf

set +e
ssh -T \
    -o BatchMode=yes \
    -o ConnectTimeout=5 \
    -o HostKeyAlias="$host_alias" \
    -o StrictHostKeyChecking=yes \
    "pi@$host_address" \
    "sudo -n /bin/bash -c 'cd / && \
remote_stage=\$(mktemp -d /run/caddy-action17n.XXXXXX) && \
trap '\\''rm -rf -- \"\$remote_stage\"'\\'' EXIT && \
tar -C \"\$remote_stage\" -xf - && \
chown root:root \"\$remote_stage\"/* && \
chmod 0700 \"\$remote_stage\" && \
chmod 0700 \"\$remote_stage/apply-node-a-dns-nss-correction-action17n.sh\" && \
chmod 0600 \"\$remote_stage/pihole-local-zone.conf\" && \
/bin/bash \"\$remote_stage/apply-node-a-dns-nss-correction-action17n.sh\" \
--candidate \"\$remote_stage/pihole-local-zone.conf\"'" \
    <"$archive" >"$transcript" 2>&1
ssh_status=$?
set -e

failed_check_count=$(
    grep -Ec '^action_17n_check_[A-Za-z0-9_]+=false$' "$transcript" || true
)
readonly failed_check_count
if [[ "$ssh_status" -eq 0 ]] &&
    grep -Fqx 'action_17n_acceptance=true' "$transcript" &&
    grep -Fqx 'action_17n_resolv_conf_mutation=false' "$transcript" &&
    [[ "$failed_check_count" -eq 0 ]]; then
    printf 'action_17n_ssh_status=0\n'
    printf 'action_17n_runner_acceptance=true\n'
    exit 0
fi

sed -n '1,240p' "$transcript" >&2
printf 'action_17n_ssh_status=%s\n' "$ssh_status" >&2
if grep -Fqx 'action_17n_rollback_complete=true' "$transcript"; then
    printf 'action_17n_runner_rollback_complete=true\n' >&2
elif grep -Fqx 'manual_intervention_required=true' "$transcript"; then
    printf 'action_17n_runner_manual_intervention_required=true\n' >&2
    exit 125
fi
printf 'action_17n_runner_acceptance=false\n' >&2
exit 1
