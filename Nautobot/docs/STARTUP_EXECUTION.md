# Application startup execution

This operation starts the single-host pilot using the accepted initialized database
and existing administrator. The master deployment plan still governs workload,
reboot persistence, Caddy onboarding and application-aware backup/restore acceptance.
None of those later stages is accepted by this startup check.

## Preconditions and authorization

Archive preservation first. Review a fresh stopped baseline with unchanged boot,
images, environment-file metadata, configuration, six stopped services, no containers
or TCP 8080 listener, verified backend guard and bounded kernel review. The launcher
requires the reviewed baseline to be no more than one hour old at execution. If it
expires, recollect and review it, rebuild the hash and obtain approval of that hash;
do not change the timestamp of old evidence.

The policy's `execution_authorized` flag enables the prepared launcher contract;
it is not user approval. The launcher additionally requires the exact approved
hash, reviewed recovery, active operation, published network evidence and clean Git
source. `assemble-startup.py OUTPUT BASELINE REVIEWED_RECOVERY` renders nonsecret
artifacts and seven concrete checks. `run-startup.py show-hash SPECIFICATION` checks
input hashes. Only `run-startup.py execute SPECIFICATION APPROVED_HASH` contacts the
host. Review the exact specification and all changed artifact destinations first.

## Mutation and checks

Target: `ama@10.1.2.170`. Stage bounded root-owned helpers, capture a journal cursor,
and arm a two-hour independent stop timer. Preserve original artifact backups;
install reviewed runtime code/Quadlets and reload the user manager. Existing
PostgreSQL/Redis units remain byte-identical. Start PostgreSQL, Redis, migration,
web, worker and scheduler serially, requiring new successful invocations.
Migration runs native `post_upgrade` against the initialized database, including
Job discovery. The web role collects static assets. The media volume is new,
durable and owned by container UID/GID 999. The application remains rootless.

The collector requires all seven groups:

1. Native configuration/migration/static receipts from current invocations, plus
   healthy service states and no restarts.
2. HTTP 200 health and nonempty CSS static response through loopback recovery.
3. Administrator form login with a valid CSRF token, existing-session identity,
   logout/session revocation, hostile Host/missing-CSRF rejection, tunnel cleanup.
   The existing Doppler administrator password stays in process memory. This is
   an HTTP session check, not rendered JavaScript or full browser UX acceptance.
4. Both proxy nodes to both backend address families; non-proxy IPv4/IPv6 timeout
   correlated with family-specific deny counters and bracketing positive checks.
   No proxy, DNS, HA or network configuration is changed.
5. One harmless asynchronous Job on the single worker with concurrency two. It
   performs SELECT 1 and deterministic hashing, restores its prior enabled flag,
   and retains its JobResult. This is a queue smoke test; the representative
   workload stage remains separate despite the historical acceptance-group name.
6. Actual container/cgroup limits, no OOM, private database/cache ports, rootless
   read-only application containers and protected credential-file metadata.
7. At least 75 seconds after preceding checks, cursor-bounded kernel review,
   unchanged boot and service invocations. No SMART query or self-test is issued.

## Success, failure and recovery

On success, disarm the unused timer and leave services running pending later
acceptance. Retain the result, lifecycle receipt and backups. On failure, stop all
six services in reverse order and prove no containers remain. Only then disarm the
timer. If stopping cannot be proved, leave the timer armed and report manual
intervention. Never automatically restore or delete data, retry migration, rotate
credentials, reboot, or publish through Caddy.

Recovery copies are verified cold copies, not exercised restores. Restoring one
requires a separate reviewed operation with services stopped, the then-current
volumes preserved, and independent post-restore validation. Artifact backups are
retained for a separately reviewed reversal; stopping services is the automatic
failure action, not a claim that files or database changes were rolled back.
