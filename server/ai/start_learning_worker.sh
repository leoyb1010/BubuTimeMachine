#!/usr/bin/env bash
set -euo pipefail
umask 077
cd "$(dirname "$0")"
[[ -f .env ]] || { echo '缺少 AI 服务 .env' >&2; exit 1; }
set -a
source .env
set +a
[[ -x .venv/bin/python ]] || { echo 'AI venv 尚未就绪' >&2; exit 1; }
exec .venv/bin/python -m learning.worker "$@"
