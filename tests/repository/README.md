# Repository shell policies

This directory owns component-neutral shell policies used by the root
pre-commit configuration. Policies here must inspect applicable files across
the repository and must not encode Caddy, Nautobot, or another component's
architecture or deployment lifecycle.

Caddy-specific policies remain under `Caddy/tests/` and use `^Caddy/`
selectors in `.pre-commit-config.yaml`. A change under `Nautobot/` therefore
cannot invoke a Caddy-only policy.

Run the policy regression checks with:

```bash
tests/repository/run-policy-self-tests.sh
```

Run the repository-wide portable AWK audit with:

```bash
tests/repository/portable-awk-policy.sh --check
```
