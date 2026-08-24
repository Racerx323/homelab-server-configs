#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=operator_documentation_policy
test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
default_repository_root=${test_directory%/Caddy/tests}
repository_root=$default_repository_root
mode=self-test

if [[ $# -eq 1 && $1 == --check ]]; then
    mode=check
elif [[ $# -eq 3 && $1 == --check && $2 == --repository-root ]]; then
    mode=check
    repository_root=$3
    [[ "$repository_root" == /tmp/* && -d "$repository_root" &&
        ! -L "$repository_root" ]] || exit 64
elif [[ $# -ne 0 ]]; then
    printf 'Usage: %s [--check [--repository-root /tmp/DIRECTORY]]\n' \
        "${0##*/}" >&2
    exit 64
fi
readonly repository_root
readonly mode
readonly docs_root=$repository_root/Caddy/docs
readonly readme=$repository_root/Caddy/README.md
readonly script_lifecycle=$repository_root/Caddy/manifests/script-lifecycle.tsv
self_test_root=

required_documents=(
    ARCHITECTURE.md
    INSTALLATION.md
    OPERATIONS.md
    QUICK_START.md
    TROUBLESHOOTING.md
    UNINSTALLATION.md
)
readonly -a required_documents

fail() {
    printf '%s_failure=%s\n' "$prefix" "$1" >&2
    exit 1
}

regular_file() {
    local operator_documentation_path=$1

    [[ -f "$operator_documentation_path" &&
        ! -L "$operator_documentation_path" ]]
}

require_text() {
    local operator_documentation_path=$1
    local operator_documentation_text=$2

    grep -Fq -- "$operator_documentation_text" \
        "$operator_documentation_path"
}

documents_regular() {
    local operator_documentation_name

    regular_file "$readme" || return 1
    for operator_documentation_name in "${required_documents[@]}"; do
        regular_file "$docs_root/$operator_documentation_name" || return 1
        [[ "$(sed -n '1p' "$docs_root/$operator_documentation_name")" == '# '* ]] ||
            return 1
    done
}

readme_index_complete() {
    local operator_documentation_name

    for operator_documentation_name in "${required_documents[@]}" \
        APPRISE_DELIVERY.md REPRODUCIBILITY.md caddy_plan-v1.1.md; do
        require_text "$readme" \
            "(docs/$operator_documentation_name)" || return 1
    done
}

authority_links_complete() {
    require_text "$docs_root/QUICK_START.md" \
        '(APPRISE_DELIVERY.md)' || return 1
    require_text "$docs_root/QUICK_START.md" \
        '(TROUBLESHOOTING.md)' || return 1
    require_text "$docs_root/INSTALLATION.md" \
        '(REPRODUCIBILITY.md)' || return 1
    require_text "$docs_root/INSTALLATION.md" \
        '(caddy_plan-v1.1.md)' || return 1
    require_text "$docs_root/INSTALLATION.md" \
        '(OPERATIONS.md)' || return 1
    require_text "$docs_root/OPERATIONS.md" \
        '(QUICK_START.md)' || return 1
    require_text "$docs_root/OPERATIONS.md" \
        '(APPRISE_DELIVERY.md)' || return 1
    require_text "$docs_root/UNINSTALLATION.md" \
        '(REPRODUCIBILITY.md)' || return 1
    require_text "$docs_root/UNINSTALLATION.md" \
        '(APPRISE_DELIVERY.md)' || return 1
    require_text "$docs_root/TROUBLESHOOTING.md" \
        '(QUICK_START.md)' || return 1
    require_text "$docs_root/TROUBLESHOOTING.md" \
        '(APPRISE_DELIVERY.md)' || return 1
    require_text "$docs_root/ARCHITECTURE.md" \
        '(caddy_plan-v1.1.md)' || return 1
    require_text "$docs_root/ARCHITECTURE.md" \
        '(APPRISE_DELIVERY.md)'
}

relative_links_resolve() {
    local operator_documentation_source
    local operator_documentation_target
    local operator_documentation_resolved

    for operator_documentation_source in "$docs_root"/*.md "$readme"; do
        while IFS= read -r operator_documentation_target; do
            [[ -n "$operator_documentation_target" ]] || continue
            operator_documentation_target=${operator_documentation_target%%#*}
            [[ -n "$operator_documentation_target" ]] || continue
            if [[ "$operator_documentation_source" == "$readme" ]]; then
                operator_documentation_resolved=$repository_root/Caddy/$operator_documentation_target
            else
                operator_documentation_resolved=$docs_root/$operator_documentation_target
            fi
            if ! regular_file "$operator_documentation_resolved"; then
                printf '%s_broken_link_source=%s target=%s\n' \
                    "$prefix" "$operator_documentation_source" \
                    "$operator_documentation_target" >&2
                return 1
            fi
        done < <(
            grep -Eo '\]\((docs/)?[A-Za-z0-9._/-]+\.md(#[A-Za-z0-9._-]+)?\)' \
                "$operator_documentation_source" |
                sed -E 's/^\]\(//; s/\)$//' || true
        )
    done
}

future_prompt_isolated() {
    local operator_documentation_surface

    for operator_documentation_surface in \
        "$readme" \
        "$docs_root/APPRISE_DELIVERY.md" \
        "$docs_root/REPRODUCIBILITY.md"; do
        ! grep -Fq 'FUTURE_COMPLETE_INSTALLATION_PROMPT.md' \
            "$operator_documentation_surface" || return 1
    done
    ! grep -Fq 'FUTURE_COMPLETE_INSTALLATION_PROMPT.md' \
        "$docs_root"/{ARCHITECTURE,INSTALLATION,OPERATIONS,QUICK_START,TROUBLESHOOTING,UNINSTALLATION}.md
}

future_prompt_registered() {
    regular_file "$docs_root/FUTURE_COMPLETE_INSTALLATION_PROMPT.md" ||
        return 1
    require_text "$docs_root/caddy_plan-v1.1.md" \
        '(FUTURE_COMPLETE_INSTALLATION_PROMPT.md)'
}

historical_commands_absent() {
    ! grep -Eiq \
        '(^|[^[:alnum:]])action[[:space:]]*[0-9]+|run-[^[:space:]`]*action[0-9]+' \
        "$docs_root"/{ARCHITECTURE,INSTALLATION,OPERATIONS,QUICK_START,TROUBLESHOOTING,UNINSTALLATION}.md
}

entrypoints_current() {
    local operator_documentation_source
    local operator_documentation_expected

    regular_file "$script_lifecycle" || return 1
    while IFS=$'\t' read -r operator_documentation_source \
        operator_documentation_expected; do
        regular_file "$repository_root/$operator_documentation_source" || return 1
        grep -Fxq "$operator_documentation_expected" \
            "$script_lifecycle" || return 1
    done <<'EOF'
Caddy/scripts/apply-serving-health-deployment.sh	Caddy/scripts/apply-serving-health-deployment.sh	production-current	no	-	-	Caddy/manifests/serving-health-operation.yaml
Caddy/scripts/run-serving-health-deployment-outer.sh	Caddy/scripts/run-serving-health-deployment-outer.sh	production-current	no	-	-	Caddy/manifests/serving-health-operation.yaml
Caddy/scripts/publish-release-v2.sh	Caddy/scripts/publish-release-v2.sh	production-current	yes	/usr/local/libexec/publish-release-v2.sh	0755	Caddy/manifests/production-artifacts.tsv
Caddy/scripts/install-caddy-ha.sh	Caddy/scripts/install-caddy-ha.sh	production-current	no	-	-	Caddy/scripts/README.md
Caddy/scripts/uninstall-caddy-ha.sh	Caddy/scripts/uninstall-caddy-ha.sh	production-current	no	-	-	Caddy/scripts/README.md
Caddy/scripts/validate-caddy-ha.sh	Caddy/scripts/validate-caddy-ha.sh	production-current	no	-	-	Caddy/scripts/README.md
EOF

    require_text "$docs_root/OPERATIONS.md" \
        'Caddy/scripts/apply-serving-health-deployment.sh' || return 1
    require_text "$docs_root/OPERATIONS.md" \
        'Caddy/scripts/run-serving-health-deployment-outer.sh' || return 1
    require_text "$docs_root/OPERATIONS.md" \
        '/usr/local/libexec/publish-release-v2.sh' || return 1
    require_text "$docs_root/INSTALLATION.md" \
        'Caddy/scripts/install-caddy-ha.sh' || return 1
    require_text "$docs_root/UNINSTALLATION.md" \
        'Caddy/scripts/uninstall-caddy-ha.sh'
}

installed_boundary_explicit() {
    require_text "$docs_root/INSTALLATION.md" \
        'No current repository' ||
        return 1
    require_text "$docs_root/INSTALLATION.md" \
        'entrypoint installs and configures the complete Caddy/DNS HA environment.' ||
        return 1
    require_text "$docs_root/INSTALLATION.md" \
        'The accepted-live hash is production truth.' || return 1
    require_text "$docs_root/OPERATIONS.md" \
        'accepted-live identities' || return 1
    require_text "$docs_root/ARCHITECTURE.md" \
        'accepted-live manifests identify installed production' ||
        require_text "$docs_root/ARCHITECTURE.md" \
            'accepted-live manifests identify installed production.' ||
        require_text "$docs_root/ARCHITECTURE.md" \
            'accepted-live manifests identify installed'
}

operational_contracts_present() {
    require_text "$docs_root/QUICK_START.md" 'PIHOLE_DUALSTACK' || return 1
    require_text "$docs_root/QUICK_START.md" '10.1.0.55' || return 1
    require_text "$docs_root/QUICK_START.md" 'fd36:5aa8:6971:1::56' || return 1
    require_text "$docs_root/QUICK_START.md" 'IPv4' || return 1
    require_text "$docs_root/QUICK_START.md" 'IPv6' || return 1
    require_text "$docs_root/OPERATIONS.md" 'Node B' || return 1
    require_text "$docs_root/OPERATIONS.md" 'Node A' || return 1
    require_text "$docs_root/OPERATIONS.md" 'status 125' || return 1
    require_text "$docs_root/OPERATIONS.md" '--emergency' || return 1
    require_text "$docs_root/UNINSTALLATION.md" \
        '/var/lib/caddy-apprise-queue' || return 1
    require_text "$docs_root/UNINSTALLATION.md" 'dead-letter' || return 1
    require_text "$docs_root/TROUBLESHOOTING.md" \
        'notification-only' || return 1
    require_text "$docs_root/ARCHITECTURE.md" \
        'PIHOLE_DUALSTACK' || return 1
    require_text "$docs_root/ARCHITECTURE.md" '```mermaid'
}

check_repository() {
    documents_regular || fail documents_not_regular
    readme_index_complete || fail readme_index_incomplete
    authority_links_complete || fail authority_links_incomplete
    relative_links_resolve || fail relative_link_broken
    future_prompt_isolated || fail future_prompt_not_isolated
    future_prompt_registered || fail future_prompt_not_registered
    historical_commands_absent || fail historical_command_present
    entrypoints_current || fail current_entrypoint_invalid
    installed_boundary_explicit || fail installed_boundary_missing
    operational_contracts_present || fail operational_contract_missing
}

run_self_test() {
    local operator_documentation_backup

    self_test_root=$(mktemp -d /tmp/caddy-operator-docs.XXXXXX)
    mkdir -p "$self_test_root/Caddy"
    cp -a "$default_repository_root/Caddy/docs" \
        "$self_test_root/Caddy/"
    cp "$default_repository_root/Caddy/README.md" \
        "$self_test_root/Caddy/"
    cp "$default_repository_root/Caddy/HISTORY.md" \
        "$self_test_root/Caddy/"
    cp -a "$default_repository_root/Caddy/scripts" \
        "$self_test_root/Caddy/"
    cp -a "$default_repository_root/Caddy/manifests" \
        "$self_test_root/Caddy/"

    /bin/bash "$0" --check --repository-root \
        "$self_test_root" >/dev/null

    operator_documentation_backup=$self_test_root/QUICK_START.backup
    cp "$self_test_root/Caddy/docs/QUICK_START.md" \
        "$operator_documentation_backup"
    printf '\nAction 999 command: run-action999.sh\n' >> \
        "$self_test_root/Caddy/docs/QUICK_START.md"
    if /bin/bash "$0" --check --repository-root \
        "$self_test_root" >/dev/null 2>&1; then
        fail self_test_historical_command_accepted
    fi
    cp "$operator_documentation_backup" \
        "$self_test_root/Caddy/docs/QUICK_START.md"

    printf '\n[FUTURE](FUTURE_COMPLETE_INSTALLATION_PROMPT.md)\n' >> \
        "$self_test_root/Caddy/docs/INSTALLATION.md"
    if /bin/bash "$0" --check --repository-root \
        "$self_test_root" >/dev/null 2>&1; then
        fail self_test_future_link_accepted
    fi

    printf '%s_self_test=true\n' "$prefix"
}

cleanup() {
    if [[ "$self_test_root" == /tmp/caddy-operator-docs.* &&
        -d "$self_test_root" && ! -L "$self_test_root" ]]; then
        find "$self_test_root" -depth -mindepth 1 -delete
        rmdir "$self_test_root"
    fi
}
trap cleanup EXIT INT TERM

if [[ "$mode" == check ]]; then
    check_repository
else
    check_repository
    run_self_test
fi

printf '%s_complete=true\n' "$prefix"
