# Caddy application onboarding

This guide defines the information and review required before Caddy proxies a
new backend. It does not approve an application, create DNS records, or
authorize a production change.

[`caddy_plan-v1.1.md`](caddy_plan-v1.1.md) owns the HA and release lifecycle.
[`OPERATIONS.md`](OPERATIONS.md) owns publication and rollback. The supported
example is `Caddy/templates/reverse-proxy.caddy.example`.

## Approval inventory

Record and obtain operator approval for every field before writing a production
fragment.

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
| Transport | Dial and response-header timeouts |
| Request headers | Exact backend `Host` value and any approved overrides |
| Authentication | Application-owned, Caddy-owned, or none |
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

A production backend requires repository and DNS reconciliation, an immutable
protocol-v2 release, production-path validation, a defined successor, and an
exact live authorization. Follow [`OPERATIONS.md`](OPERATIONS.md) and
[`PROTOCOL_V2_RELEASE_LIFECYCLE.md`](PROTOCOL_V2_RELEASE_LIFECYCLE.md). Apply
and accept Node B before Node A.

After the authorized release owns the shared VIPs, test the application name
against each address family without bypassing certificate verification:

```bash
application_fqdn=APPROVED_FQDN
curl --fail --silent --show-error --ipv4 \
    --resolve "${application_fqdn}:443:10.1.0.56" \
    "https://${application_fqdn}/APPROVED_PATH"
curl --fail --silent --show-error --ipv6 \
    --resolve "${application_fqdn}:443:[fd36:5aa8:6971:1::56]" \
    "https://${application_fqdn}/APPROVED_PATH"
```

Acceptance must also prove backend health behavior, client restrictions,
default deny, continuous DNS and Proxy service, exact VIP ownership, and clean
protocol-v2 residue.

## Rollback

Publish a new immutable release that removes the application fragment and any
release-local CA used only by that application. Restore DNS only through its
separate reviewed repository and authorization boundary. Do not edit the
active release or delete its files in place. Preserve the failed release and
bounded evidence until rollback acceptance completes.
