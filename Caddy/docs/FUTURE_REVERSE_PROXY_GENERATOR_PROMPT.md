# Future reverse-proxy fragment generator project prompt

Resume from the accepted Caddy/DNS production architecture and backend
onboarding contract documented in `Caddy/docs/caddy_plan-v1.1.md` and
`Caddy/docs/APPLICATION_ONBOARDING.md`. This task defines a deterministic,
noninteractive reverse-proxy fragment generator. It does not authorize
implementation, node contact, DNS changes, production mutation, release
publication, or a Caddy deployment successor.

## Objective

Design a repository tool that reads one reviewed, non-secret application
specification and renders one proposed `20-<application>.caddy` fragment into a
protected temporary directory. The tool must validate the rendered fragment
and a complete temporary Caddy release without writing to `Caddy/configs`, an
active release, or a production inventory.

Stop after the operator accepts the input schema, renderer interface,
lifecycle transitions, test design, and authorization boundaries. Do not write
the generator during this planning project.

## Required discovery

Inspect and map:

- the exact token allowlist and HTTP and HTTPS contracts in
  `Caddy/templates/reverse-proxy.caddy.example`;
- the application approval fields and fragment-ordering rules in
  `Caddy/docs/APPLICATION_ONBOARDING.md`;
- the accepted release sources in
  `Caddy/manifests/caddy-release-source.tsv`;
- configuration, template, manifest, and script lifecycle policies;
- the current Caddy adaptation and validation entrypoints;
- protocol-v2 publication, finalization, reconciliation, activation, and
  rollback; and
- the boundary between proposed repository source, defined deployment input,
  accepted release source, and accepted-live state.

Record any decision that the current template or manifests cannot determine.
Do not infer a backend endpoint, health response, authentication owner, TLS
identity, trust root, network allowlist, or DNS requirement.

## Input contract

Define a versioned specification with an exact key allowlist. Require:

- application slug, owner, public FQDN, and fragment ordering category;
- required application A and AAAA intent for the shared Proxy VIPs, plus the
  invariant canonical PTR target `proxy.local.theama.co.` for both addresses;
- backend protocol and exact upstream addresses;
- single- or multi-backend availability and load-balancing policy;
- backend `Host` behavior and authentication owner;
- allowed IPv4 and IPv6 client networks;
- active-health method, URI, expected status, interval, timeout, passes, and
  failures;
- passive-health window, failure count, and unhealthy status classes;
- dial and response-header timeouts; and
- HTTPS certificate identity, SNI, and system or release-local trust source.

Reject unknown keys, duplicate values, unsafe names, invalid addresses,
invalid CIDRs, control characters, binary data, secrets, symlinks, hard links,
unbounded fields, and paths outside approved roots. Reject
`tls_insecure_skip_verify`. Require separate proxy definitions for upstreams
with different HTTPS identities or trust roots.

Decide whether the specification remains a temporary reviewed input or becomes
a tracked, non-secret source artifact. Define its lifecycle before choosing a
repository path.

## Renderer contract

Design one noninteractive entrypoint that:

1. reads the exact specification version;
2. proves that the application slug and public FQDN do not collide with current
   fragments or site addresses;
3. renders the supported template without executing specification content;
4. writes one `20-<application>.caddy` file beneath a caller-provided,
   protected `/tmp` directory;
5. rejects unresolved or unapproved template tokens;
6. preserves the shared dual-stack binds, access policy, health checks,
   timeouts, backend Host contract, and default-deny ordering;
7. renders HTTP without TLS directives and HTTPS with certificate verification,
   SNI, and approved trust;
8. produces deterministic bytes for the same inputs; and
9. emits bounded paths, hashes, validation results, and review metadata without
   exposing secrets or complete certificate material.

The renderer must not edit `Caddy/configs`, `config-lifecycle.tsv`,
`caddy-release-source.tsv`, accepted-live inventories, DNS repositories,
deployment registries, or node files. It must not publish or activate a
release.

## External inventory and orchestration boundary

Evaluate Git-managed specifications, Nautobot, NetBox, and another approved
source-of-truth system as possible owners of application intent. Keep the
renderer independent of the selected product: an adapter must export the exact
versioned specification, stable object identity, source revision, approval
state, and provenance that the renderer validates.

Define which system owns hosts, IP addresses, DNS intent, applications,
upstreams, health contracts, authentication ownership, and TLS trust metadata.
Reject two systems claiming authority for the same field. Keep secrets in the
approved external secret system and expose references rather than secret
values.

Evaluate Ansible Core, AWX, Semaphore UI, Rundeck, and a purpose-built runner
as orchestration options. The orchestrator may request rendering, validation,
repository changes, and a separately authorized deployment. An inventory
event or webhook must not publish a release or contact an HA node by itself.
Require an operator approval boundary between desired-state change, generated
proposal, reviewed repository change, deployment definition, and live
authorization.

## Temporary-release validation

Define how the tool assembles a complete temporary release from reviewed
accepted sources, the rendered fragment, approved TLS test inputs, and any
release-local backend CA. The design must:

- preserve the accepted directory layout and imports;
- reject missing, extra, linked, malformed, or unsafe inputs;
- run Caddy adaptation and validation with the accepted production-compatible
  Caddy version;
- test both node-specific environment renderings;
- prove the new hostname routes only through the shared Proxy VIP listeners;
- prove denied clients receive `403` and unknown hostnames remain governed by
  the existing `421` routes;
- prove the proposed DNS intent contains the exact application A and AAAA
  values, both shared addresses retain only the canonical
  `proxy.local.theama.co.` PTR, and that canonical name resolves forward to
  both addresses; and
- leave no temporary files outside the exact caller-provided output root.

Temporary validation does not create a protocol-v2 revision. The later live
operation prepares reviewed release input, invokes the installed publisher,
and collects production-path evidence under a separate authorization.

## Lifecycle and inventory transitions

Define separate transitions for:

1. a temporary specification and rendered proposal;
2. a reviewed repository fragment associated with a defined deployment;
3. an immutable protocol-v2 candidate;
4. an accepted active release; and
5. reconciled repository and accepted-live inventories.

The design must state which actor updates each lifecycle record and at which
acceptance boundary. It must prevent a generator from claiming that proposed
bytes are installed or accepted. It must also define collision handling when a
manual repository change or newer accepted release appears between rendering
and deployment definition.

## Test design

Require production-path tests that execute the real future entrypoint and
observe its filesystem effects. Cover:

- valid HTTP and verified-HTTPS specifications;
- one and several same-identity upstreams;
- invalid names, addresses, CIDRs, health settings, timeouts, and TLS inputs;
- unknown or missing keys, unresolved tokens, collisions, and unsafe paths;
- deterministic rendering and exact output hashes;
- Caddy adaptation and validation failures;
- SIGTERM, interrupted writes, cleanup, and zero residue; and
- proof that no production manifest, release, registry, DNS source, or node
  changes during generation.

Use bounded causal substitutes only where an external program is unavailable.
Do not use prewritten results or emitted success labels as evidence.

## Required deliverables

Stop after producing:

- the accepted specification schema and examples without real backend data;
- the proposed command-line and exit-status contract;
- the rendering and temporary-release assembly design;
- the lifecycle and inventory transition map;
- the selected source-of-truth adapter and orchestration boundary;
- the security, cleanup, and concurrency rules;
- the production-path test and validation plan; and
- explicit implementation, deployment-definition, and live-authorization
  boundaries.

Do not implement the generator, select an application, create DNS records,
contact an HA node, register a deployment successor, create an operation
specification, or mutate production during this planning project.
