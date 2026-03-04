#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LABEL="com.humanpaste.collector"
PLIST_DIR="$HOME/Library/LaunchAgents"
PLIST_PATH="$PLIST_DIR/$LABEL.plist"

LOG_PATH="${1:-$ROOT/research/global_timing_log.ndjson}"
SNAP_ROOT="${2:-$ROOT/research/analysis_snapshots}"
IDLE_GAP_MS="${3:-2000}"
INTERVAL_SEC="${4:-45}"
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

mkdir -p "$PLIST_DIR" "$ROOT/research" "$SNAP_ROOT"

cat > "$PLIST_PATH" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>$LABEL</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/bash</string>
    <string>$ROOT/profiles/run_logging_supervisor.sh</string>
    <string>$LOG_PATH</string>
    <string>$SNAP_ROOT</string>
    <string>$IDLE_GAP_MS</string>
    <string>$INTERVAL_SEC</string>
    <string>$WINDOW_MS</string>
    <string>$CHECK_SEC</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
  <key>StandardOutPath</key>
  <string>$ROOT/research/launchd_supervisor.out.log</string>
  <key>StandardErrorPath</key>
  <string>$ROOT/research/launchd_supervisor.err.log</string>
</dict>
</plist>
EOF

launchctl bootout "gui/$(id -u)/$LABEL" >/dev/null 2>&1 || true
launchctl bootstrap "gui/$(id -u)" "$PLIST_PATH"
launchctl kickstart -k "gui/$(id -u)/$LABEL"

echo "installed launch agent"
echo "- plist: $PLIST_PATH"
echo "- label: $LABEL"
echo "- log_path: $LOG_PATH"
echo "- snapshots: $SNAP_ROOT"
echo "check with:"
echo "  launchctl print gui/$(id -u)/$LABEL | head -n 40"
