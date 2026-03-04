#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:-$ROOT/research/motordna_session_live.json}"
USER_ID="${2:-nickita}"
CONSENT="${3:-consent-$(date +%s)}"
CAPTURE_CONTENT="${4:-no}"  # yes|no
EXTRA_ARGS=()
if [ "$CAPTURE_CONTENT" != "yes" ]; then
  EXTRA_ARGS+=(--no-content)
fi

swiftc \
  "$ROOT/profiles/MotorDNAModels.swift" \
  "$ROOT/profiles/MotorDNARecorder.swift" \
  "$ROOT/profiles/CalibrationRecorderApp.swift" \
  -framework Cocoa \
  -o /tmp/humanpaste_calibration_recorder

/tmp/humanpaste_calibration_recorder \
  --out "$OUT" \
  --user "$USER_ID" \
  --consent "$CONSENT" \
  "${EXTRA_ARGS[@]}"
