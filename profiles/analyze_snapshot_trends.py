#!/usr/bin/env python3
import argparse
import glob
import json
import os
from statistics import mean

from analysis_common import linear_slope


def _read_json(path):
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


def analyze(snap_root):
    dirs = sorted([p for p in glob.glob(os.path.join(snap_root, "*")) if os.path.isdir(p)])
    rows = []
    for d in dirs:
        p_style = os.path.join(d, "style_behavior.json")
        p_tr = os.path.join(d, "transition_dna.json")
        p_pa = os.path.join(d, "pause_taxonomy.json")
        if not (os.path.exists(p_style) and os.path.exists(p_tr) and os.path.exists(p_pa)):
            continue
        try:
            st = _read_json(p_style)
            tr = _read_json(p_tr)
            pa = _read_json(p_pa)
        except Exception:
            continue

        top = tr.get("top_subcategory_pairs", [])
        l2l = next((x for x in top if x.get("pair") == "letter->letter"), None)
        l2s = next((x for x in top if x.get("pair") == "letter->space"), None)
        s2l = next((x for x in top if x.get("pair") == "space->letter"), None)

        row = {
            "snapshot": os.path.basename(d),
            "down_count": st.get("down_count", 0),
            "correction_rate": st.get("correction_rate", 0.0),
            "flight_p50": st.get("flight_ms", {}).get("p50", 0.0),
            "dwell_letter_p50": st.get("letter_dwell_ms", {}).get("p50", 0.0),
            "l2l_p50": (l2l or {}).get("flight_ms", {}).get("p50", 0.0),
            "l2s_p50": (l2s or {}).get("flight_ms", {}).get("p50", 0.0),
            "s2l_p50": (s2l or {}).get("flight_ms", {}).get("p50", 0.0),
            "motor_micro_pct": pa.get("pause_bucket_pct", {}).get("motor_micro", 0.0),
            "thinking_pause_pct": pa.get("pause_bucket_pct", {}).get("thinking_pause", 0.0),
            "away_pct": pa.get("pause_bucket_pct", {}).get("away_or_context_switch", 0.0),
        }
        rows.append(row)

    if not rows:
        return {"notes": ["No valid snapshots found with required files."]}

    # Only keep meaningful snapshots with enough data.
    usable = [r for r in rows if r["down_count"] >= 80]
    if not usable:
        usable = rows

    metrics = {
        "flight_p50": [r["flight_p50"] for r in usable],
        "dwell_letter_p50": [r["dwell_letter_p50"] for r in usable],
        "l2l_p50": [r["l2l_p50"] for r in usable],
        "l2s_p50": [r["l2s_p50"] for r in usable],
        "s2l_p50": [r["s2l_p50"] for r in usable],
        "correction_rate": [r["correction_rate"] for r in usable],
        "motor_micro_pct": [r["motor_micro_pct"] for r in usable],
    }

    stability = {}
    for k, vals in metrics.items():
        if not vals:
            continue
        mn = mean(vals)
        spread = max(vals) - min(vals)
        variability = (spread / mn) if mn > 0 else 0.0
        stability[k] = {
            "mean": mn,
            "min": min(vals),
            "max": max(vals),
            "variability_ratio": variability,
            "trend_slope": linear_slope(vals),
        }

    report = {
        "snapshot_count_total": len(rows),
        "snapshot_count_used": len(usable),
        "snapshots_used": [r["snapshot"] for r in usable],
        "stability_metrics": stability,
        "rows": usable,
    }
    return report


def to_md(rep):
    lines = ["# Snapshot Trend Analysis", ""]
    lines.append(f"- snapshot_count_total: {rep.get('snapshot_count_total')}")
    lines.append(f"- snapshot_count_used: {rep.get('snapshot_count_used')}")
    lines.append("")
    lines.append("## Stability Metrics")
    for k, v in rep.get("stability_metrics", {}).items():
        lines.append(
            f"- {k}: mean={v['mean']:.3f} min={v['min']:.3f} max={v['max']:.3f} variability={v['variability_ratio']:.3f} trend={v['trend_slope']:.5f}"
        )
    lines.append("")
    lines.append("## Recent Rows")
    for r in rep.get("rows", [])[-10:]:
        lines.append(
            f"- {r['snapshot']} down={r['down_count']} l2l_p50={r['l2l_p50']:.1f} dwell_p50={r['dwell_letter_p50']:.1f} corr={r['correction_rate']:.4f} motor_micro={r['motor_micro_pct']:.3f}"
        )
    return "\n".join(lines)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("snap_root")
    ap.add_argument("out_prefix")
    args = ap.parse_args()

    rep = analyze(args.snap_root)
    out_json = f"{args.out_prefix}.json"
    out_md = f"{args.out_prefix}.md"
    with open(out_json, "w", encoding="utf-8") as f:
        json.dump(rep, f, indent=2)
    with open(out_md, "w", encoding="utf-8") as f:
        f.write(to_md(rep))

    print("snapshot trend analysis complete")
    print("- json:", out_json)
    print("- md:", out_md)


if __name__ == "__main__":
    main()
