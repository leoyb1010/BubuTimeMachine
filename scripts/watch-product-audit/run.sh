#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="$ROOT/watch-product-audit-results/${1:-current}"
mkdir -p "$OUT"
python3 "$ROOT/scripts/watch-product-audit/generate.py" --output "$OUT/project" --ref "${2:-WORKTREE}"
cp "$OUT/project/source-manifest.json" "$OUT/source-manifest.json"
xcrun simctl list devices available -j > "$OUT/simulators.json"
DEVICE=$(python3 - "$OUT/simulators.json" <<'PY'
import json,sys
matches=[d for runtime,devices in json.load(open(sys.argv[1]))['devices'].items() if 'watchOS' in runtime for d in devices if '40mm' in d['name']]
if not matches: raise SystemExit('No small-watch simulator available; native watch capture is blocked')
print(matches[-1]['udid'])
PY
)
(cd "$OUT/project" && xcodegen generate)
xcodebuild -project "$OUT/project/WatchProductAudit.xcodeproj" -scheme WatchProductAudit -destination "id=$DEVICE" -derivedDataPath "$OUT/build" CODE_SIGNING_ALLOWED=NO build 2>&1 | tee "$OUT/build.log"
xcrun simctl boot "$DEVICE" || true
xcrun simctl bootstatus "$DEVICE" -b
xcrun simctl install "$DEVICE" "$OUT/build/Build/Products/Debug-watchsimulator/WatchProductAudit.app"
for MODE in normal empty missing long withdraw; do
  xcrun simctl terminate "$DEVICE" org.bubu.audit.watch-product >/dev/null 2>&1 || true
  ARGS=("-audit-$MODE")
  if [[ "$MODE" == long ]]; then ARGS+=("-watch-large-type"); fi
  xcrun simctl launch "$DEVICE" org.bubu.audit.watch-product "${ARGS[@]}"
  sleep 3
  xcrun simctl io "$DEVICE" screenshot "$OUT/$MODE-before.png"
  if [[ "$MODE" == withdraw ]]; then
    sleep 7
    xcrun simctl io "$DEVICE" screenshot "$OUT/$MODE-after-authoritative-empty.png"
  fi
done
printf '%s\n' 'Native watchOS 40mm screenshots; actual production view; synthetic snapshot/cache adapters. No physical gestures, WatchConnectivity or device integration validated.' > "$OUT/scope.txt"
