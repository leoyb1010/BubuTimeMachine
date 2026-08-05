#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
VENV_DIR="${VENV_DIR:-$SCRIPT_DIR/.venv}"
MODEL_DIR="${SEMANTIC_MODEL_DIR:-$SCRIPT_DIR/models/mobileclip_s0}"

if [[ ! -x "$VENV_DIR/bin/python" ]]; then
  echo "AI venv 不存在，请先运行 ./start_ai.sh" >&2
  exit 1
fi

"$VENV_DIR/bin/python" -m pip install -r "$SCRIPT_DIR/requirements-semantic.lock.txt"
"$VENV_DIR/bin/python" -m pip install --no-deps \
  "git+https://github.com/apple/ml-mobileclip.git@aecfb5453d022e9deff12f81a150ea8f35194baa"
mkdir -p "$MODEL_DIR"

CHECKPOINT="$MODEL_DIR/mobileclip_s0.pt"
if [[ -f "$CHECKPOINT" ]]; then
  echo "MobileCLIP 权重已存在：$CHECKPOINT"
  exit 0
fi

DOWNLOAD_URL="${SEMANTIC_MODEL_URL:-https://docs-assets.developer.apple.com/ml-research/datasets/mobileclip/mobileclip_s0.pt}"
curl --fail --location --retry 3 --output "$CHECKPOINT.partial" "$DOWNLOAD_URL"
if [[ ! -s "$CHECKPOINT.partial" ]] || (( $(stat -f %z "$CHECKPOINT.partial" 2>/dev/null || stat -c %s "$CHECKPOINT.partial") < 100000000 )); then
  echo "MobileCLIP 权重下载不完整" >&2
  rm -f "$CHECKPOINT.partial"
  exit 1
fi
mv "$CHECKPOINT.partial" "$CHECKPOINT"
echo "MobileCLIP 安装完成。请设置："
echo "SEMANTIC_MODEL_PATH=$CHECKPOINT"
