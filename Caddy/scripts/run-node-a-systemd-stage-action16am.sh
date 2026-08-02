#!/usr/bin/env bash

set -euo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly driver_sha256=86452d84350ff12cb97216991de7c608656c996db53d1a7202b1752fe75a9bab
readonly stage_digest_sha256=305120fdb6b9c970a2aab12aa21ed88c06c3f77b9f63654cd0487fc2656e6e15
readonly -a expected_files=(
    scripts/check-certificate-expiry.sh
    scripts/lsyncd-sync-failure-notify.sh
    scripts/reconcile-release.sh
    scripts/validate-sync-health.sh
    systemd/caddy-cert-expiry.service
    systemd/caddy-cert-expiry.timer
    systemd/caddy-lsyncd.service
    systemd/caddy-sync-failure@.service
    systemd/caddy-sync-health.service
    systemd/caddy-sync-health.timer
    systemd/caddy-sync-reconcile.path
    systemd/caddy-sync-reconcile.service
    systemd/caddy-validate-reload.path
    systemd/caddy-validate-reload.service
    systemd/caddy.service.d/override.conf
    systemd/lighttpd.service.d/caddy-ha.conf
)
readonly -a expected_checksums=(
    'b4fec5ef37353aa944a3f319503b96ed60768e8bb1a204c539182f8aae1ee80f  scripts/check-certificate-expiry.sh'
    'cf59ceab47ae48e2793205c90cf39fccec236d21b1d55e39821560899dc83cd6  scripts/lsyncd-sync-failure-notify.sh'
    '9dcf65119599060b064ee820655f8e8d18839fdee1d1d2526d0e3e1c3eedbc1b  scripts/reconcile-release.sh'
    '77c5ab2ada350d24bf890eb055db58e6e46086cda6e023b533c7c793c181f56b  scripts/validate-sync-health.sh'
    '8c03321c483b5761266837b35b70b388430de0781dad24e4d6b489026b22a393  systemd/caddy-cert-expiry.service'
    '409a4494eff683c602ceced8d076eed1e9681e5d351665b54a3e614afb7f05f7  systemd/caddy-cert-expiry.timer'
    '93cbc36cea03b8b7e1605c44667463592cf64e0293ded9f816d1e34760a69ac8  systemd/caddy-lsyncd.service'
    'c8cf411dba10e1344d3fa14ba0006fb8e35eda1621630d5287d8619d0dda6286  systemd/caddy-sync-failure@.service'
    '1f89ac7a444ea7f92b6f7369df4efb3f73e2a5493693e15a4522015d86ac5b78  systemd/caddy-sync-health.service'
    '65bd3ff8f969301f17d6fdf457a8b6b1676489f5e536612cab57d61e0c6bdf8e  systemd/caddy-sync-health.timer'
    '1b2084ce0a382114c10a1211dbdec1628c9b32cd84450c9d7b09a3ba0a6425fc  systemd/caddy-sync-reconcile.path'
    '848787b77cc03fe3855961cc94ad2e6aa4e05934851a98643edcdf17d84bf8eb  systemd/caddy-sync-reconcile.service'
    'f7fde941ae045e5697aa9e966e4f9a40d55a1f08f413f02cf9f8775046331bb7  systemd/caddy-validate-reload.path'
    '51be7495194143210bf805fdaa78072162eed028e8da3b3507f73f416cde8322  systemd/caddy-validate-reload.service'
    'a292487f4cbde99abce048b97ec15dbae8ef511ec845dcf5740f343e143f39df  systemd/caddy.service.d/override.conf'
    '6856404c78b9fbc7b8d0f2ddd8b184abe039df28a0d4dc0762dc7ef66747487e  systemd/lighttpd.service.d/caddy-ha.conf'
)

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_dir
caddy_root=$(cd -- "$script_dir/.." && pwd)
readonly caddy_root
readonly driver="$script_dir/stage-node-a-systemd-artifacts-action16am.sh"

verify_sources() {
    local checksum expected_hash relative_path source_path

    [[ -f "$driver" && ! -L "$driver" ]]
    [[ "$(stat -c '%U:%G:%a' "$driver")" == aaron:aaron:755 ]]
    [[ "$(sha256sum "$driver" | awk '{ print $1 }')" == "$driver_sha256" ]]
    [[ "${#expected_files[@]}" -eq 16 ]]
    [[ "${#expected_checksums[@]}" -eq 16 ]]
    for checksum in "${expected_checksums[@]}"; do
        expected_hash=${checksum%% *}
        relative_path=${checksum#*  }
        source_path="$caddy_root/$relative_path"
        [[ -f "$source_path" && ! -L "$source_path" ]]
        [[ "$(sha256sum "$source_path" | awk '{ print $1 }')" == "$expected_hash" ]]
        case "$relative_path" in
            scripts/*)
                [[ "$(stat -c '%U:%G:%a' "$source_path")" == aaron:aaron:755 ]]
                ;;
            *)
                [[ "$(stat -c '%U:%G:%a' "$source_path")" == aaron:aaron:644 ]]
                ;;
        esac
    done
}

mode=run
if [[ "${1:-}" == --self-test && $# -eq 1 ]]; then
    [[ "$driver_sha256" =~ ^[0-9a-f]{64}$ ]]
    [[ "$stage_digest_sha256" =~ ^[0-9a-f]{64}$ ]]
    verify_sources
    bash -n "$driver"
    "$driver" --self-test >/dev/null
    printf 'action_16am_systemd_stage_runner_self_test_complete=true\n'
    exit 0
elif [[ "${1:-}" == --local-test && $# -eq 1 ]]; then
    mode=local-test
elif (($#)); then
    printf 'Usage: %s [--self-test|--local-test]\n' "${0##*/}" >&2
    exit 2
fi

verify_sources
work_dir=$(mktemp -d /tmp/caddy-action16am.XXXXXX)
readonly work_dir
readonly archive="$work_dir/payload.tar"
readonly extracted="$work_dir/extracted"
readonly remote_output="$work_dir/remote.out"
readonly remote_error="$work_dir/remote.err"
cleanup() {
    rm -rf -- "$work_dir"
}
trap cleanup EXIT

finish() {
    local status=$1

    cleanup
    trap - EXIT
    if [[ -e "$work_dir" || -L "$work_dir" ]]; then
        printf 'action_16am_local_cleanup_complete=false\n' >&2
        exit 97
    fi
    printf 'action_16am_local_cleanup_complete=true\n'
    exit "$status"
}

tar --format=posix -C "$caddy_root" -cf "$archive" \
    "${expected_files[@]}"
mapfile -t archive_files < <(
    tar -tf "$archive" |
        sed 's#^\./##' |
        sed '/^$/d' |
        sort
)
[[ "${archive_files[*]}" == "${expected_files[*]}" ]]
printf 'local_archive_file_set_valid=true\n'

if [[ "$mode" == local-test ]]; then
    install -d -m 0750 "$extracted"
    tar --extract --file "$archive" --directory "$extracted" \
        --no-same-owner --no-same-permissions
    find "$extracted" -type d -exec chmod 0750 {} +
    find "$extracted/systemd" -type f -exec chmod 0644 {} +
    find "$extracted/scripts" -type f -exec chmod 0755 {} +
    (
        cd "$extracted"
        printf '%s\n' "${expected_checksums[@]}" |
            sha256sum --check --status
        observed_digest=$(
            printf '%s\n' "${expected_files[@]}" |
                sort |
                xargs sha256sum |
                sha256sum |
                awk '{ print $1 }'
        )
        [[ "$observed_digest" == "$stage_digest_sha256" ]]
    )
    printf 'local_archive_hashes_and_digest_valid=true\n'
    finish 0
fi

remote_script=$(<"$driver")
printf -v remote_command 'sudo -n /bin/bash -c %q' "$remote_script"
set +e
ssh -T \
    -o BatchMode=yes \
    -o ConnectTimeout=5 \
    -o HostKeyAlias=pihole0.local.theama.co \
    -o StrictHostKeyChecking=yes \
    pi@10.1.0.53 \
    "$remote_command" <"$archive" >"$remote_output" 2>"$remote_error"
ssh_status=$?
set -e

if grep -Eq \
    'BEGIN [A-Z ]*PRIVATE KEY|CADDY_TLS_PRIVATE_KEY_PEM|PRIVATE_KEY=' \
    "$remote_output" "$remote_error"; then
    printf 'Action 16am suppressed unexpected private material.\n' >&2
    finish 97
fi

cat "$remote_output"
cat "$remote_error" >&2
printf 'ssh_exit_status=%s\n' "$ssh_status"
if ! grep -Fxq 'action_16am_remote_reached=true' "$remote_output"; then
    finish "$ssh_status"
fi

if [[ "$ssh_status" -ne 0 ]]; then
    if grep -Fxq 'action_16am_mutation_started=true' "$remote_output"; then
        if ! grep -Fxq 'action_16am_stage_rollback_complete=true' \
            "$remote_error"; then
            printf 'Action 16am lacks required rollback evidence.\n' >&2
            finish 97
        fi
    fi
    if grep -Fq 'manual_intervention_required=true' \
        "$remote_output" "$remote_error"; then
        finish 97
    fi
    finish "$ssh_status"
fi

required_markers=(
    preflight_live_state=true
    preflight_stage_absent=true
    preflight_protected_state_capture=true
    action_16am_preflight_valid=true
    action_16am_mutation_started=true
    stage_create=true
    stage_extract=true
    stage_owner=true
    stage_directory_modes=true
    stage_unit_modes=true
    stage_script_modes=true
    stage_file_set=true
    stage_directory_set=true
    stage_file_count=true
    stage_directory_count=true
    stage_symlink_count=true
    stage_root_meta=true
    stage_digest=true
    live_state_with_stage=true
    protected_state_unchanged=true
    first_failure=none
    stage_path=/var/tmp/caddy-systemd-node-a-action16am
    stage_owner_mode=root:root:750
    stage_file_count=16
    stage_digest=305120fdb6b9c970a2aab12aa21ed88c06c3f77b9f63654cd0487fc2656e6e15
    stage_retained=true
    systemd_daemon_reload_performed=false
    service_mutations=false
    action_16am_systemd_stage_complete=true
)
for marker in "${required_markers[@]}"; do
    if ! grep -Fxq "$marker" "$remote_output"; then
        printf 'Missing required marker: %s\n' "$marker" >&2
        finish 97
    fi
done
if grep -Eq '=false$|manual_intervention_required=true|rollback_complete=' \
    "$remote_output" "$remote_error"; then
    printf 'Action 16am emitted failure or rollback evidence on success.\n' >&2
    finish 97
fi
finish 0
