#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEVECO_APP="${DEVECO_APP:-/Applications/DevEco-Studio.app}"
SDK_DIR="${DEVECO_SDK_HOME:-$DEVECO_APP/Contents/sdk}"
NODE_HOME="${NODE_HOME:-$DEVECO_APP/Contents/tools/node}"
JAVA_HOME="${JAVA_HOME:-$DEVECO_APP/Contents/jbr/Contents/Home}"
HDC="$SDK_DIR/default/openharmony/toolchains/hdc"
HAP="${BUBU_HAP_PATH:-$ROOT_DIR/entry/build/default/outputs/default/entry-default-signed.hap}"
TARGET="${1:-}"

export NODE_HOME
export DEVECO_SDK_HOME="$SDK_DIR"
export JAVA_HOME
export PATH="$NODE_HOME/bin:$JAVA_HOME/bin:$PATH"

if [[ ! -x "$HDC" ]]; then
  echo "hdc not found: $HDC" >&2
  exit 1
fi

cd "$ROOT_DIR"

if [[ -z "$TARGET" ]]; then
  targets=()
  while IFS= read -r item; do
    item="${item%$'\r'}"
    [[ -n "$item" && "$item" != "[Empty]" ]] && targets+=("$item")
  done < <("$HDC" list targets)
  if [[ "${#targets[@]}" -gt 1 ]]; then
    echo "检测到多个设备，请明确传入目标设备标识。" >&2
    exit 1
  fi
  TARGET="${targets[0]:-}"
fi

if [[ -z "$TARGET" ]]; then
  echo "No HarmonyOS target is online. Start an emulator in DevEco first." >&2
  exit 1
fi

if [[ ! -f "$HAP" || "$HAP" == *unsigned.hap ]]; then
  echo "请先完成本机签名，并用 BUBU_HAP_PATH 指定签名 HAP；不会用无签名包覆盖手机。" >&2
  exit 1
fi
"$HDC" -t "$TARGET" install -r "$HAP"
"$HDC" -t "$TARGET" shell aa start -a EntryAbility -b com.bubu.timemachine

echo "Launched com.bubu.timemachine on $TARGET"
