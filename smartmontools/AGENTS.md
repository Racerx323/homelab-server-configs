# smartmontools component rules

These rules apply beneath `smartmontools/` and refine the repository rules in
`../AGENTS.md`.

## Architecture authority

- `docs/SMARTMONTOOLS_ARCHITECTURE.md` governs reusable smartctl and smartd
  configuration, discovery, monitoring, self-test, evidence, and alerting
  boundaries.
- Consumer components own device membership, workload constraints, operation
  state, accepted health decisions, and terminal history.
- A consumer's governing plan controls device-specific acceptance. Stop and
  request an architecture decision when it conflicts with this component.

## Repository contents

- Keep reviewed non-secret smartd configuration, smartctl collection policy,
  schemas, scripts, templates, and operator documentation under
  `smartmontools/`.
- Add a consumer-specific path only when reviewed configuration exists. Do not
  create placeholder trees.
- Keep raw device reports, serial numbers, WWNs, logs, runtime state, and raw
  operation evidence outside Git. Commit sanitized evidence manifests only.
- Keep mail credentials and transport secrets in their owning secret and mail
  systems.

## Execution boundaries

- Discover the device path, protocol, bridge, and smartctl device type before
  collecting health data. Do not assume `-d sat` for a USB device.
- Decode smartctl's eight-bit exit status. A nonzero status is not one generic
  command failure.
- Treat SMART enable or disable actions, offline data collection, self-tests,
  test cancellation, drive setting changes, and smartd schedule changes as
  separate mutation classes.
- Keep self-tests out of read-only collection operations. Require separate
  authorization that names the device, test type, duration, workload impact,
  evidence, and cancellation boundary.
- Bound output and sanitize device identity before committing evidence.

## Validation

- Validate configuration syntax, device selectors, exit-mask decoding,
  notification routing, secret absence, and evidence sanitization for each
  changed implementation.
- Test clean, warning, failing-health, device-open failure, command failure,
  error-log, and self-test-log status bits.
- Use the installed smartmontools version and detected device type on the
  target as the final CLI authority during an authorized preflight.
