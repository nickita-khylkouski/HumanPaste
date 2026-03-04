#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT_DIR="$ROOT/research"
mkdir -p "$OUT_DIR"

swiftc \
  "$ROOT/profiles/MotorDNAModels.swift" \
  "$ROOT/profiles/MotorDNARecorder.swift" \
  "$ROOT/profiles/MotorDNAAnalyzer.swift" \
  "$ROOT/profiles/MotorDNASelfTest.swift" \
  -o /tmp/motordna_selftest

/tmp/motordna_selftest

cat > /tmp/motordna_session_example.json <<'JSON'
{
  "meta": {
    "sessionId": "example-1",
    "createdAtISO8601": "2026-03-02T23:55:00Z",
    "userId": "example-user",
    "consentToken": "consent-example",
    "captureContent": true,
    "appContext": "TextEdit",
    "promptId": "calib-001",
    "promptText": "the quick brown fox"
  },
  "events": [
    {"tMs": 0, "kind": "keyDown", "key": "t", "character": "t", "app": "TextEdit", "cursorIndex": 0},
    {"tMs": 92, "kind": "keyUp", "key": "t", "character": "t", "app": "TextEdit", "cursorIndex": 1},
    {"tMs": 190, "kind": "keyDown", "key": "h", "character": "h", "app": "TextEdit", "cursorIndex": 1},
    {"tMs": 294, "kind": "keyUp", "key": "h", "character": "h", "app": "TextEdit", "cursorIndex": 2},
    {"tMs": 390, "kind": "keyDown", "key": "e", "character": "e", "app": "TextEdit", "cursorIndex": 2},
    {"tMs": 488, "kind": "keyUp", "key": "e", "character": "e", "app": "TextEdit", "cursorIndex": 3},
    {"tMs": 580, "kind": "keyDown", "key": "space", "character": " ", "app": "TextEdit", "cursorIndex": 3},
    {"tMs": 650, "kind": "keyUp", "key": "space", "character": " ", "app": "TextEdit", "cursorIndex": 4}
  ]
}
JSON

swiftc \
  "$ROOT/profiles/MotorDNAModels.swift" \
  "$ROOT/profiles/MotorDNARecorder.swift" \
  "$ROOT/profiles/MotorDNAAnalyzer.swift" \
  "$ROOT/profiles/MotorDNABuildProfile.swift" \
  -o /tmp/motordna_build_profile

/tmp/motordna_build_profile "$OUT_DIR/motordna_profile_example.json" /tmp/motordna_session_example.json

echo "Wrote profile: $OUT_DIR/motordna_profile_example.json"
