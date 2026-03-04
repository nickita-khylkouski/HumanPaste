#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

stop_pid_file() {
  local pid_file="$1"
  if [ -f "$pid_file" ]; then
    local pid
    pid="$(cat "$pid_file")"
    if ps -p "$pid" >/dev/null 2>&1; then
      kill "$pid" || true
      sleep 0.4
      if ps -p "$pid" >/dev/null 2>&1; then
        kill -9 "$pid" || true
      fi
      echo "stopped pid=$pid"
    fi
    rm -f "$pid_file"
  fi
}

stop_pid_file "$ROOT/research/logging_supervisor.pid"
stop_pid_file "$ROOT/research/analysis_snapshots.pid"
stop_pid_file "$ROOT/research/global_timing_logger.pid"

echo "done"
