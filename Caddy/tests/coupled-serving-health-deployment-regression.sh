#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
readonly repository_root=${test_directory%/Caddy/tests}
readonly transaction=$repository_root/Caddy/scripts/apply-coupled-serving-health-action35.sh
readonly outer=$repository_root/Caddy/scripts/run-dual-node-coupled-serving-health-action35-outer.sh
readonly successor_registry=$repository_root/Caddy/manifests/deployable-successor.tsv
readonly candidate_manifest=$repository_root/Caddy/manifests/serving-health-production.tsv

probe_root=$(mktemp -d /tmp/caddy-action35-regression.XXXXXX)
readonly probe_root
trap 'rm -rf -- "$probe_root"' EXIT
chmod 0700 "$probe_root"

/bin/bash "$test_directory/serving-health-regression.sh"
/bin/bash "$transaction" --production-path-test >"$probe_root/transaction.stdout" \
    2>"$probe_root/transaction.stderr"
[[ ! -s "$probe_root/transaction.stderr" ]]
grep -Fxq production_path_test_complete=true "$probe_root/transaction.stdout"

outer_evidence=$probe_root/outer-evidence
readonly outer_evidence
install -d -m 0700 "$outer_evidence"
CADDY_PRODUCTION_PATH_EVIDENCE_ROOT=$outer_evidence \
    /bin/bash "$outer" --production-path-test >"$probe_root/outer.stdout" \
    2>"$probe_root/outer.stderr"
[[ ! -s "$probe_root/outer.stderr" ]]
grep -Fxq production_path_outer_test_complete=true "$probe_root/outer.stdout"
diff -u \
    <(printf '%s\n' mutation-count payload.sha256 remote-command.argv remote-path \
        transaction.status upload-events.tsv | LC_ALL=C sort) \
    <(find "$outer_evidence" -mindepth 1 -maxdepth 1 -printf '%f\n' | LC_ALL=C sort)
grep -Fxq 0 "$outer_evidence/mutation-count"
grep -Fxq 0 "$outer_evidence/transaction.status"

awk -F '\t' '
    NR == 1 { next }
    $2 == "defined" && $3 == "35" &&
        $5 == "Caddy/scripts/apply-coupled-serving-health-action35.sh" &&
        $6 == "Caddy/scripts/run-dual-node-coupled-serving-health-action35-outer.sh" {
        found++
    }
    END { exit(found == 1 ? 0 : 1) }
' "$successor_registry"

awk -F '\t' '
    /^[[:space:]]*(#|$)/ { next }
    NF != 6 || $6 != "production-candidate" { exit 1 }
    seen[$1 FS $2 FS $3]++ { exit 1 }
    END { exit(NR > 1 ? 0 : 1) }
' "$candidate_manifest"

printf 'coupled_serving_health_deployment_regression=true\n'
