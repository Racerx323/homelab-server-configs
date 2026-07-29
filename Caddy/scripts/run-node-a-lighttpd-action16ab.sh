#!/usr/bin/env bash

set -euo pipefail
umask 077

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
caddy_root=$(cd -- "$script_dir/.." && pwd)
readonly node_driver="$script_dir/stage-node-a-lighttpd-action16ab.sh"
readonly renderer="$script_dir/prepare-lighttpd-config.sh"
readonly desired_state="$caddy_root/configs/lighttpd/desired-state.conf"
readonly node_driver_sha256=064fae668c82624729b410490b3a5dd18fd2da0d9bde60e20488b3817729c1a5
readonly renderer_sha256=ce9a78aa487ce55c6fbba553b238160687852361d81c9b37179e4def8f83166f
readonly desired_state_sha256=8299970d5bb3793859071cd82f794dbae84955a6af931cf35d1509141f689027

archive=
cleanup_local() {
    local status=$?

    trap - EXIT
    if [[ -n "$archive" && (-e "$archive" || -L "$archive") ]]; then
        rm -f -- "$archive"
    fi
    exit "$status"
}
trap cleanup_local EXIT

verify_sources() {
    local source_file

    for source_file in "$node_driver" "$renderer" "$desired_state"; do
        [[ -f "$source_file" && ! -L "$source_file" ]]
    done
    [[ "$(stat -c '%a' "$node_driver")" == 755 ]]
    [[ "$(stat -c '%a' "$renderer")" == 755 ]]
    [[ "$(stat -c '%a' "$desired_state")" == 644 ]]
    [[ "$(sha256sum "$node_driver" | awk '{ print $1 }')" == "$node_driver_sha256" ]]
    [[ "$(sha256sum "$renderer" | awk '{ print $1 }')" == "$renderer_sha256" ]]
    [[ "$(sha256sum "$desired_state" | awk '{ print $1 }')" == "$desired_state_sha256" ]]
}

remote_script=$(
    cat <<'REMOTE_SCRIPT'
set -euo pipefail
umask 077

readonly source_stage=/var/tmp/caddy-ha-lighttpd-node-a-action16ab-source
readonly candidate=/var/tmp/caddy-ha-lighttpd-node-a-action16ab
readonly driver="$source_stage/scripts/stage-node-a-lighttpd-action16ab.sh"
readonly renderer="$source_stage/scripts/prepare-lighttpd-config.sh"
readonly desired_state="$source_stage/configs/lighttpd/desired-state.conf"
readonly driver_sha256=064fae668c82624729b410490b3a5dd18fd2da0d9bde60e20488b3817729c1a5
readonly renderer_sha256=ce9a78aa487ce55c6fbba553b238160687852361d81c9b37179e4def8f83166f
readonly desired_state_sha256=8299970d5bb3793859071cd82f794dbae84955a6af931cf35d1509141f689027

complete=false
cleanup() {
    local status=$?
    local cleanup_failed=false

    trap - EXIT
    set +e
    rm -rf -- "$source_stage" || cleanup_failed=true
    if [[ "$complete" != true ]]; then
        rm -rf -- "$candidate" || cleanup_failed=true
    fi
    [[ ! -e "$source_stage" && ! -L "$source_stage" ]] ||
        cleanup_failed=true
    if [[ "$complete" != true ]]; then
        [[ ! -e "$candidate" && ! -L "$candidate" ]] ||
            cleanup_failed=true
    fi
    if [[ "$cleanup_failed" == true ]]; then
        printf 'lighttpd_stage_action16ab_wrapper_cleanup_complete=false\n' >&2
        printf 'manual_intervention_required=true\n' >&2
        exit 97
    fi
    printf 'lighttpd_stage_action16ab_source_cleanup_complete=true\n'
    exit "$status"
}
trap cleanup EXIT

[[ "$(id -u)" -eq 0 ]]
[[ "$(hostname)" == j1-svpihole0 ]]
[[ ! -e "$source_stage" && ! -L "$source_stage" ]]
[[ ! -e "$candidate" && ! -L "$candidate" ]]
install -d -o root -g root -m 0700 -- "$source_stage"
tar -xf - -C "$source_stage" --no-same-owner --no-same-permissions

mapfile -t extracted < <(
    cd "$source_stage"
    find . \( -type f -o -type l \) -print | sort
)
expected=(
    ./configs/lighttpd/desired-state.conf
    ./scripts/prepare-lighttpd-config.sh
    ./scripts/stage-node-a-lighttpd-action16ab.sh
)
[[ "${extracted[*]}" == "${expected[*]}" ]]
if find "$source_stage" -type l -print -quit | grep -q .; then
    exit 1
fi
chown -R root:root -- "$source_stage"
chmod 0700 "$driver" "$renderer"
chmod 0600 "$desired_state"
[[ "$(sha256sum "$driver" | awk '{ print $1 }')" == "$driver_sha256" ]]
[[ "$(sha256sum "$renderer" | awk '{ print $1 }')" == "$renderer_sha256" ]]
[[ "$(sha256sum "$desired_state" | awk '{ print $1 }')" == \
    "$desired_state_sha256" ]]

"$driver"
complete=true
REMOTE_SCRIPT
)
bash -n <<<"$remote_script"

if [[ "${1:-}" == --self-test ]]; then
    verify_sources
    printf 'action_16ab_runner_self_test_complete=true\n'
    exit 0
elif (($#)); then
    printf 'Usage: %s [--self-test]\n' "${0##*/}" >&2
    exit 2
fi

verify_sources

archive=$(mktemp --tmpdir action16ab-lighttpd.XXXXXX.tar)
tar -C "$caddy_root" -cf "$archive" \
    scripts/stage-node-a-lighttpd-action16ab.sh \
    scripts/prepare-lighttpd-config.sh \
    configs/lighttpd/desired-state.conf

printf -v remote_command 'sudo -n /bin/bash -c %q' "$remote_script"

ssh -T \
    -o BatchMode=yes \
    -o ConnectTimeout=5 \
    -o HostKeyAlias=pihole0.local.theama.co \
    -o StrictHostKeyChecking=yes \
    pi@10.1.0.53 \
    "$remote_command" <"$archive"
