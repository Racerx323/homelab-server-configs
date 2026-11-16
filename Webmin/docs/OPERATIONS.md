# Webmin operations

## Normal fleet access: browser HTTPS

The required fleet access method is a standard browser URL through Caddy on
port 443. Operators must not need an SSH session, tunnel, custom browser proxy
or manually selected port for normal administration. Webmin retains application
login; Caddy owns frontend TLS and client-network restrictions.

Use the host's accepted Webmin URL in inventory. The approved first hostname is
`https://webmin-j2-svpi3bmf.local.theama.co` for `j2-svpi3bmf` (`10.1.3.75`).
**That hostname is approved but not yet deployed.** Its implementation and
acceptance are tracked in
[W-128](../../../homelab-monitoring-observability/changes/2026-11-09-uptime-kuma/WORK.md).
Approval of a hostname is not evidence that DNS, Caddy or backend access works.

Log in with the account selected by that host's Webmin policy. For the Pi, this
is `ama` using its existing Unix account password, not the separate Kuma account.
Other hosts retain their reviewed account policy; do not assume every host uses
`ama`, enable root login fleet-wide, or reset passwords during proxy onboarding.
Credentials, cookies and session tokens stay out of chat, source and evidence.

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

SSH tunneling is a fallback for an unavailable or not-yet-onboarded proxy path,
not the normal access method or final browser acceptance. It is optional after
browser onboarding. It does not repair Caddy/DNS, authorize a restart, or replace
ordinary-name HTTPS verification.

For the currently installed loopback HTTP profile on `j2-svpi3bmf`, run this in
**WSL/Ubuntu on the workstation running your browser**, not inside a Pi SSH session:

```bash
ssh -N -o ExitOnForwardFailure=yes -L 127.0.0.1:11000:127.0.0.1:10000 ama@10.1.3.75
```

Keep that terminal open, then visit `http://127.0.0.1:11000/` on the workstation.
Log in as `ama` with the Pi's Unix account password. The local browser leg is HTTP;
SSH encrypts transport to the Pi. The headless Pi needs no browser. `127.0.0.1:11000`
in this URL means the workstation, while forwarded `127.0.0.1:10000` means the Pi.
Stop the tunnel with Ctrl+C when finished. A port-binding error means the local
forward did not start; do not assume an already-open localhost page is this tunnel.

For another host, use its reviewed SSH identity, backend port and HTTP/HTTPS
scheme. Do not copy this host's username or turn off certificate validation to
work around a different profile. Never bind the workstation forward to `0.0.0.0`.
Existing key authentication to SSH does not replace Webmin's password check.

After the browser profile is installed, canonical redirects can send a tunneled
request back to the public HTTPS name. The tunnel alone is therefore not a
qualified independent login path during a proxy outage. Use SSH command-line
administration to diagnose or follow the host's approved recovery operation to
restore its saved loopback profile and verify service health. Do not improvise
redirect/authentication changes or describe this fallback as tested browser recovery.
The command above applies to the currently accepted loopback profile; reconcile
this section with the first host's actual recovery acceptance before deployment.

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
