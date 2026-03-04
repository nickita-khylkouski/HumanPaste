#!/usr/bin/env python3
import argparse
import json
from collections import Counter, defaultdict
from statistics import mean

from analysis_common import parse_sessions, pctl, dist


def clamp(v, lo, hi):
    return max(lo, min(hi, v))


def percentile_or(vals, q, default):
    if not vals:
        return default
    return pctl(vals, q)


def parse_all(log_path):
    sessions = parse_sessions(log_path)
    if not sessions:
        return None, []
    header = sessions[-1].get("header")
    events = []
    for s in sessions:
        events.extend(s.get("events", []))
    return header, sorted(events, key=lambda e: float(e.get("tMs", 0.0)))


def analyze(log_path):
    header, events = parse_all(log_path)
    if header is None:
        return {"notes": ["No sessions found."]}

    idle_threshold = float(header.get("idleGapThresholdMs", 2000))
    down = [e for e in events if e.get("kind") == "down"]
    up = [e for e in events if e.get("kind") == "up"]
    if len(down) < 2:
        return {"notes": ["Not enough key-down events."]}

    flights_all = []
    flights_active = []
    pair_flights = defaultdict(list)
    mode_counts = Counter()

    for i in range(1, len(down)):
        prev = down[i - 1]
        cur = down[i]
        dt = float(cur.get("tMs", 0.0)) - float(prev.get("tMs", 0.0))
        if dt <= 0:
            continue
        flights_all.append(dt)
        pair = f"{prev.get('subCategory','none')}->{cur.get('subCategory','none')}"
        pair_flights[pair].append(dt)
        if dt < idle_threshold:
            flights_active.append(dt)

    if not flights_active:
        flights_active = flights_all[:]

    q25 = percentile_or(flights_active, 0.25, 80.0)
    q75 = percentile_or(flights_active, 0.75, 180.0)
    q95 = percentile_or(flights_active, 0.95, 320.0)

    for dt in flights_all:
        if dt >= idle_threshold:
            mode_counts["away"] += 1
        elif dt <= q25:
            mode_counts["sprint"] += 1
        elif dt <= q75:
            mode_counts["cruise"] += 1
        elif dt <= q95:
            mode_counts["hesitate"] += 1
        else:
            mode_counts["micro_pause"] += 1

    mode_total = sum(mode_counts.values()) or 1
    mode_pct = {k: v / mode_total for k, v in mode_counts.items()}

    # Dwell by subcategory.
    dwell_by_sub = defaultdict(list)
    dwell_by_cat = defaultdict(list)
    for e in up:
        d = e.get("dwellMs")
        if d is None:
            continue
        dv = float(d)
        dwell_by_sub[e.get("subCategory", "none")].append(dv)
        dwell_by_cat[e.get("category", "unknown")].append(dv)

    # Correction / navigation / punctuation / boundaries.
    sub_counts = Counter(e.get("subCategory", "none") for e in down)
    cat_counts = Counter(e.get("category", "unknown") for e in down)
    correction_keys = sub_counts.get("backspace", 0) + sub_counts.get("delete", 0)
    correction_rate = correction_keys / max(1, len(down))
    punctuation_count = sum(sub_counts.get(x, 0) for x in [
        "period_terminal", "question_terminal", "exclamation_terminal",
        "comma", "semicolon", "colon"
    ])
    punctuation_rate = punctuation_count / max(1, len(down))

    # Active WPM estimate using active flight time only.
    active_time_ms = sum(dt for dt in flights_all if dt < idle_threshold)
    active_time_ms = max(active_time_ms, 1.0)
    active_cps = (len(down) / active_time_ms) * 1000.0
    active_wpm = active_cps * 60.0 / 5.0

    # Word burst estimate: words between large pauses.
    word_burst_lengths = []
    current_words = 0
    for i in range(1, len(down)):
        prev = down[i - 1]
        cur = down[i]
        dt = float(cur.get("tMs", 0.0)) - float(prev.get("tMs", 0.0))
        if prev.get("subCategory") in ("space", "return", "tab"):
            current_words += 1
        if dt > q95 and dt < idle_threshold:
            if current_words > 0:
                word_burst_lengths.append(current_words)
            current_words = 0
        if dt >= idle_threshold:
            if current_words > 0:
                word_burst_lengths.append(current_words)
            current_words = 0
    if current_words > 0:
        word_burst_lengths.append(current_words)

    burst_words_mean = mean(word_burst_lengths) if word_burst_lengths else 4.0

    # Recommended main.swift / AppDelegate values.
    rec_wpm = int(round(clamp(active_wpm * 0.92, 35, 220)))

    pause_signal = (
        mode_pct.get("hesitate", 0.0) +
        1.15 * mode_pct.get("micro_pause", 0.0) +
        1.40 * mode_pct.get("away", 0.0)
    )
    rec_pause_pct = int(round(clamp(pause_signal * 120.0, 0, 100)))

    # typoPct: 50 = "normal". Use observed correction rate to scale.
    # Around 0.5%-1.0% observed corrections should map to modest typo injection.
    rec_typo_pct = int(round(clamp(8 + correction_rate * 2500.0, 0, 100)))

    rec_flight_cap = int(round(clamp(percentile_or(flights_active, 0.97, 260.0) * 1.35, 120, 800)))
    rec_think_cap = int(round(clamp(percentile_or(flights_all, 0.995, 900.0), 220, 3000)))

    # Correction speed from correction exit timing if available.
    l2l_p50 = percentile_or(pair_flights.get("letter->letter", []), 0.50, 120.0)
    b2l_vals = pair_flights.get("backspace->letter", []) + pair_flights.get("delete->letter", [])
    b2l_p50 = percentile_or(b2l_vals, 0.50, 0.0)
    if b2l_p50 > 0:
        correction_speed = int(round(clamp(100.0 * (l2l_p50 / b2l_p50), 60, 180)))
    else:
        correction_speed = 100

    rec_burst_words = int(round(clamp(burst_words_mean, 2, 12)))

    nav_rate = cat_counts.get("navigation", 0) / max(1, len(down))
    rec_false_starts = int(clamp(round(1 + correction_rate * 50), 0, 6))
    rec_cursor_edits = int(clamp(round(nav_rate * 30), 0, 5))

    # Additional profile values for future model changes.
    profile_values = {
        "letter_flight_p50_ms": percentile_or(pair_flights.get("letter->letter", []), 0.50, 120.0),
        "word_end_flight_p50_ms": percentile_or(pair_flights.get("letter->space", []), 0.50, 90.0),
        "word_start_flight_p50_ms": percentile_or(pair_flights.get("space->letter", []), 0.50, 120.0),
        "letter_dwell_p50_ms": percentile_or(dwell_by_sub.get("letter", []), 0.50, 70.0),
        "space_dwell_p50_ms": percentile_or(dwell_by_sub.get("space", []), 0.50, 60.0),
        "mode_pct": mode_pct,
        "correction_rate": correction_rate,
        "punctuation_rate": punctuation_rate,
        "navigation_rate": nav_rate,
        "active_wpm_estimate": active_wpm,
    }

    main_values = {
        "wpm": rec_wpm,
        "pausePct": rec_pause_pct,
        "typoPct": rec_typo_pct,
        "flightCapMs": rec_flight_cap,
        "thinkCapMs": rec_think_cap,
        "initialDelayMs": 120,
        "correctionSpeed": correction_speed,
        "burstWords": rec_burst_words,
        "uncertaintyEnabled": False,
        "falseStartMax": rec_false_starts,
        "cursorEditMax": rec_cursor_edits,
    }

    change_requests = [
        "Add per-user profile loading in AppDelegate.applyAll() before default slider values.",
        "Allow per-user overrides for word-start and word-end multipliers in TimingModel.",
        "Add optional punctuation-specific pause profile once punctuation coverage improves.",
        "Split typo model into user-observed correction behaviors (entry delay, backspace burst, re-entry).",
    ]

    return {
        "session_count": len(parse_sessions(log_path)),
        "down_count": len(down),
        "up_count": len(up),
        "idle_gap_threshold_ms": idle_threshold,
        "main_engine_recommended_values": main_values,
        "personal_profile_values": profile_values,
        "flight_active_ms": dist(flights_active),
        "flight_all_ms": dist(flights_all),
        "dwell_letter_ms": dist(dwell_by_sub.get("letter", [])),
        "dwell_space_ms": dist(dwell_by_sub.get("space", [])),
        "transition_counts_top": dict(Counter({k: len(v) for k, v in pair_flights.items()}).most_common(12)),
        "change_requests_for_main_engine": change_requests,
    }


def to_md(rep):
    lines = ["# Personal Typing DNA (All Sessions)", ""]
    lines.append(f"- session_count: {rep.get('session_count')}")
    lines.append(f"- down_count: {rep.get('down_count')}")
    lines.append(f"- idle_gap_threshold_ms: {rep.get('idle_gap_threshold_ms')}")
    lines.append("")
    lines.append("## Recommended Main Values")
    for k, v in rep.get("main_engine_recommended_values", {}).items():
        lines.append(f"- {k}: {v}")
    lines.append("")
    lines.append("## Key Personal Metrics")
    for k in ["flight_active_ms", "dwell_letter_ms", "dwell_space_ms"]:
        lines.append(f"- {k}: {rep.get(k)}")
    lines.append("")
    lines.append("## Change Requests For Main Engine")
    for x in rep.get("change_requests_for_main_engine", []):
        lines.append(f"- {x}")
    return "\n".join(lines)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("log_path")
    ap.add_argument("out_prefix")
    args = ap.parse_args()

    rep = analyze(args.log_path)
    out_json = f"{args.out_prefix}.json"
    out_md = f"{args.out_prefix}.md"
    with open(out_json, "w", encoding="utf-8") as f:
        json.dump(rep, f, indent=2)
    with open(out_md, "w", encoding="utf-8") as f:
        f.write(to_md(rep))

    print("personal typing dna analysis complete")
    print("- json:", out_json)
    print("- md:", out_md)


if __name__ == "__main__":
    main()
