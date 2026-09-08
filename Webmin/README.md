# Webmin

The governing document is [WEBMIN_ARCHITECTURE.md](docs/WEBMIN_ARCHITECTURE.md).
The [drive-polling trial procedure](docs/DRIVE_POLLING_TRIAL.md) describes the
guarded configuration change, observation, and rollback.

> The drive-polling mitigation is a trial. A quiet observation does not accept
> storage for production use or satisfy Nautobot and Restic acceptance checks.

Run the focused local checks from the repository root:

```sh
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s Webmin/tests -v
git diff --check
```
