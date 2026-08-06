#!/usr/bin/env bash
# 启动 PocketBase（布布时光机后端）
# 用法：./start_pocketbase.sh [数据目录]
# 数据目录默认 ./pb_data，建议指向外接 SSD，例如：
#   ./start_pocketbase.sh /Volumes/BubuSSD/pb_data
set -euo pipefail

cd "$(dirname "$0")"

DATA_DIR="${1:-./pb_data}"
PB_BIN="${PB_BIN:-./pocketbase}"
PB_HTTP_ADDR="${PB_HTTP_ADDR:-127.0.0.1:8090}"
PB_MIGRATIONS_DIR="${PB_MIGRATIONS_DIR:-./migrations}"
PB_HOOKS_DIR="${PB_HOOKS_DIR:-./pb_hooks}"
BUBU_SERVER_ENV_FILE="${BUBU_SERVER_ENV_FILE:-../ai/.env}"

# PocketBase intake hook 与 AI staging 必须读到同一套本机密钥；launchd 只保存
# 这个 0600 文件的路径，不把 secret 明文复制进 plist。
if [[ -f "$BUBU_SERVER_ENV_FILE" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "$BUBU_SERVER_ENV_FILE"
  set +a
fi

if [ ! -x "$PB_BIN" ]; then
  echo "❌ 未找到 pocketbase 可执行文件。"
  echo "   请从 https://github.com/pocketbase/pocketbase/releases 下载对应 macOS(arm64) 版本，"
  echo "   解压后把 pocketbase 放到本目录（server/pocketbase/）。"
  exit 1
fi

echo "📦 数据目录：$DATA_DIR"
echo "🚀 启动 PocketBase，管理后台： http://$PB_HTTP_ADDR/_/"
echo "   首次启动请在后台创建管理员账号，并新建一个家庭登录用户（members 用）。"

# 默认只监听本机；需要 Tailscale 访问时显式传入：
#   PB_HTTP_ADDR="<tailscale-ip>:8090" ./start_pocketbase.sh /path/to/pb_data
# 家庭内多设备想走局域网直连（App 设置页的「局域网直连地址」）时，监听所有网卡：
#   PB_HTTP_ADDR="0.0.0.0:8090" ./start_pocketbase.sh /path/to/pb_data
# ——0.0.0.0 同时覆盖 Tailscale IP 与 192.168.x.x，App 侧会自动赛跑择快。
# 直接使用受 Git 管理的迁移目录，避免运行时副本残留已改号或已删除的旧迁移。
exec "$PB_BIN" serve \
  --http="$PB_HTTP_ADDR" \
  --dir="$DATA_DIR" \
  --migrationsDir="$PB_MIGRATIONS_DIR" \
  --hooksDir="$PB_HOOKS_DIR"
