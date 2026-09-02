# reconYa Installation and systemd Service

This guide installs a pinned, checksum-verified release of
[Dyneteq/reconya](https://github.com/Dyneteq/reconya) and configures it to run
in the background, restart after failures, and start automatically at boot.

The commands below are intended for a Linux system that uses `systemd`, such as
Debian, Ubuntu, or Raspberry Pi OS.

## 1. Install required tools

```bash
sudo apt update
sudo apt install -y curl file
```

## 2. Download and install reconYa

Do not pipe the upstream installer into a shell. It downloads a moving `latest`
release and does not verify a checksum. On a trusted controller, prepare the
pinned ARM64 release bundle described in [Updating reconYa](#8-updating-reconya),
then extract its already-verified release archive into the installation
directory.

```bash
mkdir -m 0700 -p /tmp/reconya-initial
tar -xzf /ABSOLUTE/PATH/reconya-v0.26.0-update.tar.gz \
  -C /tmp/reconya-initial
mkdir -p "$HOME/reconya"
tar -xzf /tmp/reconya-initial/reconya-linux-arm64.tar.gz \
  -C "$HOME/reconya"
chmod 755 "$HOME/reconya/reconya-linux-arm64"
```

These commands are ARM64-specific. Pin and verify the AMD64 artifact for an
AMD64 installation; do not rename an ARM64 binary.

Inspect the resulting installation:

```bash
cd "$HOME/reconya"
ls -lha
```

The executable name depends on the CPU architecture:

| Architecture | Typical executable |
| --- | --- |
| Raspberry Pi 64-bit / ARM64 | `reconya-linux-arm64` |
| Intel or AMD 64-bit | `reconya-linux-amd64` |

Confirm the installed executable:

```bash
find "$HOME/reconya" -maxdepth 1 -type f -name 'reconya-linux-*' -executable -print
```

Do not copy an executable name from another system. The `ExecStart` path in the
service must exactly match the file reported by this command.

## 3. Configure reconYa

The repository owns a complete, sanitized J1-SVMF configuration at
`Reconya/configs/svmf.env.example`. Do not build the live configuration from
the release archive's `.env.example`: the example currently on J1-SVMF
predates v0.26.0 and omits effective isolation and alert settings.

From the repository checkout on the controller, create the private target file
without printing its contents:

```bash
test -f Reconya/configs/svmf.env.example
ssh pi@svmf.local.theama.co \
  'test ! -e /home/pi/reconya/.env && umask 077 && tee /home/pi/reconya/.env >/dev/null' \
  < Reconya/configs/svmf.env.example
```

On J1-SVMF, replace both credential placeholders:

```bash
ssh -t pi@svmf.local.theama.co 'nano /home/pi/reconya/.env'
```

Generate a strong password locally or through the chosen secret manager. If
using OpenSSL directly, avoid placing the result in shell history:

```bash
openssl rand -base64 32
```

Confirm that placeholders are gone and permissions are private without
printing either credential:

```bash
ssh pi@svmf.local.theama.co \
  '! grep -Eq "REPLACE_WITH_(LOGIN_USERNAME|STRONG_PASSWORD)" /home/pi/reconya/.env && chmod 600 /home/pi/reconya/.env && test "$(stat -c %a /home/pi/reconya/.env)" = 600'
```

The live `.env` remains target-only because it contains credentials. The
repository template fixes the eight non-secret v0.26.0 settings, including all
four outbound lookup controls and the alert threshold. See the complete
[configuration ownership boundary](configs/README.md).

> [!WARNING]
> ReconYa v0.26.0 does not read `JWT_SECRET_KEY`; setting it does not change the
> application-embedded session key. Restrict port 3008 to trusted networks and
> re-audit authentication before exposing the interface more broadly.

## 4. Test the application manually

For an ARM64 system:

```bash
cd "$HOME/reconya"
sudo ./reconya-linux-arm64
```

For an AMD64 system:

```bash
cd "$HOME/reconya"
sudo ./reconya-linux-amd64
```

Open `http://SERVER-IP:3008` in a browser. Press `Ctrl+C` after confirming that
the application starts successfully.

## 5. Create the systemd service

Determine the exact home directory and executable path:

```bash
printf 'Installation directory: %s\n' "$HOME/reconya"
find "$HOME/reconya" -maxdepth 1 -type f -name 'reconya-linux-*' -executable -print
```

Validate the repository-owned service template:

```bash
/bin/bash Reconya/scripts/check-reconya-service.sh
```

For a Raspberry Pi user named `pi` with the ARM64 executable, install the
reviewed template:

```bash
sudo install -D -m 0644 \
  Reconya/templates/reconya.service \
  /etc/systemd/system/reconya.service
sudo systemd-analyze verify /etc/systemd/system/reconya.service
```

Copy the template before editing if the installation account, home directory,
or architecture differs. Change both `/home/pi/reconya` paths for another
account, or change `reconya-linux-arm64` to `reconya-linux-amd64` on AMD64.

ReconYa is run as root here because its upstream launch instructions use
`sudo`, and network discovery may require privileged networking operations.

ReconYa v0.26.0 ignores `SIGTERM`, but its graceful HTTP shutdown path listens
for `SIGINT`. The template uses `KillSignal=SIGINT` to reach that path and gives
the application 15 seconds before systemd uses `SIGKILL`. ReconYa's internal
HTTP shutdown deadline is 10 seconds, so the systemd limit leaves five seconds
for process cleanup and exit.

Treat `SIGINT` as a version-specific workaround. For each binary update, inspect
the candidate's signal registration and run a controlled stop test. Retain the
workaround while the candidate ignores `SIGTERM`. Return to systemd's standard
`SIGTERM` only after the candidate handles it through the same graceful
shutdown path.

## 6. Enable and start the service

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now reconya.service
```

Check its status:

```bash
sudo systemctl status reconya.service
```

Confirm that the web interface responds:

```bash
curl -sS -o /dev/null -w 'HTTP %{http_code}\n' http://localhost:3008/
```

An `HTTP 200`, `302`, or `303` response confirms that the web server is
reachable. Do not use `curl -I` for this check: `-I` sends an HTTP `HEAD`
request, which reconYa may reject with `405 Method Not Allowed` even though the
application is running normally.

Then open:

```text
http://SERVER-IP:3008
```

## 7. Service management and logs

Start, stop, or restart reconYa:

```bash
sudo systemctl start reconya.service
sudo systemctl stop reconya.service
sudo systemctl restart reconya.service
```

Show recent logs:

```bash
sudo journalctl -u reconya.service -n 100 --no-pager
```

Follow logs live:

```bash
sudo journalctl -u reconya.service -f
```

Confirm that reconYa is enabled at boot:

```bash
sudo systemctl is-enabled reconya.service
```

## 8. Updating reconYa

The repository pins the J1-SVMF update from v0.24.1 to v0.26.0. Read the exact
[operation specification](operations/update-v0.26.0.md) before proceeding.
The procedure preserves `.env`, snapshots the stopped SQLite data directory,
and rolls back both the binary and data if acceptance fails.

Prepare the deterministic deployment bundle on a networked, trusted controller:

```bash
cd /home/aaron/code/homelab-server-configs
/bin/bash Reconya/scripts/prepare-reconya-update.sh \
  /tmp/reconya-v0.26.0-update.tar.gz
sha256sum /tmp/reconya-v0.26.0-update.tar.gz
```

The preparation script uses exact v0.26.0 URLs, requires the publisher's exact
archive checksum, restricts archive members, verifies the extracted ARM64 ELF
binary against a pinned hash, and prints the final bundle SHA-256. The publisher
has not signed the checksum. Both the checksum and release asset come from
GitHub, so the repository-pinned value provides review visibility rather than
independent signature verification.

Review the complete bundle and obtain authorization for its exact printed
SHA-256 before transferring it or changing the live service. These commands
create the root-only target directory and transfer the authorized bytes without
sending a multi-command shell program through SSH:

```bash
ssh pi@svmf.local.theama.co \
  'sudo -n test ! -e /root/reconya-v0.26.0-bundle'
ssh pi@svmf.local.theama.co \
  'sudo -n test ! -e /root/reconya-v0.26.0-update.tar.gz'
ssh pi@svmf.local.theama.co \
  'sudo -n install -d -m 0700 /root/reconya-v0.26.0-bundle'
ssh pi@svmf.local.theama.co \
  'sudo -n tee /root/reconya-v0.26.0-update.tar.gz >/dev/null' \
  < /tmp/reconya-v0.26.0-update.tar.gz
```

Verify the target copy against the exact hash you authorized. Replace the
example hash with that reviewed value; do not copy a stale value from an older
operation:

```bash
printf '%s  %s\n' AUTHORIZED_BUNDLE_SHA256 \
  /root/reconya-v0.26.0-update.tar.gz | \
  ssh pi@svmf.local.theama.co 'sudo -n sha256sum --check --strict -'
```

Extract and run the entrypoint shipped inside that bundle:

```bash
ssh pi@svmf.local.theama.co \
  'sudo -n tar -xzf /root/reconya-v0.26.0-update.tar.gz --no-same-owner --no-same-permissions -C /root/reconya-v0.26.0-bundle'
ssh pi@svmf.local.theama.co \
  'sudo -n /bin/bash /root/reconya-v0.26.0-bundle/deploy-reconya-update.sh /root/reconya-v0.26.0-bundle'
```

Do not substitute a downloaded asset or a controller-side deployment script.
The bundled entrypoint checks the old and new hashes, host identity, service
state, architecture, archive contents, and pre-update health before it stops
the service.

After an accepted update, run the acceptance checks again from the controller:

```bash
ssh pi@svmf.local.theama.co \
  'sha256sum /home/pi/reconya/reconya-linux-arm64'
ssh pi@svmf.local.theama.co \
  'sudo -n systemctl is-active reconya.service && sudo -n systemctl is-enabled reconya.service'
curl -sS -o /dev/null -w 'HTTP %{http_code}\n' \
  http://svmf.local.theama.co:3008/
```

Expected binary SHA-256 after v0.26.0 acceptance:

```text
0f5bdd5c2198f190316595b235f7c2c2fe828632baf320f773bcb5c2f990c4c3
```

No reboot is required. Retain
`/var/backups/reconya/v0.24.1-to-v0.26.0` until the update has been observed
long enough to satisfy the operator's rollback window.

## 9. Managed OUI database updates

ReconYa uses the first three bytes of a MAC address to look up its registered
manufacturer in IEEE's MA-L registry. Keep ReconYa's own outbound lookup paths
disabled when the repository-owned updater manages this file:

```dotenv
OUI_DOWNLOAD_ENABLED=false
VENDOR_LOOKUP_ONLINE_ENABLED=false
```

Set both values in `/home/pi/reconya/.env`. An unset value also resolves to
`false` in v0.26.0, but explicit values preserve the intended policy if an
upstream default changes. ReconYa reads the updater's output from
`/home/pi/reconya/data/oui/oui.txt`; no path setting is required.

The systemd timer runs on the first day of each month, between midnight and
about 06:00 local time. `Persistent=true` runs a missed refresh after the host
returns.

IEEE states that its public listing updates once per 24 hours. Monthly refreshes
avoid needless ReconYa restarts and follow the approximate 30-day age window
used by older ReconYa releases.

The updater:

- downloads the IEEE text registry over HTTPS and permits HTTPS redirects;
- rejects files outside the expected size range, malformed records, fewer than
  30,000 records, and count drops greater than five percent;
- permits IEEE's three reviewed legacy duplicates for `08-00-30` and
  `00-01-C8`, while sending any new duplicate prefix to manual review;
- makes no service change when the downloaded bytes match the installed file;
- retains `oui.txt.previous`, installs through a same-directory rename, and
  restarts ReconYa so it loads the new data; and
- restores the prior file if ReconYa fails its active or HTTP health check.

The IEEE bulk response used here has no signature input for this updater. TLS
and strict structure checks protect transport and catch common truncation or
error pages; they cannot prove registry contents against an independent
signature.

Validate the repository artifacts before deployment:

```bash
/bin/bash Reconya/tests/reconya-oui-update-policy.sh
systemd-analyze verify \
  Reconya/templates/reconya-oui-update.service \
  Reconya/templates/reconya-oui-update.timer
systemd-analyze calendar monthly --iterations=4
```

Build the deterministic deployment bundle from a reviewed seed file. The
preparation script pins the seed SHA-256 and record count:

```bash
/bin/bash Reconya/scripts/prepare-reconya-oui-deployment.sh \
  /ABSOLUTE/PATH/reviewed-oui.txt \
  /tmp/reconya-oui-bootstrap.tar.gz
sha256sum /tmp/reconya-oui-bootstrap.tar.gz
```

Read the [operation specification](operations/install-oui-updater.md). Enabling
the timer grants recurring authority for validated registry replacement and a
ReconYa restart after each changed monthly download. Obtain authorization for
the exact bundle SHA-256 before uploading bytes.

Transfer and verify the authorized bundle:

```bash
ssh pi@svmf.local.theama.co \
  'sudo -n test ! -e /root/reconya-oui-bootstrap'
ssh pi@svmf.local.theama.co \
  'sudo -n test ! -e /root/reconya-oui-bootstrap.tar.gz'
ssh pi@svmf.local.theama.co \
  'sudo -n install -d -m 0700 /root/reconya-oui-bootstrap'
ssh pi@svmf.local.theama.co \
  'sudo -n tee /root/reconya-oui-bootstrap.tar.gz >/dev/null' \
  < /tmp/reconya-oui-bootstrap.tar.gz
printf '%s  %s\n' AUTHORIZED_BUNDLE_SHA256 \
  /root/reconya-oui-bootstrap.tar.gz | \
  ssh pi@svmf.local.theama.co 'sudo -n sha256sum --check --strict -'
```

Extract and run the deployment entrypoint from the verified bundle:

```bash
ssh pi@svmf.local.theama.co \
  'sudo -n tar -xzf /root/reconya-oui-bootstrap.tar.gz --no-same-owner --no-same-permissions -C /root/reconya-oui-bootstrap'
ssh pi@svmf.local.theama.co \
  'sudo -n /bin/bash /root/reconya-oui-bootstrap/deploy-reconya-oui-updater.sh /root/reconya-oui-bootstrap'
```

Verify the accepted installation from the controller:

```bash
ssh pi@svmf.local.theama.co \
  'sudo -n systemctl is-enabled reconya-oui-update.timer && sudo -n systemctl is-active reconya-oui-update.timer'
ssh pi@svmf.local.theama.co \
  'sudo -n systemctl list-timers reconya-oui-update.timer --all'
curl -sS -o /dev/null -w 'HTTP %{http_code}\n' \
  http://svmf.local.theama.co:3008/
```

## 10. Complete environment acceptance

A fresh J1-SVMF installation is reproducible when all of these inputs are
present:

1. the checksum-pinned v0.26.0 ARM64 binary bundle;
2. `configs/svmf.env.example`, with both credential placeholders replaced only
   in the private target copy;
3. `templates/reconya.service`;
4. the managed OUI updater script, units, and reviewed seed bundle; and
5. a restored SQLite snapshot only when recovering an existing environment.

The SQLite database, WAL files, active OUI registry, credentials, and rollback
backups are mutable or secret target state. They belong in the backup system,
not Git. The release-provided `.env.example` may remain beside the binary for
provenance, but it is not the J1-SVMF desired configuration. See
[`configs/README.md`](configs/README.md) for the path-by-path ownership table.

Validate the repository configuration contract:

```bash
/bin/bash Reconya/tests/reconya-environment-config-policy.sh
```

Confirm live immutable artifacts without inspecting `.env` values:

```bash
sha256sum \
  Reconya/templates/reconya.service \
  Reconya/templates/reconya-oui-update.service \
  Reconya/templates/reconya-oui-update.timer \
  Reconya/scripts/update-reconya-oui.sh
ssh pi@svmf.local.theama.co \
  'sudo -n sha256sum /etc/systemd/system/reconya.service /etc/systemd/system/reconya-oui-update.service /etc/systemd/system/reconya-oui-update.timer /usr/local/sbin/update-reconya-oui'
```

On a freshly installed `.env`, list names only and compare them with the
repository template. This does not reveal credential values:

```bash
awk -F= '/^[A-Z][A-Z0-9_]*=/{print $1}' \
  Reconya/configs/svmf.env.example | LC_ALL=C sort
ssh pi@svmf.local.theama.co \
  'sudo -n awk -F= '\''/^[A-Z][A-Z0-9_]*=/{print $1}'\'' /home/pi/reconya/.env | LC_ALL=C sort'
```

An upgraded legacy `.env` can contain the inert keys listed in
`configs/README.md`; remove them only through a separately reviewed
configuration deployment. It may also omit settings whose v0.26.0 defaults
currently match the repository template. Absence is runtime-compatible but is
still configuration drift from the explicit desired state.

For J1-SVMF, use the reviewed
[environment reconciliation operation](operations/reconcile-environment-config.md)
and its bundled deployment entrypoint. The accepted September 2, 2026
reconciliation is recorded in [`HISTORY.md`](HISTORY.md).

## 11. Troubleshooting

### Reboot or shutdown pauses

Check the prior boot for a stop timeout:

```bash
sudo journalctl -b -1 -u reconya.service --no-pager
sudo journalctl -b -1 -g "reconya.service: State 'stop-sigterm' timed out" --no-pager
```

Older units either inherit systemd's 90-second stop timeout or send `SIGTERM`
to a ReconYa release that ignores it. Compare the live unit to the repository
template:

```bash
sudo systemctl show reconya.service \
  -p KillSignal -p TimeoutStopUSec -p FinalKillSignal
sudo systemctl cat reconya.service
/bin/bash Reconya/scripts/check-reconya-service.sh
```

For v0.26.0, the expected policy is `SIGINT`, a 15-second upper bound, then
`SIGKILL`. A controlled restart must log `Received shutdown signal: interrupt`
and `[SUCCESS] Services stopped` without a timeout or forced kill. Repeat the
source audit and stop test after each binary update; a later release may support
the standard `SIGTERM` path.

### Status 203/EXEC or "No such file or directory"

This means `ExecStart` does not identify an executable file at that exact path.
Compare the installed binary with the service:

```bash
find "$HOME/reconya" -maxdepth 1 -type f -name 'reconya-linux-*' -executable -print
sudo systemctl cat reconya.service
```

For example, a Raspberry Pi commonly installs:

```text
/home/pi/reconya/reconya-linux-arm64
```

Using `reconya-linux-amd64` in that service will fail.

After correcting the service:

```bash
sudo systemctl daemon-reload
sudo systemctl restart reconya.service
sudo journalctl -u reconya.service -n 50 --no-pager
```

### Port 3008 is already in use

```bash
sudo ss -ltnp | grep ':3008'
```

Stop the conflicting process or change reconYa's configured port if the
installed release supports that setting.

### `curl -I` returns `405 Method Not Allowed`

The following response does not mean reconYa has failed:

```text
HTTP/1.1 405 Method Not Allowed
```

The `curl -I` option sends a `HEAD` request, and reconYa may not provide a
handler for that HTTP method. Test the application with a normal `GET` request:

```bash
curl -sS -o /dev/null -w 'HTTP %{http_code}\n' http://localhost:3008/
```

An `HTTP 200`, `302`, or `303` response indicates that reconYa is reachable.
You can also verify it by opening `http://SERVER-IP:3008` in a browser.

### Configuration or database permission errors

Because the service runs as root, data created during service operation may be
owned by root. Inspect ownership and logs:

```bash
ls -lha "$HOME/reconya"
ls -lha "$HOME/reconya/data"
sudo journalctl -u reconya.service -n 100 --no-pager
```

### Service repeatedly restarts

Stop the restart loop before troubleshooting:

```bash
sudo systemctl stop reconya.service
sudo journalctl -u reconya.service -n 100 --no-pager
```

Verify the `WorkingDirectory`, `ExecStart`, `.env`, executable permission, and
port availability before starting it again.

## References

- [Dyneteq/reconya repository](https://github.com/Dyneteq/reconya)
- [ReconYa v0.26.0 release](https://github.com/Dyneteq/reconya/releases/tag/v0.26.0)
- [ReconYa v0.26.0 configuration loader](https://github.com/Dyneteq/reconya/blob/v0.26.0/backend/internal/config/config.go)
- [ReconYa v0.26.0 environment example](https://github.com/Dyneteq/reconya/blob/v0.26.0/backend/.env.example)
- [Upstream installer](https://github.com/Dyneteq/reconya/blob/master/install.sh)
