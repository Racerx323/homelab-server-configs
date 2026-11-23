# Webmin operations

## Normal fleet access: browser HTTPS

The required fleet access method is a standard browser URL through Caddy on
port 443. Operators must not need an SSH session, tunnel, custom browser proxy
or manually selected port for normal administration. Webmin retains application
login; Caddy owns frontend TLS and client-network restrictions.

Use the accepted URL and account policy in the host inventory. Keep credentials, cookies and session tokens private.

Do not append `:10000` to an application's Caddy hostname. A name resolving to a
Proxy VIP addresses that proxy node at port 10000, not the intended backend host.
A reachable login page there does not identify the intended Webmin instance.
Do not diagnose the target's password from rejection at that different endpoint.

## Onboard another host

Follow the shared [Caddy onboarding procedure](CADDY_ONBOARDING.md). Select one
host and hostname, preserve its existing authentication and unrelated settings,
and use the established Caddy primary-first publication/secondary replication
sequence. DNS remains under its owner. Each host needs its own accepted backend,
route and browser check; the first host's result does not accept another host.

Before deployment, obtain the host's exact installed Webmin unit/drop-in identities
and current per-family route-selected sources from every Caddy node. Follow the
[mandatory readiness requirements](CADDY_ONBOARDING.md#required-readiness-evidence-for-every-host)
for capture, preflight rechecks, ingress binding and real-path acceptance.

Before sealing, define the host's
[safe WebSocket acceptance method](CADDY_ONBOARDING.md#safe-websocket-method-for-each-host),
including effective account permissions, side effects, expected results and cleanup.
Record reusable discoveries in the shared procedure as onboarding progresses;
keep host-specific evidence and unresolved gaps in the existing change record.

Keep the browser URL and observed acceptance in the host's inventory/change
record. Do not introduce an alternative fleet deployer, parallel Caddy replication
mechanism, or a certificate-repair workflow for routine proxy target additions.

## Optional recovery access: SSH tunnel

When a host uses fixed external redirect settings, a successful login through
the localhost tunnel sends the browser back to the fleet HTTPS name. For an
unavailable proxy, use administrative SSH on the backend host. To recover independent
browser access, use the approved Webmin recovery procedure to restore the
pre-change miniserv and Webmin configuration files, preserving ownership and
mode, then restart Webmin and verify its loopback listeners before using the
tunnel below. Keep an administrative shell open during that change. A successful
loopback login should then redirect to the workstation tunnel origin.

SSH tunneling is a fallback for an unavailable or not-yet-onboarded proxy path,
not the normal access method or final browser acceptance. It is optional after
browser onboarding. It does not repair Caddy/DNS, authorize a restart, or replace
ordinary-name HTTPS verification.

For a host with an approved loopback HTTP recovery profile, run this on the workstation, substituting its inventory SSH identity and address.

```sh
ssh -N -o ExitOnForwardFailure=yes -L 127.0.0.1:11000:127.0.0.1:10000 USER@HOST
```

Keep the terminal open and visit <http://127.0.0.1:11000/> on that workstation. Use the host’s configured backend scheme and port. Close the tunnel after recovery.

## Failure and maintenance boundaries

For a browser failure, first distinguish DNS/TLS, Caddy route/backend and Webmin
application login. Record the URL and safe error/status, not credentials or page
contents containing private data. A login rejection is not proof of proxy failure;
an HTTP health response is not proof of successful login or WebSocket operation.
Do not retry login POSTs automatically or remove authentication/source restrictions.

Preserve the existing service, unrelated routes and source configuration during
onboarding and recovery. Use the owning operation's exact backups and prior Caddy
release for rollback; do not replay a consumed deployment. Package upgrades,
account changes, storage/SMART trials and notification tests have separate scopes.

The proposed browser profile's guard must persist across ordinary service starts
and host boots. Use the [guard recovery procedure](CADDY_ONBOARDING.md#guard-lifecycle-and-recovery-qualification)
for the required ordering: restore and verify the saved loopback service before
removing its ingress table. A stopped guard service deliberately retains rules.
Do not flush the ruleset or remove Kuma/Netavark tables to regain Webmin access.
