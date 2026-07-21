# Needrestart notifications

`needrestart.sh` runs a noninteractive Debian `needrestart` scan and reports
obsolete kernels, services, and user sessions. It sends actionable alerts through
a sendmail-compatible local mail transfer agent (MTA). The accompanying
`needrestart_check` file runs the script daily from `/etc/cron.d` and retains
stdout and stderr for cron as a second reporting path.

## Requirements

- Debian 12
- Root access
- `needrestart`
- `cron` for scheduled execution
- `coreutils` for the bounded `timeout` command
- `util-linux` for `flock`
- A sendmail-compatible MTA; the examples below use `msmtp-mta`
- A working notification destination

Install the Debian packages:

```bash
sudo apt update
sudo apt install needrestart cron coreutils msmtp msmtp-mta ca-certificates util-linux
sudo systemctl enable --now cron
systemctl is-active cron
```

Confirm that the sendmail compatibility path resolves to msmtp:

```bash
readlink -f /usr/sbin/sendmail
msmtp --version
```

Configure the relay before installing the cron job. See
[Configure msmtp for Mailrise](msmtp-mailrise.md).

## Configure the cron job

Edit `scripts/needrestart_check` and set both addresses to a recipient supported
by the configured MTA:

```cron
MAILTO=recipient@example.com
RECIPIENT=recipient@example.com
```

`RECIPIENT` receives direct alerts from `needrestart.sh`. `MAILTO` receives the
script's stdout and stderr from cron. These are separate reporting paths, but
both use the same sendmail-compatible MTA and are not independent delivery
channels.

The supplied schedule runs daily at 05:30. Change its five time fields if a
different schedule is required. Keep the `root` user field when installing the
file under `/etc/cron.d`.

## Install

From the repository root:

```bash
sudo install -o root -g root -m 755 \
  Needrestart/scripts/needrestart.sh \
  /usr/local/sbin/needrestart.sh

sudo install -o root -g root -m 644 \
  Needrestart/scripts/needrestart_check \
  /etc/cron.d/needrestart_check
```

Files under `/etc/cron.d` must be owned by root and must not be group- or
world-writable. They do not need to be executable.

Raspberry Pi 5 hosts may also require a kernel-image filter to prevent false
upgrade reports. Follow [Configure the Raspberry Pi kernel filter](kernel-filter.md)
before installing the supplied host-specific configuration.

## Test delivery

Complete the transport-specific connectivity and delivery tests before relying
on the scheduled job. For the LAN Mailrise configuration, follow
[Configure msmtp for Mailrise](msmtp-mailrise.md#test-mailrise-delivery).

### Test `needrestart.sh` notification output

Use `--test-notification` (or `-t`) to send a representative notification when
the host has no real restart condition:

```bash
sudo env RECIPIENT=recipient@example.com \
  /usr/local/sbin/needrestart.sh --test-notification
```

Replace `recipient@example.com` with a real address accepted by the configured
MTA. This command sends a real message through `/usr/sbin/sendmail`, but the
subject begins with `[TEST]` and the body states that no action is required. It
includes synthetic kernel, service, and session entries to exercise multiline
formatting. The displayed delivery path ends with `Mailrise -> Apprise` when the
recipient domain is `mailrise.xyz`; other domains are shown as the destination
email host. The path identifies the sending device with `SYSTEM_ID` immediately
after `needrestart.sh`. Domain matching is case-insensitive. Test mode validates
the hostname, recipient, and sendmail path, then exits without running
`/usr/sbin/needrestart`.

Show command usage without requiring root, mail configuration, or installed
dependencies:

```bash
/usr/local/sbin/needrestart.sh --help
```

Run the script manually with the cron recipient:

```bash
sudo env RECIPIENT=recipient@example.com \
  /usr/local/sbin/needrestart.sh
```

## Runtime behavior

The script:

1. Determines the host name and sender address.
2. Validates `RECIPIENT`, `/usr/sbin/sendmail`, and `/usr/sbin/needrestart`.
3. Verifies that real scans run as root.
4. Runs `/usr/sbin/needrestart -bkl` in batch mode with a five-minute timeout.
   A process that ignores graceful termination is killed after another 30 seconds.
5. Parses kernel, service, and session results.
6. Sends a direct notification when attention is required.

Configuration and scan failures are written in full to stderr for cron capture.
When direct delivery is possible, the script also sends a failure notification.
Direct failure emails are capped at 12,000 characters; cron captures the
complete report. Direct and cron-generated messages share the configured MTA.

Exit statuses:

- `0`: scan completed and any required notification was submitted successfully
- `1`: notification submission failed
- `2`: required configuration or executable is unavailable, or an option is invalid
- `124`: the scan exceeded five minutes and was terminated
- `137`: the timed-out scan ignored graceful termination and was killed
- Other nonzero values: the original `needrestart` scan failure status

## Troubleshooting

Check the relevant services and paths:

```bash
test -x /usr/sbin/sendmail
test -x /usr/sbin/needrestart
sudo /usr/sbin/needrestart -bkl
```

Cron reads `needrestart_check` independently of `/etc/crontab`; environment
variables in `/etc/crontab` are not inherited. Keep `MAILTO`, `RECIPIENT`, and
`SHELL` in the installed file.
