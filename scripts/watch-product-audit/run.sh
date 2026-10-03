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
CONSOLE_PID=""
cleanup() {
  xcrun simctl terminate "$DEVICE" org.bubu.audit.watch-product >/dev/null 2>&1 || true
  if [[ -n "$CONSOLE_PID" ]]; then kill "$CONSOLE_PID" >/dev/null 2>&1 || true; fi
}
trap cleanup EXIT
wait_marker() {
  local marker="$1" file="$2"
  for ((attempt=0; attempt<20; attempt++)); do
    if grep -Fq "$marker" "$file"; then return; fi
    sleep 1
  done
  echo "Missing synthetic state transition: $marker" >&2
  return 1
}
for MODE in normal empty missing long withdraw withdraw-same-time withdraw-during-load; do
  cleanup
  ARGS=("-audit-$MODE")
  if [[ "$MODE" == long ]]; then ARGS+=("-watch-large-type"); fi
  xcrun simctl launch --console-pty "$DEVICE" org.bubu.audit.watch-product "${ARGS[@]}" > "$OUT/$MODE-console.log" 2>&1 &
  CONSOLE_PID=$!
  sleep 3
  xcrun simctl io "$DEVICE" screenshot "$OUT/$MODE-before.png"
  if [[ "$MODE" == withdraw* ]]; then
    wait_marker 'AUDIT_AUTHORITATIVE_EMPTY_SNAPSHOT_APPLIED' "$OUT/$MODE-console.log"
    if [[ "$MODE" == withdraw-during-load ]]; then
      wait_marker 'AUDIT_PHOTO_DATA_READ synthetic-2.png' "$OUT/$MODE-console.log"
    fi
    sleep 1 # allow a display frame after the observed state/decode event
    xcrun simctl io "$DEVICE" screenshot "$OUT/$MODE-after-authoritative-empty.png"
  fi
done
printf '%s\n' 'Native watchOS 40mm screenshots; actual production view; synthetic snapshot/cache adapters. No physical gestures, WatchConnectivity or device integration validated.' > "$OUT/scope.txt"
