# HumanPaste R&D Master Plan

Date: March 2, 2026
Mode: R&D only (new files, no edits to existing implementation files)

## 1) Executive Summary
HumanPaste has a clear product opening:
- Browser-only tools are common; high-quality macOS system-wide tools are rare.
- Existing competitors mostly market outcomes, not measurable realism.
- A dataset-backed timing model is a credible moat if it is tested and documented.

This package provides 5 parallel R&D tracks plus one unified execution path for software engineering.

## 2) What We Produced
- Competitor analysis: `HumanPaste/research/competitors_landscape.md`
- Dataset + calibration pipeline: `HumanPaste/research/datasets_and_calibration.md`
- Download/analyze script: `HumanPaste/research/scripts/download_and_analyze_dataset.py`
- Generated calibration: `HumanPaste/research/calibration_output.json`
- V3 architecture proposal: `HumanPaste/research/v3_engine_architecture.md`
- Risk/policy strategy: `HumanPaste/research/risk_and_policy_strategy.md`
- Experiment/KPI framework: `HumanPaste/research/experiments_and_metrics.md`

## 3) Key Findings (Cross-Track Synthesis)
### 3.1 Competitor and Product Positioning
- Closest commercial pressure is low-cost one-time or low-friction extension tooling.
- Most competitors are browser-scoped or bundled into larger anti-detect stacks.
- Strategic gap: a native, focused, measurable realism product with transparent benchmarks.

### 3.2 Dataset Findings (CMU DSL Keystroke Dataset)
Dataset used:
- URL: `http://www.cs.cmu.edu/~keystroke/DSL-StrongPasswordData.csv`
- Rows: `20,400`
- Subjects: `51`

Extracted timing summary:
- Dwell median: `0.0861s` (86.1ms)
- Dwell beta estimate (log-logistic): `5.09`
- Flight (DD) median: `0.1911s` (191.1ms)
- Flight (DD) beta estimate (log-logistic): `2.58`

Important caveat:
- `UD` includes negative values in this dataset; use `DD` for key-down interval modeling and treat `UD` as secondary signal.

### 3.3 Architecture Direction
Strong recommendation from architecture track:
- Split planning, timing, schedule compilation, and event emission.
- Move away from monolithic loop to testable scheduling pipeline.
- Keep app hotkey/menu layer thin; put behavior in engine modules.

### 3.4 Risk/Policy Direction
Must-have for launch safety:
- Explicit acceptable-use policy and anti-abuse positioning.
- Clear on-device indicator and emergency stop behavior.
- Conservative defaults and rate controls.

## 4) Parameter Baseline for Engineering Team (From Dataset)
Use this as initial v3 default profile (not final):
- `flight_alpha_ms = 191`
- `flight_beta = 2.58`
- `dwell_alpha_ms = 86`
- `dwell_beta = 5.09`
- `rollover_target_rate = 0.20 to 0.30` (validate in harness, not static)

Initial safety clamps:
- Dwell bounds: `25ms to 550ms`
- Flight bounds (DD): `18ms to 2500ms`

## 5) Engineering Handoff Sequence (Implementation Order)
1. Engine decomposition
- Implement modules per `v3_engine_architecture.md`.
- Preserve existing external app controls (`typeText`, `cancel`, callbacks).

2. Timing model integration
- Add calibration loader consuming JSON schema produced by `calibration_output.json`.
- Replace ad-hoc per-key delays with log-logistic sampler.

3. Event scheduler upgrade
- Represent each keystroke as explicit `keyDown` and `keyUp` schedule events.
- Add rollover decision path with ordering assertions.

4. Benchmark harness
- Implement Track-5 harness and baseline reports before enabling new defaults.
- Gate rollout by statistical criteria (not visual “looks human” judgment).

5. Progressive rollout
- Ship behind profile flag (`v2_legacy`, `v3_research`, `v3_default_candidate`).
- Promote only after two consecutive passing benchmark cycles.

## 6) Weekly R&D + Engineering Rhythm
- Monday: review prior benchmark report; lock experiments for week.
- Tuesday-Wednesday: implement one experiment lane.
- Thursday: run full benchmark matrix and detector checks.
- Friday: ship/no-ship decision using KPI thresholds from Track 5.

## 7) Open Questions for Next R&D Cycle
- Add a second open dataset to reduce single-corpus bias.
- Separate model families by context: short form vs long-form prose.
- Determine whether per-user calibration should be opt-in default or advanced mode.

## 8) Immediate Next Action
Software engineering team can start directly from:
- `HumanPaste/research/v3_engine_architecture.md` (implementation blueprint)
- `HumanPaste/research/calibration_output.json` (initial data priors)
- `HumanPaste/research/experiments_and_metrics.md` (acceptance gates)
