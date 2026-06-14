#!/usr/bin/env bash
# Compile-check gate for the Harmony app.
# CompileArkTS is the real correctness gate; PackageHap fails only on missing
# signing cert (environment limitation), so we treat "CompileArkTS Finished"
# with no ArkTS error as PASS.
set -uo pipefail
cd "$(dirname "$0")/.."
export DEVECO=/Applications/DevEco-Studio.app/Contents/tools
export NODE_HOME="$DEVECO/node"
export DEVECO_SDK_HOME=/Applications/DevEco-Studio.app/Contents/sdk
export JAVA_HOME="/Applications/DevEco-Studio.app/Contents/jbr/Contents/Home"
export PATH="$JAVA_HOME/bin:$NODE_HOME/bin:$DEVECO/ohpm/bin:$DEVECO/hvigor/bin:$PATH"
export NODE_OPTIONS="--max-old-space-size=8192"
OUT="$(./hvigorw assembleHap -p product=default --no-daemon 2>&1)"
echo "$OUT" | grep -E "ArkTS Compiler Error|does not meet|CompileArkTS|Failed :entry|TS[0-9]+|error:" 
if echo "$OUT" | grep -q "Finished :entry:default@CompileArkTS"; then
  echo "==> ARKTS_COMPILE: PASS"
  exit 0
else
  echo "==> ARKTS_COMPILE: FAIL"
  echo "$OUT" | tail -40
  exit 1
fi
