#!/usr/bin/env python3
import argparse
import json
from collections import Counter

from analysis_common import parse_sessions, latest_session


def analyze(log_path, use_all=False):
    if use_all:
        sessions = parse_sessions(log_path)
        if not sessions:
            return {"notes": ["No sessions found."]}
        events = []
        for s in sessions:
            events.extend(s.get("events", []))
        session_count = len(sessions)
    else:
        header, events = latest_session(log_path)
        if header is None:
            return {"notes": ["No sessions found."]}
        session_count = 1

    downs = [e for e in events if e.get("kind") == "down"]
    ups = [e for e in events if e.get("kind") == "up"]
    idle = [e for e in events if e.get("kind") == "idle_gap"]

    down_cat = Counter(e.get("category", "unknown") for e in downs)
    down_sub = Counter(e.get("subCategory", "none") for e in downs)

    unknown_down = down_cat.get("unknown", 0)
    unknown_rate = unknown_down / max(1, len(downs))

    has_sub_field = sum(1 for e in downs if "subCategory" in e)
    missing_sub = sum(1 for e in downs if "subCategory" in e and not e.get("subCategory"))
    missing_sub_rate = missing_sub / max(1, len(downs))
    missing_sub_on_present_rate = missing_sub / max(1, has_sub_field) if has_sub_field > 0 else 0.0

    dwell_missing = sum(1 for e in ups if e.get("dwellMs") is None)
    dwell_missing_rate = dwell_missing / max(1, len(ups))

    has_keycode_field = sum(1 for e in downs if "keyCode" in e)
    with_keycode = sum(1 for e in downs if e.get("keyCode") is not None)
    keycode_coverage = with_keycode / max(1, len(downs))
    keycode_field_presence = has_keycode_field / max(1, len(downs))
    keycode_coverage_on_present = (
        with_keycode / max(1, has_keycode_field)
        if has_keycode_field > 0 else 0.0
    )

    repeat_count = sum(1 for e in downs if e.get("autoRepeat") is True)
    repeat_rate = repeat_count / max(1, len(downs))

    quality_score = 100.0
    quality_score -= min(25.0, unknown_rate * 300.0)
    if has_sub_field >= max(1, int(0.20 * len(downs))):
        quality_score -= min(20.0, missing_sub_on_present_rate * 250.0)
    quality_score -= min(20.0, dwell_missing_rate * 180.0)
    # Penalize keycode coverage only if this looks like a post-upgrade schema.
    if keycode_field_presence >= 0.20:
        quality_score -= 10.0 if keycode_coverage_on_present < 0.80 else 0.0
    quality_score = max(0.0, round(quality_score, 1))

    suggestions = []
    if unknown_rate > 0.02:
        suggestions.append("Increase keycode mapping coverage for unknown keys.")
    if has_sub_field >= max(1, int(0.20 * len(downs))):
        if missing_sub_on_present_rate > 0.02:
            suggestions.append("Improve subcategory assignment for unmapped keys.")
    else:
        suggestions.append("Legacy sessions detected with partial subCategory fields.")
    if dwell_missing_rate > 0.08:
        suggestions.append("Investigate keyUp matching and auto-repeat handling.")
    if keycode_coverage < 0.95:
        if keycode_field_presence >= 0.20:
            suggestions.append("Ensure keyCode is populated for all down events.")
        else:
            suggestions.append("Legacy sessions detected (no keyCode field). Post-upgrade sessions include keyCode.")
    if not suggestions:
        suggestions.append("Logger quality is strong for current usage patterns.")

    return {
        "session_count": session_count,
        "down_count": len(downs),
        "up_count": len(ups),
        "idle_gap_count": len(idle),
        "unknown_down_rate": unknown_rate,
        "missing_subcategory_rate": missing_sub_rate,
        "missing_subcategory_on_present_rate": missing_sub_on_present_rate,
        "missing_dwell_rate_on_up": dwell_missing_rate,
        "keycode_coverage_rate": keycode_coverage,
        "keycode_field_presence_rate": keycode_field_presence,
        "keycode_coverage_on_present_rate": keycode_coverage_on_present,
        "autorepeat_rate": repeat_rate,
        "down_category_counts": dict(down_cat),
        "down_subcategory_counts_top": dict(down_sub.most_common(20)),
        "logger_quality_score_0_to_100": quality_score,
        "suggestions": suggestions,
    }


def to_md(rep):
    lines = ["# Logger Quality", ""]
    lines.append(f"- session_count: {rep.get('session_count')}")
    lines.append(f"- down_count: {rep.get('down_count')}")
    lines.append(f"- up_count: {rep.get('up_count')}")
    lines.append(f"- unknown_down_rate: {rep.get('unknown_down_rate'):.4f}")
    lines.append(f"- missing_subcategory_rate: {rep.get('missing_subcategory_rate'):.4f}")
    lines.append(f"- missing_subcategory_on_present_rate: {rep.get('missing_subcategory_on_present_rate'):.4f}")
    lines.append(f"- missing_dwell_rate_on_up: {rep.get('missing_dwell_rate_on_up'):.4f}")
    lines.append(f"- keycode_coverage_rate: {rep.get('keycode_coverage_rate'):.4f}")
    lines.append(f"- keycode_field_presence_rate: {rep.get('keycode_field_presence_rate'):.4f}")
    lines.append(f"- keycode_coverage_on_present_rate: {rep.get('keycode_coverage_on_present_rate'):.4f}")
    lines.append(f"- autorepeat_rate: {rep.get('autorepeat_rate'):.4f}")
    lines.append(f"- logger_quality_score_0_to_100: {rep.get('logger_quality_score_0_to_100')}")
    lines.append("")
    lines.append("## Suggestions")
    for s in rep.get("suggestions", []):
        lines.append(f"- {s}")
    return "\n".join(lines)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("log_path")
    ap.add_argument("out_prefix")
    ap.add_argument("--all", action="store_true", help="Analyze all sessions instead of latest.")
    args = ap.parse_args()

    rep = analyze(args.log_path, use_all=args.all)
    out_json = f"{args.out_prefix}.json"
    out_md = f"{args.out_prefix}.md"
    with open(out_json, "w", encoding="utf-8") as f:
        json.dump(rep, f, indent=2)
    with open(out_md, "w", encoding="utf-8") as f:
        f.write(to_md(rep))

    print("logger quality analysis complete")
    print("- json:", out_json)
    print("- md:", out_md)


if __name__ == "__main__":
    main()
