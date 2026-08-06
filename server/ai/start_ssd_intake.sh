#!/usr/bin/env bash
set -euo pipefail
umask 077
cd "$(dirname "$0")"

if [[ ! -f .env ]]; then
  echo "SSD_INTAKE_SKIPPED missing_env" >&2
  exit 1
fi
set -a
# shellcheck disable=SC1091
source .env
set +a

if [[ ! -x .venv/bin/python ]]; then
  echo "SSD_INTAKE_SKIPPED missing_venv" >&2
  exit 1
fi
exec .venv/bin/python scan_ssd_inbox.py
