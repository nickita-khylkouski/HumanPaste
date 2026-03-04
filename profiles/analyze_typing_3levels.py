#!/usr/bin/env python3
import argparse
import json
from collections import Counter
from statistics import mean


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


def finalize_word(words, cur_word, boundary, boundary_t):
    if not cur_word:
        return None
    end_t = cur_word.get("end_t", cur_word["start_t"])
    duration_ms = max(1.0, end_t - cur_word["start_t"])
    chars = cur_word["letters"] + cur_word["numbers"] + cur_word["symbols"]
    cps = (chars / duration_ms) * 1000.0 if chars > 0 else 0.0
    row = {
        "word_index": len(words) + 1,
        "start_t_ms": cur_word["start_t"],
        "end_t_ms": end_t,
        "duration_ms": duration_ms,
        "chars": chars,
        "letters": cur_word["letters"],
        "numbers": cur_word["numbers"],
        "symbols": cur_word["symbols"],
        "chars_per_sec": cps,
        "boundary": boundary,
        "boundary_t_ms": boundary_t,
    }
    words.append(row)
    return row


def analyze_events(header, events):
    events = sorted(events, key=lambda e: float(e.get("tMs", 0.0)))

    by_kind = Counter(e.get("kind") for e in events)
    down_events = [e for e in events if e.get("kind") == "down"]
    up_events = [e for e in events if e.get("kind") == "up"]

    by_cat = Counter(e.get("category", "unknown") for e in down_events + up_events)
    by_subcat = Counter(e.get("subCategory", "none") for e in down_events + up_events)

    dwell_by_cat = {}
    for cat in sorted(set(e.get("category", "unknown") for e in up_events)):
        vals = [float(e["dwellMs"]) for e in up_events if e.get("category") == cat and e.get("dwellMs") is not None]
        if vals:
            dwell_by_cat[cat] = dist(vals)

    idle_gaps = [float(e["gapMs"]) for e in events if e.get("kind") == "idle_gap" and e.get("gapMs") is not None]

    # Level 2 + 3: word/sentence proxies from timing categories.
    terminal_subcats = {"period_terminal", "question_terminal", "exclamation_terminal", "return"}
    boundary_subcats = terminal_subcats | {"space", "tab", "comma", "semicolon", "colon"}

    words = []
    sentences = []
    punctuation_counts = Counter()

    cur_word = None
    cur_sentence = {"start_t": None, "word_start_idx": 1, "word_count": 0}

    def sentence_boundary(boundary_t):
        nonlocal cur_sentence
        if cur_sentence["word_count"] <= 0 or cur_sentence["start_t"] is None:
            return
        sentence_words = words[cur_sentence["word_start_idx"] - 1: cur_sentence["word_start_idx"] - 1 + cur_sentence["word_count"]]
        end_t = sentence_words[-1]["end_t_ms"]
        sentences.append({
            "sentence_index": len(sentences) + 1,
            "word_count": cur_sentence["word_count"],
            "start_t_ms": cur_sentence["start_t"],
            "end_t_ms": end_t,
            "duration_ms": max(1.0, end_t - cur_sentence["start_t"]),
            "boundary_t_ms": boundary_t,
        })
        cur_sentence = {"start_t": None, "word_start_idx": len(words) + 1, "word_count": 0}

    for e in events:
        k = e.get("kind")
        t = float(e.get("tMs", 0.0))

        if k == "idle_gap":
            finalize_word(words, cur_word, "idle_gap", t)
            cur_word = None
            sentence_boundary(t)
            continue

        if k != "down":
            continue

        cat = e.get("category", "unknown")
        sub = e.get("subCategory", "none")

        if sub in terminal_subcats:
            punctuation_counts[sub] += 1

        is_word_char = cat in ("letter", "number", "symbol") and sub not in boundary_subcats
        is_boundary = (cat == "whitespace") or (sub in boundary_subcats)

        if is_word_char:
            if cur_word is None:
                cur_word = {"start_t": t, "end_t": t, "letters": 0, "numbers": 0, "symbols": 0}
                if cur_sentence["start_t"] is None:
                    cur_sentence["start_t"] = t
            else:
                cur_word["end_t"] = t

            if cat == "letter":
                cur_word["letters"] += 1
            elif cat == "number":
                cur_word["numbers"] += 1
            else:
                cur_word["symbols"] += 1

        if is_boundary:
            row = finalize_word(words, cur_word, sub, t)
            if row is not None:
                cur_sentence["word_count"] += 1
            cur_word = None
            if sub in terminal_subcats:
                sentence_boundary(t)

    row = finalize_word(words, cur_word, "end_of_stream", float(events[-1].get("tMs", 0.0)) if events else 0.0)
    if row is not None:
        cur_sentence["word_count"] += 1
    sentence_boundary(float(events[-1].get("tMs", 0.0)) if events else 0.0)

    word_durations = [w["duration_ms"] for w in words]
    word_lengths = [w["chars"] for w in words]
    effective_words = [w for w in words if w["chars"] >= 2 and w["duration_ms"] >= 80.0]
    word_speeds = [w["chars_per_sec"] for w in effective_words if w["chars_per_sec"] > 0]

    sentence_word_counts = [s["word_count"] for s in sentences]
    sentence_durations = [s["duration_ms"] for s in sentences]

    # Warm-up / fatigue signals
    n = len(word_speeds)
    first = word_speeds[: min(20, n)]
    last = word_speeds[max(0, n - 20):]
    speed_slope = linear_slope(word_speeds)

    level1 = {
        "session_start": header.get("startedAtISO8601") if header else None,
        "idle_gap_threshold_ms": float(header.get("idleGapThresholdMs", 2000)) if header else 2000,
        "total_events": len(events),
        "kind_counts": dict(by_kind),
        "category_counts": dict(by_cat),
        "subcategory_counts": dict(by_subcat),
        "dwell_by_category_ms": dwell_by_cat,
        "idle_gap_ms": dist(idle_gaps),
    }

    level2 = {
        "word_proxy_count": len(words),
        "word_proxy_effective_count": len(effective_words),
        "word_length_chars": dist(word_lengths),
        "word_duration_ms": dist(word_durations),
        "word_speed_chars_per_sec": dist(word_speeds),
        "speed_first20_mean_cps": mean(first) if first else 0.0,
        "speed_last20_mean_cps": mean(last) if last else 0.0,
        "speed_trend_slope_cps_per_word": speed_slope,
        "slow_to_start_then_warmup": (mean(last) > (mean(first) * 1.10)) if first and last else False,
        "slowest_word_samples": sorted(effective_words, key=lambda w: w["chars_per_sec"])[:5],
        "fastest_word_samples": sorted(effective_words, key=lambda w: w["chars_per_sec"], reverse=True)[:5],
    }

    level3 = {
        "sentence_proxy_count": len(sentences),
        "sentence_length_words": dist(sentence_word_counts),
        "sentence_duration_ms": dist(sentence_durations),
        "terminal_punctuation_counts": dict(punctuation_counts),
        "sentence_samples": sentences[:10],
        "notes": [
            "Sentence proxies use terminal punctuation subcategories + return + idle gaps.",
            "No raw text reconstructed; this is timing and structure telemetry only."
        ],
    }

    return {
        "level_1_macro": level1,
        "level_2_word_rhythm": level2,
        "level_3_sentence_style": level3,
    }


def to_markdown(report):
    l1 = report["level_1_macro"]
    l2 = report["level_2_word_rhythm"]
    l3 = report["level_3_sentence_style"]

    lines = []
    lines.append("# Typing Analysis (3 Levels)")
    lines.append("")
    lines.append("## Level 1 — Macro")
    lines.append(f"- session_start: {l1.get('session_start')}")
    lines.append(f"- total_events: {l1.get('total_events')}")
    lines.append(f"- categories: {l1.get('category_counts')}")
    lines.append(f"- subcategories: {l1.get('subcategory_counts')}")
    lines.append(f"- idle_gap_ms: {l1.get('idle_gap_ms')}")
    lines.append("")

    lines.append("## Level 2 — Word Rhythm")
    lines.append(f"- word_proxy_count: {l2.get('word_proxy_count')}")
    lines.append(f"- word_length_chars: {l2.get('word_length_chars')}")
    lines.append(f"- word_duration_ms: {l2.get('word_duration_ms')}")
    lines.append(f"- word_speed_chars_per_sec: {l2.get('word_speed_chars_per_sec')}")
    lines.append(f"- speed_first20_mean_cps: {l2.get('speed_first20_mean_cps'):.3f}")
    lines.append(f"- speed_last20_mean_cps: {l2.get('speed_last20_mean_cps'):.3f}")
    lines.append(f"- speed_trend_slope_cps_per_word: {l2.get('speed_trend_slope_cps_per_word'):.6f}")
    lines.append(f"- slow_to_start_then_warmup: {l2.get('slow_to_start_then_warmup')}")
    lines.append("")

    lines.append("Example slow words (proxy)")
    for row in l2.get("slowest_word_samples", [])[:5]:
        lines.append(
            f"- word#{row['word_index']} len={row['chars']} duration_ms={row['duration_ms']:.1f} cps={row['chars_per_sec']:.2f} boundary={row['boundary']}"
        )
    lines.append("")

    lines.append("## Level 3 — Sentence / Style")
    lines.append(f"- sentence_proxy_count: {l3.get('sentence_proxy_count')}")
    lines.append(f"- sentence_length_words: {l3.get('sentence_length_words')}")
    lines.append(f"- sentence_duration_ms: {l3.get('sentence_duration_ms')}")
    lines.append(f"- terminal_punctuation_counts: {l3.get('terminal_punctuation_counts')}")
    lines.append("")

    return "\n".join(lines)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("log_path")
    ap.add_argument("out_prefix")
    ap.add_argument("--all", action="store_true", help="merge all sessions instead of latest")
    args = ap.parse_args()

    sessions = parse_sessions(args.log_path)
    if not sessions:
        raise SystemExit("No sessions in log")

    if args.all:
        header = sessions[-1].get("header")
        events = []
        for s in sessions:
            events.extend(s.get("events", []))
    else:
        header = sessions[-1].get("header")
        events = sessions[-1].get("events", [])

    report = analyze_events(header, events)
    out_json = f"{args.out_prefix}.json"
    out_md = f"{args.out_prefix}.md"

    with open(out_json, "w", encoding="utf-8") as f:
        json.dump(report, f, indent=2)
    with open(out_md, "w", encoding="utf-8") as f:
        f.write(to_markdown(report))

    print("3-level analysis complete")
    print("- json:", out_json)
    print("- md:", out_md)


if __name__ == "__main__":
    main()
