#!/usr/bin/env python3
import argparse
import csv
import json

from analysis_common import latest_session


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("log_path")
    ap.add_argument("out_csv")
    ap.add_argument("--max-gap-ms", type=float, default=2000.0)
    args = ap.parse_args()

    header, events = latest_session(args.log_path)
    if header is None:
        raise SystemExit("No session in log")

    events = sorted(events, key=lambda e: float(e.get("tMs", 0.0)))
    downs = [e for e in events if e.get("kind") == "down"]

    rows = []
    prev_down_t = None
    prev_cat = "none"
    prev_sub = "none"

    t_min = float(downs[0].get("tMs", 0.0)) if downs else 0.0
    t_max = float(downs[-1].get("tMs", 0.0)) if downs else 1.0
    span = max(1.0, t_max - t_min)

    for i, e in enumerate(events):
        t = float(e.get("tMs", 0.0))
        kind = e.get("kind", "unknown")
        cat = e.get("category", "unknown")
        sub = e.get("subCategory", "none")

        gap = ""
        if kind == "down":
            if prev_down_t is not None:
                g = t - prev_down_t
                gap = g
            prev_down_t = t

        session_pct = (t - t_min) / span
        if session_pct < 0.33:
            phase = "early"
        elif session_pct < 0.66:
            phase = "mid"
        else:
            phase = "late"

        rows.append({
            "event_index": i + 1,
            "tMs": f"{t:.3f}",
            "kind": kind,
            "category": cat,
            "subCategory": sub,
            "dwellMs": "" if e.get("dwellMs") is None else f"{float(e.get('dwellMs')):.3f}",
            "gapSincePrevDownMs": "" if gap == "" else f"{float(gap):.3f}",
            "isTrainingGap": "1" if (gap != "" and float(gap) <= args.max_gap_ms) else "0",
            "prevDownCategory": prev_cat,
            "prevDownSubCategory": prev_sub,
            "sessionPhase": phase,
            "idleGapThresholdMs": header.get("idleGapThresholdMs", 2000),
        })

        if kind == "down":
            prev_cat = cat
            prev_sub = sub

    fieldnames = [
        "event_index", "tMs", "kind", "category", "subCategory", "dwellMs",
        "gapSincePrevDownMs", "isTrainingGap", "prevDownCategory", "prevDownSubCategory",
        "sessionPhase", "idleGapThresholdMs",
    ]

    with open(args.out_csv, "w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=fieldnames)
        w.writeheader()
        w.writerows(rows)

    print("training rows export complete")
    print("- csv:", args.out_csv)
    print("- rows:", len(rows))


if __name__ == "__main__":
    main()
