#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LOG_PATH="${1:-$ROOT/research/global_timing_log.ndjson}"
OUT_DIR="${2:-$ROOT/research/analysis_suite_latest}"
WINDOW_MS="${3:-30000}"

mkdir -p "$OUT_DIR"

python3 "$ROOT/profiles/summarize_global_timing_log.py" "$LOG_PATH" > "$OUT_DIR/summary_latest.txt" 2>&1
python3 "$ROOT/profiles/summarize_global_timing_log.py" "$LOG_PATH" --all > "$OUT_DIR/summary_all.txt" 2>&1
python3 "$ROOT/profiles/extract_global_timing_features.py" "$LOG_PATH" "$OUT_DIR/features.json" > "$OUT_DIR/features.log" 2>&1
python3 "$ROOT/profiles/analyze_typing_3levels.py" "$LOG_PATH" "$OUT_DIR/typing_3levels" > "$OUT_DIR/typing_3levels.log" 2>&1
python3 "$ROOT/profiles/analyze_timing_windows.py" "$LOG_PATH" "$OUT_DIR/timing_windows" --window-ms "$WINDOW_MS" > "$OUT_DIR/timing_windows.log" 2>&1
python3 "$ROOT/profiles/analyze_style_behavior.py" "$LOG_PATH" "$OUT_DIR/style_behavior" > "$OUT_DIR/style_behavior.log" 2>&1
python3 "$ROOT/profiles/analyze_pause_taxonomy.py" "$LOG_PATH" "$OUT_DIR/pause_taxonomy" > "$OUT_DIR/pause_taxonomy.log" 2>&1
python3 "$ROOT/profiles/analyze_transition_dna.py" "$LOG_PATH" "$OUT_DIR/transition_dna" > "$OUT_DIR/transition_dna.log" 2>&1
python3 "$ROOT/profiles/analyze_stability_segments.py" "$LOG_PATH" "$OUT_DIR/stability_segments" > "$OUT_DIR/stability_segments.log" 2>&1
python3 "$ROOT/profiles/analyze_bucket_expansion.py" "$LOG_PATH" "$OUT_DIR/bucket_expansion" > "$OUT_DIR/bucket_expansion.log" 2>&1
python3 "$ROOT/profiles/analyze_clone_readiness.py" "$LOG_PATH" "$OUT_DIR/clone_readiness" > "$OUT_DIR/clone_readiness.log" 2>&1
python3 "$ROOT/profiles/analyze_clone_readiness.py" "$LOG_PATH" "$OUT_DIR/clone_readiness_all" --all > "$OUT_DIR/clone_readiness_all.log" 2>&1
python3 "$ROOT/profiles/analyze_personal_typing_dna.py" "$LOG_PATH" "$OUT_DIR/personal_typing_dna" > "$OUT_DIR/personal_typing_dna.log" 2>&1
python3 "$ROOT/profiles/analyze_collection_progress.py" "$LOG_PATH" "$OUT_DIR/collection_progress" > "$OUT_DIR/collection_progress.log" 2>&1
python3 "$ROOT/profiles/generate_next_collection_mission.py" "$OUT_DIR/collection_progress.json" "$OUT_DIR/next_mission" > "$OUT_DIR/next_mission.log" 2>&1
python3 "$ROOT/profiles/analyze_logger_quality.py" "$LOG_PATH" "$OUT_DIR/logger_quality" > "$OUT_DIR/logger_quality.log" 2>&1
python3 "$ROOT/profiles/analyze_logger_quality.py" "$LOG_PATH" "$OUT_DIR/logger_quality_all" --all > "$OUT_DIR/logger_quality_all.log" 2>&1
python3 "$ROOT/profiles/export_training_rows.py" "$LOG_PATH" "$OUT_DIR/training_rows.csv" > "$OUT_DIR/training_rows.log" 2>&1

cat > "$OUT_DIR/README.txt" <<TXT
Global analysis suite outputs
- summary_latest.txt
- summary_all.txt
- features.json
- typing_3levels.json
- typing_3levels.md
- timing_windows.json
- timing_windows.md
- style_behavior.json
- style_behavior.md
- pause_taxonomy.json
- pause_taxonomy.md
- transition_dna.json
- transition_dna.md
- stability_segments.json
- stability_segments.md
- bucket_expansion.json
- bucket_expansion.md
- clone_readiness.json
- clone_readiness.md
- clone_readiness_all.json
- clone_readiness_all.md
- personal_typing_dna.json
- personal_typing_dna.md
- collection_progress.json
- collection_progress.md
- next_mission.json
- next_mission.md
- logger_quality.json
- logger_quality.md
- logger_quality_all.json
- logger_quality_all.md
- training_rows.csv

Source log: $LOG_PATH
Window ms: $WINDOW_MS
Generated at: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
TXT

echo "analysis suite complete"
echo "- out_dir: $OUT_DIR"
