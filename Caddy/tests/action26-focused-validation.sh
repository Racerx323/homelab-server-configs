#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/local/go/bin:/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_26_focused_validation
test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
readonly caddy_root=${test_directory%/tests}
readonly core=$caddy_root/scripts/run-workstation-caddy-protocols-action26.sh
readonly outer=$caddy_root/scripts/run-workstation-caddy-protocols-action26-outer.sh
readonly regression=$test_directory/action26-protocol-negotiation-regression.sh
readonly focused=$test_directory/action26-focused-validation.sh
readonly manifest=$caddy_root/manifests/protocol-validation-action26.yaml
readonly go_module=$caddy_root/tools/http3-probe/go.mod
readonly go_sum=$caddy_root/tools/http3-probe/go.sum
readonly go_source=$caddy_root/tools/http3-probe/main.go
readonly go_test_source=$caddy_root/tools/http3-probe/main_test.go
readonly core_sha256=f72ceb374f4a8c07f820dc720266458af6f2ae70b4287f84e778f8387b08c046
readonly outer_sha256=58edc2c10115dcd2b74e9b1b65e4afda7eaab3d6801301a698991d65ced943fc
readonly regression_sha256=a358580a9ee04cd16be48eb20388a66ececfd33080360d4dfddf1bf4d85005d5
readonly manifest_sha256=6cd7716fe87d8276d79a81054bb58e1d5053bce0860a5102580fb19db7704672
readonly go_module_sha256=49abe4ff921b27a9fbf6dfcd2f4aa183187385454ff00a8bdf098eafb90588b3
readonly go_sum_sha256=9211990e6b4889fa47deae4ee7d1de254e9e53307bcc55e7e36448ac5412b882
readonly go_source_sha256=e4e3d9390f13e080d3de742c7e247587a07c156a0f0083b3974100950c349f75
readonly go_test_source_sha256=22a1a7b52fc8d2c2da9ca6fd6e5263588a7e6e850444931571b8419a8179fdef

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }
record_check() {
    local action26_focused_label=$1

    shift
    if "$@" >/dev/null; then
        printf '%s_check_%s=true\n' "$prefix" "$action26_focused_label"
        return 0
    fi
    printf '%s_check_%s=false\n' "$prefix" "$action26_focused_label" >&2
    return 1
}
yaml_check() {
    if command -v yamllint >/dev/null; then
        yamllint -s "$manifest"
        return 0
    fi
    grep -Fqx 'action: 26' "$manifest" || return 1
    grep -Fqx 'status: defined' "$manifest"
}
go_test_check() {
    local action26_focused_go_cache
    local action26_focused_go_status=0

    action26_focused_go_cache=$(mktemp -d /tmp/caddy-action26-go-cache.XXXXXX) || return 1
    (
        cd -- "$caddy_root/tools/http3-probe"
        GOCACHE=$action26_focused_go_cache GOTOOLCHAIN=local GOPROXY=off GOSUMDB=off \
            go test -mod=readonly ./...
    ) || action26_focused_go_status=$?
    rm -rf -- "$action26_focused_go_cache"
    return "$action26_focused_go_status"
}
protocol_contract_check() {
    grep -Fq -- '--http1.1' "$core" || return 1
    grep -Fq -- '--http2' "$core" || return 1
    grep -Fq 'HTTP/3.0' "$core" || return 1
    grep -Fq '10.1.0.56' "$core" || return 1
    grep -Fq 'fd36:5aa8:6971:1::56' "$core" || return 1
    grep -Fq 'https://proxy.local.theama.co/' "$core" || return 1
    grep -Fq 'GOPROXY=off' "$core" || return 1
    grep -Fq 'alt_svc_only_is_insufficient: true' "$manifest"
}

record_check core_hash test "$(file_hash "$core")" = "$core_sha256"
record_check outer_hash test "$(file_hash "$outer")" = "$outer_sha256"
record_check regression_hash test "$(file_hash "$regression")" = "$regression_sha256"
record_check manifest_hash test "$(file_hash "$manifest")" = "$manifest_sha256"
record_check go_module_hash test "$(file_hash "$go_module")" = "$go_module_sha256"
record_check go_sum_hash test "$(file_hash "$go_sum")" = "$go_sum_sha256"
record_check go_source_hash test "$(file_hash "$go_source")" = "$go_source_sha256"
record_check go_test_source_hash test "$(file_hash "$go_test_source")" = "$go_test_source_sha256"
record_check syntax /bin/bash -n "$core" "$outer" "$regression" "$0"
record_check shellcheck shellcheck "$core" "$outer" "$regression" "$0"
record_check canonical_format /bin/bash "$test_directory/shfmt-canonical.sh" --check \
    "$core" "$outer" "$regression" "$0"
if [[ "${CADDY_VALIDATION_CONTAINER:-}" == 1 ]]; then
    record_check gofmt_deferred_to_host test "$CADDY_VALIDATION_CONTAINER" = 1
    record_check go_test_deferred_to_host test "$CADDY_VALIDATION_CONTAINER" = 1
    export CADDY_ACTION26_CONTAINER_NO_GO_TOOLCHAIN=true
else
    record_check gofmt test -z "$(gofmt -l "$go_source" "$go_test_source")"
    record_check go_test go_test_check
fi
record_check yaml yaml_check
record_check regression /bin/bash "$regression"
record_check protocol_contract protocol_contract_check
record_check collision_policy /bin/bash "$test_directory/check-shell-readonly-local-collisions-v2.sh" \
    "$core" "$outer" "$regression" "$0"
record_check conditional_policy /bin/bash "$test_directory/conditional-validator-errexit-policy-regression.sh"
record_check output_evidence_policy /bin/bash "$test_directory/transaction-output-evidence-policy-regression.sh"
record_check scalar_grep_policy /bin/bash "$test_directory/multifile-grep-count-policy.sh" --check \
    "$core" "$outer" "$regression" "$0"
record_check portable_awk_policy /bin/bash "$test_directory/portable-awk-policy.sh" --check \
    "$core" "$outer" "$regression" "$0"
record_check accepted_live_hash_policy /bin/bash "$test_directory/accepted-live-hash-policy.sh" --check
record_check outer_gate_policy /bin/bash "$test_directory/outer-local-gate-label-policy-regression.sh" \
    --runner "$outer"
record_check outer_gate_inventory_unique test \
    "$("$outer" --expected-local-gates | wc -l)" -eq \
    "$("$outer" --expected-local-gates | LC_ALL=C sort -u | wc -l)"
for action26_focused_entrypoint in "$core" "$outer" "$regression" "$focused"; do
    record_check "executable_index_$(basename "$action26_focused_entrypoint" | tr '.-' '__')" \
        test "$(git ls-files --stage -- "Caddy/${action26_focused_entrypoint#"$caddy_root/"}" | awk '{ print $1 }')" = 100755
done
printf '%s_node_contact=false\n' "$prefix"
printf '%s_live_protocol_probe=false\n' "$prefix"
printf '%s_live_mutation=false\n' "$prefix"
printf '%s_complete_suite_bypassed=true\n' "$prefix"
printf '%s_complete=true\n' "$prefix"
