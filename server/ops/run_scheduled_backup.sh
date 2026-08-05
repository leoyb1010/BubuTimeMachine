#!/usr/bin/env bash
set -euo pipefail

# 由 launchd 或受限 localhost SSH forced-command 调用。
# 配置文件只接受白名单键值，不 source、不 eval，防止配置内容变成任意命令。

CONFIG_FILE="${BUBU_BACKUP_CONFIG:-${HOME:?}/.config/bubu/backup.env}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"

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
    PB_DATA_DIR|MIRROR_DIR|BACKUP_STAMP|LOCK_DIR|WORK_ROOT|RESTIC_REPOSITORY|RESTIC_PASSWORD_FILE)
      export "$key=$value"
      ;;
    *) fail "配置包含不允许的键：$key" ;;
  esac
done < "$CONFIG_FILE"

exec /bin/bash "$SCRIPT_DIR/backup_pb_data.sh"
