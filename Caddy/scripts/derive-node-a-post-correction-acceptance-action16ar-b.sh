#!/usr/bin/env bash

set -euo pipefail
set +x
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly historical_inspector_sha256=c63146c3c2d7e3201bb5a90d3456333a3ccdcb4bf6a287721607e8f046ff28cb
readonly historical_runner_sha256=52302f2394c51c20945947e0b454ab94023a158f8bed7bd39e88295aa9b484d9

verify_source() {
    local source=$1
    local expected_hash=$2

    [[ -f "$source" && ! -L "$source" ]]
    [[ "$(sha256sum "$source" | awk '{ print $1 }')" == "$expected_hash" ]]
    bash -n "$source"
}

render_inspector() {
    local source=$1

    verify_source "$source" "$historical_inspector_sha256"
    awk '
        /^readonly journal_since=/ {
            print "readonly journal_since='\''2026-07-29 16:59:00 UTC'\''"
            next
        }
        /^readonly -a required_commands=/ {
            print "printf '\''caddy_version=%s\\n'\'' \"$(caddy version 2>/dev/null | awk '\''{ print $1 }'\'' | sanitize_value)\""
            print "printf '\''caddy_package_version=%s\\n'\'' \"$(dpkg-query -W -f='\''${Version}'\'' caddy 2>/dev/null | sanitize_value)\""
        }
        {
            gsub(/action16ar-node-a-default-deny/,
                "action16ar-retry-node-a-default-deny")
            gsub(/current.action16ar-new/, "current.action16ar-retry-new")
            gsub(/action16ar-a/, "action16ar-b")
            gsub(/action_16ar_a/, "action_16ar_b")
            gsub(/Action 16ar-a/, "Action 16ar-b")
            print
        }
    ' "$source"
}

render_runner() {
    local source=$1
    local inspector_hash=$2

    verify_source "$source" "$historical_runner_sha256"
    [[ "$inspector_hash" =~ ^[0-9a-f]{64}$ ]]
    awk -v inspector_hash="$inspector_hash" '
        /^readonly inspector_name=/ {
            print "readonly inspector_name=diagnose-node-a-post-correction-acceptance-action16ar-b.sh"
            next
        }
        /^readonly inspector_sha256=/ {
            print "readonly inspector_sha256=" inspector_hash
            next
        }
        {
            gsub(/action16ar-node-a-default-deny/,
                "action16ar-retry-node-a-default-deny")
            gsub(/current.action16ar-new/, "current.action16ar-retry-new")
            gsub(/action16ar-a/, "action16ar-b")
            gsub(/action_16ar_a/, "action_16ar_b")
            gsub(/Action 16ar-a/, "Action 16ar-b")
            print
        }
    ' "$source"
}

if [[ "${1:-}" == --self-test && $# -eq 1 ]]; then
    [[ "$historical_inspector_sha256" =~ ^[0-9a-f]{64}$ ]]
    [[ "$historical_runner_sha256" =~ ^[0-9a-f]{64}$ ]]
    sample=$(mktemp /tmp/caddy-action16ar-b-derive.XXXXXX)
    trap 'rm -f -- "$sample"' EXIT
    {
        printf '#!/usr/bin/env bash\n'
        printf "readonly journal_since='old'\n"
        printf 'readonly -a required_commands=(awk)\n'
        printf 'printf '\''action_16ar_a action16ar-a action16ar-node-a-default-deny current.action16ar-new\\n'\''\n'
    } >"$sample"
    sample_hash=$(sha256sum "$sample" | awk '{ print $1 }')
    output=$(
        awk '
            /^readonly journal_since=/ {
                print "readonly journal_since=new"
                next
            }
            {
                gsub(/action16ar-node-a-default-deny/,
                    "action16ar-retry-node-a-default-deny")
                gsub(/current.action16ar-new/,
                    "current.action16ar-retry-new")
                gsub(/action16ar-a/, "action16ar-b")
                gsub(/action_16ar_a/, "action_16ar_b")
                print
            }
        ' "$sample"
    )
    [[ "$sample_hash" =~ ^[0-9a-f]{64}$ ]]
    grep -Fq 'readonly journal_since=new' <<<"$output"
    grep -Fq \
        'action_16ar_b action16ar-b action16ar-retry-node-a-default-deny current.action16ar-retry-new' \
        <<<"$output"
    printf 'action_16ar_b_deriver_self_test_complete=true\n'
    exit 0
elif [[ "${1:-}" == --render-inspector && $# -eq 2 ]]; then
    render_inspector "$2"
    exit 0
elif [[ "${1:-}" == --render-runner && $# -eq 3 ]]; then
    render_runner "$2" "$3"
    exit 0
fi

printf 'Usage: %s --self-test | --render-inspector SOURCE | --render-runner SOURCE INSPECTOR_SHA256\n' \
    "${0##*/}" >&2
exit 2
