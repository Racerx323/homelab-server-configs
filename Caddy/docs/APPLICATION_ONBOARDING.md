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
| DNS | A and AAAA records for the Proxy VIPs `.56` and `::56` |
| Rollback | The prior immutable release and fragment removal plan |

Do not derive an endpoint from an existing DNS name. Confirm the backend owner,
service listener, health response, authentication boundary, and certificate
identity.

## Template contract

Copy the supported example to a new fragment outside the active release. Use a
filename in the `20-` range so the application route precedes the `90-` and
`91-` default-deny fragments. Replace every token:

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
exact live authorization. Follow [`OPERATIONS.md`](OPERATIONS.md). Apply and
accept Node B before Node A.

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
