# Webmin

The governing document is [WEBMIN_ARCHITECTURE.md](docs/WEBMIN_ARCHITECTURE.md).
The [drive-polling trial procedure](docs/DRIVE_POLLING_TRIAL.md) describes the
guarded configuration change, observation, and rollback.
The [patched-polling procedure](docs/PATCHED_POLLING_TRIAL.md) covers the
maintainer's reduced-query patch and an observation with temperatures enabled.

The corrected October 4–5 passive observation [passed full evidence review](docs/DISK_DISCOVERY_OBSERVATION_RESULT.md)
on October 6. The observer is inactive; monitoring remains enabled. The earlier
incomplete run remains archived separately.

> The drive-polling mitigation is a trial. A quiet observation does not accept
> storage for production use or satisfy Nautobot and Restic acceptance checks.

Run the focused local checks from the repository root:

```sh
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s Webmin/tests -v
git diff --check
```

## Host installation profile

The [foundation tasks](../foundation/README.md) coordinate the proposed initial
Uptime Kuma host installation. `configs/profiles/ssh-loopback.json` keeps Webmin
on dual-stack loopback for SSH-tunnel administration; it is distinct from the
Nautobot storage diagnostic. `scripts/configure-miniserv.py` atomically applies
only reviewed settings while preserving unmanaged options and rejecting duplicate
managed keys. First-start containment persists across reboot until configuration
has been checked. No generic fleet deployment or live acceptance is implied.

Run `python3 -I -B Webmin/tests/test_miniserv_configuration.py` for its focused
configuration-boundary regressions.

## Bounded HTTP diagnosis

`ansible/diagnose-http.yaml` diagnoses a stopped, disabled service under its
existing settings and limits. The selected operation defines the target and
private evidence paths. It arms a transient systemd containment timer before
creating a temporary start permit, performs unauthenticated loopback GETs, then
stops/disables the service and verifies no listeners or permit remain before
cancelling the fallback. No reboot, package action or authenticated request is
part of this diagnostic.

`scripts/diagnose-http.py` records HTTP status/timing with cgroup memory events,
CPU/I/O pressure and process state. It omits response bodies, cookies, command
lines and environments. A slow or failed request is evidence; successful
collection and containment do not accept the service or establish the cause.
The Uptime Kuma [work ledger](../../homelab-monitoring-observability/changes/2026-11-09-uptime-kuma/WORK.md)
owns the exact sealed command, authorization and outcome.

Run `python3 -I -B Webmin/tests/test_http_diagnostic.py` for the neutral
local-loopback regressions; socket tests need execution outside the filesystem
sandbox. Native service/timer qualification uses disposable Podman containers.

## Small-host dashboard collection

The proposed `system-status-small-host` profile sets only `collect_pkgs=0` in
`/etc/webmin/system-status/config`. Webmin 2.670's native status collector checks
this setting before entering `package-updates::list_possible_updates`. This
removes automatic dashboard package-update collection and its update summary;
it does not disable APT, remove the package-updates module, change collection
intervals or temperature policy, or replace fleet maintenance/needrestart.
Manual package actions remain separately reviewed maintenance.

`ansible/configure.yaml` uses the same atomic owner helper for miniserv and
module configuration. `ansible/accept.yaml` checks the effective collection
setting, both loopback login paths and the unchanged 128/192 MiB/no-swap limits.
The combined Pi resource budget remains subject to actual ARM64 acceptance.
Local fixture success does not accept the Pi correction.
