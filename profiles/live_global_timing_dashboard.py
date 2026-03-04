#!/usr/bin/env python3
import json
import time
import argparse
from collections import Counter, defaultdict


def pctl(vals, q):
    if not vals:
        return 0.0
    s = sorted(vals)
    i = int((len(s) - 1) * q)
    return s[i]


def parse_sessions(path):
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
    return sessions


def summarize(events):
    by_kind = Counter(e.get("kind") for e in events)
    by_cat = Counter(e.get("category", "unknown") for e in events if e.get("kind") in ("down", "up"))
    dwell = defaultdict(list)
    for e in events:
        if e.get("kind") == "up" and e.get("dwellMs") is not None:
            dwell[e.get("category", "unknown")].append(float(e["dwellMs"]))
    idle = [float(e["gapMs"]) for e in events if e.get("kind") == "idle_gap" and e.get("gapMs") is not None]
    return by_kind, by_cat, dwell, idle


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("path")
    ap.add_argument("--interval", type=float, default=2.0)
    args = ap.parse_args()

    print("Live global timing dashboard (Ctrl+C to stop)")
    while True:
        try:
            sessions = parse_sessions(args.path)
            latest = sessions[-1] if sessions else {"header": None, "events": []}
            header = latest.get("header") or {}
            events = latest.get("events", [])
            by_kind, by_cat, dwell, idle = summarize(events)

            print("\n---")
            print("started:", header.get("startedAtISO8601"))
            print("events:", len(events), "kinds:", dict(by_kind))
            print("categories:", dict(by_cat))
            for cat in sorted(dwell):
                vals = dwell[cat]
                print(f"dwell[{cat}] count={len(vals)} p50={pctl(vals,0.5):.1f} p95={pctl(vals,0.95):.1f}")
            if idle:
                print(f"idle-gaps count={len(idle)} p50={pctl(idle,0.5):.1f} p95={pctl(idle,0.95):.1f}")
            else:
                print("idle-gaps none")

            time.sleep(args.interval)
        except KeyboardInterrupt:
            print("\nstop")
            return
        except FileNotFoundError:
            print("log file not found yet")
            time.sleep(args.interval)


if __name__ == "__main__":
    main()
