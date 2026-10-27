# Fleet watchdog policy and adoption design

Status: proposed implementation policy, prepared for review. No deployment or
recovery execution is authorized. The [component README](../readme.md) governs
ownership; this document specifies the proposed standard and exception process.
Historical operator examples inform the comparison; they are not desired state.

## Standard and limits

Use the systemd **system manager hardware watchdog** as the preferred backend on
qualified systemd hosts with a supported watchdog device. Use one hardware-device
owner. Standardization means a shared policy, record format and lifecycle, with
explicit host exceptions; it does not require installing the Debian `watchdog`
daemon everywhere.

Proposed settings for qualification:

| Policy | Default proposal | Adoption condition |
| --- | --- | --- |
| Runtime timeout | 60 seconds | Confirm device support and actual effective timeout; qualify under intended ordinary load |
| Reboot timeout | 120 seconds | Qualify platform shutdown/reboot behavior; this is not a whole-boot deadline |
| Pretimeout and kexec watchdog | Disabled | Preserve supported effective state; changes require a specific recovery use case |
| Device | Observed identity, explicitly recorded per host | No fleet-wide assumption about device number, driver or path |
| Load, memory, ping, temperature or application-triggered host reset | Disabled/not configured | Monitor and use service-owned recovery first; any host-reset exception needs evidence and approval |
| No hardware watchdog or unqualified platform | Explicit unsupported/unqualified record | No silent software substitute and no fleet-acceptance claim |
| Existing owner | Preserve during discovery | Conflicting ownership blocks adoption or change |

The 60/120 proposal matches the observed NTP pilot. It is not evidence that all
hardware supports those values or that they are universally optimal. The systemd
manual notes that hardware may select a nearby supported timeout. Compare the
requested value, manager property and device metadata; resolve differences before
acceptance. Runtime watchdog coverage concerns missed hardware keepalives; it
does not prove an application, DNS path or network interface is healthy. Service
`WatchdogSec=` is a separate mechanism and requires a compatible service protocol.

For a qualified systemd host, use a reviewed component-owned local drop-in under
`/etc/systemd/system.conf.d/` if an explicit policy override is needed. Preserve
vendor files under `/usr/lib`; do not edit them in place. First qualify the
installed version's precedence and application/restoration mechanism. No generic
`daemon-reload`, reexec or reboot command is supplied as a universal activation
method. If adopting an unchanged vendor policy, record its exact provenance and
drift checks; do not create a redundant override merely to claim management.

A standalone `watchdog` daemon is an exception backend, considered only for a
required capability the standard cannot provide. It needs package/startup
side-effect inspection, exclusive ownership transfer, native configuration validation,
restoration and recovery qualification. Never install/start it alongside the
existing systemd device owner. No backend migration is proposed for the NTP pilot.

## Disposition of the historical example

| Example | Proposed disposition |
| --- | --- |
| Install `watchdog` on every host | Do not adopt; inspect the current owner and qualify the standard backend first |
| Disable only `max-load-1`; set `max-load-5=18`, `max-load-15=12` | Do not adopt; the daemon documents the 5- and 15-minute settings as reboot triggers too. Disabling the 1-minute check does not remove those triggers |
| Fixed load thresholds across machines | No fleet reset thresholds. Hardware capacity, workload and blocked I/O differ; role-specific monitoring is a separate policy |
| `/dev/watchdog` | Discover device identity and aliases per host; do not open a device as a probe |
| `watchdog-timeout=15` | Do not adopt as default. Preserve the pilot's 60-second runtime value pending controlled qualification |
| Symlink `/usr/lib/sendmail` to msmtp | Do not adopt blindly; preserve the fleet mail owner's package/frontend/alias lifecycle |
| Mail whenever triggered | Do not promise notification from a stalled/resetting host. Distinguish a daemon warning, external outage observation and post-recovery report |
| Reboot to apply | Only in a reviewed maintenance stage after independent recovery and service-impact checks |

No load, temperature, mail or daemon configuration from the reference has been
installed or promoted into inventory defaults.

## Host exceptions and role constraints

Use [inventory](../../inventory/README.md) membership. The existing
`common_configuration.watchdog: true` remains coverage intent. Future automation
must resolve component defaults, role requirements and explicit host overrides,
then validate the complete result. Conflicting role requirements must fail
validation; group ordering must not silently choose a safety policy.

Each exception must name the inventory key, host function, changed setting,
reason and supporting observations, accepted device/owner, operator, approval,
review date, rollback and recovery acceptance. Record requested and effective
values separately. Keep operational evidence in component records, not group
variables. Exceptions are reviewed decisions, never inferred from a host's name.

| Inventory host(s) | Function from inventory | Required exception/acceptance consideration |
| --- | --- | --- |
| `j2-svntp1` | NTP | Preserve GPS/PPS and shared-antenna power, primary service and DNAT; NTP Phase 3 recovery gate remains mandatory |
| `pihole0`, `pihole00` | DNS and reverse proxy | Treat linked DNS/Caddy Keepalived effects together; qualify peer readiness and one-node maintenance; never reset both as one batch |
| `svmf` | Monitoring and notification | Its outage can remove both observation and notification paths; require independent evidence/communication during recovery testing |
| `j2-svpi4mf` | Inventory automation | Qualify impact on its inventory/orchestration duties; no automatic fleet mutation from inventory events |

These are role constraints, not assignments of unseen backend or timeout values.
Only j2-svntp1 has the retained ownership observation used by this design. Other
hosts require their own scoped inspection before policy resolution.

## Adoption and implementation

1. Resolve the host policy from inventory without contacting targets. Use an
   explicit operation allowlist; a group flag cannot expand execution scope.
2. Inspect current versions, device/owner, effective configuration, unit/package
   behavior and recovery access under separate authorization. Preserve conflicts
   and unknowns; do not fix them in discovery.
3. Produce a per-host diff: unchanged-policy adoption or a specific configuration
   change. Keep observed, proposed and accepted states distinct. Choose the
   existing repository automation mechanism after reviewing its suitability;
   avoid a new transaction wrapper unless it owns a necessary safety boundary.
4. Qualify native configuration, actual activation, reverse restoration and
   residue checks. Capture original bytes/ownership/modes and who owns each
   destination. Review package scripts before a package operation.
5. Seal one pilot operation with exact inputs, expiry, one-use controls, health
   checks, recovery and evidence rules. Deployment and disruptive qualification
   require explicit scopes. Promote to the next host only after pilot acceptance.
6. Record accepted policy and monitoring ownership. Check drift after relevant
   OS/firmware/systemd changes and planned maintenance. Review the observation
   cadence with the operator before adding schedules; never auto-correct drift
   by restarting, resetting or taking device ownership.

The first implementation should resolve/validate/render policy and show a diff
without live changes. Deployment automation remains pending. Do not copy consumed
NTP inspection archives into runtime tooling; use repository-owned source.

## Notifications and dependencies

Fleet mail configuration belongs to `homelab-dns/msmtp`, including its
[fleet standardization procedure](../../../homelab-dns/msmtp/docs/FLEET_AUDIT_STANDARDIZATION_PROMPT.md).
Inspect and preserve the selected sendmail-compatible frontend; do not overwrite
a package-owned path or invent an account. Mailrise destinations are restricted
to `notify@mailrise.xyz` or a separately qualified `notify.<type>@mailrise.xyz`.
A sender address is not automatically an accepted recipient.

Proposed reporting uses the existing monitoring/notification owners for outage
and recovery signals. A watchdog device is not an email sender. New integration,
exact envelope/message/attachments and one-send tests need separate reviews.
SMTP submission alone does not establish downstream receipt; a wedged host may
be unable to submit anything. No new notification is part of this design work.

## Documentation basis

Primary references retrieved October 26, 2026; installed target documentation and
native behavior still govern qualification. The current upstream systemd manual
may contain options unavailable on an installed version.

- systemd source/manual: `https://www.freedesktop.org/software/systemd/man/latest/systemd-system.conf.html`
  and `https://github.com/systemd/systemd/blob/main/man/systemd.service.xml`.
- Debian Trixie watchdog configuration manual:
  `https://manpages.debian.org/trixie/watchdog/watchdog.conf.5.en.html`.
- Linux watchdog API, including close/nowayout and timeout limitations:
  `https://docs.kernel.org/watchdog/watchdog-api.html`.

These sources explain mechanisms; they do not choose fleet thresholds or prove
recovery. No claim is made that every CPU hog, blocked application or network
failure stops the hardware keepalive.
