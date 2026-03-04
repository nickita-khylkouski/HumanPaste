# HumanPaste Main Team Handoff

Date: March 2, 2026
Owner: R&D prototype track
Scope: AI prediction + humanized correction behavior prototypes only

## 1) What this handoff is
This is the complete R&D handoff for the new "human uncertainty" feature direction.
It includes:
- product ideas worth building,
- prototype code already implemented,
- what was tested and verified,
- known failure modes and fixes,
- exact integration steps for engineering.

This work was intentionally done in **new prototype files** and did not modify the current production typing path.

---

## 2) Feature direction (recommended)

### Primary feature (build first)
1. **Predictive False Start**
- At selected boundaries, generate a 2-4 word phrase.
- Type it, pause, backspace it, then continue canonical clipboard text.
- Goal: realistic uncertainty without changing final output.

### Secondary feature
2. **Cursor Visual Correction**
- Occasional short backtrack + delete/retype of exact recent span.
- Goal: add realistic late correction behavior.

### Keep/skip guidance
- Keep: deterministic fallback, strict event caps, protected-token exclusions.
- Skip for v1: semantic rewrites, high-frequency edits, per-chunk blocking cloud calls.

---

## 3) What was implemented (prototype files)
All files are under:
- `/Users/nickita/.superset/worktrees/start/sigma/HumanPaste/prototypes`

Implemented files:
1. `UncertaintyTypes.swift`
- Action DSL: `type`, `pause`, `backspace`, `deleteForward`, cursor moves.

2. `UncertaintyConfig.swift`
- Full config model + loader defaults.
- Includes provider/model/timeout config.

3. `PredictionProvider.swift`
- `PredictionProvider` protocol.
- `PredictionProviderFactory`.
- Deterministic fallback provider.
- OpenAI provider (`OpenAIPredictionProvider`) with env key loading.

4. `FalseStartPlanner.swift`
- Trigger logic and false-start action construction.

5. `CursorEditPlanner.swift`
- Visual correction action planner using forward delete.

6. `BoundaryTokenizer.swift`
- Boundary-aware tokenization preserving punctuation/whitespace structure.

7. `UncertaintyEngine.swift`
- Core orchestration over canonical text.
- Inserts synthetic events while preserving canonical output.

8. `config/default_uncertainty_config.json`
- Default settings.

9. `prompts/predictive_false_start_prompt.txt`
- Cloud prompt template.

10. `INTEGRATION_CHECKLIST.md`
- Wiring steps for software team.

11. `README.md`
- Prototype usage notes.

---

## 4) Core decisions made

1. **Canonical integrity is mandatory**
- Final emitted text must exactly equal input clipboard text.

2. **Boundary-aware processing**
- Avoid split/join whitespace loss; emit canonical token-by-token.

3. **Forward-delete for cursor correction**
- Backtrack then delete-forward fixed earlier corruption bug.

4. **Cloud is optional, fallback is mandatory**
- If cloud unavailable/slow: deterministic provider path.

5. **Fast model default for this feature**
- Default model set to `gpt-4.1-nano` (measured best practical latency for this payload).

---

## 5) Test evidence

### Compile/typecheck
- `swiftc -typecheck HumanPaste/prototypes/*.swift` passes.

### Integrity and formatting
- Combined stress test: `sample_runs=200 mismatch=0`.
- Formatting test: preserves newlines/tabs/double spaces (`formatting_equal=true`).
- Short text behavior: bypasses synthetic edits and returns canonical text.

### OpenAI live tests (chat/completions payload used by prototype)
- `gpt-4.1-nano`: non-empty responses 5/5, p50 ~534ms, p90 ~581ms.
- `gpt-4o-mini`: slower in this benchmark (~624ms p50).
- `gpt-5-nano`: produced empty content for this JSON-style short generation path in benchmark runs.

### End-to-end with OpenAI provider
- Realistic message sample run:
  - `false_starts=2`
  - `integrity_equal=true`
  - elapsed ~1.2s for planning/action generation in that test harness.

---

## 6) Known risks / where this can fail

1. **Cloud latency spikes**
- Mitigation: timeout + fallback + budget cap per message.

2. **Protected token false positives/negatives**
- Current detection is heuristic; must expand before production rollout.

3. **Over-edit behavior**
- Needs strict caps/cooldowns to avoid synthetic feel.

4. **Provider contract drift**
- OpenAI API behavior may evolve; keep provider isolated and version-tested.

---

## 7) Security note
A project API key was exposed during R&D chat.
- Action required: **revoke/rotate the leaked key immediately**.
- Production guidance: keys must be env-based only and never committed or logged.

---

## 8) Engineering integration plan (minimal)

1. Add feature flag:
- `uncertainty_prototype_enabled` default OFF.

2. Instantiate engine:
- Load config JSON.
- Provider via `PredictionProviderFactory.make(config:)`.

3. Generate action stream:
- `await UncertaintyEngine.buildActions(for: canonicalText)`.

4. Map actions to existing emitter:
- `type` -> existing char emit
- `pause` -> delay
- `backspace` -> repeat backspace
- `deleteForward` -> repeat forward delete
- cursor moves -> arrow key emits

5. Add telemetry:
- false-start count
- cursor edit count
- fallback count
- added latency ms
- integrity assertion result

6. Dogfood then rollout:
- internal only
- then 10% flag rollout if integrity and latency pass.

---

## 9) Suggested v1 defaults
(Already reflected in prototype config)
- provider: deterministic (safe default)
- cloud model when enabled: `gpt-4.1-nano`
- plan window: 3 words
- max false starts/message: 2
- max cursor edits/message: 1
- cooldown between synthetic events: 20 words
- synthetic latency budget: 1800ms

---

## 10) What not to do in v1
- Do not let synthetic edits alter semantic meaning.
- Do not run blocking cloud call per token/window without timeout fallback.
- Do not enable by default in production until telemetry validates behavior.

