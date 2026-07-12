#!/usr/bin/env bash
# 启动布布时光机 AI 服务（FastAPI + DeepSeek）
set -euo pipefail
cd "$(dirname "$0")"

# 加载 .env
if [ -f .env ]; then
  set -a; source .env; set +a
else
  echo "⚠️  未找到 .env，请先 cp .env.example .env 并填写 DEEPSEEK_API_KEY"
fi

# 虚拟环境
if [ ! -d .venv ]; then
  echo "📦 创建虚拟环境并安装依赖…"
  python3 -m venv .venv
  ./.venv/bin/pip install --quiet --upgrade pip
  REQ_FILE="requirements.txt"
  if [ -f requirements.lock.txt ]; then
    REQ_FILE="requirements.lock.txt"
  fi
  ./.venv/bin/pip install --quiet -r "${REQ_FILE}"
fi

PORT="${AI_PORT:-8000}"
# 默认只绑本机回环，不暴露到全网卡（与 PocketBase 绑 127.0.0.1 保持一致）。
# 需要经 Tailscale/内网访问时，在 .env 显式设 BUBU_AI_BIND=100.x.x.x（该机的 Tailscale 地址）
# 或 0.0.0.0，切勿在裸公网上直接放开。
BIND="${BUBU_AI_BIND:-127.0.0.1}"
echo "🚀 AI 服务启动： http://${BIND}:${PORT}  （健康检查 /health）"
exec ./.venv/bin/uvicorn main:app --host "${BIND}" --port "${PORT}"
