#!/usr/bin/env bash
set -euo pipefail

LABEL="com.humanpaste.collector"

if launchctl print "gui/$(id -u)/$LABEL" >/tmp/humanpaste_launchd_status.txt 2>&1; then
  echo "launch agent: loaded ($LABEL)"
  sed -n '1,60p' /tmp/humanpaste_launchd_status.txt
else
  echo "launch agent: not loaded ($LABEL)"
  cat /tmp/humanpaste_launchd_status.txt
fi
