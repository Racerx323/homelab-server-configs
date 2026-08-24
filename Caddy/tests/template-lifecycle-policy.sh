#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=template_lifecycle_policy
test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
repository_root=${test_directory%/Caddy/tests}
mode=check

if [[ $# -eq 0 ]]; then
    mode=self-test
elif [[ $# -eq 3 && $1 == --check && $2 == --repository-root ]]; then
    repository_root=$3
    [[ "$repository_root" == /tmp/* && -d "$repository_root" &&
        ! -L "$repository_root" ]] || exit 64
elif [[ $# -eq 1 && $1 == --self-test ]]; then
    mode=self-test
elif [[ $# -ne 1 || $1 != --check ]]; then
    exit 64
fi
readonly repository_root
readonly mode
readonly lifecycle_manifest=$repository_root/Caddy/manifests/template-lifecycle.tsv
readonly template_directory=$repository_root/Caddy/templates
readonly reverse_proxy_template=$template_directory/reverse-proxy.caddy.example
readonly onboarding_guide=$repository_root/Caddy/docs/APPLICATION_ONBOARDING.md
work_root=

fail() {
    printf '%s_failure=%s\n' "$prefix" "$1" >&2
    exit 1
}

[[ -f "$lifecycle_manifest" && ! -L "$lifecycle_manifest" ]] ||
    fail manifest_not_regular
diff -u \
    <(find "$template_directory" -maxdepth 1 -type f \
        -printf 'Caddy/templates/%f\n' | LC_ALL=C sort) \
    <(awk -F '\t' '!/^#/ && NF { print $1 }' "$lifecycle_manifest" |
        LC_ALL=C sort) >/dev/null || fail inventory_mismatch

awk -F '\t' '
    /^#/ || !NF { next }
    NF != 4 { invalid = 1; exit }
    $2 !~ /^(production-current|future-task|supported-example)$/ { invalid = 1; exit }
    $3 !~ /^(yes|no)$/ { invalid = 1; exit }
    $2 == "production-current" && $3 == "no" && $1 != "Caddy/templates/README.md" { invalid = 1; exit }
    $2 == "future-task" && $3 != "no" { invalid = 1; exit }
    $2 == "supported-example" && $3 != "no" { invalid = 1; exit }
    seen[$1]++ { invalid = 1; exit }
    END { exit invalid || length(seen) == 0 }
' "$lifecycle_manifest" || fail invalid_manifest_contract

grep -Fxq \
    $'Caddy/templates/README.md\tproduction-current\tno\tCaddy/templates/README.md' \
    "$lifecycle_manifest" || fail template_readme
grep -Fxq \
    $'Caddy/templates/authorized-key-receiver-finalized-v2.in\tproduction-current\tyes\tCaddy/manifests/synchronization-protocol-v2.yaml' \
    "$lifecycle_manifest" || fail receiver_template
grep -Fxq \
    $'Caddy/templates/caddy-ha.env-v2.in\tproduction-current\tyes\tCaddy/templates/caddy-ha.env-v2.in' \
    "$lifecycle_manifest" || fail environment_template
grep -Fxq \
    $'Caddy/templates/reverse-proxy.caddy.example\tsupported-example\tno\tCaddy/docs/APPLICATION_ONBOARDING.md' \
    "$lifecycle_manifest" || fail supported_reverse_proxy_template
[[ -f "$onboarding_guide" && ! -L "$onboarding_guide" ]] ||
    fail onboarding_authority_missing

[[ -f "$repository_root/Caddy/configs/lsyncd/caddy-node-a.lua" ]] ||
    fail node_a_lsyncd_missing
[[ -f "$repository_root/Caddy/configs/lsyncd/caddy-node-b.lua" ]] ||
    fail node_b_lsyncd_missing
! grep -Eq 'include-historical|keepalived-caddy-ha|templates/lsyncd-' \
    "$repository_root/Caddy/scripts/render-node-config.sh" ||
    fail renderer_nonproduction_consumer

supported_example_tokens_valid() {
    diff -u \
        <(
            sed -n 's/^@@\([A-Z0-9_]*\)@@$/@@\1@@/p' <<'EOF' | LC_ALL=C sort
@@ALLOWED_CLIENT_CIDRS@@
@@BACKEND_HOST_HEADER@@
@@BACKEND_TLS@@
@@BACKEND_TLS_SERVER_NAME@@
@@BACKEND_TLS_TRUST_POOL@@
@@BACKEND_UPSTREAMS@@
@@DIAL_TIMEOUT@@
@@FAIL_DURATION@@
@@HEALTH_FAILS@@
@@HEALTH_INTERVAL@@
@@HEALTH_PASSES@@
@@HEALTH_STATUS@@
@@HEALTH_TIMEOUT@@
@@HEALTH_URI@@
@@LB_POLICY@@
@@MAX_FAILS@@
@@PUBLIC_FQDN@@
@@RESPONSE_HEADER_TIMEOUT@@
EOF
        ) \
        <(grep -Eo '@@[A-Z0-9_]+@@' "$reverse_proxy_template" |
            LC_ALL=C sort -u) >/dev/null
}

supported_example_structure_valid() {
    grep -Fq 'bind 10.1.0.56 fd36:5aa8:6971:1::56' \
        "$reverse_proxy_template" || return 1
    grep -Fq '@allowed_clients remote_ip @@ALLOWED_CLIENT_CIDRS@@' \
        "$reverse_proxy_template" || return 1
    grep -Fq 'handle @allowed_clients {' "$reverse_proxy_template" || return 1
    grep -Fq 'health_method GET' "$reverse_proxy_template" || return 1
    grep -Fq 'health_uri @@HEALTH_URI@@' "$reverse_proxy_template" || return 1
    grep -Fq 'health_status @@HEALTH_STATUS@@' \
        "$reverse_proxy_template" || return 1
    grep -Fq 'health_headers {' "$reverse_proxy_template" || return 1
    grep -Fq 'Host @@BACKEND_HOST_HEADER@@' \
        "$reverse_proxy_template" || return 1
    grep -Fq 'fail_duration @@FAIL_DURATION@@' \
        "$reverse_proxy_template" || return 1
    grep -Fq 'unhealthy_status 5xx' "$reverse_proxy_template" || return 1
    grep -Fq 'header_up Host @@BACKEND_HOST_HEADER@@' \
        "$reverse_proxy_template" || return 1
    grep -Fq 'dial_timeout @@DIAL_TIMEOUT@@' \
        "$reverse_proxy_template" || return 1
    grep -Fq 'response_header_timeout @@RESPONSE_HEADER_TIMEOUT@@' \
        "$reverse_proxy_template" || return 1
    grep -Fq 'respond 403' "$reverse_proxy_template" || return 1
    grep -Fq 'respond 421' \
        "$repository_root/Caddy/configs/caddy/conf.d/90-default-deny.caddy" ||
        return 1
    grep -Fq 'respond 421' \
        "$repository_root/Caddy/configs/caddy/conf.d/91-exact-listener-default-deny.caddy"
}

supported_example_has_no_production_consumer() {
    local template_lifecycle_consumer

    for template_lifecycle_consumer in \
        Caddy/manifests/accepted-live-artifacts.tsv \
        Caddy/manifests/caddy-release-source.tsv \
        Caddy/manifests/current-live-state.tsv \
        Caddy/manifests/production-artifacts.tsv \
        Caddy/manifests/runtime-production.tsv \
        Caddy/scripts/install-caddy-ha.sh \
        Caddy/scripts/render-node-config.sh; do
        [[ -f "$repository_root/$template_lifecycle_consumer" &&
            ! -L "$repository_root/$template_lifecycle_consumer" ]] || return 1
        ! grep -Fq 'reverse-proxy.caddy.example' \
            "$repository_root/$template_lifecycle_consumer" || return 1
    done
}

replace_token() {
    local template_lifecycle_rendered=$1
    local template_lifecycle_token=$2
    local template_lifecycle_value=$3

    [[ "$template_lifecycle_value" != *'|'* ]] || return 1
    sed -i \
        "s|@@${template_lifecycle_token}@@|${template_lifecycle_value}|g" \
        "$template_lifecycle_rendered"
}

render_supported_example() {
    local template_lifecycle_release_root=$1
    local template_lifecycle_transport=$2
    local template_lifecycle_fragment

    template_lifecycle_fragment=$template_lifecycle_release_root/conf.d/20-example.caddy
    cp "$reverse_proxy_template" "$template_lifecycle_fragment"
    replace_token "$template_lifecycle_fragment" PUBLIC_FQDN \
        "app-${template_lifecycle_transport}.example.internal"
    replace_token "$template_lifecycle_fragment" ALLOWED_CLIENT_CIDRS \
        '10.1.0.0/22 fd36:5aa8:6971:1::/64'
    replace_token "$template_lifecycle_fragment" LB_POLICY first
    replace_token "$template_lifecycle_fragment" HEALTH_URI /healthz
    replace_token "$template_lifecycle_fragment" HEALTH_STATUS 200
    replace_token "$template_lifecycle_fragment" HEALTH_INTERVAL 10s
    replace_token "$template_lifecycle_fragment" HEALTH_TIMEOUT 2s
    replace_token "$template_lifecycle_fragment" HEALTH_PASSES 2
    replace_token "$template_lifecycle_fragment" HEALTH_FAILS 2
    replace_token "$template_lifecycle_fragment" FAIL_DURATION 30s
    replace_token "$template_lifecycle_fragment" MAX_FAILS 2
    replace_token "$template_lifecycle_fragment" DIAL_TIMEOUT 2s
    replace_token "$template_lifecycle_fragment" RESPONSE_HEADER_TIMEOUT 5s

    if [[ "$template_lifecycle_transport" == http ]]; then
        replace_token "$template_lifecycle_fragment" BACKEND_UPSTREAMS \
            '127.0.0.1:8080'
        replace_token "$template_lifecycle_fragment" BACKEND_HOST_HEADER \
            'backend-http.example.internal'
        replace_token "$template_lifecycle_fragment" BACKEND_TLS \
            '# HTTP backend: TLS disabled'
        replace_token "$template_lifecycle_fragment" BACKEND_TLS_SERVER_NAME \
            '# HTTP backend: no TLS server name'
        replace_token "$template_lifecycle_fragment" BACKEND_TLS_TRUST_POOL \
            '# HTTP backend: no TLS trust pool'
    elif [[ "$template_lifecycle_transport" == https ]]; then
        replace_token "$template_lifecycle_fragment" BACKEND_UPSTREAMS \
            'https://192.0.2.10:8443'
        replace_token "$template_lifecycle_fragment" BACKEND_HOST_HEADER \
            'backend-https.example.internal'
        replace_token "$template_lifecycle_fragment" BACKEND_TLS tls
        replace_token "$template_lifecycle_fragment" BACKEND_TLS_SERVER_NAME \
            'tls_server_name backend-https.example.internal'
        replace_token "$template_lifecycle_fragment" BACKEND_TLS_TRUST_POOL \
            "tls_trust_pool file $template_lifecycle_release_root/trust/application-ca.pem"
    else
        return 1
    fi

    ! grep -Eq '@@[A-Z0-9_]+@@' "$template_lifecycle_fragment"
}

validate_rendered_examples() {
    local template_lifecycle_release_root
    local template_lifecycle_transport
    local template_lifecycle_version

    [[ "${CADDY_VALIDATION_CONTAINER:-0}" == 1 ]] || return 0
    command -v caddy >/dev/null || fail caddy_missing_in_validation_container
    template_lifecycle_version=$(caddy version)
    [[ "$template_lifecycle_version" == v2.11.4* ]] ||
        fail unexpected_caddy_version

    work_root=$(mktemp -d /tmp/caddy-template-render.XXXXXX)
    for template_lifecycle_transport in http https; do
        template_lifecycle_release_root=$work_root/$template_lifecycle_transport
        cp -a "$repository_root/Caddy/configs/caddy" \
            "$template_lifecycle_release_root"
        install -d -m 0700 "$template_lifecycle_release_root/tls" \
            "$template_lifecycle_release_root/trust"
        openssl req -x509 -newkey rsa:2048 -nodes -days 1 \
            -subj '/CN=app.example.internal' \
            -keyout "$template_lifecycle_release_root/tls/privkey.pem" \
            -out "$template_lifecycle_release_root/tls/fullchain.pem" \
            >/dev/null 2>&1
        cp "$template_lifecycle_release_root/tls/fullchain.pem" \
            "$template_lifecycle_release_root/trust/application-ca.pem"
        render_supported_example "$template_lifecycle_release_root" \
            "$template_lifecycle_transport" || return 1
        if [[ "$template_lifecycle_transport" == http ]]; then
            ! grep -Eq '^[[:space:]]+tls([[:space:]]|$)' \
                "$template_lifecycle_release_root/conf.d/20-example.caddy" ||
                return 1
        else
            grep -Fq 'tls_server_name backend-https.example.internal' \
                "$template_lifecycle_release_root/conf.d/20-example.caddy" ||
                return 1
            grep -Fq "tls_trust_pool file $template_lifecycle_release_root/trust/application-ca.pem" \
                "$template_lifecycle_release_root/conf.d/20-example.caddy" ||
                return 1
        fi
        CADDY_CONFIG_ROOT=$template_lifecycle_release_root \
            NODE_FQDN=pihole0.local.theama.co \
            NODE_IPV4=10.1.0.53 \
            NODE_IPV6=fd36:5aa8:6971:1::53 \
            caddy adapt --validate --adapter caddyfile \
            --config "$template_lifecycle_release_root/Caddyfile" \
            >/dev/null || return 1
        CADDY_CONFIG_ROOT=$template_lifecycle_release_root \
            NODE_FQDN=pihole0.local.theama.co \
            NODE_IPV4=10.1.0.53 \
            NODE_IPV6=fd36:5aa8:6971:1::53 \
            caddy validate --adapter caddyfile \
            --config "$template_lifecycle_release_root/Caddyfile" \
            >/dev/null || return 1
    done
}

cleanup() {
    if [[ "$work_root" == /tmp/caddy-template-*.?????? &&
        -d "$work_root" && ! -L "$work_root" ]]; then
        find "$work_root" -depth -mindepth 1 -delete
        rmdir "$work_root"
    fi
}
trap cleanup EXIT INT TERM

supported_example_tokens_valid || fail supported_example_tokens
supported_example_structure_valid || fail supported_example_structure
supported_example_has_no_production_consumer || fail production_consumer
validate_rendered_examples || fail rendered_example_validation

if [[ "$mode" = self-test ]]; then
    template_lifecycle_manifest_backup=
    template_lifecycle_template_backup=

    work_root=$(mktemp -d /tmp/caddy-template-lifecycle.XXXXXX)
    mkdir -p "$work_root/Caddy/manifests" "$work_root/Caddy/templates" \
        "$work_root/Caddy/configs/lsyncd" "$work_root/Caddy/scripts" \
        "$work_root/Caddy/docs"
    cp -a "$repository_root/Caddy/templates/." "$work_root/Caddy/templates/"
    cp -a "$repository_root/Caddy/configs/lsyncd/." "$work_root/Caddy/configs/lsyncd/"
    cp -a "$repository_root/Caddy/manifests/." "$work_root/Caddy/manifests/"
    cp -a "$repository_root/Caddy/scripts/." "$work_root/Caddy/scripts/"
    cp -a "$repository_root/Caddy/docs/." "$work_root/Caddy/docs/"
    printf 'obsolete\n' >"$work_root/Caddy/templates/obsolete.in"
    if CADDY_VALIDATION_CONTAINER=0 /bin/bash "$0" --check \
        --repository-root "$work_root" >/dev/null 2>&1; then
        printf '%s_unregistered_rejected=false\n' "$prefix" >&2
        exit 1
    fi
    printf '%s_unregistered_rejected=true\n' "$prefix"

    find "$work_root/Caddy/templates" -maxdepth 1 -type f \
        -name obsolete.in -delete
    template_lifecycle_manifest_backup=$work_root/template-lifecycle.backup
    cp "$work_root/Caddy/manifests/template-lifecycle.tsv" \
        "$template_lifecycle_manifest_backup"
    sed -i \
        's/\tsupported-example\tno\t/\tsupported-example\tyes\t/' \
        "$work_root/Caddy/manifests/template-lifecycle.tsv"
    if CADDY_VALIDATION_CONTAINER=0 /bin/bash "$0" --check \
        --repository-root "$work_root" >/dev/null 2>&1; then
        fail self_test_deployable_example_accepted
    fi
    cp "$template_lifecycle_manifest_backup" \
        "$work_root/Caddy/manifests/template-lifecycle.tsv"

    template_lifecycle_template_backup=$work_root/reverse-proxy.backup
    cp "$work_root/Caddy/templates/reverse-proxy.caddy.example" \
        "$template_lifecycle_template_backup"
    printf '\n# @@UNKNOWN_TOKEN@@\n' >> \
        "$work_root/Caddy/templates/reverse-proxy.caddy.example"
    if CADDY_VALIDATION_CONTAINER=0 /bin/bash "$0" --check \
        --repository-root "$work_root" >/dev/null 2>&1; then
        fail self_test_unknown_token_accepted
    fi
    cp "$template_lifecycle_template_backup" \
        "$work_root/Caddy/templates/reverse-proxy.caddy.example"
    printf '%s_contract_mutations_rejected=true\n' "$prefix"
fi

printf '%s_complete=true\n' "$prefix"
