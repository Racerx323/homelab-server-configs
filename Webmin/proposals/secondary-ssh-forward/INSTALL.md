# Secondary proxy forward to Pi Webmin

Prepare the second proxy to serve the same Caddy upstream, 127.0.0.1:18075.
Its source address is 10.1.0.54. The private key belongs exclusively to the
secondary. On the Pi, authorize that key for a separate account, wmfwdpib.
Reuse the [verified Pi host pin](../primary-ssh-forward/pi.known_hosts).

## Admission

Review readiness on j1-svpihole00 and j2-svpi3bmf using pinned administrative
SSH. Confirm the secondary routes to the Pi from .54, TCP 18075 is free
including wildcard listeners and port reservations, and the proposed service,
credential directory and local wmproxyfwd user/group are available. Confirm
systemd credential support. On the Pi verify its host fingerprint, loopback
Webmin listeners, existing primary account policy and root-owned key-file
identity, SSH unit/config source, and absence of the secondary user, group and
key file. A collision or different source requires review. Never reuse the
primary key or adopt an existing account.

### Administrative connection context

In the pinned IPv4 session as `ama`, capture the peer **before sudo**.
Use the following remote command with the bundled `admin-context.py` as SSH
standard input. Retain its output privately as the admission policy.

```sh
ctx=$(/usr/bin/python3 -I -) && exec sudo -n /usr/sbin/sshd -T -C "$ctx"
```

The helper validates the tuple and emits one argument. The source port is
validated and discarded. This command uses a numeric peer for the SSH
`host` criterion. Verify that the admitted configuration uses numeric peer
matching (default `UseDNS no`) or has no applicable hostname-based Match.
If DNS-based host matching applies, resolve its effective hostname before
using the policy comparison. For the staged and installed comparisons,
capture the same criteria as at admission and pass the quoted argument to
`sshd -T` with the applicable config file. Keep the existing service
invocation/config-source check. Bind this helper with the other installation
inputs when preparing the successor.

## Installation and acceptance

Use the [accepted primary installation sequence](../primary-ssh-forward/INSTALL.md)
with this directory's unit and Match block and the substitutions below.

| Item | Secondary binding |
| --- | --- |
| Proxy administrative connection | pi@10.1.0.54 |
| Pi administrative connection | ama@10.1.3.75 |
| Client system account on the secondary | wmproxyfwd |
| Pi account and authorized-key filename | wmfwdpib |
| Secondary private key | /etc/webmin-forward/secondary-ed25519 |
| Public key comment | webmin-forward-secondary |
| Authorized-key options | `from="10.1.0.54",restrict,port-forwarding,permitopen="127.0.0.1:10000"` |
| Foreground check Host | webmin-j2-svpi3bmf.local.theama.co |

At installation capture fresh boot IDs, repeat admission and hold a Pi
administrative shell through readback. Use a fresh private backup of the
current Pi SSH configuration, which already contains the accepted primary
Match block. Append the secondary block at EOF. Reuse the existing root-owned
Pi key directory. Compare complete staged and installed effective policies
for ama and for wmfwdpi from .53 with their admission copies, and validate
the new user's restrictions from .54. Recheck the existing primary key-file
hash. After reload verify a fresh administrative SSH login and sudo before
enrollment. Generate the new key on the secondary and enroll only its public
key. Verify authenticated shell and off-destination forwarding denials.
Accept the owned secondary loopback listener, one HTTP 200 native login form
through it, active/enabled unit, boot continuity and the Pi loopback baseline.

## Recovery

Stop and disable only the new secondary service. Revoke only its matching
key. Restore the captured Pi configuration on matching installed hash,
validate, reload and verify fresh admin access plus primary policy and key-file
continuity. On drift, preserve the held admin shell and stop for reconciliation.
Remove only newly created secondary files and matching accounts after their
processes exit. Preserve the shared Pi key directory and primary configuration.
Keep a passing installation. Caddy routing, DNS and browser acceptance are
separate steps.
