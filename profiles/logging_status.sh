#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

show_pid() {
  local label="$1"
  local pid_file="$2"
  if [ ! -f "$pid_file" ]; then
    echo "$label: not started"
    return
  fi
  local pid
  pid="$(cat "$pid_file" 2>/dev/null || true)"
  if [ -n "$pid" ] && ps -p "$pid" >/dev/null 2>&1; then
    echo "$label: running pid=$pid"
  else
    echo "$label: stale pid=$pid"
  fi
}

show_pid "supervisor" "$ROOT/research/logging_supervisor.pid"
show_pid "logger" "$ROOT/research/global_timing_logger.pid"
show_pid "snapshots" "$ROOT/research/analysis_snapshots.pid"

if [ -f "$ROOT/research/logging_supervisor.status" ]; then
  echo "--- supervisor heartbeat ---"
  cat "$ROOT/research/logging_supervisor.status"
fi

echo "--- latest snapshot ---"
if [ -d "$ROOT/research/analysis_snapshots" ]; then
  ls -1 "$ROOT/research/analysis_snapshots" | tail -n 1
fi
