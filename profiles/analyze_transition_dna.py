#!/usr/bin/env python3
import argparse
import json
from collections import Counter, defaultdict

from analysis_common import latest_session, dist


def analyze(header, events):
    events = sorted(events, key=lambda e: float(e.get("tMs", 0.0)))
    down = [e for e in events if e.get("kind") == "down"]
    up = [e for e in events if e.get("kind") == "up"]

    if len(down) < 2:
        return {
            "session_start": header.get("startedAtISO8601") if header else None,
            "notes": ["Not enough down events for transition analysis."],
        }

    dwell_by_sub = defaultdict(list)
    for e in up:
        d = e.get("dwellMs")
        if d is None:
            continue
        sub = e.get("subCategory", "none")
        dwell_by_sub[sub].append(float(d))

    pair_counts = Counter()
    pair_dt = defaultdict(list)
    cat_pair_counts = Counter()
    cat_pair_dt = defaultdict(list)

    for i in range(1, len(down)):
        a = down[i - 1]
        b = down[i]
        dt = float(b.get("tMs", 0.0)) - float(a.get("tMs", 0.0))
        if dt <= 0:
            continue

        s1 = a.get("subCategory", "none")
        s2 = b.get("subCategory", "none")
        c1 = a.get("category", "unknown")
        c2 = b.get("category", "unknown")

        pair = f"{s1}->{s2}"
        cat_pair = f"{c1}->{c2}"

        pair_counts[pair] += 1
        pair_dt[pair].append(dt)
        cat_pair_counts[cat_pair] += 1
        cat_pair_dt[cat_pair].append(dt)

    top_pairs = []
    for pair, cnt in pair_counts.most_common(50):
        top_pairs.append({
            "pair": pair,
            "count": cnt,
            "flight_ms": dist(pair_dt[pair]),
        })

    top_cat_pairs = []
    for pair, cnt in cat_pair_counts.most_common(30):
        top_cat_pairs.append({
            "pair": pair,
            "count": cnt,
            "flight_ms": dist(cat_pair_dt[pair]),
        })

    dwell_sub = []
    for sub, vals in sorted(dwell_by_sub.items(), key=lambda kv: len(kv[1]), reverse=True):
        if len(vals) < 5:
            continue
        dwell_sub.append({
            "subcategory": sub,
            "count": len(vals),
            "dwell_ms": dist(vals),
        })

    signature_vector = {
        "top_pair_ids": [x["pair"] for x in top_pairs[:20]],
        "top_pair_p50_ms": [x["flight_ms"]["p50"] for x in top_pairs[:20]],
        "top_cat_pair_ids": [x["pair"] for x in top_cat_pairs[:10]],
        "top_cat_pair_p50_ms": [x["flight_ms"]["p50"] for x in top_cat_pairs[:10]],
        "top_subcategory_dwell_ids": [x["subcategory"] for x in dwell_sub[:10]],
        "top_subcategory_dwell_p50_ms": [x["dwell_ms"]["p50"] for x in dwell_sub[:10]],
    }

    return {
        "session_start": header.get("startedAtISO8601") if header else None,
        "down_count": len(down),
        "up_count": len(up),
        "top_subcategory_pairs": top_pairs,
        "top_category_pairs": top_cat_pairs,
        "dwell_by_subcategory": dwell_sub[:30],
        "signature_vector": signature_vector,
    }


def to_md(rep):
    lines = ["# Transition DNA Analysis", ""]
    lines.append(f"- session_start: {rep.get('session_start')}")
    lines.append(f"- down_count: {rep.get('down_count')}")
    lines.append(f"- up_count: {rep.get('up_count')}")
    lines.append("")
    lines.append("## Top Subcategory Transitions")
    for row in rep.get("top_subcategory_pairs", [])[:15]:
        lines.append(
            f"- {row['pair']} count={row['count']} p50={row['flight_ms']['p50']:.1f}ms p95={row['flight_ms']['p95']:.1f}ms"
        )
    lines.append("")
    lines.append("## Top Dwell by Subcategory")
    for row in rep.get("dwell_by_subcategory", [])[:10]:
        lines.append(
            f"- {row['subcategory']} count={row['count']} p50={row['dwell_ms']['p50']:.1f}ms p95={row['dwell_ms']['p95']:.1f}ms"
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

    print("transition dna analysis complete")
    print("- json:", out_json)
    print("- md:", out_md)


if __name__ == "__main__":
    main()
