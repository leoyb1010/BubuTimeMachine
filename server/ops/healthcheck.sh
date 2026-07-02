#!/usr/bin/env bash
set -euo pipefail

PB_URL="${PB_URL:-http://127.0.0.1:8090}"
AI_URL="${AI_URL:-http://127.0.0.1:8000}"
DATA_PATH="${DATA_PATH:-/Volumes/BubuSSD}"
MIN_FREE_GB="${MIN_FREE_GB:-20}"

failures=()

if ! curl -fsS --max-time 8 "$PB_URL/api/health" >/dev/null; then
  failures+=("PocketBase health failed: $PB_URL/api/health")
fi

if ! curl -fsS --max-time 8 "$AI_URL/health" >/dev/null; then
  failures+=("AI health failed: $AI_URL/health")
fi

if [[ -d "$DATA_PATH" ]]; then
  available_kb="$(df -Pk "$DATA_PATH" | awk 'NR==2 {print $4}')"
  available_gb="$((available_kb / 1024 / 1024))"
  if (( available_gb < MIN_FREE_GB )); then
    failures+=("Low disk space on $DATA_PATH: ${available_gb}GB < ${MIN_FREE_GB}GB")
  fi
else
  failures+=("Data path missing: $DATA_PATH")
fi

if (( ${#failures[@]} > 0 )); then
  printf '%s\n' "${failures[@]}" >&2
  exit 1
fi

echo "Bubu backend health OK"
