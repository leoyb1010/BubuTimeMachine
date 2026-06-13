#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEVECO_APP="${DEVECO_APP:-/Applications/DevEco-Studio.app}"
SDK_DIR="${DEVECO_SDK_HOME:-$DEVECO_APP/Contents/sdk}"
NODE_HOME="${NODE_HOME:-$DEVECO_APP/Contents/tools/node}"
JAVA_HOME="${JAVA_HOME:-$DEVECO_APP/Contents/jbr/Contents/Home}"
HDC="$SDK_DIR/default/openharmony/toolchains/hdc"
HAP="$ROOT_DIR/entry/build/default/outputs/default/entry-default-unsigned.hap"
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
  TARGET="$("$HDC" list targets | awk 'NF && $0 != "[Empty]" { print $1; exit }')"
fi

if [[ -z "$TARGET" ]]; then
  echo "No HarmonyOS target is online. Start an emulator in DevEco first." >&2
  exit 1
fi

./hvigorw assembleHap --mode module -p product=default --no-daemon
"$HDC" -t "$TARGET" install -r "$HAP"
"$HDC" -t "$TARGET" shell aa start -a EntryAbility -b com.bubu.timemachine

echo "Launched com.bubu.timemachine on $TARGET"
