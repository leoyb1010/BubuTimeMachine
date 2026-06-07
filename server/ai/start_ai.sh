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
  ./.venv/bin/pip install --quiet -r requirements.txt
fi

PORT="${AI_PORT:-8000}"
echo "🚀 AI 服务启动： http://0.0.0.0:${PORT}  （健康检查 /health）"
exec ./.venv/bin/uvicorn main:app --host 0.0.0.0 --port "${PORT}"
