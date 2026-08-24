# Caddy HA troubleshooting

Inspect before changing state. Capture a journal cursor before any authorized
service command, change one node at a time, and preserve bounded evidence.

## First checks

Run the read-only checks in [`QUICK_START.md`](QUICK_START.md). Record:

- Node A and Node B VRRP state and shared VIP count;
- IPv4 and IPv6 DNS results;
- IPv4 and IPv6 trusted HTTPS results;
- service, path, and timer state;
- selected immutable release and accepted-live identity;
- managed-lsyncd status and protocol-v2 inventories; and
- notification queue counts and filesystem capacity.

Do not use notification text as the sole source of service or ownership state.

## Caddy

```bash
systemctl --no-pager --full status caddy.service
journalctl -u caddy.service --since today --no-pager
ss -lntup
readlink -f /etc/caddy/current
```

Use `caddy validate` only with the protected installed environment and active
release paths. Do not edit `/etc/caddy/current` or an immutable release. A
Caddy failure can make the coupled node ineligible and move all four VIPs.

## DNS and Unbound

```bash
systemctl --no-pager --full status pihole-FTL.service unbound.service
journalctl -u pihole-FTL.service -u unbound.service \
  --since today --no-pager
dig +short @127.0.0.1 proxy.local.theama.co A
sudo unbound-checkconf
```

Pi-hole FTL belongs to the Pi-hole application. The resolver requires both
`pihole.conf` and `pihole-local-zone.conf`. A sustained DNS check failure can
move all four VIPs.

## lighttpd and Pi-hole web

```bash
systemctl --no-pager --full status \
  lighttpd.service caddy-pihole-web-health.timer
journalctl -u caddy-pihole-web-health.service \
  --since today --no-pager
ss -lntp | grep -F '127.0.0.1:8080'
```

The Pi-hole web monitor is notification-only. Its failure must not change VRRP
ownership. Check both Caddy and lighttpd when the monitor reports a Proxy
backend failure.

## Keepalived and ownership

```bash
systemctl --no-pager --full status keepalived.service
journalctl -u keepalived.service -t keepalived-notify \
  --since today --no-pager
ip -o -4 address show dev eth0
ip -o -6 address show dev eth0
```

The installed Keepalived parser mode is not a valid acceptance prerequisite in
this environment. Use exact repository identity, standby-first service control,
daemon-observed tracking results, settled VRRP state, and endpoint continuity.

## lsyncd and protocol v2

```bash
sudo /usr/local/libexec/validate-sync-health.sh
systemctl --no-pager --full status \
  caddy-lsyncd.service caddy-sync-reconcile.path
journalctl -u caddy-lsyncd.service \
  -u caddy-sync-reconcile.service --since today --no-pager
find /var/lib/caddy-sync/incoming \
  /var/lib/caddy-sync/outbound \
  /var/lib/caddy-sync/quarantine -mindepth 1 -maxdepth 2 -print
```

Do not delete, rename, finalize, or replay an entry during diagnosis. Classify
the exact source role, revision, manifest, markers, ownership, modes, references,
and active-release relationship before proposing disposition.

## Reconciler and status 125

The reconciler validates candidates, activates one release, reloads Caddy, and
restores the previous selection on reload failure. Inspect the cursor-bounded
`caddy-sync-reconcile.service` journal and active symlink together.

Status 125 means a mutation occurred and recovery could not be proven. Stop the
transaction. Preserve node evidence, workstation evidence, active and previous
release identities, and protocol-v2 state.

## TLS

```bash
systemctl --no-pager --full status caddy-cert-expiry.timer
journalctl -u caddy-cert-expiry.service --since today --no-pager
openssl x509 -in /etc/caddy/current/tls/leaf.pem \
  -noout -subject -issuer -dates -fingerprint -sha256
```

Check certificate names, dates, chain, private-key match, file ownership, and
the immutable release manifest. Never print private-key bytes.

## Durable notification delivery

```bash
systemctl --no-pager --full status \
  caddy-apprise-worker.path caddy-apprise-worker.timer
journalctl -t caddy-apprise-queue -t caddy-apprise-worker \
  --since today --no-pager
find /var/lib/caddy-apprise-queue -maxdepth 2 -type f \
  -printf '%M %u:%g %p\n'
df -h /var/lib/caddy-apprise-queue
```

Delivery failure does not change serving health. Resolve the transport cause,
then start the worker through the supported systemd unit. Do not edit, replay,
or purge a record manually. See [`APPRISE_DELIVERY.md`](APPRISE_DELIVERY.md).

## Timer or service identity failures

For `226/NAMESPACE`, inspect the unit's protected paths and required runtime
directories. For permission failures, compare `User`, `Group`,
`SupplementaryGroups`, file ownership, and modes with the accepted systemd and
artifact manifests. Do not loosen protected environment or TLS permissions as
a shortcut.

## Escalation evidence

Retain only bounded, relevant output:

- exact command and status;
- node, UTC time, and fresh journal cursor;
- expected and observed service or ownership state;
- endpoint and address family;
- installed and accepted-live hashes; and
- sanitized journal and filesystem evidence.

Exclude secrets, environment dumps, private keys, binary data, complete HTTP
responses, and unbounded journals.
