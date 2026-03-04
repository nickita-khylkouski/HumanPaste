#!/usr/bin/env python3
import argparse
import json
from collections import Counter

from analysis_common import latest_session, parse_sessions


def _score(metric, min_ok, max_ok):
    if metric <= min_ok:
        return 0.0
    if metric >= max_ok:
        return 1.0
    return (metric - min_ok) / (max_ok - min_ok)


def analyze(header, events):
    events = sorted(events, key=lambda e: float(e.get("tMs", 0.0)))
    down = [e for e in events if e.get("kind") == "down"]
    up = [e for e in events if e.get("kind") == "up"]
    idle = [e for e in events if e.get("kind") == "idle_gap"]

    if len(down) < 2:
        return {"notes": ["Not enough events for readiness analysis."]}

    sub_counts = Counter(e.get("subCategory", "none") for e in down)
    cat_counts = Counter(e.get("category", "unknown") for e in down)

    pair_counts = Counter()
    for i in range(1, len(down)):
        a = down[i - 1].get("subCategory", "none")
        b = down[i].get("subCategory", "none")
        pair_counts[f"{a}->{b}"] += 1

    backspace_events = sub_counts.get("backspace", 0) + sub_counts.get("delete", 0)
    return_events = sub_counts.get("return", 0)
    punctuation_events = sum(sub_counts.get(x, 0) for x in [
        "period_terminal", "question_terminal", "exclamation_terminal", "comma", "semicolon", "colon"
    ])

    # Coverage scores (0-1)
    coverage = {
        "letters": _score(cat_counts.get("letter", 0), 100, 600),
        "word_boundaries": _score(sub_counts.get("space", 0) + return_events, 30, 300),
        "corrections": _score(backspace_events, 2, 25),
        "punctuation": _score(punctuation_events, 3, 40),
        "linebreaks": _score(return_events, 2, 20),
        "navigation": _score(cat_counts.get("navigation", 0), 1, 20),
        "idle_gaps": _score(len(idle), 1, 10),
        "pair_variety": _score(len(pair_counts), 15, 120),
        "dwell_samples": _score(len([e for e in up if e.get("dwellMs") is not None]), 100, 600),
    }

    # Weighted readiness for "replicate this user's typing style".
    weights = {
        "letters": 0.20,
        "word_boundaries": 0.13,
        "corrections": 0.12,
        "punctuation": 0.12,
        "linebreaks": 0.07,
        "navigation": 0.04,
        "idle_gaps": 0.05,
        "pair_variety": 0.14,
        "dwell_samples": 0.13,
    }
    readiness = sum(coverage[k] * weights[k] for k in coverage)
    readiness_score = round(readiness * 100.0, 1)

    # What we can infer now.
    infer_now = []
    if coverage["letters"] >= 0.6 and coverage["dwell_samples"] >= 0.6:
        infer_now.append("Strong baseline cadence (letter dwell + core letter-to-letter flight).")
    if coverage["word_boundaries"] >= 0.5:
        infer_now.append("Usable word-boundary timing signature (letter->space and space->letter).")
    if coverage["idle_gaps"] >= 0.3:
        infer_now.append("Can separate active motor rhythm vs away/thinking gaps.")
    if coverage["pair_variety"] >= 0.5:
        infer_now.append("Transition diversity is enough for early pair-conditioned sampling.")

    # Missing data collection priorities.
    collect_more = []
    if coverage["punctuation"] < 0.5:
        collect_more.append("Collect punctuation-heavy samples (.,?!,:;), at least 80 punctuation keys.")
    if coverage["corrections"] < 0.5:
        collect_more.append("Collect natural correction episodes (backspace/delete), target 25+ correction keys.")
    if coverage["linebreaks"] < 0.5:
        collect_more.append("Collect multi-paragraph typing with Enter usage, target 20+ return keys.")
    if coverage["pair_variety"] < 0.5:
        collect_more.append("Collect broader key-transition variety (numbers/symbols/mixed words).")
    if coverage["navigation"] < 0.5:
        collect_more.append("Collect editing/navigation sessions with arrow/home/end interactions.")

    bucket_ideas = [
        "Pause buckets split by context: post-space, post-return, post-punctuation, mid-word.",
        "Word-position buckets: first-letter latency vs middle vs final-letter timings.",
        "Error-cycle buckets: pre-error delay, backspace burst speed, correction re-entry delay.",
        "Session-state buckets: warmup, cruise, fatigue, recovery windows.",
        "Content-type buckets: prose, command-line, chat, code-style typing signatures.",
    ]

    report = {
        "session_start": header.get("startedAtISO8601") if header else None,
        "counts": {
            "down": len(down),
            "up": len(up),
            "idle_gap": len(idle),
            "categories": dict(cat_counts),
            "subcategories": dict(sub_counts),
            "transition_pair_variety": len(pair_counts),
        },
        "coverage_scores_0_to_1": coverage,
        "clone_readiness_score_0_to_100": readiness_score,
        "what_we_can_infer_now": infer_now,
        "what_to_collect_next": collect_more,
        "new_bucket_directions": bucket_ideas,
    }
    return report


def to_md(rep):
    lines = ["# Clone Readiness Analysis", ""]
    lines.append(f"- session_start: {rep.get('session_start')}")
    lines.append(f"- clone_readiness_score_0_to_100: {rep.get('clone_readiness_score_0_to_100')}")
    lines.append(f"- coverage_scores_0_to_1: {rep.get('coverage_scores_0_to_1')}")
    lines.append("")
    lines.append("## What We Can Infer Now")
    for x in rep.get("what_we_can_infer_now", []):
        lines.append(f"- {x}")
    lines.append("")
    lines.append("## What To Collect Next")
    for x in rep.get("what_to_collect_next", []):
        lines.append(f"- {x}")
    lines.append("")
    lines.append("## New Bucket Directions")
    for x in rep.get("new_bucket_directions", []):
        lines.append(f"- {x}")
    return "\n".join(lines)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("log_path")
    ap.add_argument("out_prefix")
    ap.add_argument("--all", action="store_true", help="Analyze all sessions, not just latest.")
    args = ap.parse_args()

    if args.all:
        sessions = parse_sessions(args.log_path)
        if not sessions:
            raise SystemExit("No session in log")
        header = sessions[-1].get("header")
        events = []
        for s in sessions:
            events.extend(s.get("events", []))
    else:
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

    print("clone readiness analysis complete")
    print("- json:", out_json)
    print("- md:", out_md)


if __name__ == "__main__":
    main()
