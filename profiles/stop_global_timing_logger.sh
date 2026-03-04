#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PID_FILE="$ROOT/research/global_timing_logger.pid"

if [ ! -f "$PID_FILE" ]; then
  echo "no pid file"
  exit 0
fi

PID="$(cat "$PID_FILE")"
if ps -p "$PID" >/dev/null 2>&1; then
  kill "$PID"
  sleep 0.5
  if ps -p "$PID" >/dev/null 2>&1; then
    kill -9 "$PID" || true
  fi
  echo "stopped pid=$PID"
else
  echo "pid not running: $PID"
fi

rm -f "$PID_FILE"
