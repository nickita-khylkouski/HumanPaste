#!/usr/bin/env python3
import json
import sys
from collections import Counter, defaultdict
from statistics import mean


def pctl(vals, q):
    if not vals:
        return 0.0
    s = sorted(vals)
    i = int((len(s)-1) * q)
    return s[i]


def parse_latest_session(path):
    sessions = []
    cur = {"header": None, "events": []}
    with open(path, "r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            obj = json.loads(line)
            if obj.get("kind") == "session_start":
                if cur["header"] or cur["events"]:
                    sessions.append(cur)
                cur = {"header": obj, "events": []}
            else:
                cur["events"].append(obj)
    if cur["header"] or cur["events"]:
        sessions.append(cur)
    if not sessions:
        return None, []
    latest = sessions[-1]
    return latest.get("header"), latest.get("events", [])


def summarize_distribution(vals):
    return {
        "count": len(vals),
        "p50": pctl(vals, 0.5),
        "p95": pctl(vals, 0.95),
        "mean": mean(vals) if vals else 0.0,
    }


def main(path, out):
    header, events = parse_latest_session(path)
    if header is None:
        raise SystemExit("No session in log")

    by_kind = Counter(e.get("kind") for e in events)
    by_cat = Counter(e.get("category", "unknown") for e in events if e.get("kind") in ("down", "up"))

    dwell_by_cat = defaultdict(list)
    downs = []
    idle_gaps = []
    for e in events:
        k = e.get("kind")
        if k == "up" and e.get("dwellMs") is not None:
            dwell_by_cat[e.get("category", "unknown")].append(float(e["dwellMs"]))
        elif k == "down":
            downs.append((float(e.get("tMs", 0.0)), e.get("category", "unknown")))
        elif k == "idle_gap" and e.get("gapMs") is not None:
            idle_gaps.append(float(e["gapMs"]))

    downs.sort(key=lambda x: x[0])
    idle_threshold = float(header.get("idleGapThresholdMs", 2000))
    flight_all_raw = []
    flight_all_training = []
    flight_transition_raw = defaultdict(list)
    flight_transition_training = defaultdict(list)
    transition_counts = Counter()

    burst_lengths = []
    cur_burst = 0
    for i in range(1, len(downs)):
        t0, c0 = downs[i-1]
        t1, c1 = downs[i]
        dt = t1 - t0
        if dt <= 0:
            continue
        flight_all_raw.append(dt)
        flight_all_training.append(dt) if dt <= idle_threshold else None
        key = f"{c0}->{c1}"
        flight_transition_raw[key].append(dt)
        if dt <= idle_threshold:
            flight_transition_training[key].append(dt)
        transition_counts[key] += 1

        if dt < idle_threshold:
            cur_burst += 1
        else:
            if cur_burst > 0:
                burst_lengths.append(cur_burst)
            cur_burst = 0
    if cur_burst > 0:
        burst_lengths.append(cur_burst)

    dwell_summary = {cat: summarize_distribution(vals) for cat, vals in dwell_by_cat.items()}
    flight_transition_raw_summary = {
        k: summarize_distribution(v)
        for k, v in sorted(flight_transition_raw.items(), key=lambda kv: len(kv[1]), reverse=True)
    }
    flight_transition_training_summary = {
        k: summarize_distribution(v)
        for k, v in sorted(flight_transition_training.items(), key=lambda kv: len(kv[1]), reverse=True)
    }

    result = {
        "session_started": header.get("startedAtISO8601"),
        "idle_gap_threshold_ms": header.get("idleGapThresholdMs"),
        "event_counts": dict(by_kind),
        "category_counts": dict(by_cat),
        "dwell_by_category_ms": dwell_summary,
        "flight_all_ms_raw": summarize_distribution(flight_all_raw),
        "flight_all_ms_training": summarize_distribution(flight_all_training),
        "flight_transition_ms_raw": flight_transition_raw_summary,
        "flight_transition_ms_training": flight_transition_training_summary,
        "transition_counts": dict(transition_counts),
        "idle_gap_ms": summarize_distribution(idle_gaps),
        "burst_length_keys": summarize_distribution(burst_lengths),
    }

    with open(out, "w", encoding="utf-8") as f:
        json.dump(result, f, indent=2)

    print("feature extraction complete")
    print("- output:", out)
    print("- events:", len(events))
    print("- top categories:", dict(by_cat))


if __name__ == "__main__":
    if len(sys.argv) != 3:
        print("Usage: extract_global_timing_features.py <log.ndjson> <out.json>", file=sys.stderr)
        raise SystemExit(2)
    main(sys.argv[1], sys.argv[2])
