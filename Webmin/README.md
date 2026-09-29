# Webmin

The governing document is [WEBMIN_ARCHITECTURE.md](docs/WEBMIN_ARCHITECTURE.md).
The [drive-polling trial procedure](docs/DRIVE_POLLING_TRIAL.md) describes the
guarded configuration change, observation, and rollback.
The [patched-polling procedure](docs/PATCHED_POLLING_TRIAL.md) covers the
maintainer's reduced-query patch and an observation with temperatures enabled.

The [disk-only discovery candidate](docs/DISK_DISCOVERY_CANDIDATE.md) provides a
patch, regression fixtures and deployment review inputs. Its
[single-host qualification result](docs/DISK_DISCOVERY_DEPLOYMENT_RESULT.md)
records the completed authorized pilot. The
[24-hour passive observation](docs/DISK_DISCOVERY_OBSERVATION.md) has started;
its [startup record](docs/DISK_DISCOVERY_OBSERVATION_STATUS.md) lists checkpoint
times. Final acceptance remains pending.

> The drive-polling mitigation is a trial. A quiet observation does not accept
> storage for production use or satisfy Nautobot and Restic acceptance checks.

Run the focused local checks from the repository root:

```sh
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s Webmin/tests -v
git diff --check
```
