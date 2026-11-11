# Caddy application onboarding

This is the entry point for adding a proxy target to the existing Caddy service.
It owns the input review, routine release sequence, acceptance and recovery.
It does not authorize production changes or DNS edits.

[`caddy_plan-v1.1.md`](caddy_plan-v1.1.md) owns the architecture. The supported
example is `Caddy/templates/reverse-proxy.caddy.example`. Platform installation,
certificate repair and HA maintenance have separate procedures in
[`OPERATIONS.md`](OPERATIONS.md); their deployment checklists are not the routine
proxy-target onboarding procedure.

The approved primary-first sequence below still needs implementation and local
qualification. The installed publisher exposes outbound state immediately; the
consumed certificate-derived `application-onboarding` runner does not implement
this contract and must not be reused for it. Current component archive and
live-authorization boundaries still apply. See the
[implementation boundary](#implementation-boundary).

## Approval inventory

Record these inputs in one reviewed change. Reuse confirmed fleet defaults and
existing backend decisions; obtain one review of the completed candidate rather
than a separate approval for each field.

| Field | Required decision |
| --- | --- |
| Application | Exact application and service owner |
| Public FQDN | One approved hostname served through the Proxy VIPs |
| Fragment | `conf.d/20-<application>.caddy` with a unique application name |
| Backend protocol | `http` or verified `https` |
| Backend upstreams | Exact host or IP and port for each upstream |
| Backend TLS | Certificate name, SNI, and system or release-local CA source |
| Health contract | Method, URI, status, interval, timeout, passes, and failures |
| Passive health | Failure window, failure count, and unhealthy status classes |
| Transport | Dial and response-header timeouts; connection reuse and backend keep-alive compatibility |
| Request headers | Exact backend `Host` value and any approved overrides |
| Authentication | Application-owned, Caddy-owned, or none; rejection and retry acceptance cases |
| Client networks | Exact allowed IPv4 and IPv6 CIDRs |
| Availability | Single backend or multiple backends with a load-balancing policy |
| DNS | Application A and AAAA records for the Proxy VIPs; canonical Proxy PTR records remain unchanged |
| Rollback | The prior immutable release and fragment removal plan |

Do not derive an endpoint from an existing DNS name. Confirm the backend owner,
service listener, health response, authentication boundary, and certificate
identity.

## Fragment layout and ordering

Caddy permits several site blocks in one imported file, but this repository
uses one application per fragment. Closely related hostnames owned, reviewed,
published, and rolled back as one application may share that fragment.
Unrelated applications must use separate files. Every site address must remain
unique in the assembled configuration.

The two-digit prefix is an ordering category, not a sequence number:

| Prefix | Purpose |
| --- | --- |
| `00-09` | Shared health endpoints, snippets, and helpers |
| `10-19` | Platform services, including Pi-hole administration |
| `20-79` | Application reverse proxies |
| `90-99` | Default-deny and fallback routes |

Name a new application fragment `20-<application>.caddy`, for example
`20-homeassistant.caddy`. Multiple application fragments may use `20-`; the
unique application name distinguishes them. Use another number within
`20-79` only when a reviewed ordering dependency requires it.

The current production fragment inventory is:

| Fragment | Role |
| --- | --- |
| `00-health.caddy` | Local and shared Proxy-VIP health endpoints |
| `10-pihole-admin.caddy` | Pi-hole administration proxy and node health |
| `90-default-deny.caddy` | Default HTTP and HTTPS `421` response |
| `91-exact-listener-default-deny.caddy` | Exact node, Proxy-VIP, and loopback HTTPS `421` response |

`Caddy/manifests/config-lifecycle.tsv` is the mechanical inventory for the
repository configuration tree. Repository policy fails when a file beneath
`Caddy/configs` has no matching lifecycle row, so manually adding a fragment
also requires updating that registry in the same change. The
`Caddy/configs/caddy` tree represents accepted production configuration; stage
and validate a proposed fragment outside that tree until a reviewed production
change is defined.

`Caddy/manifests/caddy-release-source.tsv` records the exact sources and hashes
of the accepted immutable Caddy release. Do not add a proposed fragment to that
manifest or change its accepted payload identity before live acceptance. After
an authorized release is accepted, reconcile the fragment, lifecycle row,
release-source row, hashes, and accepted-live inventories together.

Repository policy does not prevent a privileged operator from changing a node.
Adding a file beneath `/etc/caddy/current` with root access creates production
drift and may change routing after the next Caddy reload. Release ownership and
read-only modes prevent ordinary service identities from writing there; root
can bypass those controls. Protocol-v2 manifest validation rejects extra or
changed files while creating and activating a candidate. No daemon continuously
compares the active release with its manifest. The routine installed validator
checks Caddy syntax but does not reject an extra file in the active release by
itself. A bounded production inventory must compare the active file set and
hashes with `manifest.sha256` and the accepted-live records to prove that no
privileged drift exists. Publish every production fragment through the reviewed
immutable-release path.

## Template contract

The current build method is an operator-reviewed copy and token replacement;
there is no repository generator. Copy the supported example to a protected
temporary directory outside the repository production tree and active release.
Use the approved `20-<application>.caddy` name so the application route
precedes the `90-` and `91-` default-deny fragments. Replace every token:

| Token | Value |
| --- | --- |
| `@@PUBLIC_FQDN@@` | Approved application hostname |
| `@@ALLOWED_CLIENT_CIDRS@@` | Space-separated IPv4 and IPv6 CIDRs |
| `@@BACKEND_UPSTREAMS@@` | Space-separated Caddy upstream addresses |
| `@@LB_POLICY@@` | Approved policy such as `random` or `first` |
| `@@HEALTH_URI@@` | Backend health path beginning with `/` |
| `@@HEALTH_STATUS@@` | Exact expected HTTP status |
| `@@HEALTH_INTERVAL@@` | Active-check interval |
| `@@HEALTH_TIMEOUT@@` | Per-check timeout |
| `@@HEALTH_PASSES@@` | Successes required to mark an upstream healthy |
| `@@HEALTH_FAILS@@` | Failures required to mark an upstream unhealthy |
| `@@FAIL_DURATION@@` | Passive failure retention window |
| `@@MAX_FAILS@@` | Passive failures allowed within that window |
| `@@BACKEND_HOST_HEADER@@` | Exact Host header expected by the backend |
| `@@DIAL_TIMEOUT@@` | Upstream connection timeout |
| `@@RESPONSE_HEADER_TIMEOUT@@` | Upstream response-header timeout |
| `@@BACKEND_TLS@@` | `tls` for HTTPS or an explanatory comment for HTTP |
| `@@BACKEND_TLS_SERVER_NAME@@` | `tls_server_name NAME` or an HTTP comment |
| `@@BACKEND_TLS_TRUST_POOL@@` | Private trust pool or a system-trust/HTTP comment |

The template uses `remote_ip` because clients connect to the Proxy VIPs
directly. Do not base access control on forwarded client headers unless a later
review defines trusted proxies. The known application hostname returns `403`
to clients outside the allowlist. Unknown hostnames continue to reach the
existing `421` default-deny routes.

Caddy supplies the standard `X-Forwarded-For`, `X-Forwarded-Proto`, and
`X-Forwarded-Host` headers. The template sets the approved `Host` for client
requests and active health requests because the backend owns that contract.
Add another `header_up` or `health_headers` value only when the backend owner
requires and approves it.

The template does not implement authentication. Record whether the application
or Caddy owns authentication. A Caddy-owned authentication design requires its
own review and secret boundary.

## Authentication rejection and retry gate

Every proxied web interface with authentication must pass this gate during
initial onboarding and after changes to authentication, proxy health policy,
or upstream transport. For an application without login, record why the
password case is not applicable and test its equivalent access-denial flow.

Record the application's expected rejection status, page, redirects, session
behavior, and any deliberate rate limit or lockout. An incorrect password must
produce the application's normal rejection and permit an immediate retry when
its policy allows. A deliberate lockout may restrict that account; it must not
make the shared backend unavailable to other users or the health monitor.
Do not classify expected authentication rejection as backend failure or enable
automatic replay of login POSTs to hide a transport error.

Validate incorrect password, immediate retry, successful login, authenticated
page access, and logout over IPv4 and IPv6. Exercise fresh connections and
connections idle near the backend's documented keep-alive timeout. Use a
bounded, approved test account and keep credentials, cookies, CSRF tokens, and
request bodies outside logs and retained evidence. For SSO or other login
methods, exercise the equivalent rejected-authentication and retry sequence.

Record a bounded, sanitized result with expected and observed application behavior
for each address family. Verify another client remains usable and expected login
rejection does not cause proxy errors or backend exclusion. Check WebSocket use
when the application requires it. These are onboarding completion checks, separate
from release activation. Keep credentials private and allow the operator to perform
the check after the route is ready; there is no ten-minute receipt window or
rollback caused solely by operator delay. Pending login verification means
onboarding is incomplete, not that replication failed. A failed functional check
requires diagnosis and the reviewed application recovery, not an automatic replay.

Use existing health signals and targeted observation appropriate to the changed
route. Routine onboarding does not require requalification of platform notification
cycles or a custom journal/receipt collector. Changes to authentication, health
policy or transport still require focused regression coverage.

For a single backend, explicitly decide whether passive exclusion offers any
benefit and record its availability cost. The example's `@@FAIL_DURATION@@`
may be `0s` to disable passive checks. Review its `unhealthy_status 5xx` against
the application's actual behavior; expected authentication responses must not
trip that policy. Connection reuse is an application-specific decision: use a
reviewed timeout compatible with the backend, or disable it. Do not apply the
accepted Pi-hole transport policy to all applications without that review.

### Pi-hole login validation

Use `scripts/validate-pihole-authentication.py` for Pi-hole Web v5.21 HTTP
acceptance. It supports node-specific targets and the shared URL, fresh and idle
sessions over IPv4/IPv6, rejection/retry, dashboard access, logout, and denial
after logout. `--connectivity-only` checks verified HTTPS and the login form
without retrieving a password or issuing a POST.

For authenticated validation, provide `--password-fd` or `--password-doppler`.
The operator confirmed that both nodes use the password at this reference:

```text
homelab-dev / prd_caddy / PIHOLE_NODE_B_WEB_PASSWORD
```

Keep that value external. The validator reads it through a bounded pipe, requires
a successful provider exit, and cleans up provider descendants. Passwords and
session cookies stay in memory; values must not enter argv, environment variables,
files, or retained evidence. Do not substitute a stored Pi-hole password hash or
reset the password for a test.

Shared-route validation requires `--shared-owner node-a`. This flag asserts an
ownership check by the caller; the validator does not verify HA ownership. The
reviewed live procedure must check ownership before and after login and observe
VIP continuity, health events, and availability on both nodes throughout. The
completed migration's outer runner is archived and must not be used as a current
collector. Define any required collection in the next reviewed procedure.

For isolated validation of accepted production behavior and the secret boundary:

```bash
/bin/bash Caddy/tests/run-focused-container.sh --profiles authentication-resilience
```

See [the governing authentication contract](caddy_plan-v1.1.md#authentication-availability-contract)
for transport and health policy and [HISTORY.md](../HISTORY.md) for accepted live
results. Repository tests do not authorize new live login tests or deployment.

## DNS record gate

Each application FQDN requires exactly these forward records:

| Type | Required value |
| --- | --- |
| `A` | `10.1.0.56` |
| `AAAA` | `fd36:5aa8:6971:1::56` |

The shared addresses have one canonical reverse identity:

| Address | Canonical PTR target |
| --- | --- |
| `10.1.0.56` | `proxy.local.theama.co.` |
| `fd36:5aa8:6971:1::56` | `proxy.local.theama.co.` |

`proxy.local.theama.co` must in turn resolve to `10.1.0.56` and
`fd36:5aa8:6971:1::56`. An application hostname does not receive another PTR
record. Sharing these addresses does not change their canonical reverse
identity. Caddy selects the application using TLS SNI and the HTTP `Host`
header; reverse DNS does not participate in routing.

`homelab-dns/Unbound/configs/pihole-local-zone.conf` owns the authoritative
local-zone data. `Caddy/manifests/dns-records.yaml` records accepted Caddy/DNS
intent; it is not the deployed Unbound source. Check both before defining the
production operation. Reject an existing A, AAAA, or CNAME collision and reject
additional address answers.

Reject additional PTR targets for either shared Proxy address unless a later
architecture decision explicitly changes the canonical reverse identity. Add
an SRV record only when the application contract requires one and the operator
approves its priority, weight, port, and target.

The production operation must keep DNS validation separate from Caddy routing
validation:

1. Validate the edited `pihole.conf` and `pihole-local-zone.conf` pair with the
   accepted Unbound parser before reload.
2. Prove the proposed Caddy route over IPv4 and IPv6 with `curl --resolve`.
   These requests bypass DNS and prove only Caddy, TLS, and backend behavior.
3. Apply and accept the DNS change on Node B before Node A. Do not reload both
   Unbound instances together.
4. Require each node's resolver to return exactly one A and one AAAA value for
   the application.
5. Require the shared IPv4 and IPv6 DNS VIPs to return the same exact answers.
6. Require reverse queries for both Proxy VIPs to return only
   `proxy.local.theama.co.` on each node and through each shared DNS transport
   family. Require that canonical name to resolve forward to both Proxy VIPs.
7. Repeat the exact forward and reverse checks after rollback or recovery.

After the separately authorized DNS change, run node-specific checks from a
trusted operator host:

```bash
application_fqdn=APPROVED_FQDN
dig +short @10.1.0.53 "$application_fqdn" A
dig +short @10.1.0.53 "$application_fqdn" AAAA
dig +short @10.1.0.54 "$application_fqdn" A
dig +short @10.1.0.54 "$application_fqdn" AAAA
dig +short @fd36:5aa8:6971:1::53 "$application_fqdn" A
dig +short @fd36:5aa8:6971:1::53 "$application_fqdn" AAAA
dig +short @fd36:5aa8:6971:1::54 "$application_fqdn" A
dig +short @fd36:5aa8:6971:1::54 "$application_fqdn" AAAA
dig +short @10.1.0.53 -x 10.1.0.56
dig +short @10.1.0.53 -x fd36:5aa8:6971:1::56
dig +short @10.1.0.54 -x 10.1.0.56
dig +short @10.1.0.54 -x fd36:5aa8:6971:1::56
dig +short @10.1.0.53 proxy.local.theama.co A
dig +short @10.1.0.53 proxy.local.theama.co AAAA
dig +short @10.1.0.54 proxy.local.theama.co A
dig +short @10.1.0.54 proxy.local.theama.co AAAA
```

Require `10.1.0.56` for each A query and
`fd36:5aa8:6971:1::56` for each AAAA query. Then validate client-facing DNS
over both shared address families:

```bash
dig +short @10.1.0.55 "$application_fqdn" A
dig +short @10.1.0.55 "$application_fqdn" AAAA
dig +short @fd36:5aa8:6971:1::55 "$application_fqdn" A
dig +short @fd36:5aa8:6971:1::55 "$application_fqdn" AAAA
dig +short @10.1.0.55 -x 10.1.0.56
dig +short @10.1.0.55 -x fd36:5aa8:6971:1::56
dig +short @fd36:5aa8:6971:1::55 -x 10.1.0.56
dig +short @fd36:5aa8:6971:1::55 -x fd36:5aa8:6971:1::56
dig +short @10.1.0.55 proxy.local.theama.co A
dig +short @10.1.0.55 proxy.local.theama.co AAAA
dig +short @fd36:5aa8:6971:1::55 proxy.local.theama.co A
dig +short @fd36:5aa8:6971:1::55 proxy.local.theama.co AAAA
```

Reject NXDOMAIN, SERVFAIL, timeout, family mismatch, missing answers, duplicate
answers, any forward value other than the two Proxy VIPs, or any reverse value
other than `proxy.local.theama.co.`. Also query A and AAAA for
`proxy.local.theama.co` and require the two Proxy VIPs. Finally run trusted
HTTPS without `--resolve`. The HTTPS requests prove that normal resolver
selection reaches the accepted Proxy VIP and that the certificate covers the
application FQDN.

```bash
curl --fail --silent --show-error --ipv4 \
    "https://${application_fqdn}/APPROVED_PATH"
curl --fail --silent --show-error --ipv6 \
    "https://${application_fqdn}/APPROVED_PATH"
```

## HTTP backend

Use upstreams without an `https://` scheme. Replace the three backend TLS
tokens with comments so the rendered fragment contains no TLS directive. Keep
the dial and response-header timeouts.

Example transport replacements:

```caddyfile
# HTTP backend: TLS disabled
# HTTP backend: no TLS server name
# HTTP backend: no TLS trust pool
```

## HTTPS backend

Use `https://` upstreams and keep certificate verification enabled. Set
`tls_server_name` to the certificate identity when the upstream address is an
IP or another name. Replace the trust-pool token with a comment when the system
trust store contains the issuing public CA. For a private CA, place the reviewed
CA certificate inside the prepared immutable release and reference it through
`{$CADDY_CONFIG_ROOT}`:

```caddyfile
tls
tls_server_name backend.example.internal
tls_trust_pool file {$CADDY_CONFIG_ROOT}/trust/application-ca.pem
```

Do not use `tls_insecure_skip_verify`. Upstreams with different certificate
names or trust roots require separate proxy definitions. Do not weaken one TLS
policy to combine them.

The health endpoint must return the approved status without an authentication
redirect. If it needs request headers, record and review them as part of the
health contract. Do not commit health credentials.

## Repository validation

Create a complete prepared release in a temporary directory. Include the
current `Caddyfile`, all accepted `conf.d` fragments, TLS inputs, the new
fragment, and any private backend CA. Set the three protected node values to
reviewed non-secret test values, then run:

```bash
CADDY_CONFIG_ROOT=/tmp/PREPARED_RELEASE \
NODE_FQDN=pihole0.local.theama.co \
NODE_IPV4=10.1.0.53 \
NODE_IPV6=fd36:5aa8:6971:1::53 \
    caddy adapt --validate --adapter caddyfile \
    --config /tmp/PREPARED_RELEASE/Caddyfile

CADDY_CONFIG_ROOT=/tmp/PREPARED_RELEASE \
NODE_FQDN=pihole0.local.theama.co \
NODE_IPV4=10.1.0.53 \
NODE_IPV6=fd36:5aa8:6971:1::53 \
    caddy validate --adapter caddyfile \
    --config /tmp/PREPARED_RELEASE/Caddyfile

Caddy/tests/run-focused.sh --profile current-repository-policies \
    --phase host --container never
```

These commands validate files on the workstation. They do not publish a
release or authorize node contact.

## Production change and acceptance

Follow the [routine release sequence](#routine-release-sequence). Use the existing
publisher, managed transport, receiver, finalizer and reconciler; do not create a
parallel release framework. [`PROTOCOL_V2_RELEASE_LIFECYCLE.md`](PROTOCOL_V2_RELEASE_LIFECYCLE.md)
explains their current implementation, including the pending sequencing change.

### Routine release sequence

1. **Prepare one candidate.** Start from the accepted release and add the reviewed
   application fragment. Preserve unrelated routes and TLS material. Validate
   the complete configuration, certificate coverage, changed inputs and exact
   parent/revision/manifest. Keep the candidate outside transport-visible outbound
   state. Record the previous release for recovery.
2. **Activate and check Node A.** Use the existing immutable-release activation
   mechanism. Verify the selected revision, successful reload, trusted HTTPS to
   the new route and representative existing routes over IPv4 and IPv6. Use
   `curl --resolve` to test the hostname before DNS changes. An unverified or
   failed primary activation must never release this candidate for replication.
3. **Release the same candidate to replication.** After Node A passes, expose
   that exact revision and payload to managed lsyncd. Do not rebuild a child
   using Node A's newly selected release as its parent. Preserve the original
   parent so Node B can accept the same child of its prior release.
4. **Accept and check Node B.** Let the receiver/finalizer/reconciler validate
   integrity, local Caddy compatibility, parent identity and safe activation.
   Confirm the selected revision and manifest match Node A, reload succeeded,
   and new/existing routes work on Node B over both families. Reject local drift
   with precise evidence rather than overwriting it or assuming primary success
   proves secondary compatibility.
5. **Complete onboarding.** Record both nodes' release acceptance and shared
   endpoint checks. Complete private login/WebSocket checks where applicable.
   Apply DNS only through its separate owner procedure after Caddy acceptance,
   then verify ordinary name resolution and HTTPS. Update accepted inventories
   only for the state actually proved.

Primary service does not wait for secondary confirmation. Completion of the HA
change does: secondary lag or rejection leaves a visible partial outcome, and
new DNS activation remains pending. Keep a finite replication/convergence deadline
in the reviewed implementation; do not add a deadline for human attendance.

## Checks and evidence

Keep one bounded result per deployment stage. Report the node, revision, check,
expected value, observed value and exit status for every rejection. Keep credentials
and private TLS material out of evidence. Retain exact changed-input hashes and
release identities; compare the preserved parent inventory rather than treating
all current repository tool hashes as installed production requirements.

Retain configuration/TLS validation, bounded convergence, existing-route checks,
release-integrity checks and explicit recovery. Rely on the receiver/finalizer/
reconciler for their existing safety checks rather than duplicating their logic in
an outer controller. Qualify their actual success and failure effects when changing
the coordinator. Installed-tool compatibility matters, but an unrelated platform
source change is not automatically a prerequisite for adding a route.

Broad certificate-repair, host-foundation, HA failover and notification qualification
belong to changes of those components. Routine onboarding must not invoke those
workflows or require their historical operation records to match a fixture.

## Recovery and partial outcomes

- **Node A fails before exposure:** restore and verify its previous immutable
  release. Do not propagate the failed candidate. Node B stays on its prior release.
- **Node A passes; Node B rejects or times out:** retain Node A's verified release
  and Node B's last proven release. Stop progression and record partial acceptance,
  the failed secondary check and the exact revision on each node. Do not claim HA
  completion, enable the new DNS record or overwrite secondary drift. Further
  repair or rollback requires the operation's reviewed recovery scope.
- **Application checks fail after both activations:** use the reviewed release
  recovery to remove or correct the new fragment. Preserve unrelated routes, TLS
  material and bounded evidence. Do not edit active immutable files in place.
- **Write state or recovery is uncertain:** stop with manual intervention required.
  Never infer success from a lost controller connection or replay a consumed action.

The temporary mixed-revision interval means failover may lose the new route until
Node B accepts it. Existing routes must remain healthy. This is the primary-first
tradeoff; it must be visible in the result rather than hidden by a success label.

## Implementation boundary

The current publisher constructs and exposes outbound revisions in one operation.
The new contract needs preparation/local activation to finish before transport
exposure, without changing candidate identity. Reconcile that boundary in the
existing release machinery and application coordinator, then qualify primary
failure/no propagation, successful replication, secondary drift/rejection, bounded
timeout, and existing-route preservation before requesting live authority.

The certificate-derived runner and its timed helper remain consumed execution
artifacts until their required terminal archive is published. They are not the
routine onboarding entry point. Preserve that history, then remove their obsolete
application-specific coupling in place; keep platform repair behavior separately
scoped. No executable command in this guide claims that the new sequence is
already implemented or live-accepted.

## Installed baseline identities in qualification

Installed-file preflight uses the accepted deployed identity from
`manifests/accepted-live-artifacts.tsv`. Repository source hashes describe the
candidate source; they do not prove the installed baseline. In particular,
`reconciler_installed_sha256` identifies the unchanged installed reconciler.
Application-only onboarding does not install the repository reconciler.

Release and application fixtures require `CADDY_ACCEPTED_RECONCILER_FIXTURE`
to name an absolute regular file containing independently retained accepted
reconciler bytes. Both container launchers mount that file read-only; the
fixture checks its SHA-256 against both nodes' accepted owner records before
using it. Keep these retained runtime bytes outside the repository. Do not
substitute repository source or update the expected hash to make a test pass.

A failed file check emits one bounded metadata line on captured stderr: path,
file type, expected SHA-256, observed SHA-256 (or unavailable/unreadable), and
rejection. It never emits contents or follows a symlink. Preserve the outer
preflight stderr/status with the execution evidence. Source-byte drift,
tampering, missing files and symlinks must reject before publication, with
staging disposition verified.
