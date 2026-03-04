#!/usr/bin/env python3
import json
import math
import random
from pathlib import Path


def log_logistic(alpha: float, beta: float) -> float:
    u = random.uniform(0.0001, 0.9999)
    return alpha * ((u / (1.0 - u)) ** (1.0 / beta))


def pct(vals, q):
    if not vals:
        return 0.0
    s = sorted(vals)
    idx = int((len(s) - 1) * q)
    return s[idx]


def sample_dist(alpha, beta, n=150000, lo=None, hi=None):
    out = []
    for _ in range(n):
        v = log_logistic(alpha, beta)
        if lo is not None and v < lo:
            v = lo
        if hi is not None and v > hi:
            v = hi
        out.append(v)
    return out


def summarize(vals):
    return {
        "p05": pct(vals, 0.05),
        "p50": pct(vals, 0.50),
        "p95": pct(vals, 0.95),
        "mean": sum(vals) / len(vals),
    }


def within(actual, expected, rel_tol):
    if expected == 0:
        return abs(actual) < 1e-9
    return abs(actual - expected) / expected <= rel_tol


def main():
    root = Path(__file__).resolve().parents[2]
    calibration_path = root / "data" / "calibration.json"
    with calibration_path.open("r", encoding="utf-8") as f:
        c = json.load(f)

    dwell = sample_dist(
        c["dwellAlphaMs"], c["dwellBeta"],
        lo=25.0, hi=550.0
    )
    flight = sample_dist(
        c["flightAlphaMs"], c["flightBeta"],
        lo=18.0, hi=2500.0
    )

    dwell_s = summarize(dwell)
    flight_s = summarize(flight)

    # Dataset-derived anchors (from analysis v2, ms)
    targets = {
        "dwell": {"p05": 49.3, "p50": 86.1, "p95": 144.8},
        "flight": {"p05": 81.6, "p50": 191.1, "p95": 568.4},
    }

    checks = {
        "dwell_p05": within(dwell_s["p05"], targets["dwell"]["p05"], 0.22),
        "dwell_p50": within(dwell_s["p50"], targets["dwell"]["p50"], 0.12),
        "dwell_p95": within(dwell_s["p95"], targets["dwell"]["p95"], 0.25),
        "flight_p05": within(flight_s["p05"], targets["flight"]["p05"], 0.25),
        "flight_p50": within(flight_s["p50"], targets["flight"]["p50"], 0.15),
        "flight_p95": within(flight_s["p95"], targets["flight"]["p95"], 0.30),
    }

    report = {
        "calibration": c,
        "sample_summary_ms": {
            "dwell": dwell_s,
            "flight": flight_s,
        },
        "targets_ms": targets,
        "checks": checks,
        "pass": all(checks.values()),
    }

    out = root / "research" / "calibration_validation_report.json"
    out.write_text(json.dumps(report, indent=2), encoding="utf-8")

    print("Calibration validation summary")
    print("- dwell  p05/p50/p95:", round(dwell_s["p05"], 2), round(dwell_s["p50"], 2), round(dwell_s["p95"], 2))
    print("- flight p05/p50/p95:", round(flight_s["p05"], 2), round(flight_s["p50"], 2), round(flight_s["p95"], 2))
    print("- checks:")
    for k, v in checks.items():
        print(f"  - {k}: {'PASS' if v else 'FAIL'}")
    print("- overall:", "PASS" if report["pass"] else "FAIL")
    print("- report:", out)

    raise SystemExit(0 if report["pass"] else 2)


if __name__ == "__main__":
    main()
