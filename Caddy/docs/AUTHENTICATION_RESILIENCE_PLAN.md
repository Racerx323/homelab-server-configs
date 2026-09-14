# Caddy authentication resilience plan

## Scope and status

The earlier Node B operation is archived in its pushed terminal tag; its failed
acceptance and successful baseline restoration are recorded in [HISTORY.md](../HISTORY.md).
The operator reports fixing workstation IPv6 by updating to WSL prerelease 2.9.11.
Read-only checks subsequently verified Node B HTTPS over both families. The old
workstation `/tmp` evidence was no longer available after the reported Ubuntu
stop/start; the archive retains the exact operation and sanitized evidence hashes.

One replacement operation is defined and unexecuted. It runs a credential-free
workstation HTTPS check before uploads, SSH, Doppler retrieval, or service changes.
Both numeric-address paths must verify TLS for the Node B hostname and return
HTTP 200 with the Pi-hole login form. Either failure stops without remote mutation.
The governing authority remains [caddy_plan-v1.1.md](caddy_plan-v1.1.md).

The web monitor source now classifies both families independently. Its source
hash advances in `production-artifacts.tsv`; accepted deployed hashes and the
accepted immutable release remain unchanged. This is planned source divergence,
not a claim of deployment or production drift.

## Repository audit

| Area | Finding and disposition |
| --- | --- |
| `scripts/check-pihole-web-health.sh` | IPv4 precedence hid dual failures; source now reports both results and separates HTTP, TLS, connection, timeout, redirect, and terminal failures. |
| `tests/serving-health-regression.sh` | Generic failure lacked family coverage; add isolated mixed-family cases, sanitization, deduplication, enqueue retry, and recovery coverage. Validate source separately from accepted deployed identity. |
| `docs/APPLICATION_ONBOARDING.md` | Authentication ownership existed but rejection/retry acceptance was missing; require it for every authenticated web interface. |
| `templates/reverse-proxy.caddy.example` | Passive checks and 5xx policy require an application-specific review; document `0s` and the authentication gate without changing the token schema. |
| `configs/caddy/conf.d/10-pihole-admin.caddy` | Sole local backend has `fail_duration 30s` and default connection reuse; leave accepted source intact until the production change is defined. |
| Release and deployment manifests | Retain accepted live identities; archive the consumed operation and register one replacement with a workstation connectivity gate. |
| Operator and project documents | Link this plan and explain notification classifications and authentication acceptance. |

Only Pi-hole administration is an application proxy in the current production
fragment inventory. Health and default-deny fragments have no login flow.
The proposed generator must carry the authentication gate into its input and
acceptance contracts. DNS, Keepalived, and notification delivery behavior need
no change for this work.

## Implemented candidate preparation

The retained incident evidence shows a login POST failing with a closed
upstream connection, followed by HTTP 503 responses while direct lighttpd
health requests succeeded. Passive failure retention explains the extended
exclusion. Incorrect-password entry was the operator action; the reason for
the connection closure remains unproven. Do not describe a keep-alive mismatch
as a confirmed root cause.

`scripts/prepare-pihole-auth-release.sh` prepares a full release outside the
accepted production tree. It verifies accepted source hashes, removes
`fail_duration 30s` from the existing `pihole_ui` reverse proxy, and adds:

```caddyfile
transport http {
    keepalive off
}
```

Retain the local upstream, active health checks, TLS, hostnames, and listener
bindings. Removing passive exclusion prevents a single transport failure from
suppressing the only backend for 30 seconds. Disabling connection reuse removes
stale reuse as a possible trigger at the cost of local connection setup per
request. Active checks may still exclude an unhealthy backend. Do not add login
POST retries or change Pi-hole authentication.

The candidate is implemented and locally tested, not installed configuration. See the upstream
[reverse-proxy documentation](https://caddyserver.com/docs/caddyfile/directives/reverse_proxy)
for passive-health and transport semantics.

## Validation and execution sequence

1. Run the current repository-policy and serving-health host profiles, shell
   collision policy, and complete pre-commit suite for the notification source
   and documentation. Run the serving-health Debian container profile for the
   modified runtime helper. Retain actual results and unresolved limitations.
2. Prepare the proposed full immutable release; adapt and validate with the
   accepted Caddy version. Add a causal integration regression using a local
   backend that rejects incorrect credentials normally and can close a
   connection. Assert no passive 30-second exclusion after a transport error,
   normal rejection/retry behavior, and continued genuine-failure detection.
   Static assertions or canned successful requests do not prove this behavior.
3. Run the onboarding authentication gate in controlled staging with the real
   Pi-hole/lighttpd application. Test each family, a separate concurrent client,
   fresh and idle connections, and successful recovery. Record sanitized
   per-request outcomes; do not retain credentials or session material.
4. After the repository fix and integration coverage are complete, define one
   reviewed deployment operation. Pin the monitor, full release, transaction,
   outer runner, acceptance, and rollback inputs. Request exact live
   authorization through the existing lifecycle; none is granted by this plan.
5. Validate and accept standby Node B before changing Node A. Publish the
   configuration using normal Node A protocol-v2 publication and its guarded
   receiver/reconciler lifecycle; define the exact ordering with the helper
   installation and approved ownership transitions in the operation. Do not
   imply that standby-first permits normal publication from Node B.
6. Perform separately authorized live authentication acceptance on both node
   routes and the shared application route over both families. Require normal
   rejection then immediate allowed retry and successful login, no 502/503,
   no unintended notification or VIP movement, and stable health for two full
   monitor/check cycles. Keep controlled genuine backend-failure validation
   separate from expected authentication rejection.
7. On failure, follow the reviewed reverse-order rollback, restoring exact
   helper identity and selecting the prior immutable release through the
   release lifecycle. Preserve queues and evidence. After live acceptance,
   reconcile source/deployed hashes, serving-health and release manifests,
   current-live state, handoff snapshot, and terminal history/tag records.

Step 2 is implemented by the preparation tool and causal integration test.
Steps 3 through 7 remain outstanding. Node B is a production standby, so its
real-application stage requires a bounded, reviewed operation and exact live
authorization before any candidate listener, service, or release is changed.
Define that stage boundary before executing step 3; do not interpret the
original ordering as permission to mutate Node B before step 4's controls.
No real Pi-hole browser login or production acceptance has been performed.

## Candidate preparation and integration

With Caddy 2.11.4 available, provide an empty mode-0700 directory owned by the
caller beneath `/tmp`, and a protected TLS directory containing `fullchain.pem`
and `privkey.pem`:

```bash
/bin/bash Caddy/scripts/prepare-pihole-auth-release.sh \
    /tmp/REVIEWED_EMPTY_CANDIDATE /PROTECTED_TLS_DIRECTORY
```

The tool validates the complete candidate for both production node identities.
It does not construct protocol markers, install files, publish, or select a
release. The publisher remains the protocol metadata owner. On failure the
caller-owned output remains for inspection and is not accepted.

The dedicated `authentication-resilience` container profile runs Caddy 2.11.4
with an actual local HTTP backend. The accepted configuration is a negative
control: one closed POST connection produces 502 followed by 503 on both
families. The candidate produces the initial 502 but immediately serves the
next request successfully. The test also proves one POST attempt (no replay),
normal incorrect-password rejection and immediate successful retry, separate
clients, fresh and idle requests, logout, distinct backend connections, and
active-health exclusion followed by recovery. Exclusion is proved by observing
that a 503 request no longer reaches the backend, not by a hard-coded log
message. See [tests/README.md](../tests/README.md) for the image and commands.

The backend is a causal test fixture, not Pi-hole. Synthetic credentials and
session values are test-only; evidence contains only method, path, family,
status, and timing. Temporary certificates/configuration/processes are cleaned
up. The listener projection uses loopback and a temporary trusted certificate;
the production snippet and backend address are unchanged. Full production
candidate adaptation/validation is a separate check.

## Node B serving-release acceptance boundary

Read-only preflight found Node B's Caddy, lighttpd, and Keepalived active with
zero recorded restarts and no shared VIPs assigned. The selected release is
`20260818T221516Z-f8a87266-2c11-475e-af1e-dd026d44ee8d`. Its Pi-hole fragment
and web-monitor hashes match the accepted baseline. Caddy reports 2.11.4 and
lighttpd 1.4.69. These are a snapshot, not authorization or a substitute for execution-time
checks. The operator selected changing Node B's serving release, not a
temporary listener. After successful acceptance, Node B keeps the fixed release
and updated web monitor. Node A keeps its current serving release and retains
the same published candidate for its later rollout. Restoration is a failure
path, not a mandatory end to a successful test. Node A activation remains a
separate stage.

Before real acceptance, the reviewed operation must establish Node A health
and ownership, recheck Node B eligibility and zero VIPs, and publish normally
from Node A through protocol v2 so Node B can activate and pass acceptance
before Node A activation. Do not directly edit the active release or use
emergency Node B publication. Pin exact helper installation, publication,
promotion, evidence, acceptance, timeout, and reverse-restoration paths.

The operator clarified that no existing login automation is defined.
`scripts/validate-pihole-authentication.py` now defines the real HTTP workflow
for the recorded Pi-hole Web v5.21 contract. It starts with an unauthenticated
session, submits one generated incorrect password, requires the normal rejection
page, immediately submits the valid password once, verifies the dashboard,
logs out, and verifies loss of authenticated access. It repeats over both
families with fresh and idle requests and a concurrent independent client,
then observes login-page availability for at least 64 seconds. Configure the
observation window to span two complete actual monitor/active-check cycles.

The script accepts only the recorded node-a, node-b, or shared endpoints and
verifies TLS using workstation trust. It neither follows arbitrary redirects
nor retries POSTs. Credentials and cookies stay in memory. Successful login
requires the existing plaintext password supplied through a protected inherited
file descriptor or the integrated Doppler retrieval, not the stored `WEBPASSWORD`
hash. Do not put credentials in
argv, environment variables, repository files, or retained output. Never reset
or disable the production password for testing.

After the separately reviewed operation authorizes the Node B login test:

```bash
python3 Caddy/scripts/validate-pihole-authentication.py \
    --target node-b --password-fd 3 \
    --idle-seconds 5 --observation-seconds 64 \
    3</PROTECTED_EXISTING_PASSWORD_INPUT
```

The operator confirmed that the Doppler secret has been added at project
`homelab-dev`, configuration `prd_caddy`, key `PIHOLE_NODE_B_WEB_PASSWORD`.
This records operator-confirmed provisioning, not a successful retrieval or
login test. The automation has not read or verified the value. The missing-key
provisioning blocker is cleared; validate retrieval and authentication during
the separately authorized Node B acceptance stage. Do not rotate Pi-hole's
password as part of this work or infer that Node A uses the same password.

The preferred invocation retrieves the fixed Node B secret directly into the
validator's memory using the locally authenticated Doppler CLI:

```bash
python3 Caddy/scripts/validate-pihole-authentication.py \
    --target node-b --password-doppler \
    --idle-seconds 5 --observation-seconds 64
```

The validator invokes `/usr/bin/doppler secrets get` for exactly the reference
above, with raw/plain output, one request attempt, and a 10-second HTTP timeout.
It pins the Doppler API host and disables environment configuration overrides;
local CLI authentication must already be configured. It does not export the
password, write a fallback file, or include it in command arguments. Provider
stderr is discarded. Retrieval must finish successfully within 15 seconds and
produce a nonempty UTF-8 password of at most 4096 bytes before any HTTP request.
The descriptor input alternative also has a 15-second read deadline. A single
trailing line terminator is allowed; other password whitespace is preserved.
The Doppler option rejects Node A and the shared route before retrieving anything.

Do not use process substitution to fetch the password: its producer can exit
unsuccessfully after emitting nonempty output, without propagating that status
to the validator. The integrated mode requires both valid output and exit zero.
The regression uses isolated subprocesses to cover successful retrieval,
nonzero status after output, malformed/oversized input, blocked input, timeout,
route restrictions, descriptor closure, and sanitized CLI errors. It never calls
Doppler or a production endpoint.

The automation has not retrieved or verified the production secret value.
Retain only the validator's bounded status and timing output. Correlate requests
with the real web monitor, Caddy/lighttpd journals, DNS continuity, and both
nodes' ownership; the HTTP validator alone cannot prove those system
properties. The node target does not substitute for shared-VIP acceptance after
the separately authorized ownership stage.

The HTTP contract was checked against upstream Pi-hole Web v5.21 commit
`be05b0f61d3fcf796dae4cc3f89f8540b2359325`, particularly `login.php`,
`scripts/pi-hole/php/password.php`, `header_authenticated.php`, and `logout.php`.
A later Pi-hole version requires reviewing these assertions. The real validator
is also exercised against the causal integration fixture; that proves its
control flow, not acceptance of the real Pi-hole installation.

The Node B operation was registered and qualified before the execution recorded above. Its credential
reference, validator, payload inputs, policy, and qualification sources are pinned.
Full real login acceptance was not achieved; baseline restoration passed.

## Repository validation result

The repository-only notification and documentation change passed:

- `current-repository-policies` host profile;
- `current-serving-health` host and network-disabled Debian profiles;
- ShellCheck, canonical shfmt, and readonly/local collision checks on changed
  shell files;
- the operator-documentation self-test, including missing authentication-gate
  rejection;
- `pre-commit run --all-files` and explicit Markdown lint of the new plan and
  changed operator documents; and
- `git diff --check`.

The workspace vexp verifier reported verification unavailable because its
workspace root is not a Git repository. Direct repository checks above supply
the validation evidence. These checks do not establish the proposed proxy
fix, real incorrect-password behavior, or live acceptance. The earlier notification-only checkpoint contacted no node. This implementation
performed the read-only Node B preflight described above; no production state
was mutated.

## Implementation checkpoint

Candidate preparation, the real-Caddy causal integration regression, and the
non-secret Pi-hole HTTP acceptance workflow are implemented. The dedicated
`authentication-resilience` Debian profile passed, including the accepted
configuration negative control, candidate recovery, and rejection of an
incorrect supplied valid password. The secret-input regression passed all ten cases on the host and in the
network-disabled Debian image, including provider failure after nonempty output,
bounded reads and provider exit, descendant cleanup, route restrictions, and
sanitized errors before HTTP. The real-Caddy integration profile was rerun and
passed after the retrieval implementation was added. The current repository-policy host
profile and complete pre-commit suite passed for this checkpoint. Shell checks,
source/lifecycle registrations, and Markdown validation passed.

The plan is not fully executed. Doppler provisioning is operator-confirmed;
real Pi-hole acceptance, the pinned Node B serving-release operation and its
production-path coverage, live authorization, rollout, and post-acceptance
bookkeeping remain outstanding. No acceptance hash or production success is
claimed. Node B was inspected read-only; no production service or release was
changed. Changes remain uncommitted.

## Scoped deployment implementation

The neutral transaction now has Node B-only `auth-helper-preflight`,
`auth-helper-install`, and `auth-helper-rollback` modes. They pin the accepted
and candidate web-monitor identities, reject filesystem drift, save and verify
the original executable, record mutation intent, and replace the monitor by
rename on the same filesystem. No daemon reload is needed for this executable.
Rollback restores the exact original identity and is repeatable. A pre-mutation
failure does not rewrite the installed file. An untrusted backup, missing
mutation evidence, unrelated installed-file drift, or unidentified staging
residue rejects recovery with status `125` and preserves evidence.

The neutral outer runner owns the corresponding helper-stage and rollback
calls. Its local `--authentication-helper-test` exercises the real upload,
streamed transaction, readback, and cleanup paths through an isolated SSH
substitute that performs remote-shell parsing. Fourteen state variants cover
successful replacement/restoration, preflight drift, symlinks, hardlinks,
permissions, source and backup tampering, wrong-node rejection, repeat rollback,
missing evidence, and complete versus partial staging residue. These are
filesystem/transport tests; they do not prove service or release acceptance.

The `authentication-deployment` focused profile runs this regression on the
host and in the network-disabled Debian image. The then-inactive operation and
outer-runner pins were refreshed to the changed neutral transaction; accepted
live hashes and the clean deployment stream remain unchanged. Test fixtures
read the accepted monitor's content-addressed Git blob and check its independent
SHA-256 baseline hash. This remains valid after committing the candidate source.
The blob must be present in the checkout; tests never execute an archived
transaction or the saved monitor.

The neutral transaction now also implements candidate preparation, normal Node A
publication, discovery after a failed publication reply, Node B reconciliation
wait, release acceptance, publication withdrawal, and release rollback. It
compares the full candidate against the baseline, allowing only the intended
Pi-hole fragment change. Before rollback, the coordinator stops Node B's
reconciler and withdraws Node A's publication to prevent reapplication. A
restoration retry reloads Caddy even when an earlier failed attempt already
restored the selection symlink. Ambiguous publication, unknown residue, or
failed restoration returns `125` for manual intervention.

The outer coordinator source now connects monitor installation, publication,
reconciliation, the real login validator, health/ownership observation, and
failure restoration. Successful acceptance retains the candidate on Node B and
the publication on Node A. Failed final acceptance uses a separate rollback
observation directory, preserving candidate evidence. Acceptance checks the
selected releases, monitor identities, required services, synchronization
residue, and ownership; observation separately checks availability and bounded
journal counts. The dedicated `pihole-authentication-node-b` dispatch now selects this coordinator
and requires authorization-ready policy before contacting a node. No operation
is registered, and full production-path qualification is still pending; the
new dispatch cannot pass that gate in the current clean state.

The network-disabled release regression executes the real publisher, finalizer,
reconciler, and transaction release modes. Seven scenarios cover successful
publication/reconciliation/restoration, prepared-source tampering, failure before
publication, a failed reply after publication, reconciliation reload failure,
rollback reload failure with retry, and retained successful acceptance. The
retained case independently checks Node B's selected candidate and monitor,
Node A's unchanged selection and retained publication, and absence of service
mutations during acceptance. Negative checks reject inactive application
services and unexpected peer incoming residue. The fixture substitutes systemd
and ownership queries and models the lsyncd transfer; it does not prove the
complete outer sequence, real systemd behavior, or real Pi-hole acceptance.

The outer runner now constructs a minimal, deterministic eleven-file payload.
Its embedded input catalog pins the accepted state and configuration sources,
release preparation code, and candidate monitor. The workstation login validator
is also pinned, but is not uploaded. Only the monitor appears in the installation
manifest. TLS and password values are excluded; all payload directories are
0700 and files are 0600. Hash, symlink, hardlink, missing-input, and validator
drift checks run before an archive can be produced. The existing isolated SSH
regression now uses this real builder and proves identical archives from
identical inputs, plus rejection of four adjacent invalid input states.

Preflight and final release acceptance now check the accepted installed publisher,
finalizer, and reconciler identities. The release regression executes the accepted
reconciler runtime blob, whose only difference from current repository source is
a self-test fixture name. It verifies the independent accepted SHA-256 before
execution; no archived transaction or test is executed.

The real coordinator also has isolated pre-mutation failure and interruption
coverage. Both execute upload and preflight, then prove disposition of owned
uploads without target mutation. Signals preserve recovery inputs after a
possible mutation and return `125`; they do not infer that a lost reply means
no change. Post-mutation coverage is implemented by the `authentication-outer` profile.
It runs the actual outer stage, transaction, publication/finalization/reconciliation,
monitor, and workstation login validator against real Caddy and HTTP in an
isolated namespace. SSH transport, systemd, DNS, journal collection, and HA
ownership are bounded external-system models. Synthetic credentials stay inside
the container; no real Doppler secret or production node is used.

Nine full-stage scenarios cover retained success, rejected valid-password input,
failed restoration reload, interruption after monitor replacement, failed evidence
readback, post-mutation DNS failure, lost publication reply, rejected reconciliation
reload, and reordered sampler evidence. Each checks the actual stage status and
independently inspects selected releases, monitor identity, and publication
residue. Caddy reloads and login requests execute against the real fixture runtime.
Restoration returns status `1` for a failed operation whose baseline was proved;
unproved restoration and ambiguous interruption return `125` without claiming
acceptance or recovery.

Observation acceptance requires the exact ordered probe matrix, valid endpoints
and outcomes, complete cycles, monotonic timestamps, no inter-request gap over
15 seconds, a 64–600 second observation span, and address-monitor coverage of
that span. It rejects oversized, linked, malformed, duplicate, reordered, and
incomplete records. Reordered-evidence coverage corrupts actual sampler output
before invoking the real acceptance path. A short rollback observation cannot
establish successful authentication acceptance; independent baseline-restoration
checks remain separate.
The sampler captures the scenario once for each primary/retry pair. This fixes
a race found by the full DNS-failure scenario: advancing from baseline to final
between requests previously made a real retry appear missing and incorrectly
escalated otherwise recoverable failure handling.

The focused container wrapper selects the authentication image and adds `--init`
and `NET_ADMIN` only for this isolated full-stage fixture, always with
`--network none`. It preserves bounded producer output, command records, and
independent decision JSON under its reported evidence directory. The address
capability is confined to the container namespace and is not a live permission.

The preceding bundle's `authentication-outer` profile passed its nine scenarios before live execution.
Retained raw-command hashes and command/HTTP assertions were independently
rechecked for every scenario, and every scenario recorded zero observer residue.
The host helper/payload profile, shell collision policy, documentation checks,
and complete pre-commit suite also passed. These results qualify the isolated
full-stage behavior; they do not establish real Pi-hole or production acceptance.

The Node B operation is now registered in the deployment stream and successor
registry. The operation specification defines Node A publication, Node B monitor
replacement and reconciliation, dual-stack login acceptance, retained success,
and failure rollback. The authorization input manifest pins policy and fixture
sources as well as the registry and coverage schema. The outer runner pins that
manifest, the operation, transaction, and payload catalog.

The registered `--production-path-test` dispatch runs the full isolated container
qualification. Each scenario records the source graph before execution and
checks it again afterward. Proportional decision records bind actual phase status,
independent installed-state observations, and hashes of bounded producer evidence.
Authorization readiness validates these records against the current graph and
rechecks the emitted command sequence and login outcomes. A missing or stale
qualification cannot authorize execution. The policy's ordinary `--check` checks
the definition; `--authorization-ready` additionally requires the retained evidence.

Run from the repository root, outside the filesystem sandbox because the first
command invokes Podman:

```bash
/bin/bash Caddy/scripts/run-serving-health-deployment-outer.sh --production-path-test
export CADDY_AUTH_QUALIFICATION_EVIDENCE=/tmp/REPORTED-EVIDENCE-DIRECTORY
/bin/bash Caddy/tests/deployable-successor-policy.sh --authorization-ready
sha256sum Caddy/scripts/run-serving-health-deployment-outer.sh
```

After exact live authorization, execute the same pinned outer runner without a
mode argument, with `CADDY_AUTH_QUALIFICATION_EVIDENCE` still set. It repeats the
readiness gate before upload or node contact. The secret remains external at the
configured Doppler reference. Node A serving activation and shared-VIP functional
acceptance remain later, separately authorized stages. Repository qualification
does not establish successful login against the installed Pi-hole application.

The preceding registered qualification passed nine scenarios against its
34-file source graph, with zero observer residue. Its authorization readiness
passed with evidence that is no longer available. The policy regressions reject seven adjacent source
changes and six evidence changes, including stale graph identities and a duplicate
command whose evidence hashes were recomputed. Full repository checks passed.
The exact review command, outer-runner identity, source hashes, and evidence hashes
are retained in the protected qualification directory reported by the runner.
Those qualification tests contacted no production node. The subsequent live run
failed and restored baseline as recorded in the current status above.

The consumed definition and terminal result are retained in the pushed archive
tag. Current registries now identify one replacement operation. Its qualification
adds five pre-mutation cases to the existing nine deployment/rollback cases:
missing IPv6 connectivity, untrusted TLS, HTTP 503, an inactive backend service,
and interruption during remote preflight. The first three require zero SSH,
SCP, and Doppler calls; the latter two require unchanged installed state and
cleanup through the actual coordinator. No production credential is retrieved
by `--connectivity-only`.

Host-only helper tests continue to cover helper installation, rollback, payload
identity, and SSH serialization. Full-coordinator preflight cases now run only
inside the network-disabled HTTPS fixture so host tests never contact live nodes.
The new bundle needs fresh qualification and exact-hash live authorization.

The replacement qualification passed all fourteen scenarios with zero observer
residue. Authorization readiness validated seventeen proportional decision records
against the unchanged 34-file source graph. Source-drift and evidence-tampering
regressions, secret-input tests, helper tests, and repository checks passed.
A protected evidence copy is retained outside `/tmp` under the workstation's
`.caddy-evidence` directory; the review document records the exact command and
restoration procedure if the original `/tmp` evidence is purged. No production
node or credential was contacted during this qualification. The new bundle is
ready for exact-hash live authorization.
