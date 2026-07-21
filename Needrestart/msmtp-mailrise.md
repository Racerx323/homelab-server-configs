# Configure msmtp for Mailrise

This configuration routes the sendmail-compatible output from
`needrestart.sh` and cron through msmtp to a LAN Mailrise service.

The following system-wide `/etc/msmtprc` account connects without
authentication or TLS:

```ini
defaults
aliases /etc/aliases

account apprise
host mailrise.local.theama.co
port 8025
from %H@local.theama.co
domain %H
set_from_header on
allow_from_override off
auth off
tls off

account default: apprise
```

Use `auth off` and `tls off` only on a trusted LAN. Restrict TCP port `8025` on
the Mailrise host to trusted source networks. If another msmtp account must
remain the system default, account selection for both the script and cron mail
needs a separate design; both currently use `/usr/sbin/sendmail` and therefore
the default msmtp account.

Create or update the system-wide configuration without embedding credentials:

```bash
sudoedit /etc/msmtprc
sudo chown root:root /etc/msmtprc
sudo chmod 600 /etc/msmtprc
```

Mailrise routes messages by the recipient local part. For example, this
Mailrise configuration defines `notify@mailrise.xyz`:

```yaml
configs:
  notify:
    urls:
      - apprise://apprise-api:8000/YOUR_APPRISE_CONFIG_KEY
```

Restart Mailrise after changing its configuration:

```bash
sudo systemctl restart mailrise
sudo journalctl -u mailrise -f
```

## Test Mailrise delivery

Netcat (`nc`, provided by `netcat-openbsd`) is used only to verify TCP
connectivity to the Mailrise SMTP port during setup and troubleshooting. It is
not used by `needrestart.sh` during normal operation.

Install Netcat if it is not already available:

```bash
sudo apt install netcat-openbsd
```

Verify that msmtp can parse the Mailrise account without sending a message:

```bash
sudo msmtp --pretend --account=apprise notify@mailrise.xyz </dev/null
```

Verify DNS and SMTP connectivity:

`getent` confirms that the Mailrise hostname resolves. Netcat then attempts a
TCP connection to port `8025`; a successful result confirms that the SMTP port
is reachable, but it does not send a message or validate Mailrise routing.

```bash
getent hosts mailrise.local.theama.co
nc -vz mailrise.local.theama.co 8025
```

Send an end-to-end message through the same sendmail-compatible interface used
by `needrestart.sh` and cron:

```bash
printf 'From: needrestart-test@local.theama.co\nTo: notify@mailrise.xyz\nSubject: Needrestart Mailrise test\n\nMailrise delivery is working.\n' \
  | sudo /usr/sbin/sendmail -t
```

Confirm that the downstream Apprise notification arrives. If Mailrise reports
that the recipient is not configured, confirm that `notify` exists under
`configs` in `mailrise.conf`, then restart Mailrise.

Inspect Mailrise logs while testing:

```bash
sudo journalctl -u mailrise -f
```

## Test an external Mailgun account

Use an explicitly selected `mailgun` account to test delivery to an external
email service without changing the default `apprise` account. The account must
already be configured with valid Mailgun credentials. Do not store the password
directly in `/etc/msmtprc`; place it in a root-owned mode `0600` file and use an
msmtp `passwordeval` directive to read it. Keep `/etc/msmtprc` root-owned and
mode `0600` as well because this workflow runs as root.

First verify account selection and configuration without sending:

```bash
sudo msmtp --pretend --account=mailgun you@your-real-domain.example </dev/null
```

For a live test, replace `you@your-real-domain.example` with an external address
you control. The `.example` address is intentionally non-deliverable and must
not be used unchanged.

### Option 1: invoke msmtp directly

```bash
recipient='you@your-real-domain.example'
printf 'To: %s\nSubject: Needrestart Mailgun test\n\nExternal Mailgun delivery is working.\n' "$recipient" \
  | sudo /usr/bin/msmtp --account=mailgun "$recipient"
```

This test invokes the `mailgun` account directly, so it does not exercise
`/usr/sbin/sendmail` or the default Mailrise route. Confirm receipt at the
external mailbox and inspect the msmtp output or system logs if delivery fails.

### Option 2: use the sendmail-compatible interface

First confirm that `/usr/sbin/sendmail` resolves to msmtp. The
`--account=mailgun` option is specific to msmtp and may not be supported by a
different sendmail-compatible MTA.

```bash
readlink -f /usr/sbin/sendmail
```

Then submit the message through the interface used by `needrestart.sh`, while
explicitly selecting the `mailgun` account instead of the default `apprise`
account:

```bash
SYSTEM_ID=$(hostname -f 2>/dev/null || hostname)
recipient='you@your-real-domain.example'
printf 'To: %s\nSubject: Needrestart sendmail to Mailgun test from %s\n\nSystem ID: %s\nThe sendmail to msmtp to Mailgun path is working.\n' \
  "$recipient" "$SYSTEM_ID" "$SYSTEM_ID" \
  | sudo /usr/sbin/sendmail --account=mailgun -t
```

This verifies the path:

```text
sendmail (SYSTEM_ID) -> msmtp -> Mailgun (external email host)
```

`SYSTEM_ID` is replaced at runtime with the sending device's fully qualified
hostname, falling back to its short hostname when necessary.

Explicit account selection leaves the default Mailrise route unchanged. Confirm
receipt at the external mailbox before relying on this path.
