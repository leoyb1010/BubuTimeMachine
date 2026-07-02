#!/usr/bin/env bash
# 启动 PocketBase（布布时光机后端）
# 用法：./start_pocketbase.sh [数据目录]
# 数据目录默认 ./pb_data，建议指向外接 SSD，例如：
#   ./start_pocketbase.sh /Volumes/BubuSSD/pb_data
set -euo pipefail

cd "$(dirname "$0")"

DATA_DIR="${1:-./pb_data}"
PB_BIN="./pocketbase"
PB_HTTP_ADDR="${PB_HTTP_ADDR:-127.0.0.1:8090}"

if [ ! -x "$PB_BIN" ]; then
  echo "❌ 未找到 pocketbase 可执行文件。"
  echo "   请从 https://github.com/pocketbase/pocketbase/releases 下载对应 macOS(arm64) 版本，"
  echo "   解压后把 pocketbase 放到本目录（server/pocketbase/）。"
  exit 1
fi

# 把迁移文件软链到 PocketBase 期望的 pb_migrations 目录
mkdir -p pb_migrations
cp -f migrations/*.js pb_migrations/ 2>/dev/null || true

echo "📦 数据目录：$DATA_DIR"
echo "🚀 启动 PocketBase，管理后台： http://$PB_HTTP_ADDR/_/"
echo "   首次启动请在后台创建管理员账号，并新建一个家庭登录用户（members 用）。"

# 默认只监听本机；需要 Tailscale 访问时显式传入：
#   PB_HTTP_ADDR="<tailscale-ip>:8090" ./start_pocketbase.sh /path/to/pb_data
exec "$PB_BIN" serve --http="$PB_HTTP_ADDR" --dir="$DATA_DIR" --migrationsDir="./pb_migrations"
