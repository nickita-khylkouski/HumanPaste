#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:-$ROOT/research/global_timing_log.ndjson}"
IDLE_GAP_MS="${2:-2000}"

swiftc \
  "$ROOT/profiles/GlobalTimingLoggerModels.swift" \
  "$ROOT/profiles/GlobalTimingLoggerApp.swift" \
  -framework Cocoa \
  -o /tmp/humanpaste_global_timing_logger

nohup /tmp/humanpaste_global_timing_logger \
  --out "$OUT" \
  --idle-gap-ms "$IDLE_GAP_MS" \
  > "$ROOT/research/global_timing_logger.log" 2>&1 &

echo $! > "$ROOT/research/global_timing_logger.pid"
echo "started pid=$(cat "$ROOT/research/global_timing_logger.pid") out=$OUT"
