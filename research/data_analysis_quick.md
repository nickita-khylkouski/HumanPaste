# Quick Data Analysis (CMU DSL)

## What matters
- Dataset size: 20,400 rows, 51 subjects.
- Dwell (`H.*`) is clean and positive.
- `UD.*` has negatives (about 10.84%), so don't use `UD` directly for lower-bound flight calibration.
- `DD.*` is clean positive flight timing and should be the primary flight source.

## Key stats
- Dwell median: 86.1 ms
- Dwell p05/p95: 49.3 ms / 144.8 ms
- Dwell fit (log-logistic): alpha=86.1 ms, beta=5.090282

- Flight DD median: 191.1 ms
- Flight DD p05/p95: 77.9 ms / 602.1 ms
- Flight DD trimmed (p01..p99) p05/p95: 81.6 ms / 568.4 ms
- Flight DD trimmed fit (log-logistic): alpha=191.1 ms, beta=2.638225

## Why v2 script is better
- Prevents bad downloads (rejects HTML/login pages).
- Separates DD and UD instead of combining them.
- Reports UD negative fraction explicitly.
- Trims DD outliers (p01..p99) before fit.
- Emits direct engine params in ms and beta.

## Recommended defaults to ship first
- dwell_alpha_ms: 86.1
- dwell_beta: 5.090282
- flight_alpha_ms: 191.1
- flight_beta: 2.638225
- dwell clamp: 49.3 ms to 144.8 ms (or wider runtime clamp)
- flight clamp: 81.6 ms to 568.4 ms (or wider runtime clamp)

## Files
- Old script: `HumanPaste/research/scripts/download_and_analyze_dataset.py`
- New script: `HumanPaste/research/scripts/download_and_analyze_dataset_v2.py`
- New output: `HumanPaste/research/calibration_output_v2.json`
