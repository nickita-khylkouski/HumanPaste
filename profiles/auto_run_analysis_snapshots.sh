#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LOG_PATH="${1:-$ROOT/research/global_timing_log.ndjson}"
SNAP_ROOT="${2:-$ROOT/research/analysis_snapshots}"
INTERVAL_SEC="${3:-60}"
WINDOW_MS="${4:-30000}"

mkdir -p "$SNAP_ROOT"

echo "snapshot loop started"
echo "- log: $LOG_PATH"
echo "- interval_sec: $INTERVAL_SEC"

while true; do
  TS="$(date +"%Y%m%d_%H%M%S")"
  OUT_DIR="$SNAP_ROOT/$TS"
  mkdir -p "$OUT_DIR"

  if [ -s "$LOG_PATH" ]; then
    if "$ROOT/profiles/run_global_analysis_suite.sh" "$LOG_PATH" "$OUT_DIR" "$WINDOW_MS" >"$OUT_DIR/run.log" 2>&1; then
      echo "ok $(date -u +"%Y-%m-%dT%H:%M:%SZ")" > "$OUT_DIR/STATUS.txt"
    else
      echo "error $(date -u +"%Y-%m-%dT%H:%M:%SZ")" > "$OUT_DIR/STATUS.txt"
    fi
  else
    echo "no-log $(date -u +"%Y-%m-%dT%H:%M:%SZ")" > "$OUT_DIR/STATUS.txt"
  fi

  sleep "$INTERVAL_SEC"
done
