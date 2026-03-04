#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LOG_PATH="${1:-$ROOT/research/global_timing_log.ndjson}"
SNAP_ROOT="${2:-$ROOT/research/analysis_snapshots}"
IDLE_GAP_MS="${3:-2000}"
INTERVAL_SEC="${4:-60}"
WINDOW_MS="${5:-30000}"
CHECK_SEC="${6:-8}"

to_abs() {
  local p="$1"
  if [[ "$p" = /* ]]; then
    printf "%s" "$p"
  else
    printf "%s/%s" "$(pwd)" "$p"
  fi
}

LOG_PATH="$(to_abs "$LOG_PATH")"
SNAP_ROOT="$(to_abs "$SNAP_ROOT")"

mkdir -p "$ROOT/research" "$SNAP_ROOT"

if [ -f "$ROOT/research/logging_supervisor.pid" ]; then
  OLD_PID="$(cat "$ROOT/research/logging_supervisor.pid" 2>/dev/null || true)"
  if [ -n "${OLD_PID:-}" ] && ps -p "$OLD_PID" >/dev/null 2>&1; then
    echo "already running supervisor pid=$OLD_PID"
    exit 0
  fi
fi

nohup "$ROOT/profiles/run_logging_supervisor.sh" \
  "$LOG_PATH" \
  "$SNAP_ROOT" \
  "$IDLE_GAP_MS" \
  "$INTERVAL_SEC" \
  "$WINDOW_MS" \
  "$CHECK_SEC" \
  > "$ROOT/research/logging_supervisor.log" 2>&1 &
SUP_PID=$!
echo "$SUP_PID" > "$ROOT/research/logging_supervisor.pid"

sleep 0.8
LOGGER_PID="$(cat "$ROOT/research/global_timing_logger.pid" 2>/dev/null || true)"
AUTO_PID="$(cat "$ROOT/research/analysis_snapshots.pid" 2>/dev/null || true)"

echo "started"
echo "- supervisor_pid=$SUP_PID"
echo "- logger_pid=${LOGGER_PID:-unknown}"
echo "- auto_pid=${AUTO_PID:-unknown}"
echo "- log=$LOG_PATH"
echo "- snapshots=$SNAP_ROOT"
