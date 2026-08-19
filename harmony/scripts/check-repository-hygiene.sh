#!/bin/sh
set -eu

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
cd "$repo_root"

if git grep -nE '"(keyPassword|storePassword|certpath|storeFile)"[[:space:]]*:' -- harmony/build-profile.json5; then
  echo "harmony/build-profile.json5 不得提交签名材料或口令。" >&2
  exit 1
fi

if git grep -n '/Users/' -- harmony ':!harmony/scripts/check-repository-hygiene.sh'; then
  echo "HarmonyOS 工程不得提交本机绝对路径。" >&2
  exit 1
fi

if [ ! -f harmony/PARITY_MATRIX.md ]; then
  echo "缺少 harmony/PARITY_MATRIX.md。" >&2
  exit 1
fi

echo "HarmonyOS 仓库卫生检查通过。"
