# HumanPaste R&D GitHub Competitor Scan (2026-03-02)

## Scope
- Request: find other GitHub projects similar to HumanPaste (clipboard text replayed as human-like typing), then hand off R&D findings.
- Constraint honored: no changes to `main.swift` or existing production implementation in this step.

## Confirmed Similar Repos

1. ArbenP/TypeClipboard
- Link: https://github.com/ArbenP/TypeClipboard
- What it does: macOS app that types clipboard content as keystrokes; countdown, per-char delay, cancel, accessibility permission flow.
- Signals: Swift app, releases available, active as of Feb 15, 2026 (`v1.0.1`).

2. aashish-shukla/Autotyper-for-MacOS
- Link: https://github.com/aashish-shukla/Autotyper-for-MacOS
- What it does: Python macOS clipboard autotyper with speed modes and Gaussian timing.
- Gap vs us: Python dependency stack; Gaussian timing (less realistic than heavy-tail models).

3. krish-199/clipboard-type
- Link: https://github.com/krish-199/clipboard-type
- What it does: Raycast extension to type clipboard content where paste is blocked.
- Gap vs us: extension scope; less emphasis on deep timing model.

4. andresharpe/ClipboardTextTyper
- Link: https://github.com/andresharpe/ClipboardTextTyper
- What it does: AutoHotkey script for Windows; types clipboard text instead of paste.
- Gap vs us: Windows-only script, not native macOS.

5. GitLitAF/Auto-Type
- Link: https://github.com/GitLitAF/Auto-Type
- What it does: Google Docs userscript simulating human typing with profiles and corrections.
- Gap vs us: browser/userscript context only, not system-wide macOS typing.

6. shreeratn/human-typing-simulation
- Link: https://github.com/shreeratn/human-typing-simulation
- What it does: Python clipboard-to-typing simulator with basic delay randomness.
- Gap vs us: lightweight script, limited biometric realism.

7. Lax3n/HumanTyping
- Link: https://github.com/Lax3n/HumanTyping
- What it does: human typing simulator project (small footprint).
- Gap vs us: lower maturity/feature depth.

8. JamoCA gist (EmulateTyping.ahk)
- Link: https://gist.github.com/JamoCA/1d6d4a14b3ccfd9b3a0bf94db0c447ed
- What it does: Ctrl+Shift+V clipboard typing in AutoHotkey with random sleep buckets.
- Gap vs us: gist-level script; basic delay model.

## Competitive Read (Quick)
- Most alternatives are script-level (`pyautogui`, AutoHotkey, user scripts).
- Many have adjustable speed and hotkeys, but timing models are simplistic (uniform/Gaussian buckets).
- A newer direct macOS competitor exists (`TypeClipboard`) with strong packaging and clean UX.

## What We Should Copy Fast (1 sprint)
1. Distribution and packaging quality
- Stable `.app` release flow and simple first-run permission UX.

2. User-facing controls
- Clear countdown + per-char delay + quick cancel + explicit mode labels.

3. Reliability UX
- Visible status banners when accessibility permissions are missing.

## What We Should Differentiate On (core moat)
1. Biometric realism engine
- Keep heavy-tail dwell/flight modeling and per-digraph/finger behavior as core differentiator.

2. Personal calibration
- Offer optional user recording + profile calibration (their own typing dynamics).

3. Uncertainty behaviors
- Controlled false-start/backspace/cursor-revision patterns with exact final-text integrity checks.

## Engineering Hand-off (No code touched in this step)
- Track A (Product parity): package/release polish, settings clarity, onboarding.
- Track B (Moat): personalized timing calibration and evaluation metrics.
- Track C (Validation): A/B test generated traces vs recorded user traces on dwell/flight/n-graph distributions.

## Sources
- https://github.com/ArbenP/TypeClipboard
- https://github.com/aashish-shukla/Autotyper-for-MacOS
- https://github.com/krish-199/clipboard-type
- https://github.com/andresharpe/ClipboardTextTyper
- https://github.com/GitLitAF/Auto-Type
- https://github.com/shreeratn/human-typing-simulation
- https://github.com/Lax3n/HumanTyping
- https://gist.github.com/JamoCA/1d6d4a14b3ccfd9b3a0bf94db0c447ed
