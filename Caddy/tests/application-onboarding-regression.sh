#!/usr/bin/env bash
set -Eeuo pipefail
# Native execution uses run-application-qualification.py and its offline image.
# Keep definition checks usable without starting Podman or contacting a node.
exec python3 -I "$(dirname -- "${BASH_SOURCE[0]}")/application-onboarding-regression.py" --definition-check
