# Webmin architecture

This document governs Webmin-owned configuration and the drive-polling trial.
It does not govern the storage stack, smartmontools packages or daemon,
Munin, Nautobot, or Restic.

## Authorized mitigation design

The trial sets `collect_notemp=1` in Webmin's system-status configuration.
This bypasses scheduled drive-temperature SMART collection for all drives.
Disk-space reporting is a separate collection path. CPU-temperature collection
is also separate, but its availability must be verified on each target.
The setting does not disable manual SMART Drive Status queries or independent
SMART callers.

The existing setting is preferred for this trial because it avoids maintaining
a local Webmin source patch. Losing scheduled drive temperatures is an explicit
tradeoff. Package removal, upgrades, USB-driver changes, and service restarts
are outside this mitigation.

## Execution boundary

The custom runner owns exact configuration comparison, atomic replacement,
backup and rollback, and an observer that survives controller disconnection.
It is a bounded diagnostic operation, not a general Webmin installer. Each
execution uses a reviewed operation specification and hashes of its inputs.
Only one operation may be active; observer repairs remain within that operation
and preserve the invalid evidence they supersede.

The observer collects existing history, kernel messages, filesystem counters,
service identities, and ordinary disk activity. It does not issue SMART requests
or generate storage workloads. A short execution trace verifies the Webmin
query path. Neither successful service status nor missing kernel messages alone
establishes adequate drive-health coverage.

## Review and adoption

Review two-hour and 24-hour checkpoints, including completed collection cycles,
query suppression, storage errors, and the monitoring coverage that remains.
Missing evidence or a failed probe requires review. A quiet checkpoint is an
observation, not proof of hardware reliability.

Only after the full observation and coverage review should the mitigation be
recorded as accepted desired configuration in this component. Storage acceptance
and Restic validation remain separate. Active operation state and raw evidence
stay outside Git; procedures belong in [DRIVE_POLLING_TRIAL.md](DRIVE_POLLING_TRIAL.md).

## Isolated patched-polling trial

The approved next intervention tests Webmin's upstream reduced-temperature-query
patch with smartmontools 7.4 unchanged. Remove only the temporary
`collect_notemp=1` override after the exact patch is installed and the observer's
execution trace is attached. This restores the default temperature behavior
without resetting unrelated configuration.

The patched trial uses continuous execution tracing and an automatic temperature
shutoff on unexpected queries, storage events, or observer failure. It also
disables temperature collection at the end of the bounded observation pending
review. Exact source backups support rollback while collection stays disabled.

Munin identity changes are retained for review and do not alone invalidate the
new trial: its installed daily log rotation intentionally restarts the daemon.
Service unavailability still fails the trial. Webmin and smartd identities remain
strict checks. This revised rule does not rewrite earlier checkpoint results.

See [PATCHED_POLLING_TRIAL.md](PATCHED_POLLING_TRIAL.md) for execution and reporting.
Upgrading smartmontools is a separate intervention after reviewing patch results.

## Repeated observation with the existing patch

After separately reviewed package or kernel changes, a new bounded observation
may retain the installed patch. The `start-existing` entrypoint binds the exact
reviewed smartmontools version, running kernel, boot identity, source bytes and
monitoring inputs. It changes only the temperature override; replacing sources
is prohibited in this mode. The original patch-install entrypoint remains scoped
to its 7.4 comparison. Repeated observations retain the same continuous query
trace, two-hour/24-hour evidence requirements and automatic shutoff, and neither
supersede historical results nor grant storage or workload acceptance.

## Host transport ownership

[Host storage](../../host-storage/docs/HOST_STORAGE_ARCHITECTURE.md) owns
root transport, boot configuration, reboot and recovery. Host inventory selects
the shared hardware/transport profile. `smartmontools/` owns the package workaround,
SMART collection and smartd policy; `Webmin/` owns temperature polling behavior.
Nautobot and other Restic consumers retain workload/storage acceptance and
backup/restore criteria. Transport convergence does not clear those gates.
Historical Nautobot remediation definitions and evidence remain retained; future
transport operations use the shared component without modifying active observers.

## Initial host administration profiles

The proposed `ssh-loopback` profile provides initial administration through an
operator-owned SSH tunnel, without another LAN listener or Caddy/DNS change.
HTTP is confined to `127.0.0.1` and `::1`; SSH protects the remote transport.
Disable automatic local-peer authentication (`localauth`); require existing
`ama` sudo/PAM authentication and explicit private operator login
acceptance. Do not create accounts or collect passwords as part of qualification.

Native [foundation tasks](../../foundation/README.md) install the persistent
first-start condition before package configuration, apply only managed miniserv
settings, then permit startup. The owner helper preserves other keys and file
metadata and refuses duplicate managed assignments. A failed operation removes
the permit and contains the listener while retaining packages/configuration for
review. No drive-temperature override, USB source patch or Nautobot-specific
state is selected by this profile.

## Fleet browser-access requirement

Normal fleet administration uses a dedicated HTTPS hostname through Caddy on
port 443, without a workstation tunnel. The initial `ssh-loopback` profile remains
an installed bootstrap/recovery baseline, not the final fleet access policy.
[Operations](OPERATIONS.md) clearly separates normal browser use from optional
SSH recovery; [onboarding](CADDY_ONBOARDING.md) reuses the existing Caddy and DNS
owner workflows for one selected host at a time.

Preserve existing Webmin authentication, unrelated settings and resource limits.
Restrict backend ingress to reviewed proxy identities plus loopback; retain
Caddy's intended-client allowlist and trusted frontend TLS. Backend transport,
referers, redirects, cookies and WebSocket behavior require pinned-version
qualification before exposure. Never disable authentication, global referer
checks or backend TLS verification as a shortcut. A host's private login and
browser-path acceptance remain distinct from Caddy configuration validity.

### TLS on both connections

The workstation connects to the cluster VIP on port 443 and verifies Caddy's
certificate for the browser hostname. Caddy terminates that TLS session so it
can proxy the HTTP request or WebSocket upgrade. The serving Caddy node then
acts as a TLS client: it connects directly to the selected Webmin host on port
10000 and verifies the certificate presented by Webmin's native HTTPS listener.
This keeps administrator passwords and sessions encrypted on the LAN. Caddy
remains a trusted endpoint that can read the requests.

Webmin holds its own server private key. Do not distribute the frontend TLS
key to fleet hosts. Both Caddy nodes must trust the backend issuer and verify
the expected certificate identity. When dialing a fixed IP with a DNS-name
certificate, set the upstream TLS server name to a DNS subject alternative
name on that certificate; this does not require another browser DNS record.
Keep the external hostname for Webmin redirects and referrer checks. Never
dial the frontend VIP as the upstream, disable verification, or fall back to
HTTP. Source restrictions still apply.

For each host, identify the certificate issuer, identity, renewal owner and
how both proxies receive any required public CA certificate before activation.
The first Pi's issuer and backend certificate have not been established.
See [Caddy upstream TLS](https://caddyserver.com/docs/caddyfile/directives/reverse_proxy#the-http-transport)
and [Webmin SSL encryption](https://webmin.com/docs/modules/webmin-configuration/#ssl-encryption).

The browser profile explicitly enables native referrer checks (`referer=0`),
preserves the host's missing-referrer policy (`referers_none`, where `1` rejects
missing referrers on protected actions), and adds only the selected trusted browser
hostname. These are separate controls. Native login/index exceptions remain.
Host ingress uses a Webmin-owned nftables table alongside existing application
and runtime tables; no full-ruleset replacement or shared firewall takeover.
Backend listener exposure requires verified ingress before startup, with the
same bound source list in miniserv. Host recovery restores exact prior settings.
