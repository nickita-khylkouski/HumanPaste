#!/bin/bash
set -e
cd "$(dirname "$0")"
pkill -f HumanPaste 2>/dev/null || true
sleep 0.3
swiftc -framework Cocoa -framework Carbon -framework SwiftUI -o HumanPaste.app/Contents/MacOS/HumanPaste \
  KeyboardLayout.swift \
  TimingModel.swift \
  ErrorModel.swift \
  KeystrokeEmitter.swift \
  HumanTyper.swift \
  SettingsView.swift \
  main.swift \
  prototypes/UncertaintyTypes.swift \
  prototypes/UncertaintyConfig.swift \
  prototypes/PredictionProvider.swift \
  prototypes/FalseStartPlanner.swift \
  prototypes/CursorEditPlanner.swift \
  prototypes/BoundaryTokenizer.swift \
  prototypes/UncertaintyEngine.swift
# Try persistent cert first, fall back to ad-hoc
if security find-identity -v -p codesigning 2>/dev/null | grep -q "HumanPaste Dev"; then
    codesign --force --sign "HumanPaste Dev" --identifier com.humanpaste.app HumanPaste.app/Contents/MacOS/HumanPaste
else
    codesign --force --sign - --identifier com.humanpaste.app HumanPaste.app/Contents/MacOS/HumanPaste
fi
echo "Built and signed. Launching..."
open HumanPaste.app
