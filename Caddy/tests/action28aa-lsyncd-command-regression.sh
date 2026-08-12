#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
readonly caddy_root=${script_directory%/tests}
readonly node_a_config=$caddy_root/configs/lsyncd/caddy-node-a.lua
readonly node_b_config=$caddy_root/configs/lsyncd/caddy-node-b.lua

if ! command -v lsyncd >/dev/null 2>&1; then
    if [[ "${CADDY_VALIDATION_CONTAINER:-}" = 1 ]]; then
        printf 'action_28aa_lsyncd_command_lsyncd_required=false\n' >&2
        exit 1
    fi
    printf 'action_28aa_lsyncd_command_host_deferred_to_debian=true\n'
    exit 0
fi

fixture_root=$(mktemp -d /tmp/action28aa-lsyncd-command.XXXXXX)
readonly fixture_root
trap 'rm -rf -- "$fixture_root"' EXIT INT TERM
mkdir -p "$fixture_root/source"
printf 'fixture\n' >"$fixture_root/source/release"

fake_rsync=$fixture_root/fake-rsync
cat >"$fake_rsync" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
printf '%s\n' "$@" >"$LSYNCD_ARGUMENT_CAPTURE"
EOF
chmod 0755 "$fake_rsync"

run_config() {
    local action28aa_lsyncd_source=$1
    local action28aa_lsyncd_protect_args=$2
    local action28aa_lsyncd_name=$3
    local action28aa_lsyncd_config=$fixture_root/$action28aa_lsyncd_name.lua
    local action28aa_lsyncd_capture=$fixture_root/$action28aa_lsyncd_name.args
    local action28aa_lsyncd_log=$fixture_root/$action28aa_lsyncd_name.log
    local action28aa_lsyncd_pid
    local action28aa_lsyncd_attempt

    awk -v source="$fixture_root/source/" -v binary="$fake_rsync" \
        -v protect="$action28aa_lsyncd_protect_args" '
        /^    source = / {
            printf "    source = \"%s\",\n", source
            next
        }
        /^        protect_args = / {
            printf "        protect_args = %s,\n", protect
            next
        }
        /^    rsync = [{]$/ {
            print
            printf "        binary = \"%s\",\n", binary
            next
        }
        { print }
    ' "$action28aa_lsyncd_source" >"$action28aa_lsyncd_config"
    LSYNCD_ARGUMENT_CAPTURE=$action28aa_lsyncd_capture \
        lsyncd -nodaemon -log Exec "$action28aa_lsyncd_config" \
        >"$action28aa_lsyncd_log" 2>&1 &
    action28aa_lsyncd_pid=$!
    for action28aa_lsyncd_attempt in 1 2 3 4 5 6 7 8; do
        : "$action28aa_lsyncd_attempt"
        [[ -s "$action28aa_lsyncd_capture" ]] && break
        sleep 1
    done
    kill "$action28aa_lsyncd_pid" >/dev/null 2>&1 || :
    wait "$action28aa_lsyncd_pid" 2>/dev/null || :
    if [[ ! -s "$action28aa_lsyncd_capture" ]]; then
        printf 'action_28aa_lsyncd_command_%s_capture_present=false\n' \
            "$action28aa_lsyncd_name" >&2
        if [[ -f "$action28aa_lsyncd_log" ]]; then
            sed -n '1,80p' "$action28aa_lsyncd_log" >&2
        fi
        return 1
    fi
    printf '%s\n' "$action28aa_lsyncd_capture"
}

for action28aa_lsyncd_role in node-a node-b; do
    case "$action28aa_lsyncd_role" in
        node-a) action28aa_lsyncd_source=$node_a_config ;;
        node-b) action28aa_lsyncd_source=$node_b_config ;;
        *) exit 1 ;;
    esac
    action28aa_lsyncd_safe_capture=$(run_config \
        "$action28aa_lsyncd_source" false "$action28aa_lsyncd_role-safe")
    if grep -Eq -- '^-[^-]*s|^--(protect|secluded)-args$' \
        "$action28aa_lsyncd_safe_capture"; then
        printf 'action_28aa_lsyncd_command_%s_protect_args_absent=false\n' \
            "$action28aa_lsyncd_role" >&2
        exit 1
    fi
    action28aa_lsyncd_rejected_capture=$(run_config \
        "$action28aa_lsyncd_source" true "$action28aa_lsyncd_role-rejected")
    if ! grep -Eq -- '^-[^-]*s|^--(protect|secluded)-args$' \
        "$action28aa_lsyncd_rejected_capture"; then
        printf 'action_28aa_lsyncd_command_%s_default_reproduces_rrsync_rejection=false\n' \
            "$action28aa_lsyncd_role" >&2
        sed -n '1,80p' "$action28aa_lsyncd_rejected_capture" >&2
        exit 1
    fi
    printf 'action_28aa_lsyncd_command_%s_protect_args_absent=true\n' \
        "$action28aa_lsyncd_role"
    printf 'action_28aa_lsyncd_command_%s_default_reproduces_rrsync_rejection=true\n' \
        "$action28aa_lsyncd_role"
done

printf 'action_28aa_lsyncd_command_regression_complete=true\n'
