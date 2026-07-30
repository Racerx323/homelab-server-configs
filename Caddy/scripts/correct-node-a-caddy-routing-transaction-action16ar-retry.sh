#!/usr/bin/env bash

set -euo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly historical_driver_sha256=a361d0f4e37bd84a440de9115c0a3148cf9511f3e80736ae93795d812b09278a

render_retry() {
    local source=$1

    [[ -f "$source" && ! -L "$source" ]]
    [[ "$(sha256sum "$source" | awk '{ print $1 }')" == "$historical_driver_sha256" ]]
    awk '
        function emit_listener_snapshot() {
            print "listener_snapshot() {"
            print "    ss -H -lntup 2>/dev/null |"
            print "        awk '\''$5 ~ /:(80|443|8080|2019)$/ {"
            print "            process = \"none\""
            print "            if (match($0, /users:\\(\\(\"[^\"]+\"/)) {"
            print "                process = substr($0, RSTART + 9, RLENGTH - 10)"
            print "            }"
            print "            print $1 \"|\" $2 \"|\" $5 \"|\" process"
            print "        }'\'' |"
            print "        sort"
            print "}"
        }

        $0 == "listener_snapshot() {" {
            emit_listener_snapshot()
            replacing_listener = 1
            next
        }
        replacing_listener && $0 == "}" {
            replacing_listener = 0
            next
        }
        replacing_listener {
            next
        }
        {
            gsub(/action16ar/, "action16ar-retry")
            gsub(/action_16ar_/, "action_16ar_retry_")
            gsub(/16ar-routing-correction/, "16ar-retry-routing-correction")
            print
        }
    ' "$source"
}

if [[ "${1:-}" == --self-test && $# -eq 1 ]]; then
    [[ "$historical_driver_sha256" =~ ^[0-9a-f]{64}$ ]]
    sample=$(mktemp /tmp/caddy-action16ar-retry-transform.XXXXXX)
    trap 'rm -f -- "$sample"' EXIT
    {
        printf '#!/usr/bin/env bash\n'
        printf 'listener_snapshot() {\n'
        printf '    printf old\n'
        printf '}\n'
        printf 'printf '\''action_16ar_complete action16ar-path 16ar-routing-correction\\n'\''\n'
    } >"$sample"
    output=$(
        awk '
            function emit_listener_snapshot() {
                print "listener_snapshot() {"
                print "    printf semantic"
                print "}"
            }
            $0 == "listener_snapshot() {" {
                emit_listener_snapshot()
                replacing_listener = 1
                next
            }
            replacing_listener && $0 == "}" {
                replacing_listener = 0
                next
            }
            replacing_listener { next }
            {
                gsub(/action16ar/, "action16ar-retry")
                gsub(/action_16ar_/, "action_16ar_retry_")
                gsub(/16ar-routing-correction/, "16ar-retry-routing-correction")
                print
            }
        ' "$sample"
    )
    grep -Fq 'printf semantic' <<<"$output"
    grep -Fq 'action_16ar_retry_complete' <<<"$output"
    grep -Fq 'action16ar-retry-path' <<<"$output"
    grep -Fq '16ar-retry-routing-correction' <<<"$output"
    printf 'action_16ar_retry_transform_self_test_complete=true\n'
    exit 0
elif [[ "${1:-}" == --render && $# -eq 2 ]]; then
    render_retry "$2"
    exit 0
fi

printf 'Usage: %s --self-test | --render HISTORICAL_DRIVER\n' \
    "${0##*/}" >&2
exit 2
