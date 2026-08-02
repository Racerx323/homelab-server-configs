#!/usr/bin/env bash

set -euo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly historical_inspector_name=diagnose-node-a-action16ar-recovery-action16ar-a.sh
readonly historical_inspector_sha256=c63146c3c2d7e3201bb5a90d3456333a3ccdcb4bf6a287721607e8f046ff28cb
readonly historical_runner_name=run-node-a-action16ar-recovery-diagnostic-action16ar-a.sh
readonly historical_runner_sha256=52302f2394c51c20945947e0b454ab94023a158f8bed7bd39e88295aa9b484d9
readonly deriver_name=derive-node-a-post-correction-acceptance-action16ar-b.sh
readonly deriver_sha256=f3f07ddd688373eef38d56b6361ddd897e83d38f492120516797693afb4f0a47
readonly rendered_inspector_name=diagnose-node-a-post-correction-acceptance-action16ar-b.sh
readonly rendered_inspector_sha256=71c31f7e04beed53edc58bda0ac72b5079c15231f29639548aab9971710aed0f
readonly rendered_runner_name=run-node-a-post-correction-inner-action16ar-b.sh
readonly rendered_runner_sha256=8af27b5c54eda5a6a9f47692ea0072eda9312016e5a5545d3ac521d7d13fcf5d

readonly release=/etc/caddy/releases/action16ar-retry-node-a-default-deny
readonly staging=/etc/caddy/releases/.action16ar-retry-node-a-default-deny.staging
readonly temporary_link=/etc/caddy/current.action16ar-retry-new
readonly correction_sha256=d3a31eabc6fd75784f5f3891d55dd80d3f024463d112d8dd68549c91bcde8ae7
readonly release_manifest_sha256=3e25f80cba754f7cbadfa08420889004cffc7781664bb624896efe5c4f5131dd
readonly content_manifest_sha256=272c1f17ad59d7050e61caa2da47fc8768d87777c0759cebdf513988ba837e70
readonly caddyfile_sha256=a41c7816e927c16278fab018675a3f2db5b2aae89dd5b181f1ecb06ec9beb86e
readonly historical_deny_sha256=9ce8430d11882f4e2008ff27f4f4a2fcad568f81081629289f64ad2450316b27
readonly environment_sha256=2e439dd4c868736fd7a9dceff7ba3627a1d9fe8780ba7dcef2ce5d0e5e62a2b8
readonly keepalived_tree_sha256=dad64e4a5893e37a101081e5272ea1b8b924c5e66a10d7f52bfb408fb0c92f66
readonly lighttpd_tree_sha256=95a8752f36371996b5fc55c30cdffdcfd548cbed588c2e7eb52a4c79248d3372
readonly expected_caddy_pid=1085652
readonly expected_host_key_alias=HostKeyAlias=pihole0.local.theama.co
readonly expected_ssh_target=pi@10.1.0.53

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_dir
readonly historical_inspector="$script_dir/$historical_inspector_name"
readonly historical_runner="$script_dir/$historical_runner_name"
readonly deriver="$script_dir/$deriver_name"

verify_file() {
    local target=$1
    local expected_hash=$2

    [[ -f "$target" && ! -L "$target" ]]
    [[ "$(stat -c '%U:%G:%a' "$target")" == aaron:aaron:755 ]]
    [[ "$(sha256sum "$target" | awk '{ print $1 }')" == "$expected_hash" ]]
    bash -n "$target"
}

verify_source_artifacts() {
    verify_file "$historical_inspector" "$historical_inspector_sha256"
    verify_file "$historical_runner" "$historical_runner_sha256"
    verify_file "$deriver" "$deriver_sha256"
    "$historical_inspector" --self-test >/dev/null
    "$historical_runner" --self-test >/dev/null
    "$deriver" --self-test >/dev/null
}

render_artifacts() {
    local destination=$1
    local inspector=$destination/$rendered_inspector_name
    local runner=$destination/$rendered_runner_name

    "$deriver" --render-inspector "$historical_inspector" >"$inspector"
    chmod 0755 "$inspector"
    [[ "$(sha256sum "$inspector" | awk '{ print $1 }')" == "$rendered_inspector_sha256" ]]
    "$deriver" --render-runner "$historical_runner" \
        "$rendered_inspector_sha256" >"$runner"
    chmod 0755 "$runner"
    [[ "$(sha256sum "$runner" | awk '{ print $1 }')" == "$rendered_runner_sha256" ]]
    bash -n "$inspector" "$runner"
    grep -Fq "$expected_host_key_alias" "$runner"
    grep -Fq "$expected_ssh_target" "$runner"
}

require_one_fixed() {
    local value=$1
    local transcript=$2

    [[ "$(grep -Fxc "$value" "$transcript")" -eq 1 ]]
}

require_one_regex() {
    local expression=$1
    local transcript=$2

    [[ "$(grep -Ec "$expression" "$transcript")" -eq 1 ]]
}

validate_route_topology() {
    local label=$1
    local transcript=$2

    sed -n "s/^route_record=${label}|//p" "$transcript" |
        jq -s -e '
            def selected($listeners):
                [.[] | select((.listen | sort) == ($listeners | sort))];
            def includes_hosts($wanted):
                .hosts as $actual
                | all($wanted[]; $actual | index(.) != null);

            (selected(["10.1.0.53:443",
                "[fd36:5aa8:6971:1::53]:443"])) as $physical
            | (selected(["10.1.0.56:443",
                "[fd36:5aa8:6971:1::56]:443"])) as $vip
            | (selected(["127.0.0.1:443", "[::1]:443"])) as $loopback
            | (selected([":443"])) as $wildcard_https
            | (selected([":80"])) as $wildcard_http
            | length == 5
            and ($physical | length) == 1
            and ($vip | length) == 1
            and ($loopback | length) == 1
            and ($wildcard_https | length) == 1
            and ($wildcard_http | length) == 1
            and ($physical[0]
                | includes_hosts(["pihole0.local.theama.co"]))
            and ($vip[0] | includes_hosts([
                "pihole-admin.local.theama.co",
                "proxy.local.theama.co"
            ]))
            and ($loopback[0] | includes_hosts(["localhost"]))
            and all(.[];
                .hostless_421 == true
                and (.server | type) == "string"
                and (.hosts | type) == "array")
        ' >/dev/null
}

evaluate_acceptance() {
    local transcript=$1
    local error_file=$2
    local inner_status=$3
    local caddy_pid

    [[ "$inner_status" -eq 0 ]] || return 97
    [[ ! -s "$error_file" ]] || return 97
    if grep -Eq \
        'BEGIN [A-Z ]*PRIVATE KEY|CADDY_TLS_PRIVATE_KEY_PEM|PRIVATE_KEY=|DOPPLER_TOKEN' \
        "$transcript" "$error_file"; then
        return 97
    fi
    if LC_ALL=C grep -n '[^[:print:][:space:]]' \
        "$transcript" "$error_file" >/dev/null; then
        return 97
    fi

    for marker in \
        action_16ar_b_remote_reached=true \
        runtime_metrics_counter_effect=true \
        peer_connections=false \
        installed_helper_execution=false \
        systemd_daemon_reload_performed=false \
        service_mutations=false \
        filesystem_mutations=false \
        action_16ar_b_recovery_diagnostic_complete=true \
        ssh_exit_status=0 \
        action_16ar_b_local_cleanup_complete=true; do
        require_one_fixed "$marker" "$transcript" || return 97
    done
    require_one_fixed 'node_hostname=j1-svpihole0' "$transcript" ||
        return 97
    require_one_fixed 'node_architecture=arm64' "$transcript" || return 97
    require_one_fixed 'caddy_version=v2.11.4' "$transcript" || return 97
    require_one_fixed 'caddy_package_version=2.11.4' "$transcript" || return 97
    require_one_fixed 'caddy_validate_status=0' "$transcript" || return 97

    require_one_regex \
        "^path_record=/etc/caddy/current\\|symlink\\|[^|]+\\|${release}\\|${release}\\|none$" \
        "$transcript" || return 97
    require_one_regex \
        "^path_record=${release}\\|directory\\|[^|]+\\|none\\|${release}\\|[0-9a-f]{64}$" \
        "$transcript" || return 97
    require_one_fixed \
        "path_record=${staging}|absent|unavailable|none|none|none" \
        "$transcript" || return 97
    require_one_fixed \
        "path_record=${temporary_link}|absent|unavailable|none|none|none" \
        "$transcript" || return 97
    require_one_regex \
        "^path_record=/etc/default/caddy-ha\\|regular\\|[^|]+\\|none\\|/etc/default/caddy-ha\\|${environment_sha256}$" \
        "$transcript" || return 97
    require_one_fixed \
        'path_record=/etc/keepalived/conf.d/caddy-ha.conf|absent|unavailable|none|none|none' \
        "$transcript" || return 97
    require_one_regex \
        "^path_record=/etc/caddy/current/Caddyfile\\|regular\\|[^|]+\\|none\\|${release}/Caddyfile\\|${caddyfile_sha256}$" \
        "$transcript" || return 97
    require_one_regex \
        "^path_record=/etc/caddy/current/conf.d/90-default-deny.caddy\\|regular\\|[^|]+\\|none\\|${release}/conf.d/90-default-deny.caddy\\|${historical_deny_sha256}$" \
        "$transcript" || return 97
    require_one_regex \
        "^path_record=/etc/caddy/current/conf.d/91-exact-listener-default-deny.caddy\\|regular\\|[^|]+\\|none\\|${release}/conf.d/91-exact-listener-default-deny.caddy\\|${correction_sha256}$" \
        "$transcript" || return 97
    require_one_regex \
        "^path_record=${release}/manifest.sha256\\|regular\\|[^|]+\\|none\\|${release}/manifest.sha256\\|${content_manifest_sha256}$" \
        "$transcript" || return 97
    require_one_regex \
        "^path_record=${release}/release-manifest.json\\|regular\\|[^|]+\\|none\\|${release}/release-manifest.json\\|${release_manifest_sha256}$" \
        "$transcript" || return 97
    require_one_regex \
        "^release_record=${release}\\|directory\\|[^|]+\\|[0-9a-f]{64}\\|regular\\|0\\|action16ar-retry-node-a-default-deny\\|bootstrap\\|/etc/caddy/releases/bootstrap\\|node-a\\|16ar-retry-routing-correction\\|[1-9][0-9]*\\|${correction_sha256}$" \
        "$transcript" || return 97

    for record in \
        'NODE_ROLE|node-a' \
        'NODE_FQDN|pihole0.local.theama.co' \
        'NODE_IPV4|10.1.0.53' \
        'NODE_IPV6|fd36:5aa8:6971:1::53' \
        'PEER_ROLE|node-b' \
        'PEER_IPV4|10.1.0.54' \
        'PEER_IPV6|fd36:5aa8:6971:1::54' \
        'CADDY_PRIORITY|140' \
        'NETWORK_INTERFACE|eth0' \
        'SYNC_TARGET|pihole00.local.theama.co'; do
        require_one_fixed "environment_record=${record}" "$transcript" ||
            return 97
    done
    require_one_fixed "environment_file_sha256=${environment_sha256}" \
        "$transcript" || return 97

    require_one_regex \
        "^service_record=caddy.service\\|loaded\\|active\\|running\\|disabled\\|success\\|${expected_caddy_pid}\\|0\\|[0-9]+\\|[^|]+\\|.*$" \
        "$transcript" || return 97
    require_one_regex \
        '^service_record=lighttpd.service\|loaded\|active\|running\|enabled\|success\|[1-9][0-9]*\|0\|[0-9]+\|[^|]+\|.*$' \
        "$transcript" || return 97
    require_one_regex \
        '^service_record=keepalived.service\|loaded\|active\|running\|enabled\|success\|[1-9][0-9]*\|0\|[0-9]+\|[^|]+\|.*$' \
        "$transcript" || return 97
    require_one_regex \
        '^service_record=lsyncd.service\|loaded\|inactive\|dead\|masked\|' \
        "$transcript" || return 97
    require_one_regex \
        '^service_record=caddy-api.service\|loaded\|inactive\|dead\|masked\|' \
        "$transcript" || return 97
    for unit in caddy-lsyncd.service caddy-validate-reload.path \
        caddy-validate-reload.service; do
        require_one_regex \
            "^service_record=${unit}\\|loaded\\|inactive\\|dead\\|" \
            "$transcript" || return 97
    done

    for label in adapted runtime; do
        require_one_regex \
            "^config_record=${label}\\|0\\|[0-9a-f]{64}\\|5$" \
            "$transcript" || return 97
        [[ "$(grep -c "^route_record=${label}|" "$transcript")" -eq 5 ]] ||
            return 97
        validate_route_topology "$label" "$transcript" || return 97
    done

    for label in backend management_ipv4 management_ipv6; do
        require_one_regex \
            "^probe_record=${label}\\|0\\|[23][0-9]{2}%7C[^|]+$" \
            "$transcript" || return 97
    done
    require_one_regex \
        '^probe_record=localhost_health\|0\|204%7C[^|]+$' \
        "$transcript" || return 97
    for label in unknown_ipv4 unknown_ipv6 unknown_loopback_ipv4 \
        unknown_loopback_ipv6; do
        require_one_regex \
            "^probe_record=${label}\\|0\\|421%7C[^|]+$" \
            "$transcript" || return 97
    done

    require_one_fixed \
        "tree_record=/etc/keepalived|${keepalived_tree_sha256}" \
        "$transcript" || return 97
    require_one_fixed "tree_record=/etc/lighttpd|${lighttpd_tree_sha256}" \
        "$transcript" || return 97
    require_one_regex '^tree_record=/etc/caddy\|[0-9a-f]{64}$' \
        "$transcript" || return 97

    for endpoint in \
        '10.1.0.53:443' \
        '[fd36:5aa8:6971:1::53]:443' \
        '10.1.0.56:443' \
        '[fd36:5aa8:6971:1::56]:443' \
        '127.0.0.1:443' \
        '[::1]:443' \
        '127.0.0.1:2019'; do
        [[ "$(grep -F "listener_record=" "$transcript" |
            grep -Fc "$endpoint")" -ge 1 ]] || return 97
    done
    [[ "$(grep -F 'listener_record=' "$transcript" |
        grep -Fc '127.0.0.1:8080')" -eq 1 ]] || return 97
    if grep -E \
        '^listener_record=.*(0[.]0[.]0[.]0:8080|\[\:\:\]:8080)' \
        "$transcript"; then
        return 97
    fi

    caddy_pid=$(
        awk -F '|' '/^service_record=caddy[.]service[|]/ {
            print $7
        }' "$transcript"
    )
    [[ "$caddy_pid" == "$expected_caddy_pid" ]] || return 97
    require_one_regex \
        "^process_record=caddy\\|${caddy_pid} .+" "$transcript" ||
        return 97
    return 0
}

write_contract_transcript() {
    local transcript=$1
    local label

    {
        printf '%s\n' \
            action_16ar_b_remote_reached=true \
            node_hostname=j1-svpihole0 \
            node_architecture=arm64 \
            caddy_version=v2.11.4 \
            caddy_package_version=2.11.4 \
            "path_record=/etc/caddy/current|symlink|root:caddy-tls:777:0:1:1:1|${release}|${release}|none" \
            "path_record=${release}|directory|root:caddy-tls:550:1:1:1:1|none|${release}|$(printf '%064d' 1)" \
            "path_record=${staging}|absent|unavailable|none|none|none" \
            "path_record=${temporary_link}|absent|unavailable|none|none|none" \
            "path_record=/etc/default/caddy-ha|regular|root:root:640:1:1:1:1|none|/etc/default/caddy-ha|${environment_sha256}" \
            'path_record=/etc/keepalived/conf.d/caddy-ha.conf|absent|unavailable|none|none|none' \
            "path_record=/etc/caddy/current/Caddyfile|regular|root:caddy-tls:440:1:1:1:1|none|${release}/Caddyfile|${caddyfile_sha256}" \
            "path_record=/etc/caddy/current/conf.d/90-default-deny.caddy|regular|root:caddy-tls:440:1:1:1:1|none|${release}/conf.d/90-default-deny.caddy|${historical_deny_sha256}" \
            "path_record=/etc/caddy/current/conf.d/91-exact-listener-default-deny.caddy|regular|root:caddy-tls:440:1:1:1:1|none|${release}/conf.d/91-exact-listener-default-deny.caddy|${correction_sha256}" \
            "path_record=${release}/manifest.sha256|regular|root:caddy-tls:440:1:1:1:1|none|${release}/manifest.sha256|${content_manifest_sha256}" \
            "path_record=${release}/release-manifest.json|regular|root:caddy-tls:440:1:1:1:1|none|${release}/release-manifest.json|${release_manifest_sha256}" \
            "release_record=${release}|directory|root:caddy-tls:550:1:1:1:1|$(printf '%064d' 2)|regular|0|action16ar-retry-node-a-default-deny|bootstrap|/etc/caddy/releases/bootstrap|node-a|16ar-retry-routing-correction|14|${correction_sha256}" \
            'environment_record=NODE_ROLE|node-a' \
            'environment_record=NODE_FQDN|pihole0.local.theama.co' \
            'environment_record=NODE_IPV4|10.1.0.53' \
            'environment_record=NODE_IPV6|fd36:5aa8:6971:1::53' \
            'environment_record=PEER_ROLE|node-b' \
            'environment_record=PEER_IPV4|10.1.0.54' \
            'environment_record=PEER_IPV6|fd36:5aa8:6971:1::54' \
            'environment_record=CADDY_PRIORITY|140' \
            'environment_record=NETWORK_INTERFACE|eth0' \
            'environment_record=SYNC_TARGET|pihole00.local.theama.co' \
            "environment_file_sha256=${environment_sha256}" \
            "service_record=caddy.service|loaded|active|running|disabled|success|${expected_caddy_pid}|0|0|/lib/systemd/system/caddy.service|" \
            'service_record=lighttpd.service|loaded|active|running|enabled|success|456|0|0|/lib/systemd/system/lighttpd.service|' \
            'service_record=keepalived.service|loaded|active|running|enabled|success|789|0|0|/lib/systemd/system/keepalived.service|' \
            'service_record=lsyncd.service|loaded|inactive|dead|masked|success|0|0|0|/lib/systemd/system/lsyncd.service|' \
            'service_record=caddy-lsyncd.service|loaded|inactive|dead|disabled|success|0|0|0|/etc/systemd/system/caddy-lsyncd.service|' \
            'service_record=caddy-api.service|loaded|inactive|dead|masked|success|0|0|0|/etc/systemd/system/caddy-api.service|' \
            'service_record=caddy-validate-reload.path|loaded|inactive|dead|disabled|success|0|0|0|/etc/systemd/system/caddy-validate-reload.path|' \
            'service_record=caddy-validate-reload.service|loaded|inactive|dead|static|success|0|0|0|/etc/systemd/system/caddy-validate-reload.service|' \
            'config_record=adapted|0|1111111111111111111111111111111111111111111111111111111111111111|5' \
            'config_record=runtime|0|2222222222222222222222222222222222222222222222222222222222222222|5'
        for label in adapted runtime; do
            for route in \
                '{"server":"physical","listen":["10.1.0.53:443","[fd36:5aa8:6971:1::53]:443"],"hosts":["pihole0.local.theama.co"],"hostless_421":true}' \
                '{"server":"vip","listen":["10.1.0.56:443","[fd36:5aa8:6971:1::56]:443"],"hosts":["pihole-admin.local.theama.co","proxy.local.theama.co"],"hostless_421":true}' \
                '{"server":"loopback","listen":["127.0.0.1:443","[::1]:443"],"hosts":["localhost"],"hostless_421":true}' \
                '{"server":"wildcard-https","listen":[":443"],"hosts":[],"hostless_421":true}' \
                '{"server":"wildcard-http","listen":[":80"],"hosts":[],"hostless_421":true}'; do
                printf 'route_record=%s|%s\n' "$label" "$route"
            done
        done
        printf '%s\n' \
            'probe_record=backend|0|302%7C127.0.0.1%7C1.1%7C0%7C0' \
            'probe_record=localhost_health|0|204%7C127.0.0.1%7C2%7C0%7C0' \
            'probe_record=management_ipv4|0|302%7C10.1.0.53%7C2%7C0%7C0' \
            'probe_record=management_ipv6|0|302%7Cfd36:5aa8:6971:1::53%7C2%7C0%7C0' \
            'probe_record=unknown_ipv4|0|421%7C10.1.0.53%7C2%7C0%7C0' \
            'probe_record=unknown_ipv6|0|421%7Cfd36:5aa8:6971:1::53%7C2%7C0%7C0' \
            'probe_record=unknown_loopback_ipv4|0|421%7C127.0.0.1%7C2%7C0%7C0' \
            'probe_record=unknown_loopback_ipv6|0|421%7C::1%7C2%7C0%7C0' \
            "tree_record=/etc/caddy|$(printf '%064d' 3)" \
            "tree_record=/etc/keepalived|${keepalived_tree_sha256}" \
            "tree_record=/etc/lighttpd|${lighttpd_tree_sha256}" \
            'listener_record=tcp LISTEN 0 4096 10.1.0.53:443 users:(("caddy"))' \
            'listener_record=tcp LISTEN 0 4096 [fd36:5aa8:6971:1::53]:443 users:(("caddy"))' \
            'listener_record=tcp LISTEN 0 4096 10.1.0.56:443 users:(("caddy"))' \
            'listener_record=tcp LISTEN 0 4096 [fd36:5aa8:6971:1::56]:443 users:(("caddy"))' \
            'listener_record=tcp LISTEN 0 4096 127.0.0.1:443 users:(("caddy"))' \
            'listener_record=tcp LISTEN 0 4096 [::1]:443 users:(("caddy"))' \
            'listener_record=tcp LISTEN 0 4096 127.0.0.1:2019 users:(("caddy"))' \
            'listener_record=tcp LISTEN 0 1024 127.0.0.1:8080 users:(("lighttpd"))' \
            "process_record=caddy|${expected_caddy_pid} /usr/bin/caddy run" \
            'caddy_validate_status=0' \
            runtime_metrics_counter_effect=true \
            peer_connections=false \
            installed_helper_execution=false \
            systemd_daemon_reload_performed=false \
            service_mutations=false \
            filesystem_mutations=false \
            action_16ar_b_recovery_diagnostic_complete=true \
            ssh_exit_status=0 \
            action_16ar_b_local_cleanup_complete=true
    } >"$transcript"
}

if [[ "${1:-}" == --self-test && $# -eq 1 ]]; then
    verify_source_artifacts
    self_test_dir=$(mktemp -d /tmp/caddy-action16ar-b-self-test.XXXXXX)
    trap 'rm -rf -- "$self_test_dir"' EXIT
    render_artifacts "$self_test_dir"
    "$self_test_dir/$rendered_inspector_name" --self-test >/dev/null
    "$self_test_dir/$rendered_runner_name" --self-test >/dev/null
    "$self_test_dir/$rendered_runner_name" --contract-test >/dev/null
    printf 'action_16ar_b_acceptance_runner_self_test_complete=true\n'
    exit 0
elif [[ "${1:-}" == --contract-test && $# -eq 1 ]]; then
    contract_dir=$(mktemp -d /tmp/caddy-action16ar-b-contract.XXXXXX)
    trap 'rm -rf -- "$contract_dir"' EXIT
    success=$contract_dir/success.out
    error_file=$contract_dir/error
    write_contract_transcript "$success"
    : >"$error_file"
    evaluate_acceptance "$success" "$error_file" 0

    wrong_release=$contract_dir/wrong-release.out
    sed 's#action16ar-retry-node-a-default-deny#bootstrap#' \
        "$success" >"$wrong_release"
    if evaluate_acceptance "$wrong_release" "$error_file" 0; then
        printf 'Incorrect selected release was accepted.\n' >&2
        exit 1
    fi
    wrong_probe=$contract_dir/wrong-probe.out
    sed 's/^probe_record=unknown_ipv6|0|421/probe_record=unknown_ipv6|0|200/' \
        "$success" >"$wrong_probe"
    if evaluate_acceptance "$wrong_probe" "$error_file" 0; then
        printf 'Incorrect unknown-host response was accepted.\n' >&2
        exit 1
    fi
    missing_route=$contract_dir/missing-route.out
    sed '/^route_record=runtime|.*"server":"vip"/d' \
        "$success" >"$missing_route"
    if evaluate_acceptance "$missing_route" "$error_file" 0; then
        printf 'Incomplete runtime routing topology was accepted.\n' >&2
        exit 1
    fi
    secret=$contract_dir/secret.out
    cp -- "$success" "$secret"
    printf '%s\n' '-----BEGIN PRIVATE KEY-----' >>"$secret"
    if evaluate_acceptance "$secret" "$error_file" 0; then
        printf 'Secret-bearing evidence was accepted.\n' >&2
        exit 1
    fi
    if evaluate_acceptance "$success" "$error_file" 97; then
        printf 'Failed inner runner was accepted.\n' >&2
        exit 1
    fi
    printf 'action_16ar_b_acceptance_contract_test_complete=true\n'
    exit 0
elif (($#)); then
    printf 'Usage: %s [--self-test|--contract-test]\n' "${0##*/}" >&2
    exit 2
fi

verify_source_artifacts
work_dir=$(mktemp -d /tmp/caddy-action16ar-b.XXXXXX)
readonly work_dir
readonly inner_output=$work_dir/inner.out
readonly inner_error=$work_dir/inner.err

cleanup() {
    rm -rf -- "$work_dir"
}
trap cleanup EXIT

finish() {
    local status=$1

    cleanup
    trap - EXIT
    if [[ -e "$work_dir" || -L "$work_dir" ]]; then
        printf 'action_16ar_b_outer_local_cleanup_complete=false\n' >&2
        exit 97
    fi
    printf 'action_16ar_b_outer_local_cleanup_complete=true\n'
    exit "$status"
}

render_artifacts "$work_dir"
set +e
"$work_dir/$rendered_runner_name" >"$inner_output" 2>"$inner_error"
inner_status=$?
set -e

cat "$inner_output"
cat "$inner_error" >&2
printf 'action_16ar_b_inner_runner_status=%s\n' "$inner_status"
set +e
evaluate_acceptance "$inner_output" "$inner_error" "$inner_status"
acceptance_status=$?
set -e
if [[ "$acceptance_status" -eq 0 ]]; then
    printf 'action_16ar_b_post_correction_accepted=true\n'
fi
finish "$acceptance_status"
