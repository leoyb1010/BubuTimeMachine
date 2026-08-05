#!/usr/bin/env bash
set -euo pipefail
umask 077
cd "$(dirname "$0")"
mkdir -p ../logs
chmod 700 ../logs

if [ ! -f .env ]; then
  echo "缺少 server/ai/.env" >&2
  exit 2
fi
set -a
source .env
set +a

exec ./.venv/bin/python weekly_report_worker.py
