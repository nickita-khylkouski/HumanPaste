# AI Uncertainty Typing Feature Plan (Cloud-First, Local-Later)

Date: March 2, 2026
Owner: R&D
Status: Proposed

## Goal
Add a typing behavior layer that feels more human by simulating uncertainty:
- micro planning in 3-word chunks,
- occasional mid-thought corrections,
- delete-and-rewrite bursts,
- hesitation before rare words.

This is a behavior layer on top of the timing engine (dwell/flight/rollover).

## Product Idea
Humans do not type as a perfect stream. They:
- think in short phrase chunks,
- start typing, then revise,
- replace a word with a better one,
- correct after 1-3 extra words.

We model this with a lightweight "uncertainty controller".

## Architecture
1. `Chunk Planner`
- Splits input into chunks of 1-3 words.
- Assigns each chunk a confidence score (high/medium/low).

2. `Uncertainty Controller`
- If confidence is low:
  - inject hesitation pause,
  - optionally type a weak candidate then backspace and rewrite,
  - occasionally insert filler correction flow (type, delete, retype).

3. `Typing Executor`
- Receives action sequence:
  - `type(text)`
  - `pause(ms)`
  - `backspace(n)`
  - `replace(from,to)`
- Uses existing keystroke timing engine to emit events.

## Cloud-First MVP (Now)
Use a small cloud model to produce short planning metadata only.

### Input to model
- current 3-word chunk
- previous 5-10 words context
- mode (`casual`, `professional`)

### Output schema
```json
{
  "chunk": "next three words",
  "confidence": 0.0,
  "alt": "optional rewrite phrase",
  "actions": ["none" | "hesitate" | "rewrite" | "late_correct"]
}
```

### Runtime behavior
- `confidence >= 0.75`: type normally.
- `0.45 <= confidence < 0.75`: add hesitation + small punctuation pause.
- `< 0.45`: 20-35% chance rewrite flow:
  1. type tentative phrase,
  2. pause 250-700ms,
  3. backspace phrase,
  4. type alt phrase.

## Local Model Path (Later)
Run a tiny model locally for same metadata generation (not full text generation).

Candidate class:
- 1B-3B instruct model via `llama.cpp`/`MLX`.
- Quantized 4-bit for low memory.

Local mode constraints:
- max context small (<256 tokens),
- strict JSON output,
- timeout budget <120ms/chunk.

## Feature Flags
- `ai_uncertainty_enabled` (default off)
- `ai_uncertainty_provider` (`cloud` | `local`)
- `ai_uncertainty_intensity` (`low` | `med` | `high`)
- `ai_uncertainty_max_rewrites_per_100_words` (default 4)

## Safety/Quality Constraints
- Never alter semantic meaning too much in rewrite mode.
- Keep correction rate bounded; avoid chaotic typing.
- Hard cap on deletion bursts.
- If model fails/timeout: fallback to deterministic rules.

## Deterministic Fallback (No Model)
If no model response, use heuristics:
- rare/long word => higher hesitation,
- clause boundary => occasional restart,
- every 40-80 chars => optional rethink pause,
- bounded rewrite probability table.

## Metrics
Track per 100 words:
- hesitation count,
- rewrite count,
- avg backspaces,
- timeout fallback rate,
- user "felt human" rating.

Ship gates:
- fallback rate <5%,
- no stuck loops,
- no >15% throughput regression,
- positive user realism delta.

## 2-Week Build Plan
Week 1:
1. Add action DSL (`type/pause/backspace/rewrite`).
2. Implement deterministic uncertainty rules.
3. Add telemetry counters.

Week 2:
1. Add cloud metadata endpoint client.
2. Integrate with chunk planner and executor.
3. A/B test: deterministic vs cloud uncertainty.

## Open Questions
- Should rewrite preserve exact original text always, or allow synonym swap?
- Should uncertainty be disabled in strict mode (e.g. code snippets)?
- Max acceptable additional latency per 100 words?
