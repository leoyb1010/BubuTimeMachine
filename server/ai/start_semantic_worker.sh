#!/usr/bin/env bash
set -euo pipefail
umask 077
cd "$(dirname "$0")"

if [[ ! -f .env ]]; then
  echo "未找到 .env，语义 worker 拒绝启动" >&2
  exit 1
fi
set -a
source .env
set +a

if [[ ! -x .venv/bin/python ]]; then
  echo "AI venv 不存在，请先运行 ./start_ai.sh" >&2
  exit 1
fi
# 与 main.py / semantic_worker.py 的判定保持一致（1/true/yes/on），避免 /health 报已启用而 worker 拒启。
case "$(printf %s "${SEMANTIC_SEARCH_ENABLED:-false}" | tr "[:upper:]" "[:lower:]")" in
  1|true|yes|on) ;;
  *) echo "SEMANTIC_SEARCH_ENABLED 未开启，语义 worker 拒绝启动" >&2; exit 1 ;;
esac
if [[ -z "${PB_WORKER_TOKEN:-}" ]] && { [[ -z "${PB_WORKER_EMAIL:-}" ]] || [[ -z "${PB_WORKER_PASSWORD:-}" ]]; }; then
  echo "缺少 PB_WORKER_TOKEN 或 PB_WORKER_EMAIL / PB_WORKER_PASSWORD" >&2
  exit 1
fi

exec .venv/bin/python semantic_worker.py
