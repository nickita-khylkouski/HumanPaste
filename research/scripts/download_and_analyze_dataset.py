#!/usr/bin/env python3
"""Download a public keystroke dataset and compute calibration statistics."""

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
OUTPUT_PATH = RESEARCH_DIR / "calibration_output.json"

CANDIDATES: list[DatasetCandidate] = [
    DatasetCandidate(
        name="CMU Keystroke Dynamics Benchmark (DSL Strong Password)",
        url="http://www.cs.cmu.edu/~keystroke/DSL-StrongPasswordData.csv",
        local_filename="DSL-StrongPasswordData.csv",
        notes=(
            "Publicly downloadable CSV hosted by CMU. No login required. "
            "Contains hold (H.*), down-down (DD.*), and up-down (UD.*) timings."
        ),
    ),
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
    low = math.floor(rank)
    high = math.ceil(rank)
    if low == high:
        return sorted_values[low]
    fraction = rank - low
    return sorted_values[low] * (1.0 - fraction) + sorted_values[high] * fraction


def summarize(values: Iterable[float]) -> dict[str, float | int]:
    vals = list(values)
    if not vals:
        return {"count": 0}
    vals.sort()
    return {
        "count": len(vals),
        "min": vals[0],
        "max": vals[-1],
        "mean": statistics.fmean(vals),
        "median": statistics.median(vals),
        "stddev": statistics.stdev(vals) if len(vals) > 1 else 0.0,
        "p05": percentile(vals, 5),
        "p25": percentile(vals, 25),
        "p75": percentile(vals, 75),
        "p95": percentile(vals, 95),
    }


def try_download(candidate: DatasetCandidate, force_download: bool) -> Path:
    DATASET_DIR.mkdir(parents=True, exist_ok=True)
    local_path = DATASET_DIR / candidate.local_filename
    if local_path.exists() and not force_download:
        return local_path

    request = urllib.request.Request(
        candidate.url,
        headers={"User-Agent": "HumanPaste-Research/1.0"},
    )
    with urllib.request.urlopen(request, timeout=45) as resp:
        payload = resp.read()
    local_path.write_bytes(payload)
    return local_path


def pick_and_download_dataset(force_download: bool) -> tuple[DatasetCandidate, Path]:
    errors: list[str] = []
    for candidate in CANDIDATES:
        try:
            path = try_download(candidate, force_download=force_download)
            return candidate, path
        except (urllib.error.URLError, TimeoutError, OSError) as exc:
            errors.append(f"{candidate.name}: {exc}")
    details = "\n".join(errors) if errors else "No dataset candidates configured."
    raise RuntimeError(f"Unable to download any dataset candidate.\n{details}")


def parse_cmu_csv(path: Path) -> dict[str, object]:
    dwell_values: list[float] = []
    flight_dd_values: list[float] = []
    flight_ud_values: list[float] = []
    subjects: set[str] = set()
    rows = 0

    with path.open(newline="", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        if not reader.fieldnames:
            raise ValueError("CSV has no header row")

        dwell_cols = [col for col in reader.fieldnames if col.startswith("H.")]
        flight_dd_cols = [col for col in reader.fieldnames if col.startswith("DD.")]
        flight_ud_cols = [col for col in reader.fieldnames if col.startswith("UD.")]

        if not dwell_cols or not (flight_dd_cols or flight_ud_cols):
            raise ValueError(
                "Expected CMU timing columns (H.*, DD.*, UD.*) were not found"
            )

        for row in reader:
            rows += 1
            subject = (row.get("subject") or "").strip()
            if subject:
                subjects.add(subject)

            for col in dwell_cols:
                raw = (row.get(col) or "").strip()
                if raw:
                    dwell_values.append(float(raw))
            for col in flight_dd_cols:
                raw = (row.get(col) or "").strip()
                if raw:
                    flight_dd_values.append(float(raw))
            for col in flight_ud_cols:
                raw = (row.get(col) or "").strip()
                if raw:
                    flight_ud_values.append(float(raw))

    combined_flight = flight_dd_values + flight_ud_values

    dwell_summary = summarize(dwell_values)
    flight_summary = summarize(combined_flight)

    return {
        "row_count": rows,
        "subject_count": len(subjects),
        "subjects": sorted(subjects),
        "dwell_column_count": len(dwell_cols),
        "flight_dd_column_count": len(flight_dd_cols),
        "flight_ud_column_count": len(flight_ud_cols),
        "dwell_seconds": dwell_summary,
        "flight_seconds_dd": summarize(flight_dd_values),
        "flight_seconds_ud": summarize(flight_ud_values),
        "flight_seconds_combined": flight_summary,
        "calibration": {
            "recommended_dwell_seconds": {
                "mean": dwell_summary.get("mean"),
                "stddev": dwell_summary.get("stddev"),
                "lower_bound_p05": dwell_summary.get("p05"),
                "upper_bound_p95": dwell_summary.get("p95"),
            },
            "recommended_flight_seconds": {
                "mean": flight_summary.get("mean"),
                "stddev": flight_summary.get("stddev"),
                "lower_bound_p05": flight_summary.get("p05"),
                "upper_bound_p95": flight_summary.get("p95"),
            },
        },
    }


def main() -> int:
    parser = argparse.ArgumentParser(
        description=(
            "Find/download a public keystroke dataset and compute dwell/flight "
            "summary statistics."
        )
    )
    parser.add_argument(
        "--force-download",
        action="store_true",
        help="Re-download dataset even if it already exists locally.",
    )
    args = parser.parse_args()

    candidate, dataset_path = pick_and_download_dataset(force_download=args.force_download)
    parsed = parse_cmu_csv(dataset_path)

    output = {
        "generated_at_utc": datetime.now(timezone.utc).isoformat(),
        "dataset": {
            "name": candidate.name,
            "source_url": candidate.url,
            "notes": candidate.notes,
            "local_path": str(dataset_path),
            "file_size_bytes": dataset_path.stat().st_size,
            "sha256": sha256_of_file(dataset_path),
        },
        "analysis": parsed,
    }

    OUTPUT_PATH.write_text(json.dumps(output, indent=2), encoding="utf-8")
    print(f"Wrote calibration output: {OUTPUT_PATH}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
