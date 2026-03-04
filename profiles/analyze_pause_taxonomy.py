#!/usr/bin/env python3
import argparse
import json
from collections import Counter, defaultdict

from analysis_common import latest_session, dist


def pause_bucket(ms: float) -> str:
    if ms < 180:
        return "motor_micro"
    if ms < 500:
        return "fluent_transition"
    if ms < 2000:
        return "thinking_pause"
    return "away_or_context_switch"


def analyze(header, events):
    events = sorted(events, key=lambda e: float(e.get("tMs", 0.0)))
    down = [e for e in events if e.get("kind") == "down"]
    idle_threshold = float(header.get("idleGapThresholdMs", 2000)) if header else 2000.0

    if len(down) < 2:
        return {
            "session_start": header.get("startedAtISO8601") if header else None,
            "notes": ["Not enough down events for pause analysis."],
        }

    flights = []
    by_bucket = Counter()
    by_prev_subcat = defaultdict(list)
    by_prev_category = defaultdict(list)
    long_gaps = []

    for i in range(1, len(down)):
        prev = down[i - 1]
        cur = down[i]
        t0 = float(prev.get("tMs", 0.0))
        t1 = float(cur.get("tMs", 0.0))
        dt = t1 - t0
        if dt <= 0:
            continue
        bucket = pause_bucket(dt)
        flights.append(dt)
        by_bucket[bucket] += 1

        prev_sub = prev.get("subCategory", "none")
        prev_cat = prev.get("category", "unknown")
        by_prev_subcat[prev_sub].append(dt)
        by_prev_category[prev_cat].append(dt)

        if dt >= idle_threshold:
            long_gaps.append({
                "index": i,
                "gap_ms": dt,
                "prev_category": prev_cat,
                "prev_subcategory": prev_sub,
                "next_category": cur.get("category", "unknown"),
                "next_subcategory": cur.get("subCategory", "none"),
            })

    top_prev_sub = []
    for sub, vals in by_prev_subcat.items():
        if len(vals) < 5:
            continue
        top_prev_sub.append({
            "prev_subcategory": sub,
            "count": len(vals),
            "timing_ms": dist(vals),
        })
    top_prev_sub.sort(key=lambda x: x["count"], reverse=True)

    top_prev_cat = []
    for cat, vals in by_prev_category.items():
        if len(vals) < 5:
            continue
        top_prev_cat.append({
            "prev_category": cat,
            "count": len(vals),
            "timing_ms": dist(vals),
        })
    top_prev_cat.sort(key=lambda x: x["count"], reverse=True)

    bucket_total = sum(by_bucket.values()) or 1
    bucket_pct = {k: (v / bucket_total) for k, v in by_bucket.items()}

    report = {
        "session_start": header.get("startedAtISO8601") if header else None,
        "idle_gap_threshold_ms": idle_threshold,
        "flight_count": len(flights),
        "flight_ms": dist(flights),
        "pause_buckets": dict(by_bucket),
        "pause_bucket_pct": bucket_pct,
        "top_prev_subcategory_timing": top_prev_sub[:20],
        "top_prev_category_timing": top_prev_cat[:20],
        "long_gap_samples": sorted(long_gaps, key=lambda x: x["gap_ms"], reverse=True)[:20],
    }
    return report


def to_md(rep):
    lines = ["# Pause Taxonomy Analysis", ""]
    for k in [
        "session_start",
        "idle_gap_threshold_ms",
        "flight_count",
        "flight_ms",
        "pause_buckets",
        "pause_bucket_pct",
    ]:
        lines.append(f"- {k}: {rep.get(k)}")

    lines.append("")
    lines.append("## Top Previous Subcategory Timing")
    for row in rep.get("top_prev_subcategory_timing", [])[:10]:
        lines.append(
            f"- {row['prev_subcategory']} count={row['count']} p50={row['timing_ms']['p50']:.1f}ms p95={row['timing_ms']['p95']:.1f}ms"
        )

    lines.append("")
    lines.append("## Long Gap Samples")
    for row in rep.get("long_gap_samples", [])[:10]:
        lines.append(
            f"- idx={row['index']} gap={row['gap_ms']:.1f}ms prev={row['prev_category']}/{row['prev_subcategory']} next={row['next_category']}/{row['next_subcategory']}"
        )
    return "\n".join(lines)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("log_path")
    ap.add_argument("out_prefix")
    args = ap.parse_args()

    header, events = latest_session(args.log_path)
    if header is None:
        raise SystemExit("No session in log")

    rep = analyze(header, events)
    out_json = f"{args.out_prefix}.json"
    out_md = f"{args.out_prefix}.md"
    with open(out_json, "w", encoding="utf-8") as f:
        json.dump(rep, f, indent=2)
    with open(out_md, "w", encoding="utf-8") as f:
        f.write(to_md(rep))

    print("pause taxonomy analysis complete")
    print("- json:", out_json)
    print("- md:", out_md)


if __name__ == "__main__":
    main()
