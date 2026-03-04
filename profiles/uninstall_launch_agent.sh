#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LABEL="com.humanpaste.collector"
PLIST_PATH="$HOME/Library/LaunchAgents/$LABEL.plist"

launchctl bootout "gui/$(id -u)/$LABEL" >/dev/null 2>&1 || true

if [ -f "$PLIST_PATH" ]; then
  rm "$PLIST_PATH"
fi

"$ROOT/profiles/stop_logging_with_auto_analysis.sh" >/dev/null 2>&1 || true

echo "uninstalled launch agent"
echo "- label: $LABEL"
echo "- plist removed: $PLIST_PATH"
