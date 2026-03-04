#!/usr/bin/env python3
import argparse
import json
from statistics import mean

from analysis_common import latest_session, linear_slope, pctl


def _segment_index(t, t0, span, n):
    if span <= 0:
        return 0
    pos = (t - t0) / span
    idx = int(pos * n)
    if idx < 0:
        return 0
    if idx >= n:
        return n - 1
    return idx


def analyze(header, events, segments=10):
    events = sorted(events, key=lambda e: float(e.get("tMs", 0.0)))
    down = [e for e in events if e.get("kind") == "down"]
    up = [e for e in events if e.get("kind") == "up"]

    if len(down) < 2:
        return {
            "session_start": header.get("startedAtISO8601") if header else None,
            "notes": ["Not enough events for segment analysis."],
        }

    t0 = float(down[0].get("tMs", 0.0))
    t1 = float(down[-1].get("tMs", 0.0))
    span = max(1.0, t1 - t0)
    seg = []
    for i in range(segments):
        seg.append({
            "segment_index": i,
            "down_count": 0,
            "editing_count": 0,
            "terminal_punc_count": 0,
            "flight_ms": [],
            "dwell_ms": [],
        })

    for i, e in enumerate(down):
        t = float(e.get("tMs", 0.0))
        si = _segment_index(t, t0, span, segments)
        seg[si]["down_count"] += 1
        if e.get("category") == "editing":
            seg[si]["editing_count"] += 1
        if e.get("subCategory") in ("period_terminal", "question_terminal", "exclamation_terminal"):
            seg[si]["terminal_punc_count"] += 1
        if i > 0:
            dt = t - float(down[i - 1].get("tMs", 0.0))
            if dt > 0:
                seg[si]["flight_ms"].append(dt)

    for e in up:
        d = e.get("dwellMs")
        if d is None:
            continue
        t = float(e.get("tMs", 0.0))
        si = _segment_index(t, t0, span, segments)
        seg[si]["dwell_ms"].append(float(d))

    rows = []
    for s in seg:
        seg_span_s = (span / segments) / 1000.0
        kps = s["down_count"] / max(0.001, seg_span_s)
        row = {
            "segment_index": s["segment_index"],
            "down_count": s["down_count"],
            "keys_per_sec": kps,
            "editing_rate": s["editing_count"] / max(1, s["down_count"]),
            "terminal_punc_rate": s["terminal_punc_count"] / max(1, s["down_count"]),
            "flight_p50_ms": pctl(s["flight_ms"], 0.50),
            "flight_p95_ms": pctl(s["flight_ms"], 0.95),
            "dwell_p50_ms": pctl(s["dwell_ms"], 0.50),
            "dwell_p95_ms": pctl(s["dwell_ms"], 0.95),
        }
        rows.append(row)

    kps = [r["keys_per_sec"] for r in rows]
    flight = [r["flight_p50_ms"] for r in rows if r["flight_p50_ms"] > 0]
    dwell = [r["dwell_p50_ms"] for r in rows if r["dwell_p50_ms"] > 0]

    stable_candidates = [r for r in rows if r["down_count"] >= 10]
    if stable_candidates:
        stable_best = min(
            stable_candidates,
            key=lambda r: abs(r["keys_per_sec"] - (mean(kps) if kps else 0.0)),
        )
    else:
        stable_best = None

    report = {
        "session_start": header.get("startedAtISO8601") if header else None,
        "segments": segments,
        "segment_rows": rows,
        "kps_trend_slope": linear_slope(kps),
        "flight_trend_slope": linear_slope(flight),
        "dwell_trend_slope": linear_slope(dwell),
        "kps_mean": mean(kps) if kps else 0.0,
        "kps_min": min(kps) if kps else 0.0,
        "kps_max": max(kps) if kps else 0.0,
        "stable_segment": stable_best,
        "flags": {
            "front_loaded_fast": (kps[0] > mean(kps) * 1.2) if len(kps) >= 3 else False,
            "end_slowdown": (kps[-1] < mean(kps) * 0.85) if len(kps) >= 3 else False,
            "editing_spike_exists": any(r["editing_rate"] > 0.08 for r in rows),
        },
    }
    return report


def to_md(rep):
    lines = ["# Stability Segment Analysis", ""]
    for k in [
        "session_start",
        "segments",
        "kps_trend_slope",
        "flight_trend_slope",
        "dwell_trend_slope",
        "kps_mean",
        "kps_min",
        "kps_max",
        "stable_segment",
        "flags",
    ]:
        lines.append(f"- {k}: {rep.get(k)}")
    lines.append("")
    lines.append("## Segment Snapshot")
    for r in rep.get("segment_rows", [])[:12]:
        lines.append(
            f"- s{r['segment_index']} kps={r['keys_per_sec']:.2f} edit={r['editing_rate']:.3f} flight_p50={r['flight_p50_ms']:.1f} dwell_p50={r['dwell_p50_ms']:.1f}"
        )
    return "\n".join(lines)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("log_path")
    ap.add_argument("out_prefix")
    ap.add_argument("--segments", type=int, default=10)
    args = ap.parse_args()

    header, events = latest_session(args.log_path)
    if header is None:
        raise SystemExit("No session in log")

    rep = analyze(header, events, segments=args.segments)
    out_json = f"{args.out_prefix}.json"
    out_md = f"{args.out_prefix}.md"
    with open(out_json, "w", encoding="utf-8") as f:
        json.dump(rep, f, indent=2)
    with open(out_md, "w", encoding="utf-8") as f:
        f.write(to_md(rep))

    print("stability segment analysis complete")
    print("- json:", out_json)
    print("- md:", out_md)


if __name__ == "__main__":
    main()
