# Caddy HA quick start

Use this page for routine inspection and first response. The commands are
read-only unless a command explicitly says otherwise. Run node commands on the
named HA node with an account permitted to use the listed inspection command.

## Expected production state

| Item | Node A | Node B |
| --- | --- | --- |
| Host | `j1-svpihole0` | `j1-svpihole00` |
| Role | Preferred owner | Standby |
| IPv4 VRRP | MASTER | BACKUP |
| IPv6 VRRP | MASTER | BACKUP |
| Shared VIP count | 4 | 0 |

The four addresses move together under `PIHOLE_DUALSTACK`:

- DNS: `10.1.0.55` and `fd36:5aa8:6971:1::55`
- Proxy: `10.1.0.56` and `fd36:5aa8:6971:1::56`

## Node status

Run on each node:

```bash
systemctl --no-pager --full status \
  caddy.service keepalived.service caddy-lsyncd.service
systemctl --no-pager --full status \
  caddy-sync-reconcile.path caddy-cert-expiry.timer \
  caddy-sync-health.timer caddy-apprise-worker.path \
  caddy-apprise-worker.timer caddy-pihole-web-health.timer
sudo /usr/local/libexec/validate-sync-health.sh
```

Inspect VRRP state and exact addresses:

```bash
busctl get-property org.keepalived.Vrrp1 \
  /org/keepalived/Vrrp1/Instance/eth0/100/IPv4 \
  org.keepalived.Vrrp1.Instance State
busctl get-property org.keepalived.Vrrp1 \
  /org/keepalived/Vrrp1/Instance/eth0/101/IPv6 \
  org.keepalived.Vrrp1.Instance State
ip -o -4 address show dev eth0
ip -o -6 address show dev eth0
```

Reject split-family ownership, one or three shared VIPs, simultaneous
ownership, or an owner that cannot serve DNS and trusted HTTPS.

## Service checks

Check shared DNS over both families:

```bash
dig +short @10.1.0.55 proxy.local.theama.co A
dig +short @fd36:5aa8:6971:1::55 proxy.local.theama.co AAAA
```

Check shared trusted HTTPS over both families:

```bash
curl --fail --silent --show-error \
  --resolve proxy.local.theama.co:443:10.1.0.56 \
  https://proxy.local.theama.co/
curl --fail --silent --show-error \
  --resolve 'proxy.local.theama.co:443:[fd36:5aa8:6971:1::56]' \
  https://proxy.local.theama.co/
```

Check the shared Pi-hole interface through Caddy and lighttpd:

```bash
curl --fail --silent --show-error --location \
  --resolve pihole-admin.local.theama.co:443:10.1.0.56 \
  https://pihole-admin.local.theama.co/admin/login.php
curl --fail --silent --show-error --location \
  --resolve 'pihole-admin.local.theama.co:443:[fd36:5aa8:6971:1::56]' \
  https://pihole-admin.local.theama.co/admin/login.php
```

Check the node-specific Pi-hole interface without changing shared ownership:

```bash
curl --fail --silent --show-error \
  --resolve pihole0.local.theama.co:443:10.1.0.53 \
  https://pihole0.local.theama.co/healthz
curl --fail --silent --show-error \
  --resolve pihole00.local.theama.co:443:10.1.0.54 \
  https://pihole00.local.theama.co/healthz
```

## Notification queue

```bash
systemctl --no-pager --full status \
  caddy-apprise-worker.path caddy-apprise-worker.timer
journalctl -t caddy-apprise-queue -t caddy-apprise-worker \
  --since today --no-pager
find /var/lib/caddy-apprise-queue -maxdepth 2 -type f \
  -printf '%M %u:%g %p\n'
df -h /var/lib/caddy-apprise-queue
```

Do not edit queue records. Follow
[`APPRISE_DELIVERY.md`](APPRISE_DELIVERY.md) for retry and dead-letter rules.

## Repository validation

From `homelab-server-configs`:

```bash
Caddy/tests/run-focused.sh \
  --profile current-repository-policies --phase host --container never
Caddy/tests/run-focused.sh \
  --profile current-synchronization --phase host --container never
Caddy/tests/run-focused.sh \
  --profile current-serving-health --phase host --container never
Caddy/tests/deployable-successor-policy.sh --check
```

Repository checks do not prove live node state. Compare live observations with
the accepted identities in `Caddy/manifests/accepted-live-artifacts.tsv` and
`Caddy/manifests/current-live-state.tsv`.

## First response

Start with [`TROUBLESHOOTING.md`](TROUBLESHOOTING.md) when any expected state or
endpoint differs. Do not restart both nodes, move VIPs, publish a release, or
alter a queue record during first response.
