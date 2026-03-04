#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LOG_PATH="${1:-$ROOT/research/global_timing_log.ndjson}"
OUT_DIR="${2:-$ROOT/research/collection_autopilot_latest}"
WINDOW_MS="${3:-30000}"

mkdir -p "$OUT_DIR"

# 1) Full analysis suite
"$ROOT/profiles/run_global_analysis_suite.sh" "$LOG_PATH" "$OUT_DIR/analysis_suite" "$WINDOW_MS" > "$OUT_DIR/analysis_suite.log" 2>&1

# 2) Progress against collection targets
python3 "$ROOT/profiles/analyze_collection_progress.py" "$LOG_PATH" "$OUT_DIR/collection_progress" > "$OUT_DIR/collection_progress.log" 2>&1

# 3) Next mission plan
python3 "$ROOT/profiles/generate_next_collection_mission.py" \
  "$OUT_DIR/collection_progress.json" \
  "$OUT_DIR/next_mission" > "$OUT_DIR/next_mission.log" 2>&1

# 4) Snapshot drift report
python3 "$ROOT/profiles/analyze_snapshot_trends.py" \
  "$ROOT/research/analysis_snapshots" \
  "$OUT_DIR/snapshot_trends" > "$OUT_DIR/snapshot_trends.log" 2>&1 || true

cat > "$OUT_DIR/README.txt" <<TXT
Collection autopilot outputs
- analysis_suite/ (full timing + clone reports)
- collection_progress.json
- collection_progress.md
- next_mission.json
- next_mission.md
- snapshot_trends.json
- snapshot_trends.md

Source log: $LOG_PATH
Window ms: $WINDOW_MS
Generated at: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
TXT

echo "collection autopilot complete"
echo "- out_dir: $OUT_DIR"
