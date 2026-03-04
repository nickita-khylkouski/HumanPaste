# Dataset Acquisition and Calibration (Track 2)

## Deliverables
- `scripts/download_and_analyze_dataset.py`
- `calibration_output.json`

## Public dataset found and downloaded
- Dataset: **CMU Keystroke Dynamics Benchmark (DSL Strong Password)**
- Source URL (no login): `http://www.cs.cmu.edu/~keystroke/DSL-StrongPasswordData.csv`
- Local copy: `HumanPaste/research/datasets/DSL-StrongPasswordData.csv`
- SHA-256: `b11d23538b1865fa6ecf4e8b78567caa312e9c1027604bb022fcc6ad7eaa7a33`
- File size: `4,669,935` bytes

## Analysis method
- Dwell times are parsed from all `H.*` columns.
- Flight times are parsed from `DD.*` and `UD.*` columns.
- Summary statistics computed:
  - count, min, max, mean, median, stddev
  - p05, p25, p75, p95
- Calibration ranges are derived from p05/p95 and mean/stddev.

## Current summary (from `calibration_output.json`)
- Rows: `20,400`
- Subjects: `51`
- Dwell samples (`H.*`): `224,400`
- Flight samples (`DD.* + UD.*`): `408,000`

### Dwell seconds
- mean: `0.090096`
- stddev: `0.030496`
- p05: `0.0493`
- p95: `0.1448`

### Flight seconds (combined DD/UD)
- mean: `0.204055`
- stddev: `0.224208`
- p05: `-0.0027`
- p95: `0.5677`

## How to run
From repo root:

```bash
python3 HumanPaste/research/scripts/download_and_analyze_dataset.py
```

Optional forced re-download:

```bash
python3 HumanPaste/research/scripts/download_and_analyze_dataset.py --force-download
```

The script writes:
- Downloaded dataset file under `HumanPaste/research/datasets/`
- Calibration JSON to `HumanPaste/research/calibration_output.json`
