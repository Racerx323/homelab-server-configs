# Caddy project handoff, version 1

This document is the restart-safe entry point for a follow-on Caddy project.
It identifies the repositories, current authorities, accepted production
snapshot, operating boundaries, and validation commands needed before work
begins.

The current architecture and authorization authority is
[`caddy_plan-v1.1.md`](caddy_plan-v1.1.md). The Caddy operation-window rules
are in [`DEPLOYMENT_LIFECYCLE.md`](DEPLOYMENT_LIFECYCLE.md).

## Versioned snapshot

Update this block in one reviewed repository checkpoint when a referenced
repository baseline, accepted production identity, archive boundary, or major
handoff contract changes. The primary repository baseline is the commit read
to create this document. A Git commit cannot include its own final identity.

```yaml
schema: caddy-project-handoff/v1
document_version: 1.0.0
snapshot_date: "2026-09-14"
primary_repository:
  path: /home/aaron/code/homelab-server-configs
  remote: https://github.com/Racerx323/homelab-server-configs.git
  branch: main
  source_baseline: e99c1dd0c3398e01e3c99ed4d3650f8b912ad73d
related_repositories:
  homelab_dns:
    path: /home/aaron/code/homelab-dns
    remote: https://github.com/Racerx323/homelab-dns.git
    baseline: f33b24e70fe886d5975e19ce58bf3e7e907a9be3
  homelab_docs:
    path: /home/aaron/code/homelab-docs
    remote: https://github.com/Racerx323/homelab-docs.git
    baseline: c9b55d307f24884f1a739dfcb4c9ba9d2ac1ee4c
  homelab_network:
    path: /home/aaron/code/homelab-network
    remote: https://github.com/Racerx323/homelab-network.git
    baseline: 3a29c4ffeca0802191815acfffb1fcf2d67a3d4a
  homelab_notification:
    path: /home/aaron/code/homelab-notification
    remote: https://github.com/Racerx323/homelab-notification.git
    baseline: 8d5b718efe4f73aa7e594f460267c3af70dec8fa
accepted_production:
  archive_tag: caddy-action35as-terminal-2026-08-24
  payload_manifest_sha256: 2253a491e048c9d670865e3d39efa3c9e9acd92a31ec33219f97ba91428b0133
  stream_state: clean
  successor_state: none
current_planned_repository_project:
  prompt: Caddy/docs/FUTURE_REVERSE_PROXY_GENERATOR_PROMPT.md
  authorization: definition-only
```

The baselines record repository state, not a permanent pin. Fetch each
repository and compare its current `HEAD` with `origin/main` before using the
snapshot. Repository manifests describe the last accepted production state;
they do not prove that production has remained unchanged since capture.

## Follow-on project prompt

Copy the text below into a new task and replace `FOLLOW_ON_OBJECTIVE` with the
approved objective.

```text
Resume work on the accepted HA Caddy and DNS platform.

Objective:
FOLLOW_ON_OBJECTIVE

Workspace root:
/home/aaron/code

Primary repository:
/home/aaron/code/homelab-server-configs

Related repositories:

- /home/aaron/code/homelab-dns
- /home/aaron/code/homelab-docs
- /home/aaron/code/homelab-network
- /home/aaron/code/homelab-notification

Read the Versioned snapshot in:

/home/aaron/code/homelab-server-configs/Caddy/docs/PROJECT_HANDOFF-v1.md

Treat its commit identities as orientation baselines. Fetch every repository
in scope and verify its current branch, HEAD, origin/main, ahead/behind count,
and worktree state. Preserve unrelated changes. Do not discard, overwrite,
amend, squash, or include work outside the approved scope.

Read and follow completely:

/home/aaron/code/AGENTS.md
/home/aaron/code/homelab-server-configs/AGENTS.md
/home/aaron/code/homelab-server-configs/Caddy/AGENTS.md
/home/aaron/code/homelab-server-configs/Caddy/docs/caddy_plan-v1.1.md
/home/aaron/code/homelab-server-configs/Caddy/docs/DEPLOYMENT_LIFECYCLE.md

Read each related repository's AGENTS.md before changing that repository.

Current project status:

- The dual-node Caddy service is accepted in production.
- Action 35 closed through accepted Action 35as on 2026-08-24.
- Historical chronology belongs in Caddy/HISTORY.md and annotated Git tags.
- Do not restore or create action-numbered implementation artifacts.
- The Caddy deployment stream is clean.
- No deployment successor is registered.
- The successor coverage registry is header-only.
- The governing plan does not authorize live work.

Verify those statements against:

/home/aaron/code/homelab-server-configs/Caddy/manifests/deployment-streams.tsv
/home/aaron/code/homelab-server-configs/Caddy/manifests/deployable-successor.tsv
/home/aaron/code/homelab-server-configs/Caddy/manifests/deployable-successor-coverage.tsv

Accepted architecture:

- Node A is j1-svpihole0, the preferred owner, at 10.1.0.53 and
  fd36:5aa8:6971:1::53.
- Node B is j1-svpihole00, the standby, at 10.1.0.54 and
  fd36:5aa8:6971:1::54.
- pihole.local.theama.co uses DNS VIPs 10.1.0.55 and
  fd36:5aa8:6971:1::55.
- proxy.local.theama.co uses Proxy VIPs 10.1.0.56 and
  fd36:5aa8:6971:1::56.
- pihole-admin.local.theama.co also resolves to both Proxy VIPs.
- PIHOLE_DUALSTACK controls all four VIPs as one ownership group.
- DNS VIPs remain in virtual_ipaddress.
- Proxy VIPs remain in virtual_ipaddress_excluded. Exclusion changes VRRP
  advertisement encoding, not ownership.
- Accepted ownership is Node A dual-stack MASTER with four VIPs and Node B
  dual-stack BACKUP with zero VIPs.
- Split-family, simultaneous, ambiguous, or unhealthy ownership rejects.

Health contract:

- check-dns.sh evaluates Pi-hole FTL and Unbound serving health.
- check-caddy.sh evaluates trusted Caddy HTTPS serving health.
- Both Keepalived probes are synchronous, silent, minimal, bounded by the
  two-second Keepalived timeout, and SIGTERM-friendly.
- Caddy or DNS serving failure can move all four VIPs.
- Pi-hole and lighttpd web monitoring is notification-only.
- Notification delivery, lsyncd, reconciliation, certificate monitoring,
  router reachability, and general monitoring do not control VRRP.
- Keepalived's observed exit or signal and its cursor-bounded journal are the
  authoritative tracking-script result.

Proxy DNS identity:

- Each approved application gets A and AAAA records for the shared Proxy VIPs.
- Application hostnames do not receive individual PTR records.
- Both Proxy VIPs have the canonical PTR proxy.local.theama.co.
- proxy.local.theama.co resolves forward to both Proxy VIPs.
- Caddy selects applications through TLS SNI and the HTTP Host header.

Caddy release contract:

- The accepted inventory records Caddy 2.11.4.
- Caddy reads /etc/caddy/current/Caddyfile.
- /etc/caddy/current selects an immutable protocol-v2 release.
- Node A performs normal publication.
- Node B publication requires explicit guarded emergency mode while Node B
  owns both address families and all four VIPs.
- Managed lsyncd transfers releases to Node B.
- The receiver, finalizer, and reconciler validate and activate releases.
- Direct edits under /etc/caddy/current are prohibited.
- Read the accepted payload-manifest SHA-256 from the Versioned snapshot and
  confirm it against caddy-release-source.tsv and accepted-live manifests.

Accepted Caddy release sources:

/home/aaron/code/homelab-server-configs/Caddy/configs/caddy/Caddyfile
/home/aaron/code/homelab-server-configs/Caddy/configs/caddy/conf.d/00-health.caddy
/home/aaron/code/homelab-server-configs/Caddy/configs/caddy/conf.d/10-pihole-admin.caddy
/home/aaron/code/homelab-server-configs/Caddy/configs/caddy/conf.d/90-default-deny.caddy
/home/aaron/code/homelab-server-configs/Caddy/configs/caddy/conf.d/91-exact-listener-default-deny.caddy

Current documentation authorities:

/home/aaron/code/homelab-server-configs/Caddy/README.md
/home/aaron/code/homelab-server-configs/Caddy/HISTORY.md
/home/aaron/code/homelab-server-configs/Caddy/docs/caddy_plan-v1.1.md
/home/aaron/code/homelab-server-configs/Caddy/docs/QUICK_START.md
/home/aaron/code/homelab-server-configs/Caddy/docs/INSTALLATION.md
/home/aaron/code/homelab-server-configs/Caddy/docs/OPERATIONS.md
/home/aaron/code/homelab-server-configs/Caddy/docs/UNINSTALLATION.md
/home/aaron/code/homelab-server-configs/Caddy/docs/TROUBLESHOOTING.md
/home/aaron/code/homelab-server-configs/Caddy/docs/ARCHITECTURE.md
/home/aaron/code/homelab-server-configs/Caddy/docs/APPRISE_DELIVERY.md
/home/aaron/code/homelab-server-configs/Caddy/docs/REPRODUCIBILITY.md
/home/aaron/code/homelab-server-configs/Caddy/docs/APPLICATION_ONBOARDING.md
/home/aaron/code/homelab-server-configs/Caddy/docs/PROTOCOL_V2_RELEASE_LIFECYCLE.md

Production authority manifests:

/home/aaron/code/homelab-server-configs/Caddy/manifests/deployment.yaml
/home/aaron/code/homelab-server-configs/Caddy/manifests/current-live-state.tsv
/home/aaron/code/homelab-server-configs/Caddy/manifests/accepted-live-artifacts.tsv
/home/aaron/code/homelab-server-configs/Caddy/manifests/production-artifacts.tsv
/home/aaron/code/homelab-server-configs/Caddy/manifests/runtime-production.tsv
/home/aaron/code/homelab-server-configs/Caddy/manifests/caddy-release-source.tsv
/home/aaron/code/homelab-server-configs/Caddy/manifests/config-lifecycle.tsv
/home/aaron/code/homelab-server-configs/Caddy/manifests/dependencies.yaml
/home/aaron/code/homelab-server-configs/Caddy/manifests/reproducibility-production.yaml
/home/aaron/code/homelab-server-configs/Caddy/manifests/dns-records.yaml
/home/aaron/code/homelab-server-configs/Caddy/manifests/synchronization-protocol-v2.yaml
/home/aaron/code/homelab-server-configs/Caddy/manifests/serving-health-production.tsv
/home/aaron/code/homelab-server-configs/Caddy/manifests/durable-apprise-production.tsv

Accepted-live manifests remain authoritative when repository source differs
from installed production. Do not rewrite accepted hashes to match the working
tree without evidence. Classify each mismatch as planned source, bookkeeping
error, or verified production drift.

Ownership and external inputs:

- homelab-server-configs owns Caddy configuration, release tools, systemd
  units, and the accepted durable-notification client.
- homelab-dns owns Keepalived, DNS probes, the notifier, and both required
  Unbound files: Unbound/configs/pihole.conf and
  Unbound/configs/pihole-local-zone.conf.
- Pi-hole manages its application-owned FTL installation.
- homelab-network owns network-controller and firewall implementation.
- homelab-notification owns the Apprise API deployment.
- TLS material comes from Doppler project homelab-dev, configuration
  prd_caddy.
- Secret bytes, credentials, private SSH keys, and host trust material remain
  outside Git.
- The accepted Apprise endpoint contract is
  http://10.1.3.83:8000/notify/apprise.
- install-caddy-ha.sh is a partial filesystem and identity installer. Do not
  use it for production installation, migration, repair, or recovery.

Neutral production entrypoints:

/home/aaron/code/homelab-server-configs/Caddy/scripts/apply-serving-health-deployment.sh
/home/aaron/code/homelab-server-configs/Caddy/scripts/run-serving-health-deployment-outer.sh
/home/aaron/code/homelab-server-configs/Caddy/scripts/publish-release-v2.sh
/home/aaron/code/homelab-server-configs/Caddy/scripts/caddy-sync-release-receiver-v2
/home/aaron/code/homelab-server-configs/Caddy/scripts/finalize-incoming-release-v2.sh
/home/aaron/code/homelab-server-configs/Caddy/scripts/reconcile-release-v2.sh
/home/aaron/code/homelab-server-configs/Caddy/scripts/validate-caddy-ha.sh
/home/aaron/code/homelab-server-configs/Caddy/scripts/validate-sync-health.sh

Deployment rules:

- Keep one neutral transaction and one neutral outer runner.
- Keep one production artifact manifest.
- Use at most one small versioned operation specification.
- Fix an unexecuted neutral implementation in place instead of creating a
  successor for an orchestration correction.
- Production-path tests execute the real outer and transaction state machines.
- Bounded substitutes receive exact emitted commands and create causal,
  observable effects.
- Do not fabricate command, transport, journal, mutation, rollback,
  convergence, acceptance, or success evidence.
- Run residue-sensitive lifecycle tests serially.
- Live mutation requires a reviewed outer-runner SHA-256 and separate operator
  authorization.
- Definition-only work cannot contact either HA node.
- Apply and accept Node B before changing Node A.
- Never restart or reload both nodes together.
- Roll back in reverse mutation order.
- Return status 125 only when mutation occurred and exact recovery cannot be
  proven.
- Capture a journal cursor before a command and retain bounded post-cursor
  evidence.
- Preserve pending and dead-letter notifications. Delivery failure remains
  outside DNS, Caddy, and VRRP acceptance.

Current planned follow-on work:

The governing plan identifies the reverse-proxy fragment generator project as
the next Caddy repository project. Its definition begins at:

/home/aaron/code/homelab-server-configs/Caddy/docs/FUTURE_REVERSE_PROXY_GENERATOR_PROMPT.md

Keep that project definition-only until the operator approves its input
schema, inventory adapter, orchestration boundary, renderer, tests, lifecycle,
and authorization boundaries. Do not select an application, change DNS,
render production configuration, publish a release, contact a node, or
register a successor without separate authorization.

The complete-installation project and generic durable-Apprise project are
separate future projects. If the requested objective differs from the current
planned project, reconcile it with the governing plan before editing files.

Task procedure:

1. State the exact objective and classify it as read-only, repository-only,
   definition-only, or a proposed live change.
2. Verify repositories and preserve unrelated changes.
3. Read the authorities and manifests relevant to the objective.
4. Separate current verified facts, accepted repository records, and proposals.
5. Identify ownership boundaries and affected repositories.
6. Present the smallest sound change set before crossing a live boundary.
7. Do not infer endpoints, records, credentials, TLS trust, health behavior,
   authentication, or access policy.
8. Do not contact production without explicit bounded authorization.

Validation from /home/aaron/code/homelab-server-configs:

Caddy/tests/run-focused.sh \
  --profile current-repository-policies \
  --phase host \
  --container never

Caddy/tests/run-focused.sh \
  --profile current-serving-health \
  --phase host \
  --container never

Caddy/tests/run-focused.sh \
  --profile current-synchronization \
  --phase host \
  --container never

Caddy/tests/deployable-successor-policy.sh --check
git diff --check
pre-commit run --all-files

Use the network-disabled Debian 12 Podman phase when the change depends on
Debian, systemd, Caddy adaptation, or installed-command behavior:

Caddy/tests/run-focused-container.sh \
  --profiles current-repository-policies,current-serving-health,current-synchronization

Run Podman wrappers outside the filesystem sandbox. Run tests that inspect
global /tmp residue serially. Format changed shell files with:

tests/repository/shfmt-canonical.sh --write FILE...

Do not run bare shfmt -w.

For LikeC4 work, read:

/home/aaron/code/homelab-docs/AGENTS.md
/home/aaron/code/homelab-docs/architecture/likec4/README.md

Use the LikeC4 skill and repository-pinned version. Validate edited .c4 files,
then run likec4 format --check, likec4 validate, and the complete pre-commit
suite. Run Mermaid validation outside the filesystem sandbox.

Completion report:

- Exact scope completed.
- Files changed in each repository.
- Validation commands and results.
- Commit hashes created.
- Unresolved or unverified production facts.
- Deployment-stream and successor-registry state.
- Whether any node was contacted.
- Whether production was mutated.
- Exact next authorization, when required.

Do not push, tag, contact nodes, define a deployment successor, create an
operation specification, publish a release, or mutate production unless the
operator authorizes that specific action.
```

## Snapshot maintenance

Use a new document major version only when the handoff schema, authority model,
or deployment lifecycle changes incompatibly. Update `document_version` within
version 1 for repository baselines, production identities, paths, or clarified
instructions.

For a snapshot-only update:

1. Fetch every referenced repository.
2. Confirm that each worktree is clean and synchronized.
3. Reconcile repository baselines with the authoritative manifests.
4. Update only the YAML snapshot values and any instructions invalidated by
   the new state.
5. Run the documentation policy, current repository-policy profile,
   `git diff --check`, and the complete pre-commit suite.
6. Commit the update as a repository-only documentation checkpoint.

Do not claim live parity from Git state. A production identity changes only
after bounded live acceptance and repository bookkeeping establish it.
