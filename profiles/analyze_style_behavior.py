#!/usr/bin/env python3
import argparse
import json
from collections import Counter
from statistics import mean

from analysis_common import latest_session, pctl, dist, linear_slope


def analyze(header, events):
    events = sorted(events, key=lambda e: float(e.get("tMs", 0.0)))
    down = [e for e in events if e.get("kind") == "down"]
    up = [e for e in events if e.get("kind") == "up"]
    idle = [e for e in events if e.get("kind") == "idle_gap"]

    if not down:
        return {"session_start": header.get("startedAtISO8601") if header else None, "notes": ["No down events"]}

    by_subcat = Counter(e.get("subCategory", "none") for e in down)

    # correction behavior
    editing_down = [e for e in down if e.get("category") == "editing"]
    correction_rate = len(editing_down) / max(1, len(down))

    # punctuation behavior
    terminal_keys = [e for e in down if e.get("subCategory") in ("period_terminal", "question_terminal", "exclamation_terminal")]
    comma_like = [e for e in down if e.get("subCategory") in ("comma", "semicolon", "colon")]
    boundaries = [e for e in down if e.get("subCategory") in ("space", "return", "tab")]

    # flight estimates between downs
    downs = sorted((float(e.get("tMs", 0.0)), e.get("category", "unknown"), e.get("subCategory", "none")) for e in down)
    flight = []
    flight_post_terminal = []
    flight_post_boundary = []
    for i in range(1, len(downs)):
        t0, c0, s0 = downs[i - 1]
        t1, _, _ = downs[i]
        dt = t1 - t0
        if dt <= 0:
            continue
        flight.append(dt)
        if s0 in ("period_terminal", "question_terminal", "exclamation_terminal"):
            flight_post_terminal.append(dt)
        if s0 in ("space", "return", "tab"):
            flight_post_boundary.append(dt)

    # dwell-based stability/variability
    dwell_letter = [float(e.get("dwellMs")) for e in up if e.get("category") == "letter" and e.get("dwellMs") is not None]

    # session thirds behavior
    tmin = downs[0][0]
    tmax = downs[-1][0]
    span = max(1.0, tmax - tmin)
    t1 = tmin + span / 3.0
    t2 = tmin + (2.0 * span) / 3.0

    thirds = [[], [], []]
    for t, _, _ in downs:
        if t < t1:
            thirds[0].append(t)
        elif t < t2:
            thirds[1].append(t)
        else:
            thirds[2].append(t)

    def kps(ts):
        if len(ts) < 2:
            return 0.0
        return len(ts) / max(0.001, (ts[-1] - ts[0]) / 1000.0)

    kps_thirds = [kps(x) for x in thirds]
    kps_slope = linear_slope(kps_thirds)

    report = {
        "session_start": header.get("startedAtISO8601") if header else None,
        "down_count": len(down),
        "up_count": len(up),
        "idle_gap_count": len(idle),
        "subcategories": dict(by_subcat),
        "correction_rate": correction_rate,
        "word_boundary_rate": len(boundaries) / max(1, len(down)),
        "terminal_punctuation_rate": len(terminal_keys) / max(1, len(down)),
        "comma_like_rate": len(comma_like) / max(1, len(down)),
        "flight_ms": dist(flight),
        "flight_post_terminal_ms": dist(flight_post_terminal),
        "flight_post_boundary_ms": dist(flight_post_boundary),
        "letter_dwell_ms": dist(dwell_letter),
        "kps_thirds": kps_thirds,
        "kps_slope_thirds": kps_slope,
        "interpretation_flags": {
            "likely_planning_pauses": pctl([float(e.get('gapMs', 0.0)) for e in idle if e.get('gapMs') is not None], 0.50) > 3000 if idle else False,
            "punctuation_heavy": (len(terminal_keys) + len(comma_like)) / max(1, len(down)) > 0.06,
            "correction_heavy": correction_rate > 0.035,
            "fatigue_like_slowdown": kps_thirds[-1] < kps_thirds[0] * 0.9 if kps_thirds[0] > 0 else False,
        },
    }

    return report


def to_md(rep):
    lines = ["# Style Behavior Analysis", ""]
    for k in [
        "session_start", "down_count", "up_count", "idle_gap_count",
        "correction_rate", "word_boundary_rate", "terminal_punctuation_rate", "comma_like_rate",
    ]:
        lines.append(f"- {k}: {rep.get(k)}")
    lines.append(f"- kps_thirds: {rep.get('kps_thirds')}")
    lines.append(f"- kps_slope_thirds: {rep.get('kps_slope_thirds')}")
    lines.append(f"- interpretation_flags: {rep.get('interpretation_flags')}")
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

    print("style behavior analysis complete")
    print("- json:", out_json)
    print("- md:", out_md)


if __name__ == "__main__":
    main()
