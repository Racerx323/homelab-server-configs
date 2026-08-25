# Nautobot deployment plan

## Status and authorization boundary

This document is the governing definition for deploying Nautobot on
`j2-svpi4mf`. It records the accepted architecture, implementation stages,
ownership boundaries, validation, and acceptance criteria.

Creating this plan does not authorize host mutation, package installation,
network or DNS changes, UniFi changes, Caddy publication, container startup,
secrets creation, source-of-truth migration, or production acceptance. Each
live stage requires separately reviewed inputs and scoped authorization.

## Accepted target

| Property | Accepted value |
| --- | --- |
| Host | `j2-svpi4mf` |
| SSH administration | `ama@10.1.2.170` |
| Ethernet MAC | `dc:a6:32:eb:49:69` |
| IPv4 | UniFi fixed DHCP assignment `10.1.2.170/22` |
| Permanent IPv6 ULA | `fd36:5aa8:6971:1::170/64` |
| Host FQDN | `j2-svpi4mf.local.theama.co` |
| Application FQDN | `nautobot.local.theama.co` |
| Platform | Raspberry Pi 4B, four ARM64 cores, 8 GB RAM |
| Power | PoE Texas `GAT-PiHAT`, IEEE 802.3at, rated up to 20 W |
| Storage adapter | Geekworm `X872 V2.0`, USB 3.0 to M.2 NVMe, up to 5 Gbps |
| Storage | 1 TB NVMe over USB 3 UAS, ext4 root filesystem |
| Container runtime | Rootless Podman with user Quadlets |

Before defining the host-baseline operation, a fresh read-only qualification
must prove that the hardware, storage, temperature, current load, cgroup-v2
support, and 64-bit Debian installation remain sufficient for a small homelab
deployment. Preserve the bounded qualification evidence outside this
architecture plan and bind its sanitized evidence manifest to the operation.
ARM64 remains a pilot risk because Nautobot publishes ARM64 images but does not
cover that architecture in its automated tests.

The storage diagnostic must treat both the power and transport paths as
possible contributors to a USB/UAS reset. Verify the negotiated PoE supply,
Raspberry Pi throttling history, USB link speed, bridge identity, UAS driver,
and NVMe health from the live host rather than inferring them from product
names. Manufacturer references: [PoE Texas GAT-PiHAT][gat-pihat] and
[Geekworm X872 V2.0][x872-v2].

Pin these initial application versions:

- Nautobot `3.2.3` using the upstream `3.2.3-py3.12` ARM64 image variant;
- Nautobot DNS Models `2.3.0`;
- PostgreSQL `17`;
- Redis `7.4`; and
- Semaphore UI `2.18.29` only after the Nautobot acceptance and soak gates.

Resolve and record architecture-specific image digests before implementation.
Do not deploy mutable tags such as `latest`.

## Ownership model

During bootstrap, the existing repositories retain authority:

| Information | Bootstrap authority |
| --- | --- |
| Host membership, functions, components, and OS facts | `homelab-server-configs/inventory` |
| VLANs, prefixes, addresses, DHCP, firewall, and NAT | `homelab-network` |
| A, AAAA, PTR, CNAME, and SRV records | `homelab-dns` |
| Caddy configuration and release lifecycle | `homelab-server-configs/Caddy` |
| Passwords, tokens, application keys, and private keys | Approved secrets system |

After Nautobot passes backup and restore acceptance, migrate authority one
domain at a time. A repository becomes a generated or reconciled projection
only after an exact comparison, reviewed cutover, and explicit ownership
update. Caddy configuration bytes, protocol-v2 candidates, accepted-live
evidence, and live authorization remain repository-owned.

Nautobot events and webhooks may request export or validation. They must never
publish a release, reload DNS, contact an HA node, or initiate a live change.

## Host baseline

### Service identity and rootless runtime

- Preserve `ama` as the SSH administration identity.
- Create a non-login `nautobot` service account with home
  `/var/lib/nautobot`.
- Assign the non-overlapping subordinate UID and GID range
  `165536:65536`, after proving that range is unused.
- Enable systemd lingering only for the `nautobot` service account.
- Store rootless Quadlets beneath
  `/var/lib/nautobot/.config/containers/systemd/`.
- Store persistent container data on the SSD beneath the service account's
  rootless Podman storage.

Install the reviewed Debian packages for `podman`, `uidmap`, `passt`,
`slirp4netns`, `fuse-overlayfs`, `crun`, `dbus-user-session`, `smartmontools`,
`restic`, `msmtp`, and `msmtp-mta`. Record exact installed versions. The two
MSMTP packages provide a sendmail-compatible outbound transport for host
software; relay configuration and credentials require separate review and
must remain outside Git.

### Required and unwanted services

Preserve and validate these required host-baseline services:

- SSH;
- NetworkManager;
- systemd-timesyncd;
- Munin Node;
- Webmin; and
- watchdog.

`homelab-dns` owns Keepalived removal. Its separately authorized process must
purge the package and `/etc/keepalived` after an APT dry run proves the removal
set. The Nautobot host-baseline operation must fail before mutation unless the
package, unit, process, and configuration directory are absent. This host has
no VIP or HA ownership role.

Disable and mask:

- `avahi-daemon.service` and `avahi-daemon.socket`;
- `bluetooth.service`; and
- `ModemManager.service`.

Do not purge Avahi, Bluetooth, or ModemManager packages unless a later APT dry
run proves NetworkManager, Raspberry Pi, and USB-gadget dependencies remain
intact.

Restrict Webmin, Munin, SSH, and the Nautobot backend through authoritative
UniFi firewall policy. A wildcard listener must not become reachable through
the host's ISP-delegated global IPv6 address.

Install SMART monitoring and test the JMicron USB bridge with the applicable
SAT/UAS device type. If the bridge cannot pass SMART commands, record the
limitation and compensate with kernel I/O monitoring and verified off-host
backups.

## Dual-stack network and DNS

Preserve the existing NetworkManager profile behavior:

- `Wired connection 1` remains bound to `eth0` and autoconnects;
- `ipv4.method` remains `auto`;
- UniFi continues fixing `10.1.2.170` to MAC `dc:a6:32:eb:49:69`;
- `ipv6.method` remains `auto`;
- router advertisements continue supplying the IPv6 default route, SLAAC ULA,
  and ISP-delegated global address; and
- `fd36:5aa8:6971:1::170/64` is added as the permanent host ULA.

Do not publish the temporary SLAAC ULA or ISP-delegated global address as the
host's stable identity.

Define `homelab-network/Ubiquiti/j2-svpi4mf-ip-configuration.md` in the
separately authorized network stage. It must include pre-change evidence, a
non-autoconnecting cloned NetworkManager rollback profile, exact change and
recovery commands, address and route validation, and the UniFi fixed-lease
boundary.

The separately authorized DNS stage adds:

| Type | Owner/name | Value |
| --- | --- | --- |
| A | `j2-svpi4mf.local.theama.co.` | `10.1.2.170` |
| AAAA | `j2-svpi4mf.local.theama.co.` | `fd36:5aa8:6971:1::170` |
| PTR | `10.1.2.170` | `j2-svpi4mf.local.theama.co.` |
| PTR | `fd36:5aa8:6971:1::170` | `j2-svpi4mf.local.theama.co.` |

Validate exact forward and reverse results through both Pi-hole nodes and both
shared DNS VIP address families before accepting the host identity.

## Nautobot runtime

Build one custom ARM64 image from the pinned Nautobot base. Install the pinned
DNS Models package and a hash-locked Python dependency set during the image
build. A later `nautobot-homelab-intent` app requires its own schema and review
before inclusion.

Create one private Podman network and these Quadlet-managed services:

- PostgreSQL with no host-published port and a dedicated volume;
- Redis with no host-published port, authentication, persistence appropriate
  for the task queue, and a bounded memory policy;
- Nautobot web;
- one Celery worker with concurrency `2`;
- one Celery Beat scheduler; and
- a one-shot migration unit that runs `nautobot-server post_upgrade` before
  web, worker, or scheduler startup.

Use these initial memory ceilings:

| Service | Limit |
| --- | ---: |
| Nautobot web | 1536 MiB |
| Celery worker | 1536 MiB |
| Celery scheduler | 384 MiB |
| PostgreSQL | 1536 MiB |
| Redis | 512 MiB |

Change a ceiling only from recorded pilot evidence. Leave the remaining memory
for Debian, Podman, baseline services, filesystem cache, migrations, and
upgrades.

Bind the web backend only to `10.1.2.170:8080`,
`[fd36:5aa8:6971:1::170]:8080`, and loopback where required for recovery.
Permit TCP 8080 only from `pihole0` and `pihole00` over their exact IPv4 and
permanent ULA addresses. PostgreSQL and Redis remain private to the Podman
network.

Configure:

- `ALLOWED_HOSTS` for `nautobot.local.theama.co` and the approved recovery
  identity;
- the trusted HTTPS origin for `https://nautobot.local.theama.co`;
- the secure proxy header for Caddy's `X-Forwarded-Proto: https`; and
- Nautobot as the authentication owner, without a second Caddy authentication
  layer.

Store the Django secret key, database password, Redis password, initial
administrator credential, Restic repository password, and Backblaze
credentials in the approved secrets system. Inject values through protected
Podman secrets or credential files; never commit secret values.

## Caddy application onboarding

Use an SSH tunnel for bootstrap administration. Direct LAN browser access is
not an accepted steady-state interface.

Onboard `nautobot.local.theama.co` through the existing application and
protocol-v2 lifecycle with this contract:

| Field | Accepted value |
| --- | --- |
| Fragment | `20-nautobot.caddy` |
| Public A | `10.1.0.56` |
| Public AAAA | `fd36:5aa8:6971:1::56` |
| Allowed clients | `10.1.0.0/22 fd36:5aa8:6971:1::/64` |
| Backend protocol | HTTP; Caddy terminates TLS |
| Upstreams | `10.1.2.170:8080 [fd36:5aa8:6971:1::170]:8080` |
| Load-balancing policy | `first` |
| Host header | `nautobot.local.theama.co` |
| Authentication owner | Nautobot |

The two upstreams are network paths to one application instance. They do not
constitute application HA.

Use this health and transport contract:

| Field | Accepted value |
| --- | --- |
| Active method and URI | `GET /health/` |
| Expected status | `200` |
| Interval / timeout | `30s` / `5s` |
| Passes / failures | `2` / `3` |
| Passive window / maximum failures | `30s` / `2` |
| Unhealthy status | `5xx` |
| Dial timeout | `3s` |
| Response-header timeout | `10s` |

The route uses HTTP backend comments in place of TLS directives. Application
DNS receives only the Proxy VIP A and AAAA records. It receives no PTR; the
Proxy VIP PTR targets remain exclusively `proxy.local.theama.co.`.

DNS changes, the Caddy fragment, immutable release creation, publication,
acceptance, and rollback remain separate authorizations. No inventory event,
webhook, or scheduled task may invoke them automatically.

## Inventory and authority migration

During the separately authorized repository implementation stage:

- add `j2-svpi4mf` to `inventory/prod/hosts.yaml`;
- add an `inventory_automation` group with functions `inventory` and
  `automation`;
- record `podman`, `nautobot`, `postgresql`, `redis`, `restic`, `munin-node`,
  `webmin`, and `watchdog` as components;
- add `semaphore` only after its deployment is accepted; and
- record the Raspberry Pi hardware, SSD storage, management FQDN, permanent
  ULA, and absence of an HA role.

After platform acceptance, migrate authority in this order:

1. Host membership, functions, components, and OS facts.
2. Prefixes, IP addresses, and allocation intent.
3. DNS zones and records through DNS Models.
4. Applications, upstreams, health contracts, authentication ownership, and
   TLS trust references through the reviewed homelab intent app.
5. Versioned adapter exports for the future Caddy fragment generator.

Each cutover requires an exact repository comparison, resolution of every
difference, approval of a specific Nautobot revision, deterministic export,
and an explicit ownership-document update.

## Semaphore boundary

After seven accepted days of Nautobot-only operation, define Semaphore UI as a
separate deployment stage. Use version `2.18.29`, a pinned ARM64 artifact or
image digest, a separate database and database user, and the Nautobot Ansible
inventory plugin.

Semaphore may launch bounded inventory checks, proposal generation, validation,
and separately authorized Ansible tasks. It must not turn an inventory event,
webhook, or schedule into a live Caddy, DNS, network, or HA-node change.

## Backups and recovery

Use Restic with a dedicated private Backblaze B2 bucket through its
S3-compatible endpoint. Use a bucket-scoped application key with only the
list, read, write, and delete capabilities required by Restic. Do not use the
Backblaze master key.

Each backup contains:

- a PostgreSQL custom-format logical dump;
- Nautobot media and required configuration artifacts;
- custom-image and Python dependency manifests;
- Quadlet and application configuration hashes; and
- installed Nautobot/App versions and migration state.

Run nightly backups and retain 7 daily, 5 weekly, and 12 monthly snapshots.
Run `restic check` weekly and perform a monthly isolated restore test.

Nautobot must not become authoritative until the exact B2 bucket, endpoint,
scoped application key, repository-password recovery location, successful
upload, integrity check, and clean isolated restore are recorded.

## Validation and acceptance

Host acceptance requires:

- zero failed systemd units;
- required baseline services active and unwanted services absent;
- rootless services surviving logout and reboot;
- no host-published PostgreSQL or Redis ports;
- SMART health recorded or an explicit USB-bridge limitation documented;
- no firmware throttling, OOM events, persistent swap growth, or sustained
  temperature above 80 degrees Celsius; and
- at least 1.5 GiB memory available during representative imports, exports,
  backups, and Jobs.

Network and application acceptance requires:

- exact A, AAAA, and PTR results for the host;
- SSH reachability over IPv4 and the permanent ULA;
- preservation of the SLAAC ULA, global IPv6 address, and IPv6 default route;
- `/health/` returning `200` through both backend address families;
- trusted HTTPS through both public Proxy VIP address families;
- denied clients receiving `403` and unknown hostnames retaining `421`; and
- no unintended direct access to the backend, database, Redis, Webmin, or
  Munin through the global IPv6 address.

Data and recovery acceptance requires:

- deterministic inventory and DNS exports with no unexplained drift;
- all secrets absent from Git and bounded evidence;
- successful Backblaze upload, Restic integrity check, and isolated full
  restore; and
- seven days of stable pilot operation before authority migration or Semaphore
  installation.

## Execution stages

1. **Repository plan:** this document only.
2. **Repository implementation:** reviewed Containerfile, Quadlets, templates,
   validators, tests, backup tooling, manifests, and proposed cross-repository
   definitions; no live contact.
3. **Host baseline:** package installation, service cleanup, SMART validation,
   service account, rootless Podman, and firewall prerequisites.
4. **Dual-stack identity:** permanent ULA, host DNS, forward/reverse validation,
   and rollback proof.
5. **Nautobot pilot:** pinned image build, secrets, data services, application
   startup, monitoring, backup, restore, and resource testing.
6. **Caddy onboarding:** reviewed DNS intent, route, immutable release, and
   separately authorized production publication.
7. **Authority migration:** one data domain at a time after reconciliation.
8. **Semaphore:** separately accepted after the Nautobot soak period.

Do not combine these stages into one authorization. Before every live stage,
collect a read-only baseline, present the exact inputs and hashes, state the
rollback boundary, and obtain scoped authorization.

## References

- `inventory/README.md`
- `Caddy/docs/APPLICATION_ONBOARDING.md`
- `Caddy/docs/caddy_plan-v1.1.md`
- `Caddy/docs/FUTURE_REVERSE_PROXY_GENERATOR_PROMPT.md`
- `../../../homelab-network/Ubiquiti/udm-se-ipv6-ula-configuration.md`
- `../../../homelab-network/Ubiquiti/pihole0-ip-configuration.md`
- <https://docs.nautobot.com/projects/core/en/stable/>
- <https://docs.nautobot.com/projects/dns-models/en/stable/>
- <https://docs.podman.io/en/latest/markdown/podman-systemd.unit.5.html>
- <https://www.backblaze.com/docs/cloud-storage-integrate-restic-with-backblaze-b2>

[gat-pihat]: https://shop.poetexas.com/products/gat-pihat
[x872-v2]: https://geekworm.com/products/x872-v2
