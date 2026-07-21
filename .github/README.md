# Homelab Server Configs

![License](https://badgen.net/github/license/Racerx323/homelab-server-configs)
![Last commit](https://badgen.net/github/last-commit/Racerx323/homelab-server-configs)
[![Open issues](https://badgen.net/github/open-issues/Racerx323/homelab-server-configs)](https://github.com/Racerx323/homelab-server-configs/issues?q=is%3Aissue%20state%3Aopen)

Configuration, automation, and operational documentation for services running
in my homelab. The repository keeps host maintenance tasks reproducible and
reviewable without storing credentials or machine-specific secrets.

## Current contents

| Area | Status | Purpose |
| --- | --- | --- |
| [`Needrestart`](../Needrestart/) | Implemented | Runs a scheduled Debian `needrestart` scan and sends actionable notifications through a sendmail-compatible MTA. |
| [`Webmin`](../Webmin/) | Scaffold | Reserved `configs`, `scripts`, and `templates` directories for future Webmin configuration. |
| [`watchdog`](../watchdog/) | Scaffold | Reserved `configs`, `scripts`, and `templates` directories for future watchdog configuration. |

The Needrestart workflow currently includes:

- `scripts/needrestart.sh`, which performs a bounded, noninteractive scan for
  obsolete kernels, services, and user sessions;
- `scripts/needrestart_check`, an `/etc/cron.d` entry that runs the scan daily;
- installation, testing, runtime, and troubleshooting guidance; and
- an example system-wide msmtp configuration for relaying notifications to a
  LAN Mailrise service, plus optional Mailgun delivery tests.

See the [Needrestart documentation](../Needrestart/README.md) for requirements,
installation commands, exit statuses, and testing instructions. The
[msmtp and Mailrise guide](../Needrestart/msmtp-mailrise.md) documents the mail
transport separately.

## Repository layout

```text
.
├── .github/             Community, contribution, security, and issue templates
├── Needrestart/
│   ├── configs/         Reserved for service configuration
│   ├── scripts/         Notification script and cron definition
│   └── templates/       Reserved for templates
├── Webmin/              Future Webmin configs, scripts, and templates
└── watchdog/            Future watchdog configs, scripts, and templates
```

## Getting started

Clone the repository and enter the working tree:

```bash
git clone https://github.com/Racerx323/homelab-server-configs.git
cd homelab-server-configs
```

Each implemented service has its own README with prerequisites and deployment
steps. Do not copy example addresses, hostnames, or routes into production
unchanged. Review the files first, substitute values for your environment, and
keep passwords, tokens, and other secrets outside the repository.

To deploy the currently implemented workflow, continue with
[Needrestart notifications](../Needrestart/README.md#requirements).

## Development and validation

The repository uses pre-commit hooks to check:

- shell scripts with ShellCheck and shfmt;
- Markdown with markdownlint-cli2;
- YAML with yamllint;
- GitHub issue forms and Compose files with check-jsonschema;
- JSON with jq; and
- staged content with Gitleaks.

Install the required command-line tools, install the hooks, and validate the
repository before submitting a change:

```bash
pre-commit install
pre-commit run --all-files
```

See [CONTRIBUTING.md](CONTRIBUTING.md) for the contribution workflow and
[SECURITY.md](SECURITY.md) for private vulnerability reporting.

## License

This project is licensed under the
[GNU General Public License v3.0](../LICENSE.md).
