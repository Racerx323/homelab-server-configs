#!/usr/bin/env bash

set -euo pipefail
set +x
umask 077
PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH
readonly PATH

readonly retained_stage=/var/tmp/caddy-sync-ssh-node-a-action16aj-e
readonly parent_path=/var/tmp
readonly libexec=/usr/local/libexec
readonly -a expected_stage_files=(
    caddy-sync-rsync-receiver
    node-b-host-ed25519.pub
    node-b-sync-ed25519.pub
    setup-sync-ssh.sh
    validate-sync-ssh.sh
)
readonly -a expected_stage_checksums=(
    '65d872f63a7a7e9dc108111057164c1785a77bf00429672452cfd3f9f3fe7134  caddy-sync-rsync-receiver'
    '909ee3ca843757d8d956ac6d442d6079134b0235fa7d37c97d80590eb5870fbd  node-b-host-ed25519.pub'
    'c9a2ecfcc6a44c0cd30d06bbb2841ec50ffd11866ce1da77ff69f2b5ff8320b0  node-b-sync-ed25519.pub'
    'd1d1e4fd0fd3787e43d7801babfbcdec20015b6517282cdba67904aa1b554140  setup-sync-ssh.sh'
    '85df8a934c8dd9561a6f567f42549ebc01ee2605ca630150265004b9ec108072  validate-sync-ssh.sh'
)
readonly -a live_targets=(
    /var/lib/caddy-sync/.ssh/id_ed25519
    /var/lib/caddy-sync/.ssh/id_ed25519.pub
    /var/lib/caddy-sync/.ssh/known_hosts
    /var/lib/caddy-sync/.ssh/authorized_keys
    /usr/local/libexec/caddy-sync-rsync-receiver
    /usr/local/libexec/setup-sync-ssh.sh
    /usr/local/libexec/validate-sync-ssh.sh
    /etc/lsyncd/caddy.lua
)

if [[ "${1:-}" == --self-test ]]; then
    [[ "$retained_stage" == /var/tmp/caddy-sync-ssh-node-a-action16aj-e ]]
    [[ "$parent_path" == /var/tmp ]]
    [[ "${#expected_stage_files[@]}" -eq 5 ]]
    [[ "${#expected_stage_checksums[@]}" -eq 5 ]]
    [[ "${#live_targets[@]}" -eq 8 ]]
    printf 'action_16ak_b_retained_stage_metadata_self_test_complete=true\n'
    exit 0
elif (($#)); then
    printf 'Usage: %s [--self-test]\n' "${0##*/}" >&2
    exit 2
fi

fail_inspection() {
    local label=$1

    printf '%s=false\n' "$label"
    printf 'first_failure=%s\n' "$label"
    printf 'action_16ak_b_read_only_inspection_complete=false\n'
    exit 1
}

require_command() {
    local label=$1
    shift

    if ! "$@" >/dev/null 2>&1; then
        fail_inspection "$label"
    fi
    printf '%s=true\n' "$label"
}

require_absent() {
    local label=$1
    local target=$2

    if [[ -e "$target" || -L "$target" ]]; then
        fail_inspection "$label"
    fi
    printf '%s=true\n' "$label"
}

print_metadata() {
    local label=$1
    local path=$2

    printf '%s_owner_names=%s\n' "$label" \
        "$(stat -c '%U:%G' "$path")"
    printf '%s_owner_numeric=%s\n' "$label" \
        "$(stat -c '%u:%g' "$path")"
    printf '%s_mode_numeric=%s\n' "$label" \
        "$(stat -c '%a' "$path")"
    printf '%s_mode_symbolic=%s\n' "$label" \
        "$(stat -c '%A' "$path")"
    # shellcheck disable=SC2012 # ls exposes the ACL marker that stat omits.
    printf '%s_ls_mode=%s\n' "$label" \
        "$(ls -ld -- "$path" | awk '{ print $1 }')"
    printf '%s_inode=%s\n' "$label" \
        "$(stat -c '%i' "$path")"
    printf '%s_device=%s\n' "$label" \
        "$(stat -c '%d' "$path")"
    printf '%s_hard_links=%s\n' "$label" \
        "$(stat -c '%h' "$path")"
    printf '%s_size_bytes=%s\n' "$label" \
        "$(stat -c '%s' "$path")"
    printf '%s_birth_time=%s\n' "$label" \
        "$(stat -c '%w' "$path")"
    printf '%s_access_time=%s\n' "$label" \
        "$(stat -c '%x' "$path")"
    printf '%s_modify_time=%s\n' "$label" \
        "$(stat -c '%y' "$path")"
    printf '%s_change_time=%s\n' "$label" \
        "$(stat -c '%z' "$path")"
}

print_acl() {
    local label=$1
    local path=$2
    local acl_text acl_extended acl_hash acl_line_count

    acl_text=$(getfacl -cpn -- "$path")
    acl_line_count=$(
        printf '%s\n' "$acl_text" |
            sed '/^$/d' |
            wc -l
    )
    acl_hash=$(
        printf '%s\n' "$acl_text" |
            sha256sum |
            awk '{ print $1 }'
    )
    acl_extended=false
    if grep -Eq \
        '^(default:|user:[^:]|group:[^:]|mask:)' \
        <<<"$acl_text"; then
        acl_extended=true
    fi

    printf '%s_acl_line_count=%s\n' "$label" "$acl_line_count"
    printf '%s_acl_sha256=%s\n' "$label" "$acl_hash"
    printf '%s_acl_extended=%s\n' "$label" "$acl_extended"
    printf '%s\n' "$acl_text" |
        sed '/^$/d' |
        sed "s/^/${label}_acl_entry=/"
}

printf 'action_16ak_b_remote_reached=true\n'
require_command root_effective_uid test "$(id -u)" -eq 0
require_command node_hostname \
    test "$(hostname)" = j1-svpihole0
require_command retained_stage_directory \
    test -d "$retained_stage"
require_command retained_stage_not_symlink \
    test ! -L "$retained_stage"
require_command parent_directory \
    test -d "$parent_path"
require_command parent_not_symlink \
    test ! -L "$parent_path"
require_command findmnt_available \
    test -x /usr/bin/findmnt

mapfile -t actual_stage_files < <(
    find "$retained_stage" -mindepth 1 -maxdepth 1 -type f \
        -printf '%f\n' |
        sort
)
if [[ "${actual_stage_files[*]}" != "${expected_stage_files[*]}" ]]; then
    fail_inspection retained_stage_file_set
fi
printf 'retained_stage_file_set=true\n'
if find "$retained_stage" -type l -print -quit | grep -q .; then
    fail_inspection retained_stage_symlink_count
fi
printf 'retained_stage_symlink_count=true\n'
(
    cd "$retained_stage"
    printf '%s\n' "${expected_stage_checksums[@]}" |
        sha256sum --check --status
) || fail_inspection retained_stage_hashes
printf 'retained_stage_hashes=true\n'
for target in "${live_targets[@]}"; do
    require_absent live_synchronization_targets_absent "$target"
done
require_absent libexec_absent "$libexec"
printf 'action_16ak_a_continuity_anchor=true\n'

print_metadata retained_stage "$retained_stage"
print_metadata parent "$parent_path"

printf 'filesystem_mount_target=%s\n' \
    "$(findmnt -n -T "$retained_stage" -o TARGET)"
printf 'filesystem_type=%s\n' \
    "$(findmnt -n -T "$retained_stage" -o FSTYPE)"
printf 'filesystem_options=%s\n' \
    "$(findmnt -n -T "$retained_stage" -o OPTIONS)"

acl_tool=$(command -v getfacl 2>/dev/null || true)
if [[ -n "$acl_tool" ]]; then
    printf 'acl_tool_available=true\n'
    printf 'acl_tool_path=%s\n' "$acl_tool"
    print_acl retained_stage "$retained_stage"
    print_acl parent "$parent_path"
else
    printf 'acl_tool_available=false\n'
    printf 'acl_tool_path=unavailable\n'
    printf 'retained_stage_acl_line_count=unavailable\n'
    printf 'retained_stage_acl_sha256=unavailable\n'
    printf 'retained_stage_acl_extended=unknown\n'
    printf 'parent_acl_line_count=unavailable\n'
    printf 'parent_acl_sha256=unavailable\n'
    printf 'parent_acl_extended=unknown\n'
fi

printf 'first_failure=none\n'
printf 'service_mutations=false\n'
printf 'action_16ak_b_read_only_inspection_complete=true\n'
