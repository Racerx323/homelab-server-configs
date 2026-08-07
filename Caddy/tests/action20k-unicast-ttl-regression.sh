#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_20k_regression
readonly installer_sha256=abe962654982e9ab7cbcf6eabc4875a54eec2c81bf41868b3b5b6c393553a76e
readonly template_sha256=fd5ca8528468c97be6792e2184a71d6c06dc2c2a16abd44183bbfc170ff1f036
readonly node_a_candidate_sha256=8117510587c79fa597ebd5e48da6ab4be8d8dfef6740d57b9b327037b70830be
readonly node_b_candidate_sha256=0dd8ec0a5410bcd3c41db0d3fed74cf8bd75978f09b01a797468dd6266b4b518

test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
readonly caddy_root=${test_directory%/tests}
readonly installer=$caddy_root/scripts/install-caddy-unicast-ttl-action20k.sh
readonly outer=$caddy_root/scripts/run-caddy-unicast-ttl-action20k-outer.sh
readonly template=$caddy_root/templates/keepalived-caddy-ha.conf.in

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }
record_check() {
    local action20k_regression_label=$1

    shift
    if "$@"; then
        printf '%s_check_%s=true\n' "$prefix" "$action20k_regression_label"
        return 0
    fi
    printf '%s_check_%s=false\n' "$prefix" "$action20k_regression_label" >&2
    return 1
}
render_template() {
    local action20k_regression_role=$1
    local action20k_regression_output=$2
    local action20k_regression_ipv4
    local action20k_regression_ipv6
    local action20k_regression_peer4
    local action20k_regression_peer6
    local action20k_regression_priority

    case "$action20k_regression_role" in
        node-a)
            action20k_regression_ipv4=10.1.0.53
            action20k_regression_ipv6=fd36:5aa8:6971:1::53
            action20k_regression_peer4=10.1.0.54
            action20k_regression_peer6=fd36:5aa8:6971:1::54
            action20k_regression_priority=140
            ;;
        node-b)
            action20k_regression_ipv4=10.1.0.54
            action20k_regression_ipv6=fd36:5aa8:6971:1::54
            action20k_regression_peer4=10.1.0.53
            action20k_regression_peer6=fd36:5aa8:6971:1::53
            action20k_regression_priority=100
            ;;
        *) return 1 ;;
    esac
    sed \
        -e 's/@NETWORK_INTERFACE@/eth0/g' \
        -e "s/@NODE_IPV4@/$action20k_regression_ipv4/g" \
        -e "s#@NODE_IPV6@#$action20k_regression_ipv6#g" \
        -e "s/@PEER_IPV4@/$action20k_regression_peer4/g" \
        -e "s#@PEER_IPV6@#$action20k_regression_peer6#g" \
        -e "s/@CADDY_PRIORITY@/$action20k_regression_priority/g" \
        -e 's/user keepalived_script$/user keepalived_script caddy-tls/' \
        "$template" >"$action20k_regression_output"
}
run_transport_case() {
    local action20k_regression_case=$1
    local action20k_regression_node=$2
    local action20k_regression_expected_status=$3
    local action20k_regression_case_root=$regression_root/$action20k_regression_case-$action20k_regression_node
    local action20k_regression_status=0

    install -d -m 0700 "$action20k_regression_case_root"
    ACTION20K_FAKE_MODE=$action20k_regression_case \
        ACTION20K_EXPECTED_INSTALLER_SHA256=$installer_sha256 \
        CADDY_ACTION20K_TEST_MODE=1 \
        CADDY_ACTION20K_SSH_BINARY=$fake_ssh \
        /bin/bash "$outer" --test-transport "$action20k_regression_node" \
        >"$action20k_regression_case_root/stdout" \
        2>"$action20k_regression_case_root/stderr" ||
        action20k_regression_status=$?
    [[ "$action20k_regression_status" -eq "$action20k_regression_expected_status" ]]
}

regression_root=$(mktemp -d /tmp/caddy-action20k-regression.XXXXXX)
readonly regression_root
trap 'rm -rf -- "$regression_root"' EXIT INT TERM
readonly fake_ssh=$regression_root/ssh
cat >"$fake_ssh" <<'FAKE_SSH'
#!/usr/bin/env bash
set -Eeuo pipefail
PATH=/usr/bin:/bin
export PATH
payload=$(mktemp /tmp/action20k-fake-payload.XXXXXX)
trap 'rm -f -- "$payload"' EXIT
cat >"$payload"
[[ "$(sha256sum "$payload" | awk '{ print $1 }')" = "$ACTION20K_EXPECTED_INSTALLER_SHA256" ]]
case " $* " in
    *' --node node-a '*) node=node-a ;;
    *' --node node-b '*) node=node-b ;;
    *) exit 64 ;;
esac
mapfile -t labels < <(/bin/bash "$payload" --expected-checks)
case "$ACTION20K_FAKE_MODE" in
    valid) ;;
    missing) labels=("${labels[@]:1}") ;;
    reordered)
        first=${labels[0]}
        labels[0]=${labels[1]}
        labels[1]=$first
        ;;
    status) exit 42 ;;
    stderr)
        printf 'bounded simulated stderr\n' >&2
        ;;
    false) ;;
    duplicate) ;;
    *) exit 64 ;;
esac
for label in "${labels[@]}"; do
    if [[ "$ACTION20K_FAKE_MODE" = false && "$label" = identity_root ]]; then
        printf 'action_20k_check_%s=false\n' "$label"
    else
        printf 'action_20k_check_%s=true\n' "$label"
    fi
    if [[ "$ACTION20K_FAKE_MODE" = duplicate && "$label" = identity_root ]]; then
        printf 'action_20k_check_%s=true\n' "$label"
    fi
done
printf 'action_20k_backup_path=/var/backups/caddy-ha/action20k-%s-unicast-ttl.FIXTURE\n' "$node"
printf 'action_20k_node=%s\n' "$node"
printf 'action_20k_keepalived_reload=false\n'
printf 'action_20k_keepalived_restart=false\n'
printf 'action_20k_service_mutation=false\n'
printf 'action_20k_vrrp_transition=false\n'
printf 'action_20k_vip_mutation=false\n'
printf 'action_20k_complete=true\n'
FAKE_SSH
chmod 0755 "$fake_ssh"

record_check installer_hash_exact test "$(file_hash "$installer")" = "$installer_sha256"
record_check template_hash_exact test "$(file_hash "$template")" = "$template_sha256"
record_check installer_self_test /bin/bash "$installer" --self-test
record_check installer_check_count test \
    "$(/bin/bash "$installer" --expected-checks | wc -l)" -eq 58
record_check installer_check_labels_unique test \
    "$(/bin/bash "$installer" --expected-checks | LC_ALL=C sort -u | wc -l)" -eq 58
record_check template_ttl_count test \
    "$(grep -Fxc '    unicast_ttl 255' "$template")" -eq 2
record_check template_hoplimit_absent test \
    "$(grep -Ec '^[[:space:]]*hoplimit([[:space:]]|$)' "$template" || true)" -eq 0
render_template node-a "$regression_root/node-a.conf"
render_template node-b "$regression_root/node-b.conf"
record_check node_a_candidate_hash test \
    "$(file_hash "$regression_root/node-a.conf")" = "$node_a_candidate_sha256"
record_check node_b_candidate_hash test \
    "$(file_hash "$regression_root/node-b.conf")" = "$node_b_candidate_sha256"
record_check no_config_test grep -Fq \
    'keepalived_config_test_invoked=false' <(printf 'keepalived_config_test_invoked=false\n')
# The positional parameter belongs to the literal child-shell program.
# shellcheck disable=SC2016
record_check production_no_config_test bash -c \
    '! grep -Eq "keepalived[[:space:]].*(--config-test|-t([[:space:]]|$))" "$1"' \
    _ "$installer"
# The positional parameter belongs to the literal child-shell program.
# shellcheck disable=SC2016
record_check production_no_reload bash -c \
    '! grep -Eq "systemctl[[:space:]]+(reload|restart)[[:space:]]+keepalived" "$1"' \
    _ "$installer"
record_check node_a_transport_valid run_transport_case valid node-a 0
record_check node_b_transport_valid run_transport_case valid node-b 0
record_check missing_assertion_rejected run_transport_case missing node-a 97
record_check false_assertion_rejected run_transport_case false node-a 97
record_check duplicate_assertion_rejected run_transport_case duplicate node-a 97
record_check reordered_assertion_rejected run_transport_case reordered node-a 97
record_check stderr_rejected run_transport_case stderr node-a 97
record_check nonzero_status_preserved run_transport_case status node-a 42
printf '%s_false_positive_controls=true\n' "$prefix"
printf '%s_false_negative_controls=true\n' "$prefix"
printf '%s_node_a_contacted=false\n' "$prefix"
printf '%s_node_b_contacted=false\n' "$prefix"
printf '%s_action_executed=false\n' "$prefix"
printf '%s_complete=true\n' "$prefix"
