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

## Fleet browser onboarding

Use the [fleet Webmin onboarding procedure](docs/CADDY_ONBOARDING.md) for backend selection, transport, Caddy publication, DNS and browser acceptance. The loopback profile and managed-settings editor preserve settings outside the selected keys.

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
Confirm capacity on each selected host under its intended workload.

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
