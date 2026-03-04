#!/usr/bin/env python3
"""Download public keystroke dataset and compute robust calibration (v2)."""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import math
import statistics
import urllib.error
import urllib.request
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Iterable


@dataclass(frozen=True)
class DatasetCandidate:
    name: str
    url: str
    local_filename: str
    notes: str


RESEARCH_DIR = Path(__file__).resolve().parents[1]
DATASET_DIR = RESEARCH_DIR / "datasets"
OUTPUT_PATH = RESEARCH_DIR / "calibration_output_v2.json"

CANDIDATES: list[DatasetCandidate] = [
    DatasetCandidate(
        name="CMU Keystroke Dynamics Benchmark (DSL Strong Password)",
        url="http://www.cs.cmu.edu/~keystroke/DSL-StrongPasswordData.csv",
        local_filename="DSL-StrongPasswordData.csv",
        notes=(
            "Public CSV hosted by CMU. Holds H.*, DD.*, UD.* columns. "
            "Use DD for non-negative key-down flight timing calibration."
        ),
    )
]


def sha256_of_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def percentile(sorted_values: list[float], p: float) -> float:
    if not sorted_values:
        raise ValueError("Cannot compute percentile of empty values")
    if p <= 0:
        return sorted_values[0]
    if p >= 100:
        return sorted_values[-1]
    rank = (len(sorted_values) - 1) * (p / 100.0)
    lo = math.floor(rank)
    hi = math.ceil(rank)
    if lo == hi:
        return sorted_values[lo]
    frac = rank - lo
    return sorted_values[lo] * (1.0 - frac) + sorted_values[hi] * frac


def summarize(values: Iterable[float]) -> dict[str, float | int]:
    vals = sorted(values)
    if not vals:
        return {"count": 0}
    return {
        "count": len(vals),
        "min": vals[0],
        "p01": percentile(vals, 1),
        "p05": percentile(vals, 5),
        "p25": percentile(vals, 25),
        "median": percentile(vals, 50),
        "mean": statistics.fmean(vals),
        "p75": percentile(vals, 75),
        "p95": percentile(vals, 95),
        "p99": percentile(vals, 99),
        "max": vals[-1],
        "stddev": statistics.stdev(vals) if len(vals) > 1 else 0.0,
    }


def quartile_log_logistic_fit(values: list[float]) -> dict[str, float]:
    vals = sorted(v for v in values if v > 0)
    if len(vals) < 10:
        return {"alpha": 0.0, "beta": 0.0}
    q25 = percentile(vals, 25)
    q50 = percentile(vals, 50)
    q75 = percentile(vals, 75)
    beta = math.log(9.0) / math.log(q75 / q25)
    alpha = q50
    return {"alpha": alpha, "beta": beta}


def try_download(candidate: DatasetCandidate, force_download: bool) -> Path:
    DATASET_DIR.mkdir(parents=True, exist_ok=True)
    local_path = DATASET_DIR / candidate.local_filename
    if local_path.exists() and not force_download:
        return local_path

    request = urllib.request.Request(
        candidate.url,
        headers={"User-Agent": "HumanPaste-Research-v2/1.0"},
    )
    with urllib.request.urlopen(request, timeout=45) as resp:
        payload = resp.read()

    # guard: avoid saving HTML/login pages as CSV
    head = payload[:512].decode("utf-8", errors="ignore").lower()
    if "<html" in head or "<!doctype" in head:
        raise RuntimeError(f"Dataset URL returned HTML, not CSV: {candidate.url}")

    local_path.write_bytes(payload)
    return local_path


def pick_and_download_dataset(force_download: bool) -> tuple[DatasetCandidate, Path]:
    errors: list[str] = []
    for candidate in CANDIDATES:
        try:
            return candidate, try_download(candidate, force_download)
        except (urllib.error.URLError, TimeoutError, OSError, RuntimeError) as exc:
            errors.append(f"{candidate.name}: {exc}")
    raise RuntimeError("Unable to download dataset.\n" + "\n".join(errors))


def parse_cmu_csv(path: Path) -> dict[str, object]:
    dwell: list[float] = []
    dd: list[float] = []
    ud: list[float] = []
    subjects: set[str] = set()
    rows = 0

    with path.open(newline="", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        if not reader.fieldnames:
            raise ValueError("CSV has no header row")

        dwell_cols = [c for c in reader.fieldnames if c.startswith("H.")]
        dd_cols = [c for c in reader.fieldnames if c.startswith("DD.")]
        ud_cols = [c for c in reader.fieldnames if c.startswith("UD.")]

        if not dwell_cols or not dd_cols:
            raise ValueError("Expected H.* and DD.* columns in CMU dataset")

        for row in reader:
            rows += 1
            subj = (row.get("subject") or "").strip()
            if subj:
                subjects.add(subj)

            for c in dwell_cols:
                v = (row.get(c) or "").strip()
                if v:
                    dwell.append(float(v))
            for c in dd_cols:
                v = (row.get(c) or "").strip()
                if v:
                    dd.append(float(v))
            for c in ud_cols:
                v = (row.get(c) or "").strip()
                if v:
                    ud.append(float(v))

    neg_ud = sum(1 for x in ud if x < 0)

    # robust slice (clip at p01..p99) to reduce huge long-tail spikes
    dd_sorted = sorted(dd)
    dd_p01 = percentile(dd_sorted, 1)
    dd_p99 = percentile(dd_sorted, 99)
    dd_trim = [x for x in dd if dd_p01 <= x <= dd_p99]

    dwell_fit = quartile_log_logistic_fit(dwell)
    dd_fit = quartile_log_logistic_fit(dd_trim)

    return {
        "row_count": rows,
        "subject_count": len(subjects),
        "subjects": sorted(subjects),
        "dwell_column_count": len(dwell_cols),
        "flight_dd_column_count": len(dd_cols),
        "flight_ud_column_count": len(ud_cols),
        "dwell_seconds": summarize(dwell),
        "flight_seconds_dd": summarize(dd),
        "flight_seconds_dd_trimmed_p01_p99": summarize(dd_trim),
        "flight_seconds_ud": summarize(ud),
        "ud_negative_fraction": neg_ud / len(ud) if ud else 0.0,
        "fit_log_logistic": {
            "dwell": dwell_fit,
            "flight_dd_trimmed": dd_fit,
        },
        "calibration": {
            "recommended_engine_inputs": {
                "dwell_alpha_ms": round(dwell_fit["alpha"] * 1000.0, 3),
                "dwell_beta": round(dwell_fit["beta"], 6),
                "flight_alpha_ms": round(dd_fit["alpha"] * 1000.0, 3),
                "flight_beta": round(dd_fit["beta"], 6),
                "dwell_lower_bound_ms_p05": round(percentile(sorted(dwell), 5) * 1000.0, 3),
                "dwell_upper_bound_ms_p95": round(percentile(sorted(dwell), 95) * 1000.0, 3),
                "flight_lower_bound_ms_p05": round(percentile(sorted(dd_trim), 5) * 1000.0, 3),
                "flight_upper_bound_ms_p95": round(percentile(sorted(dd_trim), 95) * 1000.0, 3),
            },
            "notes": [
                "Flight calibration uses DD timings only to avoid negative UD artifacts.",
                "DD is trimmed at p01..p99 before fitting to reduce extreme outlier influence.",
            ],
        },
    }


def main() -> int:
    parser = argparse.ArgumentParser(description="Dataset download + robust calibration v2")
    parser.add_argument("--force-download", action="store_true")
    args = parser.parse_args()

    candidate, dataset_path = pick_and_download_dataset(force_download=args.force_download)
    analysis = parse_cmu_csv(dataset_path)

    out = {
        "generated_at_utc": datetime.now(timezone.utc).isoformat(),
        "dataset": {
            "name": candidate.name,
            "source_url": candidate.url,
            "notes": candidate.notes,
            "local_path": str(dataset_path),
            "file_size_bytes": dataset_path.stat().st_size,
            "sha256": sha256_of_file(dataset_path),
        },
        "analysis": analysis,
    }

    OUTPUT_PATH.write_text(json.dumps(out, indent=2), encoding="utf-8")
    print(f"Wrote: {OUTPUT_PATH}")
    rec = analysis["calibration"]["recommended_engine_inputs"]
    print("Recommended engine inputs:")
    for k, v in rec.items():
        print(f"  {k}: {v}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
