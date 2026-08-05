#!/usr/bin/env bash
set -euo pipefail

PB_URL="${PB_URL:-http://127.0.0.1:8090}"
AI_URL="${AI_URL:-http://127.0.0.1:8000}"
DATA_PATH="${DATA_PATH:-/Volumes/BubuSSD}"
MIN_FREE_GB="${MIN_FREE_GB:-20}"
BACKUP_STAMP="${BACKUP_STAMP:-}"
MAX_BACKUP_AGE_HOURS="${MAX_BACKUP_AGE_HOURS:-30}"
NTFY_URL="${NTFY_URL:-}"
NTFY_TOKEN="${NTFY_TOKEN:-}"
NTFY_TOKEN_FILE="${NTFY_TOKEN_FILE:-}"

if [[ -z "$NTFY_TOKEN" && -n "$NTFY_TOKEN_FILE" && -f "$NTFY_TOKEN_FILE" ]]; then
  NTFY_TOKEN="$(cat "$NTFY_TOKEN_FILE")"
fi

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

if [[ -n "$BACKUP_STAMP" ]]; then
  if [[ ! -f "$BACKUP_STAMP" ]]; then
    failures+=("Backup success stamp missing")
  else
    now_epoch="$(date +%s)"
    stamp_epoch="$(stat -f %m "$BACKUP_STAMP" 2>/dev/null || stat -c %Y "$BACKUP_STAMP" 2>/dev/null || echo 0)"
    age_hours="$(((now_epoch - stamp_epoch) / 3600))"
    if (( age_hours > MAX_BACKUP_AGE_HOURS )); then
      failures+=("Backup is stale: ${age_hours}h > ${MAX_BACKUP_AGE_HOURS}h")
    fi
  fi
fi

if (( ${#failures[@]} > 0 )); then
  printf '%s\n' "${failures[@]}" >&2
  if [[ -n "$NTFY_URL" ]]; then
    alert_body="$(printf '%s\n' "${failures[@]}")"
    curl_args=(--fail --silent --show-error --max-time 8 -H "Title: 布布服务器告警" -H "Tags: warning,computer")
    if [[ -n "$NTFY_TOKEN" ]]; then
      curl_args+=(-H "Authorization: Bearer $NTFY_TOKEN")
    fi
    curl "${curl_args[@]}" --data-binary "$alert_body" "$NTFY_URL" >/dev/null || true
  fi
  exit 1
fi

echo "Bubu backend health OK"
