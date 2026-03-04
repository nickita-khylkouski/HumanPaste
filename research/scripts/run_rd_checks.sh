#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

echo "[1/2] Calibration validation"
python3 research/scripts/validate_engine_calibration.py

echo "[2/2] Uncertainty integrity self-test"
swiftc \
  prototypes/UncertaintyTypes.swift \
  prototypes/UncertaintyConfig.swift \
  prototypes/BoundaryTokenizer.swift \
  prototypes/FalseStartPlanner.swift \
  prototypes/CursorEditPlanner.swift \
  prototypes/PredictionProvider.swift \
  prototypes/UncertaintyEngine.swift \
  prototypes/UncertaintySelfTest.swift \
  -o /tmp/humanpaste_uncertainty_selftest

/tmp/humanpaste_uncertainty_selftest

echo "RD checks: PASS"
