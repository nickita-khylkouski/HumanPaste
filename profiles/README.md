# Motor DNA (Consent-Based) Pipeline

This folder contains an R&D implementation for cloning a user's typing style from explicit calibration sessions.

## Safety boundary
- This is designed for consent-based calibration flows.
- Do not wire as covert/global keylogging.
- Default capture should focus on timing features. Plaintext capture is optional and should be minimized.

## Files
- `MotorDNAModels.swift`: event/profile schema + stats helpers.
- `MotorDNARecorder.swift`: session recorder (explicit consent token required).
- `MotorDNAAnalyzer.swift`: feature extraction + personalized calibration fitting.
- `MotorDNASelfTest.swift`: synthetic test that validates end-to-end profile generation.

## Features extracted
- Exact per-event timestamp (`tMs`) and key identity (`key`, `keyCode`) for calibration sessions.
- Dwell times and flight times.
- Digraph timings.
- Key travel distance (keyboard geometry proxy).
- Rollover rates (next key-down before previous key-up).
- Backspace/delete behavior rates.
- Pause tiers (<200ms, 200-2000ms, >2000ms).
- Long-gap exclusion for calibration (default excludes flight gaps >2000ms as likely idle/away time).

## Output
- `MotorDNAProfile` JSON including `personalizedCalibration`.
- Software team can map `personalizedCalibration` into `data/calibration.json` format for runtime.

## Local test
```bash
swiftc \
  HumanPaste/profiles/MotorDNAModels.swift \
  HumanPaste/profiles/MotorDNARecorder.swift \
  HumanPaste/profiles/MotorDNAAnalyzer.swift \
  HumanPaste/profiles/MotorDNASelfTest.swift \
  -o /tmp/motordna_selftest && /tmp/motordna_selftest
```

## Build a profile from sessions
```bash
swiftc \
  HumanPaste/profiles/MotorDNAModels.swift \
  HumanPaste/profiles/MotorDNARecorder.swift \
  HumanPaste/profiles/MotorDNAAnalyzer.swift \
  HumanPaste/profiles/MotorDNABuildProfile.swift \
  -o /tmp/motordna_build_profile

/tmp/motordna_build_profile \
  /tmp/motordna_profile.json \
  /path/to/session1.json /path/to/session2.json \
  --max-gap-ms 2000
```

## Start recorder (timing-only default)
```bash
HumanPaste/profiles/start_calibration_recorder.sh
```

- 4th arg controls content capture: `yes` to include characters, default `no`.
- Example: `HumanPaste/profiles/start_calibration_recorder.sh /tmp/session.json nickita consent-123 yes`


## Global timing logger (category-only)
```bash
HumanPaste/profiles/start_global_timing_logger.sh
# ... use Mac normally for a while ...
HumanPaste/profiles/stop_global_timing_logger.sh
python3 HumanPaste/profiles/summarize_global_timing_log.py HumanPaste/research/global_timing_log.ndjson
```

- Captures timestamp + event kind + coarse key category only.
- Does not store typed text or key labels.
- Requires Accessibility permission on first run.

### Logged categories
- `letter`, `number`, `symbol`, `whitespace`, `editing`, `navigation`, `modifier`, `function`, `unknown`, `idle`.
- Also logs `subCategory` when available (examples: `space`, `return`, `period_terminal`, `question_terminal`, `letter`, `digit`, arrows, etc).

### 3-level analysis output
```bash
python3 HumanPaste/profiles/analyze_typing_3levels.py \
  HumanPaste/research/global_timing_log.ndjson \
  HumanPaste/research/global_typing_3level_latest
```

Outputs:
- `global_typing_3level_latest.json`
- `global_typing_3level_latest.md`

Levels:
- Level 1: macro session behavior (counts, dwell stats, idle gaps).
- Level 2: per-word timing proxies (length, duration, cps, speed trend).
- Level 3: sentence/style proxies (sentence-length, punctuation boundary counts, sentence durations).

### More analysis scripts
- `analyze_timing_windows.py`: rolling-window trend detection (warmup/slowdown by window).
- `analyze_style_behavior.py`: correction rates, punctuation behavior, thirds-of-session drift.
- `analyze_pause_taxonomy.py`: pause bucket taxonomy (`motor_micro` vs thinking/away) and context around long gaps.
- `analyze_transition_dna.py`: transition matrix (`subcategory->subcategory`, `category->category`) with timing distributions.
- `analyze_stability_segments.py`: session segmentation for drift/stability/fatigue diagnostics.
- `analyze_bucket_expansion.py`: deeper bucketization (mode buckets, context buckets, word-position buckets).
- `analyze_clone_readiness.py`: what current data can infer vs what data to collect next (`--all` for cross-session readiness).
- `analyze_personal_typing_dna.py`: outputs direct recommended values for main engine knobs from all sessions.
- `analyze_collection_progress.py`: scores progress vs target coverage and ranks collection deficits.
- `generate_next_collection_mission.py`: creates the next best typing mission from progress output.
- `analyze_logger_quality.py`: validates logger capture quality (unknown/missing dwell/subcategory/keycode coverage, `--all` supported).
- `analyze_snapshot_trends.py`: longitudinal drift/stability across snapshot folders.
- `extract_global_timing_features.py`: transition and burst statistics for modeling.
- `export_training_rows.py`: event-level CSV for model fitting.

### One-command automation
```bash
HumanPaste/profiles/run_global_analysis_suite.sh \
  HumanPaste/research/global_timing_log.ndjson \
  HumanPaste/research/analysis_suite_latest \
  30000
```

### Continuous snapshots while logging
```bash
HumanPaste/profiles/auto_run_analysis_snapshots.sh \
  HumanPaste/research/global_timing_log.ndjson \
  HumanPaste/research/analysis_snapshots \
  60 \
  30000
```

### Supervisor mode (auto-restart if logger/snapshot loop dies)
```bash
HumanPaste/profiles/start_logging_with_auto_analysis.sh \
  HumanPaste/research/global_timing_log.ndjson \
  HumanPaste/research/analysis_snapshots \
  2000 \
  45 \
  30000 \
  8

HumanPaste/profiles/logging_status.sh
HumanPaste/profiles/stop_logging_with_auto_analysis.sh
```

### Collection Autopilot (recommended)
```bash
HumanPaste/profiles/run_collection_autopilot.sh \
  HumanPaste/research/global_timing_log.ndjson \
  HumanPaste/research/collection_autopilot_latest \
  30000
```

Outputs:
- full analysis suite
- progress score vs targets
- next mission plan
- snapshot trend report

### Launch At Login (fully automated)
```bash
# Install + auto-start on login, auto-restart if process exits
HumanPaste/profiles/install_launch_agent.sh \
  HumanPaste/research/global_timing_log.ndjson \
  HumanPaste/research/analysis_snapshots \
  2000 \
  45 \
  30000 \
  8

# Inspect launchd service
HumanPaste/profiles/launch_agent_status.sh

# Remove service
HumanPaste/profiles/uninstall_launch_agent.sh
```
