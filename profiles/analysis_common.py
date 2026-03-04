#!/usr/bin/env python3
import json
from statistics import mean


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


def latest_session(path):
    sessions = parse_sessions(path)
    if not sessions:
        return None, []
    s = sessions[-1]
    return s.get("header"), s.get("events", [])


def pctl(vals, q):
    if not vals:
        return 0.0
    s = sorted(vals)
    i = int((len(s) - 1) * q)
    return s[i]


def dist(vals):
    return {
        "count": len(vals),
        "p50": pctl(vals, 0.50),
        "p95": pctl(vals, 0.95),
        "mean": mean(vals) if vals else 0.0,
    }


def linear_slope(values):
    n = len(values)
    if n < 2:
        return 0.0
    xs = list(range(n))
    x_bar = (n - 1) / 2.0
    y_bar = sum(values) / n
    num = sum((x - x_bar) * (y - y_bar) for x, y in zip(xs, values))
    den = sum((x - x_bar) ** 2 for x in xs)
    if den == 0:
        return 0.0
    return num / den


def chunk(seq, n):
    for i in range(0, len(seq), n):
        yield seq[i:i+n]
