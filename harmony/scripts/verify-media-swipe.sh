#!/bin/sh
set -eu

HDC=${HDC:-/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/toolchains/hdc}
TARGET=${1:-}
if [ -z "$TARGET" ]; then
  TARGET=$($HDC list targets | awk 'NF && $0 != "[Empty]" { print $1; exit }')
fi
if [ -z "$TARGET" ]; then
  echo '没有在线 HarmonyOS 设备' >&2
  exit 2
fi

work_dir=$(mktemp -d /tmp/bubu-media-swipe.XXXXXX)
cleanup() {
  case "$work_dir" in /tmp/bubu-media-swipe.*) rm -rf -- "$work_dir" ;; esac
}
trap cleanup EXIT HUP INT TERM

dump_counter() {
  suffix=$1
  remote="/data/local/tmp/bubu-media-$suffix.json"
  local_file="$work_dir/$suffix.json"
  $HDC -t "$TARGET" shell uitest dumpLayout -p "$remote" -i >/dev/null
  $HDC -t "$TARGET" file recv "$remote" "$local_file" >/dev/null
  node - "$local_file" <<'NODE'
const fs = require('fs');
const root = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
let found = '';
function walk(node) {
  const text = node?.attributes?.text ?? '';
  if (/^\d+ \/ \d+ · 左右滑动$/.test(text)) found = text;
  for (const child of node?.children ?? []) walk(child);
}
walk(root);
if (!found) process.exit(3);
process.stdout.write(found);
NODE
}

before=$(dump_counter before) || {
  echo '当前屏幕不是多媒体查看器，或媒体总数只有 1；请先打开显示“x / N · 左右滑动”的页面' >&2
  exit 3
}
index=$(printf '%s' "$before" | awk '{print $1}')
total=$(printf '%s' "$before" | awk '{print $3}')

if [ "$index" -lt "$total" ]; then
  $HDC -t "$TARGET" shell uitest uiInput swipe 1050 920 220 920 800 >/dev/null
  expected='increase'
else
  $HDC -t "$TARGET" shell uitest uiInput swipe 220 920 1050 920 800 >/dev/null
  expected='decrease'
fi
sleep 1
after=$(dump_counter after) || {
  echo "滑动后页码消失：$before" >&2
  exit 4
}
after_index=$(printf '%s' "$after" | awk '{print $1}')
after_total=$(printf '%s' "$after" | awk '{print $3}')

if [ "$total" -ne "$after_total" ]; then
  echo "媒体总数变化异常：$before -> $after" >&2
  exit 5
fi
if { [ "$expected" = increase ] && [ "$after_index" -le "$index" ]; } ||
   { [ "$expected" = decrease ] && [ "$after_index" -ge "$index" ]; }; then
  echo "左右滑动失败：$before -> $after" >&2
  exit 6
fi

echo "左右滑动通过：$before -> $after"
