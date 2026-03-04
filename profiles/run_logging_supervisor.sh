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

LOGGER_BIN="/tmp/humanpaste_global_timing_logger"
LOGGER_LOG="$ROOT/research/global_timing_logger.log"
AUTO_LOG="$ROOT/research/analysis_snapshots.log"
STATUS_FILE="$ROOT/research/logging_supervisor.status"

compile_logger() {
  swiftc \
    "$ROOT/profiles/GlobalTimingLoggerModels.swift" \
    "$ROOT/profiles/GlobalTimingLoggerApp.swift" \
    -framework Cocoa \
    -o "$LOGGER_BIN"
}

is_pid_running() {
  local pid="$1"
  [ -n "$pid" ] && ps -p "$pid" >/dev/null 2>&1
}

start_logger() {
  nohup "$LOGGER_BIN" \
    --out "$LOG_PATH" \
    --idle-gap-ms "$IDLE_GAP_MS" \
    >> "$LOGGER_LOG" 2>&1 &
  LOGGER_PID=$!
  echo "$LOGGER_PID" > "$ROOT/research/global_timing_logger.pid"
}

start_auto() {
  nohup "$ROOT/profiles/auto_run_analysis_snapshots.sh" \
    "$LOG_PATH" \
    "$SNAP_ROOT" \
    "$INTERVAL_SEC" \
    "$WINDOW_MS" \
    >> "$AUTO_LOG" 2>&1 &
  AUTO_PID=$!
  echo "$AUTO_PID" > "$ROOT/research/analysis_snapshots.pid"
}

shutdown_children() {
  for pid in "${AUTO_PID:-}" "${LOGGER_PID:-}"; do
    if is_pid_running "$pid"; then
      kill "$pid" >/dev/null 2>&1 || true
      sleep 0.2
      if is_pid_running "$pid"; then
        kill -9 "$pid" >/dev/null 2>&1 || true
      fi
    fi
  done
}

trap 'shutdown_children; rm -f "$ROOT/research/global_timing_logger.pid" "$ROOT/research/analysis_snapshots.pid"; exit 0' INT TERM EXIT

compile_logger
LOGGER_PID=""
AUTO_PID=""
start_logger
start_auto

while true; do
  if ! is_pid_running "${LOGGER_PID:-}"; then
    start_logger
  fi
  if ! is_pid_running "${AUTO_PID:-}"; then
    start_auto
  fi

  printf "ts=%s logger_pid=%s auto_pid=%s\n" \
    "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
    "${LOGGER_PID:-}" \
    "${AUTO_PID:-}" > "$STATUS_FILE"

  sleep "$CHECK_SEC"
done
