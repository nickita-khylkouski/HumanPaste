#!/usr/bin/env python3
import json
import sys
from collections import Counter, defaultdict
from statistics import mean


def pctl(vals, q):
    if not vals:
        return 0.0
    s = sorted(vals)
    i = int((len(s) - 1) * q)
    return s[i]


def parse_sessions(path):
    sessions=[]
    cur={"header":None,"events":[]}
    with open(path, "r", encoding="utf-8") as f:
        for line in f:
            line=line.strip()
            if not line:
                continue
            obj=json.loads(line)
            if obj.get("kind")=="session_start":
                if cur["header"] or cur["events"]:
                    sessions.append(cur)
                cur={"header":obj,"events":[]}
            else:
                cur["events"].append(obj)
    if cur["header"] or cur["events"]:
        sessions.append(cur)
    return sessions

def main(path, latest_only=True):
    sessions=parse_sessions(path)
    if not sessions:
        print("No sessions")
        return
    if latest_only:
        target=[sessions[-1]]
    else:
        target=sessions

    header=target[-1].get("header")
    events=[]
    for sess in target:
        events.extend(sess.get("events",[]))

    by_kind = Counter(e['kind'] for e in events)
    by_cat = Counter(e.get('category', 'unknown') for e in events if e['kind'] in ('down', 'up'))
    by_subcat = Counter(e.get('subCategory', 'none') for e in events if e['kind'] in ('down', 'up'))

    dwell_by_cat = defaultdict(list)
    for e in events:
        if e.get('kind') == 'up' and e.get('dwellMs') is not None:
            dwell_by_cat[e.get('category', 'unknown')].append(float(e['dwellMs']))

    idle_gaps = [float(e['gapMs']) for e in events if e.get('kind') == 'idle_gap' and e.get('gapMs') is not None]

    print('Global timing summary')
    if header:
        print(f"- started: {header.get('startedAtISO8601')}")
        print(f"- idle-gap-threshold-ms: {header.get('idleGapThresholdMs')}")
    print(f"- total-events: {len(events)}")
    print(f"- kinds: {dict(by_kind)}")
    print(f"- categories: {dict(by_cat)}")
    print(f"- subcategories: {dict(by_subcat)}")

    print('- dwell-by-category-ms:')
    for cat, vals in sorted(dwell_by_cat.items()):
        print(
            f"  - {cat}: count={len(vals)} p50={pctl(vals,0.5):.1f} p95={pctl(vals,0.95):.1f} mean={mean(vals):.1f}"
        )

    if idle_gaps:
        print(f"- idle-gaps: count={len(idle_gaps)} p50={pctl(idle_gaps,0.5):.1f} p95={pctl(idle_gaps,0.95):.1f}")
    else:
        print('- idle-gaps: none')


if __name__ == '__main__':
    if len(sys.argv) < 2 or len(sys.argv) > 3:
        print('Usage: summarize_global_timing_log.py <path.ndjson> [--all]', file=sys.stderr)
        raise SystemExit(2)
    latest_only = not (len(sys.argv) == 3 and sys.argv[2] == '--all')
    main(sys.argv[1], latest_only=latest_only)
