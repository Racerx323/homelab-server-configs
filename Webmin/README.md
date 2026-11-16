# Webmin

The governing document is [WEBMIN_ARCHITECTURE.md](docs/WEBMIN_ARCHITECTURE.md).
[Operations](docs/OPERATIONS.md) defines browser HTTPS as normal fleet access and
SSH tunneling as optional recovery. Use the shared
[Caddy onboarding procedure](docs/CADDY_ONBOARDING.md) for each fleet host; the
first approved hostname is not yet deployed. Existing loopback installations
remain unchanged until their own onboarding is accepted.
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

Browser-onboarding trial preparation uses the existing profile renderer and
`ansible/proxy-trial.yaml`, with exact loopback restoration through
`ansible/proxy-trial-restore.yaml`. Follow the
[native trial contract](docs/CADDY_ONBOARDING.md#native-backend-trial-and-recovery).
These includes require a separately sealed parent operation; they grant no live
authority. `tests/test_proxy_recovery.py` covers failure ordering, and
`tests/qualify-proxy-recovery.py` checks native timer/service/firewall recovery
with a dummy HTTP service in an isolated container. Neither test accepts host
capacity or actual Webmin browser behavior.

## Bounded HTTP diagnosis

`ansible/diagnose-http.yaml` diagnoses a stopped, disabled service under its
existing settings and limits. The selected operation defines the target and
private evidence paths. It arms a transient systemd containment timer before
creating a temporary start permit, performs unauthenticated loopback GETs, then
stops/disables the service and verifies no listeners or permit remain before
cancelling the fallback. No reboot, package action or authenticated request is
part of this diagnostic.

`scripts/diagnose-http.py` records HTTP status/timing with cgroup memory events,
CPU/I/O pressure and process state. Samples include memory charge categories,
limits/swap usage and numeric per-process PSS aggregates. Missing rollups and
truncated process inventories remain explicit; RSS totals alone are not a
cgroup memory attribution. It omits response bodies, cookies, command
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

## Read-only proxy readiness

`scripts/inspect-proxy-readiness.py --expected-hostname HOSTNAME` is the shared
host-side collector for a separately approved inspection. Stream it over existing
strict-host-key SSH with bounded privilege and private controller output; do not
install it or run it across inventory automatically. It verifies exact hostname
and boot continuity, projects only selected non-secret configuration fields,
checks file identity before/after, and reads service/listener/network/firewall
state. It performs no HTTP requests, login, staging, writes or service control.
Whole configuration contents, password/session stores and private keys are excluded.
A zero exit means capture completed, not that proxy deployment is ready.

Run `python3 -I -B Webmin/tests/test_proxy_readiness.py` for privacy, identity,
drift and bounded-failure contracts. Live inspection and browser onboarding
require their own exact reviewed scope.

The shared Caddy backend renderer and fictional input are documented in
[onboarding](docs/CADDY_ONBOARDING.md#render-the-backend-profile). Its local
qualification does not deploy a host or replace native browser acceptance.
The readiness collector requires an explicit `--interface` alongside hostname.
