# Temporary capture qualification

Target: ama@10.1.2.170, rootless Nautobot containers.

Scope: create one new root-owned mode-0700 directory under /tmp; stage
nonsecret reviewed inputs; read a PostgreSQL custom dump, directory-only media,
reviewed configuration/Quadlets, image/dependency and version/migration metadata.
Check dump listing and health between captures. No workload Jobs, B2 access,
secrets resolution, service changes, package changes or production data writes.
Maximum raw capture: 256 MiB database plus five 16 MiB sections; 384 MiB headroom
required. Node command deadline 900 seconds; controller limit 1100 seconds.
Quiet application window is required; only accepted running services continue.
Raw captures are independently removed on ordinary failure/success. Only
nonsecret receipt is fetched. Retain staged nonsecret files and result for review.
Loss of node/controller may leave raw data: inspect this exact directory and
process state before any cleanup or retry. No automatic database rollback.
This qualifies captures/staging only, not workload, continuous monitoring,
backup upload, application restore or persistence.
