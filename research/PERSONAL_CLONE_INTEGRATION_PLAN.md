# Personal Clone Integration Plan (Main Engine)

Date: 2026-03-02
Source reports:
- `HumanPaste/research/analysis_suite_latest/personal_typing_dna.json`
- `HumanPaste/research/snapshot_trends_latest.json`

## 1) Your Current Typing DNA (from all sessions)
- Session coverage: 9 sessions, ~3.1k key-down events.
- Strong stable baselines:
  - letter dwell p50: ~69ms
  - letter->letter flight p50: ~104-119ms (snapshot range)
  - space dwell p50: ~60ms
- Rhythm profile:
  - motor micro transitions: ~88-93%
  - pause distribution supports moderate pause intensity, not heavy
- Boundary asymmetry:
  - word-end (`letter->space`) faster than word-start (`space->letter`)

## 2) Recommended Main App Values Right Now
Use these as the default profile for your machine:

```json
{
  "wpm": 162,
  "pausePct": 31,
  "typoPct": 24,
  "flightCapMs": 244,
  "thinkCapMs": 801,
  "initialDelayMs": 120,
  "correctionSpeed": 60,
  "burstWords": 8,
  "uncertaintyEnabled": false,
  "falseStartMax": 1,
  "cursorEditMax": 0
}
```

Range safety if you want less volatility:
- `wpm`: 150-165
- `pausePct`: 28-35
- `typoPct`: 16-25
- `flightCapMs`: 235-255
- `thinkCapMs`: 750-1100
- `burstWords`: 6-8

## 3) Where To Apply In Main Engine
Code touchpoints:
- Defaults in AppDelegate config:
  - `HumanPaste/main.swift:565` through `:575`
- Runtime mapping of those knobs into engine:
  - `HumanPaste/main.swift:590` through `:636`
- Calibration knobs for timing model:
  - `HumanPaste/TimingModel.swift:16` through `:53`
- Flight/dwell and context timing functions:
  - `HumanPaste/TimingModel.swift:159` through `:247`
- Core runtime behavior (fatigue, pauses, burst, typo execution):
  - `HumanPaste/HumanTyper.swift:85` through `:309`

## 4) Required Main-Engine Changes For Better “Looks Like Me”
1. Add per-user profile load before defaults.
- In `AppDelegate.applicationDidFinishLaunching`, load `data/user_profile.json` and override config state before `applyAll()`.

2. Add boundary-specific timing multipliers to calibration.
- Extend `TypingCalibration` with:
  - `wordEndMultiplier`
  - `wordMiddleMultiplier`
  - `spaceToLetterMultiplier`
- Use these in `computeFlightTime` (`TimingModel.swift`) so your measured boundary asymmetry is explicit.

3. Add correction behavior parameters (not just rate).
- Add:
  - `correctionNoticeAlphaMs`
  - `correctionBackspaceAlphaMs`
  - `correctionReentryAlphaMs`
- Wire into typo execution in `HumanTyper.executeError(...)`.

4. Add per-user burst profile.
- Store `burstWordsMean` + `burstWordsStd`.
- Replace current random burst span with sampled value centered on your measured burst.

5. Keep punctuation model separate until data is richer.
- Keep defaults for punctuation pauses today.
- Auto-promote punctuation profile only after coverage threshold (e.g. 80+ punctuation key-downs).

## 5) Data Collection Gaps Blocking Perfect Clone
- Punctuation usage still low for robust punctuation timing model.
- Navigation/edit behavior still sparse.
- Need more correction loops for high-fidelity typo-recovery modeling.

## 6) Operational Setup (R&D)
- Logger + analysis are now scriptable with supervisor tooling:
  - `HumanPaste/profiles/start_logging_with_auto_analysis.sh`
  - `HumanPaste/profiles/logging_status.sh`
  - `HumanPaste/profiles/stop_logging_with_auto_analysis.sh`
- Personal profile exporter:
  - `HumanPaste/profiles/analyze_personal_typing_dna.py`

## 7) Immediate Next Commit for Main Team
Small safe PR:
1. Change AppDelegate defaults to recommended values.
2. Add user profile load path (`data/user_profile.json`).
3. Keep runtime behavior unchanged otherwise.

Second PR:
1. Boundary/correction multiplier extensions in `TypingCalibration`.
2. Wire those into `computeFlightTime` and `executeError`.
