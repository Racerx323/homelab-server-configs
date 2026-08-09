#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
readonly caddy_root=${test_directory%/tests}
readonly source_inspector=$caddy_root/scripts/inspect-dual-node-keepalived-post-action20p-a.sh
readonly source_outer=$caddy_root/scripts/run-dual-node-keepalived-post-action20p-a-outer.sh
readonly retry_outer=$caddy_root/scripts/run-dual-node-keepalived-post-action20p-a-retry-outer.sh
readonly source_inspector_sha256=55bf9878744e75ff7f79cb93d565cd4c5bb3e500bc2a575c04333e94456ee2f8
readonly source_outer_sha256=e2450fc5d10115d7576d8ad39535688e5abf29c43f028b8b27de03e4d30730e3
readonly rendered_inspector_sha256=a72b9ae988513de85bc0dc15bcdb777482e2d769e4458a6046fd4da90c678663
readonly rendered_core_sha256=bd1e83db6c7682385a5497df9a9aa20813016cb63a5fc86a400e103b6e00efb7
readonly state_hash=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa

record_check() {
    local action20pa_retry_regression_label=$1

    shift
    if "$@"; then
        printf 'action_20p_a_retry_regression_check_%s=true\n' "$action20pa_retry_regression_label"
        return 0
    fi
    printf 'action_20p_a_retry_regression_check_%s=false\n' "$action20pa_retry_regression_label" >&2
    return 1
}
fixture() {
    local action20pa_retry_regression_role=$1
    local action20pa_retry_regression_mode=${2:-success}
    local action20pa_retry_regression_node_label=${action20pa_retry_regression_role//-/_}
    local action20pa_retry_regression_prefix=action_20p_a_${action20pa_retry_regression_node_label}
    local action20pa_retry_regression_label
    local action20pa_retry_regression_main
    local action20pa_retry_regression_fragment
    local action20pa_retry_regression_state
    local action20pa_retry_regression_count
    local action20pa_retry_regression_check_count

    action20pa_retry_regression_check_count=$("$source_inspector" --expected-checks | wc -l) || return 1
    case "$action20pa_retry_regression_role" in
        node-a)
            action20pa_retry_regression_main=8fc9dcf8e079b7131f86a58038ae5543804a5158a02d53a4614452de212ce47c
            action20pa_retry_regression_fragment=8117510587c79fa597ebd5e48da6ab4be8d8dfef6740d57b9b327037b70830be
            action20pa_retry_regression_state=Master
            action20pa_retry_regression_count=1
            ;;
        node-b)
            action20pa_retry_regression_main=5480e6994994b65b0a498f42cb7943b5de86958416732a44983e341a93db1393
            action20pa_retry_regression_fragment=0dd8ec0a5410bcd3c41db0d3fed74cf8bd75978f09b01a797468dd6266b4b518
            action20pa_retry_regression_state=Backup
            action20pa_retry_regression_count=0
            ;;
        *) return 1 ;;
    esac
    while IFS= read -r action20pa_retry_regression_label; do
        if [[ "$action20pa_retry_regression_mode" = missing &&
            "$action20pa_retry_regression_label" = main_include_once ]]; then
            continue
        fi
        printf '%s_check_%s=true\n' "$action20pa_retry_regression_prefix" "$action20pa_retry_regression_label"
    done < <("$source_inspector" --expected-checks)
    printf '%s\n' \
        "${action20pa_retry_regression_prefix}_observation_ttl_hl_quiet_window_status=0" \
        "${action20pa_retry_regression_prefix}_observation_ttl_hl_quiet_window_classification=bounded_safe" \
        "${action20pa_retry_regression_prefix}_value_expected_check_count=$action20pa_retry_regression_check_count" \
        "${action20pa_retry_regression_prefix}_value_main_sha256=$action20pa_retry_regression_main" \
        "${action20pa_retry_regression_prefix}_value_fragment_sha256=$action20pa_retry_regression_fragment" \
        "${action20pa_retry_regression_prefix}_value_health_sha256=5cb42ba05b36fecd0c0cf5bc649741661b847e8f8dce94a19288d21874d87fb3" \
        "${action20pa_retry_regression_prefix}_value_dbus_state=$action20pa_retry_regression_state" \
        "${action20pa_retry_regression_prefix}_value_caddy_ipv4_count=$action20pa_retry_regression_count" \
        "${action20pa_retry_regression_prefix}_value_caddy_ipv6_count=$action20pa_retry_regression_count" \
        "${action20pa_retry_regression_prefix}_value_before_state_sha256=$state_hash"
    if [[ "$action20pa_retry_regression_mode" = changed_snapshot ]]; then
        printf '%s_value_after_state_sha256=%064d\n' "$action20pa_retry_regression_prefix" 0
    else
        printf '%s_value_after_state_sha256=%s\n' "$action20pa_retry_regression_prefix" "$state_hash"
    fi
    printf '%s\n' \
        "${action20pa_retry_regression_prefix}_check_count=$action20pa_retry_regression_check_count" \
        "${action20pa_retry_regression_prefix}_failed_check_count=0" \
        "${action20pa_retry_regression_prefix}_first_failure=none" \
        "${action20pa_retry_regression_prefix}_read_only=true" \
        "${action20pa_retry_regression_prefix}_keepalived_reload=false" \
        "${action20pa_retry_regression_prefix}_keepalived_restart=false" \
        "${action20pa_retry_regression_prefix}_filesystem_mutations=false" \
        "${action20pa_retry_regression_prefix}_service_mutations=false" \
        "${action20pa_retry_regression_prefix}_vrrp_mutations=false" \
        "${action20pa_retry_regression_prefix}_vip_mutations=false" \
        "${action20pa_retry_regression_prefix}_remote_complete=true"
}
validate_pair() {
    local action20pa_retry_regression_node_a_fixture=$1
    local action20pa_retry_regression_node_b_fixture=$2

    /bin/bash "$retry_outer" --validate-fixtures \
        "$action20pa_retry_regression_node_a_fixture" "$action20pa_retry_regression_node_b_fixture"
}
expect_rejected() {
    local action20pa_retry_regression_node_a_fixture=$1
    local action20pa_retry_regression_node_b_fixture=$2

    if validate_pair "$action20pa_retry_regression_node_a_fixture" \
        "$action20pa_retry_regression_node_b_fixture"; then
        return 1
    fi
}
production_path_test() {
    local action20pa_retry_regression_work_root=$1
    local action20pa_retry_regression_status=0

    cat >"$action20pa_retry_regression_work_root/ssh" <<'MOCK'
#!/usr/bin/env bash
set -Eeuo pipefail
[[ "$#" -eq 7 ]] || exit 91
[[ "$1" = -T && "$2" = -o && "$3" = BatchMode=yes ]] || exit 92
[[ "$4" = -o && "$5" = ConnectTimeout=10 ]] || exit 93
payload_hash=$(sha256sum | awk '{ print $1 }')
[[ "$payload_hash" = "$ACTION20PA_RETRY_EXPECTED_INSPECTOR_SHA256" ]] || exit 94
case "$6:$7" in
    'pi@10.1.0.53:cd / && sudo -n /bin/bash -s -- --node node-a') fixture=$ACTION20PA_RETRY_NODE_A_FIXTURE ;;
    'pi@10.1.0.54:cd / && sudo -n /bin/bash -s -- --node node-b') fixture=$ACTION20PA_RETRY_NODE_B_FIXTURE ;;
    *) exit 95 ;;
esac
cat "$fixture"
MOCK
    chmod 0755 "$action20pa_retry_regression_work_root/ssh" || return 1
    CADDY_ACTION20PA_RETRY_SSH_BIN=$action20pa_retry_regression_work_root/ssh \
        ACTION20PA_RETRY_NODE_A_FIXTURE=$action20pa_retry_regression_work_root/node-a.fixture \
        ACTION20PA_RETRY_NODE_B_FIXTURE=$action20pa_retry_regression_work_root/node-b.fixture \
        ACTION20PA_RETRY_EXPECTED_INSPECTOR_SHA256=$rendered_inspector_sha256 \
        /bin/bash "$retry_outer" --transport-test \
        >"$action20pa_retry_regression_work_root/stdout" \
        2>"$action20pa_retry_regression_work_root/stderr" || action20pa_retry_regression_status=$?
    if [[ "$action20pa_retry_regression_status" -ne 0 ]]; then
        printf 'action_20p_a_retry_regression_production_status=%s\n' \
            "$action20pa_retry_regression_status" >&2
        for action20pa_retry_regression_stream in stdout stderr; do
            printf 'action_20p_a_retry_regression_production_%s_bytes=%s\n' \
                "$action20pa_retry_regression_stream" \
                "$(wc -c <"$action20pa_retry_regression_work_root/$action20pa_retry_regression_stream")" >&2
            printf 'action_20p_a_retry_regression_production_%s_sha256=%s\n' \
                "$action20pa_retry_regression_stream" \
                "$(sha256sum "$action20pa_retry_regression_work_root/$action20pa_retry_regression_stream" | awk '{ print $1 }')" >&2
            printf 'action_20p_a_retry_regression_production_%s_begin\n' \
                "$action20pa_retry_regression_stream" >&2
            sed -n '1,240p' "$action20pa_retry_regression_work_root/$action20pa_retry_regression_stream" >&2
            printf 'action_20p_a_retry_regression_production_%s_end\n' \
                "$action20pa_retry_regression_stream" >&2
        done
        return 1
    fi
    [[ ! -s "$action20pa_retry_regression_work_root/stderr" ]] || return 1
    grep -Fqx 'action_20p_a_retry_outer_complete=true' "$action20pa_retry_regression_work_root/stdout" || return 1
}

action20pa_retry_regression_root=$(mktemp -d /tmp/caddy-action20p-a-retry-regression.XXXXXX)
readonly action20pa_retry_regression_root
trap 'rm -rf -- "$action20pa_retry_regression_root"' EXIT INT TERM

fixture node-a success >"$action20pa_retry_regression_root/node-a.fixture"
fixture node-b success >"$action20pa_retry_regression_root/node-b.fixture"
record_check source_inspector_immutable test "$(sha256sum "$source_inspector" | awk '{ print $1 }')" = "$source_inspector_sha256" || exit 1
record_check source_outer_immutable test "$(sha256sum "$source_outer" | awk '{ print $1 }')" = "$source_outer_sha256" || exit 1
action20pa_retry_regression_rendered_hashes=$(/bin/bash "$retry_outer" --render-hashes) || exit 1
readonly action20pa_retry_regression_rendered_hashes
record_check rendered_inspector_hash grep -Fqx \
    "rendered_inspector_sha256=$rendered_inspector_sha256" <<<"$action20pa_retry_regression_rendered_hashes" || exit 1
record_check rendered_core_hash grep -Fqx \
    "rendered_core_sha256=$rendered_core_sha256" <<<"$action20pa_retry_regression_rendered_hashes" || exit 1
record_check accepted_pair validate_pair "$action20pa_retry_regression_root/node-a.fixture" \
    "$action20pa_retry_regression_root/node-b.fixture" || exit 1

awk '$0 != "action_20p_a_node_a_check_main_include_once=true"' \
    "$action20pa_retry_regression_root/node-a.fixture" >"$action20pa_retry_regression_root/node-a-missing.fixture"
record_check missing_include_rejected expect_rejected \
    "$action20pa_retry_regression_root/node-a-missing.fixture" \
    "$action20pa_retry_regression_root/node-b.fixture" || exit 1
fixture node-b changed_snapshot >"$action20pa_retry_regression_root/node-b-changed.fixture"
record_check changed_snapshot_rejected expect_rejected \
    "$action20pa_retry_regression_root/node-a.fixture" \
    "$action20pa_retry_regression_root/node-b-changed.fixture" || exit 1
record_check production_path production_path_test "$action20pa_retry_regression_root" || exit 1

printf '%s\n' \
    action_20p_a_retry_regression_immutable_sources=true \
    action_20p_a_retry_regression_exact_derivation=true \
    action_20p_a_retry_regression_accepted_include_contract=true \
    action_20p_a_retry_regression_deterministic_semantic_snapshot=true \
    action_20p_a_retry_regression_missing_include_rejected=true \
    action_20p_a_retry_regression_changed_snapshot_rejected=true \
    action_20p_a_retry_regression_positive_production_path=true \
    action_20p_a_retry_regression_complete=true
