#!/usr/bin/env python3
import argparse
import json
from collections import Counter

from analysis_common import parse_sessions


TARGETS = {
    "sessions": 12,
    "letters": 3000,
    "word_boundaries": 600,    # space + return + tab
    "returns": 20,
    "punctuation": 120,        # .,!?:;
    "corrections": 60,         # backspace/delete
    "navigation": 80,          # arrow/home/end/page keys
    "number_symbol": 300,      # number + symbol category
}


MISSION_MAP = {
    "punctuation": {
        "id": "punctuation_rich",
        "duration_min": 8,
        "goal": "Increase punctuation timing realism.",
        "instructions": [
            "Type 8-10 paragraphs with mixed punctuation: . , ! ? : ;",
            "Use questions, exclamations, clauses, and short/long sentences.",
            "Do not paste; type naturally with pauses.",
        ],
    },
    "corrections": {
        "id": "correction_sprint",
        "duration_min": 6,
        "goal": "Capture natural error/correction loops.",
        "instructions": [
            "Free-write quickly for 6 minutes without stopping.",
            "Let mistakes happen and correct naturally with backspace/delete.",
            "Avoid perfection; capture realistic correction behavior.",
        ],
    },
    "navigation": {
        "id": "edit_navigation",
        "duration_min": 7,
        "goal": "Capture cursor/edit navigation dynamics.",
        "instructions": [
            "Type one paragraph, then revise it with arrow keys and edits.",
            "Move cursor back, insert/delete, and reword sections.",
            "Repeat for 3-4 paragraphs.",
        ],
    },
    "number_symbol": {
        "id": "numbers_symbols",
        "duration_min": 6,
        "goal": "Capture numeric/symbol transition patterns.",
        "instructions": [
            "Type URLs, shell commands, emails, and code-like snippets.",
            "Include numbers and symbols: @ # $ % ^ & * ( ) - _ + = / : .",
            "Mix with normal prose words.",
        ],
    },
    "returns": {
        "id": "paragraph_flow",
        "duration_min": 6,
        "goal": "Capture line-break and paragraph transition behavior.",
        "instructions": [
            "Type multi-paragraph text with frequent Enter usage.",
            "Use short and long paragraphs with natural pauses between them.",
            "Include lists and section breaks.",
        ],
    },
    "word_boundaries": {
        "id": "steady_prose",
        "duration_min": 7,
        "goal": "Increase boundary timing consistency at scale.",
        "instructions": [
            "Type continuous prose for 7 minutes.",
            "Focus on natural word flow and spacing.",
            "Do not over-correct.",
        ],
    },
    "letters": {
        "id": "volume_build",
        "duration_min": 10,
        "goal": "Increase core letter transition sample volume.",
        "instructions": [
            "Type any long-form content continuously for 10 minutes.",
            "Prefer original writing over copy typing.",
            "Keep a natural pace.",
        ],
    },
    "sessions": {
        "id": "multi_session_day",
        "duration_min": 3,
        "goal": "Increase day/session diversity.",
        "instructions": [
            "Do 3 short typing sessions across different times today.",
            "Each session: 3+ minutes, different context (chat/prose/commands).",
        ],
    },
}


def _score(count, target):
    if target <= 0:
        return 1.0
    return min(1.0, float(count) / float(target))


def _extract_counts(events):
    down = [e for e in events if e.get("kind") == "down"]
    cat = Counter(e.get("category", "unknown") for e in down)
    sub = Counter(e.get("subCategory", "none") for e in down)

    punctuation = sum(sub.get(x, 0) for x in [
        "period_terminal", "question_terminal", "exclamation_terminal",
        "comma", "semicolon", "colon"
    ])
    corrections = sub.get("backspace", 0) + sub.get("delete", 0)
    boundaries = sub.get("space", 0) + sub.get("return", 0) + sub.get("tab", 0)
    returns = sub.get("return", 0)
    navigation = cat.get("navigation", 0)
    number_symbol = cat.get("number", 0) + cat.get("symbol", 0)
    letters = cat.get("letter", 0)

    return {
        "letters": letters,
        "word_boundaries": boundaries,
        "returns": returns,
        "punctuation": punctuation,
        "corrections": corrections,
        "navigation": navigation,
        "number_symbol": number_symbol,
        "down_total": len(down),
        "categories": dict(cat),
        "subcategories": dict(sub),
    }


def analyze(log_path):
    sessions = parse_sessions(log_path)
    if not sessions:
        return {"notes": ["No sessions found."]}

    all_events = []
    for s in sessions:
        all_events.extend(s.get("events", []))

    counts = _extract_counts(all_events)
    counts["sessions"] = len(sessions)

    scores = {k: _score(counts.get(k, 0), TARGETS[k]) for k in TARGETS}

    # Weighted overall progress.
    weights = {
        "sessions": 0.08,
        "letters": 0.22,
        "word_boundaries": 0.12,
        "returns": 0.05,
        "punctuation": 0.15,
        "corrections": 0.14,
        "navigation": 0.10,
        "number_symbol": 0.14,
    }
    overall = sum(scores[k] * weights[k] for k in weights)
    overall_pct = round(overall * 100.0, 1)

    deficits = []
    for k, target in TARGETS.items():
        c = counts.get(k, 0)
        missing = max(0, target - c)
        deficits.append({
            "metric": k,
            "count": c,
            "target": target,
            "missing": missing,
            "completion": scores[k],
        })
    deficits.sort(key=lambda x: x["completion"])

    # Pick next mission by worst completion metric.
    top_deficit = deficits[0]["metric"] if deficits else "letters"
    mission = MISSION_MAP.get(top_deficit, MISSION_MAP["letters"])

    report = {
        "session_count": len(sessions),
        "overall_progress_0_to_100": overall_pct,
        "targets": TARGETS,
        "counts": counts,
        "scores_0_to_1": scores,
        "deficits_ranked": deficits,
        "next_mission": {
            "driver_metric": top_deficit,
            **mission,
        },
    }
    return report


def to_md(rep):
    lines = ["# Collection Progress", ""]
    lines.append(f"- session_count: {rep.get('session_count')}")
    lines.append(f"- overall_progress_0_to_100: {rep.get('overall_progress_0_to_100')}")
    lines.append("")
    lines.append("## Top Deficits")
    for row in rep.get("deficits_ranked", [])[:6]:
        lines.append(
            f"- {row['metric']}: {row['count']}/{row['target']} (missing {row['missing']}, completion {row['completion']:.2f})"
        )
    lines.append("")
    nm = rep.get("next_mission", {})
    lines.append("## Next Mission")
    lines.append(f"- id: {nm.get('id')}")
    lines.append(f"- driver_metric: {nm.get('driver_metric')}")
    lines.append(f"- duration_min: {nm.get('duration_min')}")
    lines.append(f"- goal: {nm.get('goal')}")
    for step in nm.get("instructions", []):
        lines.append(f"- {step}")
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

    print("collection progress analysis complete")
    print("- json:", out_json)
    print("- md:", out_md)


if __name__ == "__main__":
    main()
