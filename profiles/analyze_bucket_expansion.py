#!/usr/bin/env python3
import argparse
import json
from collections import Counter, defaultdict

from analysis_common import latest_session, pctl, dist


BOUNDARY_SUBS = {"space", "return", "tab"}


def _mode_from_flight(dt, q25, q75, q95, idle_threshold):
    if dt >= idle_threshold:
        return "away"
    if dt <= q25:
        return "sprint"
    if dt <= q75:
        return "cruise"
    if dt <= q95:
        return "hesitate"
    return "micro_pause"


def analyze(header, events):
    events = sorted(events, key=lambda e: float(e.get("tMs", 0.0)))
    down = [e for e in events if e.get("kind") == "down"]
    up = [e for e in events if e.get("kind") == "up"]
    idle_threshold = float(header.get("idleGapThresholdMs", 2000)) if header else 2000.0

    if len(down) < 2:
        return {
            "session_start": header.get("startedAtISO8601") if header else None,
            "notes": ["Not enough events for bucket expansion analysis."],
        }

    # Dwell distributions by category / subcategory.
    dwell_by_category = defaultdict(list)
    dwell_by_subcategory = defaultdict(list)
    for e in up:
        d = e.get("dwellMs")
        if d is None:
            continue
        dv = float(d)
        dwell_by_category[e.get("category", "unknown")].append(dv)
        dwell_by_subcategory[e.get("subCategory", "none")].append(dv)

    # Flight distributions and context buckets.
    flights = []
    flights_no_away = []
    contextual = defaultdict(list)
    by_position = defaultdict(list)  # word char position bucket -> incoming flight

    word_pos = 0
    for i, e in enumerate(down):
        sub = e.get("subCategory", "none")
        cat = e.get("category", "unknown")

        if cat == "letter":
            word_pos += 1
        elif sub in BOUNDARY_SUBS:
            word_pos = 0

        if i == 0:
            continue
        prev = down[i - 1]
        dt = float(e.get("tMs", 0.0)) - float(prev.get("tMs", 0.0))
        if dt <= 0:
            continue
        flights.append(dt)
        if dt < idle_threshold:
            flights_no_away.append(dt)

        ps = prev.get("subCategory", "none")
        pc = prev.get("category", "unknown")
        cs = sub
        cc = cat

        # Context buckets
        if pc == "letter" and cc == "letter":
            contextual["intra_word_letter_letter"].append(dt)
        if pc == "letter" and cs in BOUNDARY_SUBS:
            contextual["word_end_transition"].append(dt)
        if ps in BOUNDARY_SUBS and cc == "letter":
            contextual["word_start_transition"].append(dt)
        if pc == "letter" and cc == "editing":
            contextual["correction_entry"].append(dt)
        if pc == "editing" and cc == "letter":
            contextual["correction_exit"].append(dt)
        if pc == "navigation" or cc == "navigation":
            contextual["navigation_transition"].append(dt)
        if ps == "return" and cc == "letter":
            contextual["new_line_start"].append(dt)

        # Position buckets based on current key position in word.
        if cc == "letter":
            if word_pos <= 1:
                by_position["pos1"].append(dt)
            elif word_pos == 2:
                by_position["pos2"].append(dt)
            elif word_pos == 3:
                by_position["pos3"].append(dt)
            else:
                by_position["pos4_plus"].append(dt)

    q25 = pctl(flights_no_away, 0.25)
    q75 = pctl(flights_no_away, 0.75)
    q95 = pctl(flights_no_away, 0.95)
    mode_counts = Counter(_mode_from_flight(x, q25, q75, q95, idle_threshold) for x in flights)
    mode_total = sum(mode_counts.values()) or 1

    contextual_summary = {}
    for k, vals in contextual.items():
        if len(vals) >= 2:
            contextual_summary[k] = dist(vals)

    position_summary = {}
    for k, vals in by_position.items():
        if len(vals) >= 3:
            position_summary[k] = dist(vals)

    dwell_category_summary = {
        k: dist(v) for k, v in dwell_by_category.items() if len(v) >= 3
    }
    dwell_subcategory_summary = {
        k: dist(v) for k, v in dwell_by_subcategory.items() if len(v) >= 3
    }

    report = {
        "session_start": header.get("startedAtISO8601") if header else None,
        "idle_gap_threshold_ms": idle_threshold,
        "flight_ms_all": dist(flights),
        "flight_ms_no_away": dist(flights_no_away),
        "flight_quantiles_no_away": {
            "q25": q25,
            "q50": pctl(flights_no_away, 0.50),
            "q75": q75,
            "q90": pctl(flights_no_away, 0.90),
            "q95": q95,
        },
        "mode_buckets": dict(mode_counts),
        "mode_bucket_pct": {k: (v / mode_total) for k, v in mode_counts.items()},
        "context_buckets_ms": contextual_summary,
        "word_position_buckets_ms": position_summary,
        "dwell_by_category_ms": dwell_category_summary,
        "dwell_by_subcategory_ms": dwell_subcategory_summary,
    }
    return report


def to_md(rep):
    lines = ["# Bucket Expansion Analysis", ""]
    for k in [
        "session_start",
        "idle_gap_threshold_ms",
        "flight_ms_no_away",
        "flight_quantiles_no_away",
        "mode_buckets",
        "mode_bucket_pct",
    ]:
        lines.append(f"- {k}: {rep.get(k)}")
    lines.append("")
    lines.append("## Context Buckets")
    for k, v in rep.get("context_buckets_ms", {}).items():
        lines.append(f"- {k}: count={v['count']} p50={v['p50']:.1f} p95={v['p95']:.1f}")
    lines.append("")
    lines.append("## Word Position Buckets")
    for k, v in rep.get("word_position_buckets_ms", {}).items():
        lines.append(f"- {k}: count={v['count']} p50={v['p50']:.1f} p95={v['p95']:.1f}")
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

    print("bucket expansion analysis complete")
    print("- json:", out_json)
    print("- md:", out_md)


if __name__ == "__main__":
    main()
