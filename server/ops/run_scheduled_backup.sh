#!/usr/bin/env bash
set -euo pipefail

# 由 launchd 或受限 localhost SSH forced-command 调用。
# 配置文件只接受白名单键值，不 source、不 eval，防止配置内容变成任意命令。

CONFIG_FILE="${BUBU_BACKUP_CONFIG:-${HOME:?}/.config/bubu/backup.env}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

fail() {
  printf '定时备份启动失败：%s\n' "$1" >&2
  exit 1
}

[[ -f "$CONFIG_FILE" ]] || fail "配置文件不存在"

if owner_id="$(stat -f %u "$CONFIG_FILE" 2>/dev/null)"; then
  mode="$(stat -f %Lp "$CONFIG_FILE")"
else
  owner_id="$(stat -c %u "$CONFIG_FILE")"
  mode="$(stat -c %a "$CONFIG_FILE")"
fi
[[ "$owner_id" == "$(id -u)" ]] || fail "配置文件所有者不正确"
[[ "$mode" == "600" ]] || fail "配置文件权限必须为 600"

while IFS='=' read -r key value || [[ -n "$key" ]]; do
  [[ -z "$key" || "$key" == \#* ]] && continue
  case "$key" in
    PB_DATA_DIR|MIRROR_DIR|BACKUP_STAMP|LOCK_DIR|WORK_ROOT|RESTIC_REPOSITORY|RESTIC_PASSWORD_FILE|NTFY_URL|NTFY_TOKEN_FILE)
      export "$key=$value"
      ;;
    *) fail "配置包含不允许的键：$key" ;;
  esac
done < "$CONFIG_FILE"

if /bin/bash "$SCRIPT_DIR/backup_pb_data.sh"; then
  exit 0
else
  backup_status="$?"
fi

# 只发送故障类型，不发送数据路径、文件名或家庭内容。告警失败不能掩盖备份失败码。
if [[ -n "${NTFY_URL:-}" && -f "${NTFY_TOKEN_FILE:-}" ]]; then
  ntfy_token="$(cat "$NTFY_TOKEN_FILE")"
  curl -fsS --max-time 8 \
    -H "Authorization: Bearer $ntfy_token" \
    -H "Title: 布布服务器 · 自动备份失败" \
    -H "Tags: warning,computer" \
    --data-binary "PocketBase 自动备份失败，请检查 mini 备份日志。" \
    "$NTFY_URL" >/dev/null || true
  unset ntfy_token
fi
exit "$backup_status"
