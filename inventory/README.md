# Server inventory

This directory is the source of truth for server membership, configuration
groups, and host-specific configuration differences. The tool-neutral YAML
layout is suitable for shell scripts and other automation to consume.

## Directory structure

```text
inventory/
├── README.md
├── dev/
│   ├── groups/
│   │   └── all.yaml
│   ├── hosts/
│   │   └── .gitkeep
│   └── hosts.yaml
└── prod/
    ├── groups/
    │   ├── all.yaml
    │   ├── dns.yaml
    │   ├── inventory_automation.yaml
    │   ├── monitoring.yaml
    │   ├── notification.yaml
    │   └── reverse_proxy.yaml
    ├── hosts/
    │   ├── j2-svpi4mf.yaml
    │   ├── monitoring.yaml
    │   ├── notification.yaml
    │   ├── pihole0.yaml
    │   └── pihole00.yaml
    └── hosts.yaml
```

Each environment is independent:

- `hosts.yaml` declares hosts, connection names, and group membership.
- `groups/all.yaml` contains non-secret defaults shared by every host in the
  environment.
- Other files under `groups/` contain defaults shared by one host group.
- Files under `hosts/` contain only facts or overrides unique to the named host.

The filename of a host-variable file must match its key in `hosts.yaml`.

## Functions and components

Use `functions` to describe what a host or group does. Examples include `dns`,
`monitoring`, `notification`, and `reverse_proxy`. A host can belong to more
than one functional group; the production Pi-hole pair provides both DNS and
reverse-proxy functions.

Use `components` to list concrete software or configuration bundles deployed
to provide those functions. Examples include `keepalived`, `pihole`, `unbound`,
`caddy`, `lsyncd`, and `mailrise`.

```yaml
functions:
  - dns

components:
  - keepalived
  - pihole
  - unbound
```

Keeping these concepts separate lets automation select hosts by purpose without
mistaking a software package for a server function.

## Host facts

Host-variable files may record stable, non-secret facts needed by automation,
including hardware model and architecture, memory capacity, storage media and
filesystem, and an explicit absence of HA or virtual-IP ownership.

A permanent management address may be recorded as a connection identity only
when an accepted component architecture requires it. Pair it with
`address_authority` to identify the owning repository. Its presence in this
inventory does not transfer address-allocation, DHCP, firewall, or DNS
authority.

## Ownership boundaries

Keep the inventory focused on which servers exist, which functions they perform,
and which configuration differences apply to them.

| Information | Source of truth |
| --- | --- |
| Host membership, functions, components, and OS differences | This inventory |
| VM and infrastructure resource creation | `homelab-terraform` |
| VLANs, subnets, firewall policy, and address allocation | `homelab-network` |
| A, AAAA, PTR, CNAME, and SRV records | `homelab-dns` |
| Portable application configuration | The application or service repository |
| Architecture and deployment diagrams | `homelab-docs` |
| Passwords, tokens, and private keys | The approved secrets manager |

An inventory may contain the DNS name needed to connect to a host. Do not copy
authoritative DNS zones, address-allocation tables, Terraform resources, or
complete service configurations into it.

## Naming conventions

- Use lowercase host keys containing letters, numbers, and hyphens.
- Prefer stable hostnames over IP addresses for `management_fqdn`.
- Use group names that describe a server function, such as `dns`, `monitoring`,
  or `notification`.
- Use lowercase component identifiers that match their software or
  configuration bundle names.
- Use the same host key in automation, documentation, and monitoring labels.
- Put shared values in `groups`; put only exceptions in `hosts`.

## Adding a host

1. Add the host to the appropriate environment's `hosts.yaml`.
2. Add it to every group representing a function it performs.
3. Create `hosts/<hostname>.yaml` only when the host has unique facts or
   overrides.
4. Update the authoritative network, DNS, or Terraform repository when those
   systems also need a change.
5. Validate the YAML before applying configuration.

## Secrets

Do not commit passwords, API keys, tokens, private keys, or secret URLs.
Inventory files may contain non-secret identifiers that automation uses to
look up values from the approved secrets manager.

## Validation

Run the repository checks from the repository root:

```bash
yamllint --strict inventory
pre-commit run --all-files
```
