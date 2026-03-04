#!/usr/bin/env python3
import argparse
import json
from collections import Counter, defaultdict
from statistics import mean

from analysis_common import latest_session, linear_slope, pctl


def analyze(header, events, window_ms=30000):
    events = sorted(events, key=lambda e: float(e.get("tMs", 0.0)))
    down = [e for e in events if e.get("kind") == "down"]
    up = [e for e in events if e.get("kind") == "up"]

    if not down:
        return {
            "window_ms": window_ms,
            "window_count": 0,
            "windows": [],
            "trends": {},
        }

    t0 = float(down[0].get("tMs", 0.0))

    dwell_lookup = defaultdict(list)
    for e in up:
        if e.get("dwellMs") is not None:
            dwell_lookup[(e.get("category", "unknown"), e.get("subCategory", "none"))].append((float(e.get("tMs", 0.0)), float(e["dwellMs"])))

    windows = {}
    for e in down:
        t = float(e.get("tMs", 0.0))
        wi = int((t - t0) // window_ms)
        w = windows.setdefault(wi, {
            "window_index": wi,
            "start_t_ms": t0 + wi * window_ms,
            "end_t_ms": t0 + (wi + 1) * window_ms,
            "down_count": 0,
            "category_counts": Counter(),
            "subcategory_counts": Counter(),
            "dwell_samples": [],
            "word_boundary_count": 0,
            "terminal_punctuation_count": 0,
        })
        w["down_count"] += 1
        cat = e.get("category", "unknown")
        sub = e.get("subCategory", "none")
        w["category_counts"][cat] += 1
        w["subcategory_counts"][sub] += 1

        if sub in ("space", "return", "tab"):
            w["word_boundary_count"] += 1
        if sub in ("period_terminal", "question_terminal", "exclamation_terminal"):
            w["terminal_punctuation_count"] += 1

    # attach dwell by time bucket
    for wi, w in windows.items():
        start = w["start_t_ms"]
        end = w["end_t_ms"]
        dwells = []
        for _, arr in dwell_lookup.items():
            for t, d in arr:
                if start <= t < end:
                    dwells.append(d)
        w["dwell_samples"] = dwells

    rows = []
    max_wi = max(windows.keys())
    for wi in range(max_wi + 1):
        w = windows.get(wi, {
            "window_index": wi,
            "start_t_ms": t0 + wi * window_ms,
            "end_t_ms": t0 + (wi + 1) * window_ms,
            "down_count": 0,
            "category_counts": Counter(),
            "subcategory_counts": Counter(),
            "dwell_samples": [],
            "word_boundary_count": 0,
            "terminal_punctuation_count": 0,
        })
        seconds = window_ms / 1000.0
        cps = w["down_count"] / seconds
        row = {
            "window_index": wi,
            "start_t_ms": w["start_t_ms"],
            "end_t_ms": w["end_t_ms"],
            "keys_per_sec": cps,
            "down_count": w["down_count"],
            "word_boundary_count": w["word_boundary_count"],
            "terminal_punctuation_count": w["terminal_punctuation_count"],
            "dwell_p50_ms": pctl(w["dwell_samples"], 0.50),
            "dwell_p95_ms": pctl(w["dwell_samples"], 0.95),
            "category_counts": dict(w["category_counts"]),
            "subcategory_counts": dict(w["subcategory_counts"]),
        }
        rows.append(row)

    cps_series = [r["keys_per_sec"] for r in rows]
    dwell_series = [r["dwell_p50_ms"] for r in rows if r["dwell_p50_ms"] > 0]

    trends = {
        "keys_per_sec_slope_per_window": linear_slope(cps_series),
        "dwell_p50_slope_per_window": linear_slope(dwell_series),
        "first_3_windows_avg_kps": mean(cps_series[:3]) if cps_series else 0.0,
        "last_3_windows_avg_kps": mean(cps_series[-3:]) if cps_series else 0.0,
        "warmup_detected": (mean(cps_series[-3:]) > mean(cps_series[:3]) * 1.10) if len(cps_series) >= 6 else False,
        "slowdown_detected": (mean(cps_series[-3:]) < mean(cps_series[:3]) * 0.90) if len(cps_series) >= 6 else False,
    }

    return {
        "session_start": header.get("startedAtISO8601") if header else None,
        "window_ms": window_ms,
        "window_count": len(rows),
        "windows": rows,
        "trends": trends,
    }


def to_md(rep):
    lines = ["# Timing Window Analysis", ""]
    lines.append(f"- session_start: {rep.get('session_start')}")
    lines.append(f"- window_ms: {rep.get('window_ms')}")
    lines.append(f"- window_count: {rep.get('window_count')}")
    lines.append(f"- trends: {rep.get('trends')}")
    lines.append("")
    lines.append("## Window Snapshot")
    for r in rep.get("windows", [])[:20]:
        lines.append(
            f"- w{r['window_index']} kps={r['keys_per_sec']:.2f} dwell_p50={r['dwell_p50_ms']:.1f} boundaries={r['word_boundary_count']} terminal_punc={r['terminal_punctuation_count']}"
        )
    return "\n".join(lines)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("log_path")
    ap.add_argument("out_prefix")
    ap.add_argument("--window-ms", type=int, default=30000)
    args = ap.parse_args()

    header, events = latest_session(args.log_path)
    if header is None:
        raise SystemExit("No session in log")

    rep = analyze(header, events, window_ms=args.window_ms)

    out_json = f"{args.out_prefix}.json"
    out_md = f"{args.out_prefix}.md"
    with open(out_json, "w", encoding="utf-8") as f:
        json.dump(rep, f, indent=2)
    with open(out_md, "w", encoding="utf-8") as f:
        f.write(to_md(rep))

    print("timing windows analysis complete")
    print("- json:", out_json)
    print("- md:", out_md)


if __name__ == "__main__":
    main()
