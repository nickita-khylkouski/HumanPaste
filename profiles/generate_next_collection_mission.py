#!/usr/bin/env python3
import argparse
import json
from datetime import datetime, timezone


def build(progress):
    mission = progress.get("next_mission", {})
    deficits = progress.get("deficits_ranked", [])
    top3 = deficits[:3]

    payload = {
        "generated_at_utc": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "overall_progress_0_to_100": progress.get("overall_progress_0_to_100"),
        "mission": mission,
        "top_deficits": top3,
        "success_criteria": [
            f"Complete mission for at least {mission.get('duration_min', 5)} minutes.",
            "No copy-paste; natural typing only.",
            f"Primary metric improved: {mission.get('driver_metric', 'n/a')}.",
            "Run autopilot again and verify deficit moved up the ranking.",
        ],
    }
    return payload


def to_md(obj):
    m = obj.get("mission", {})
    lines = ["# Next Collection Mission", ""]
    lines.append(f"- generated_at_utc: {obj.get('generated_at_utc')}")
    lines.append(f"- overall_progress_0_to_100: {obj.get('overall_progress_0_to_100')}")
    lines.append("")
    lines.append("## Mission")
    lines.append(f"- id: {m.get('id')}")
    lines.append(f"- driver_metric: {m.get('driver_metric')}")
    lines.append(f"- duration_min: {m.get('duration_min')}")
    lines.append(f"- goal: {m.get('goal')}")
    for step in m.get("instructions", []):
        lines.append(f"- {step}")
    lines.append("")
    lines.append("## Top Deficits")
    for d in obj.get("top_deficits", []):
        lines.append(
            f"- {d.get('metric')}: {d.get('count')}/{d.get('target')} (missing {d.get('missing')}, completion {d.get('completion'):.2f})"
        )
    lines.append("")
    lines.append("## Success Criteria")
    for s in obj.get("success_criteria", []):
        lines.append(f"- {s}")
    return "\n".join(lines)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("progress_json")
    ap.add_argument("out_prefix")
    args = ap.parse_args()

    with open(args.progress_json, "r", encoding="utf-8") as f:
        progress = json.load(f)

    obj = build(progress)
    out_json = f"{args.out_prefix}.json"
    out_md = f"{args.out_prefix}.md"
    with open(out_json, "w", encoding="utf-8") as f:
        json.dump(obj, f, indent=2)
    with open(out_md, "w", encoding="utf-8") as f:
        f.write(to_md(obj))

    print("next mission generated")
    print("- json:", out_json)
    print("- md:", out_md)


if __name__ == "__main__":
    main()
