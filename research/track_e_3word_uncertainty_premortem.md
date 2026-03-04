# Track E - 3-Word AI Uncertainty Pre-Mortem

Date: March 2, 2026
Scope: Stress-test the 3-word uncertainty feature before implementation.

## Context Assumptions
- Current engine already has pause and typo/correction behavior in a monolithic runtime loop.
- Proposed feature adds chunk-level uncertainty (hesitate, rewrite, late-correct) and optional cloud metadata.
- Product goal is realism without chaos, semantic drift, or major latency inflation.

## Pre-Mortem: "It failed in production" - Why?

### [TIGER] 1) Latency explosion from per-chunk model calls
Failure mode:
- A cloud call is made for each ~3-word chunk. At 100 words, this is roughly 30-35 calls.
- Even modest p95 network latency creates visible stalls and throughput regression.

Why this is likely:
- The current typing engine is synchronous and sleep-driven; adding blocking RPC inside the loop compounds delay.

Fix:
- Enforce async lookahead (prefetch next 3-5 chunks) with strict timeout budget per chunk.
- If metadata is unavailable by deadline, execute deterministic fallback immediately.
- Add circuit breaker: after N timeouts/failures, disable cloud mode for the rest of run.

Safe limits:
- Timeout budget: <=80ms/chunk.
- Added overhead target: <=10% per 100 words.

### [TIGER] 2) Rewrite loops and correction storms
Failure mode:
- Low-confidence chunks repeatedly trigger rewrite/late-correct logic.
- Combined with existing typo model, this causes cascading backspaces and chaotic output.

Why this is likely:
- Current engine already injects typo corrections. Uncertainty rewrites stack on top unless arbitrated.

Fix:
- Single-action rule: at most one uncertainty action per chunk.
- Cooldown rule: minimum 10-15 words between uncertainty rewrites.
- Mutual exclusion with typo subsystem: if a typo correction occurred in last N chars, skip uncertainty rewrite.
- Hard run budget: max rewrites and max backspaces per 100 words.

Safe limits:
- Max rewrites: 2 per 100 words in MVP.
- Max rewrite burst: <=6 backspaces.

### [TIGER] 3) Meaning drift / text fidelity breaks
Failure mode:
- "Alt phrase" generation changes meaning, formatting, legal wording, code, IDs, or URLs.
- User expects exact paste content but receives altered text.

Why this is likely:
- Plan allows optional replacement phrase; no strict fidelity policy in runtime invariants.

Fix:
- In MVP, rewrite is visual-only: delete and retype the exact same original span.
- No synonym swaps in safe mode.
- Add strict mode default-on for high-risk content (code-like, URL/email/number-heavy, form fields).

Safe limits:
- Final output must be byte-identical to input in minimal safe version.

### [TIGER] 4) Boundary errors on non-prose text
Failure mode:
- 3-word chunking breaks on code, markdown, CLI flags, punctuation-heavy text, CJK/no-space languages.
- Edits occur at syntactically unsafe boundaries.

Why this is likely:
- Fixed "3-word" strategy assumes whitespace-delimited natural language.

Fix:
- Replace fixed chunk size with boundary-aware tokenizer.
- Disable uncertainty actions for protected tokens: code spans, URLs, emails, long numerics, quoted literals.
- For unsupported scripts, degrade to pause-only uncertainty (no backspace rewrite).

Safe limits:
- If tokenization confidence is low, force deterministic pause-only mode.

### [TIGER] 5) Cancellation and responsiveness regressions
Failure mode:
- User hits Esc but run continues during model wait or long rewrite burst.

Why this is likely:
- Current cancellation is polled in-loop; blocking operations can delay checks.

Fix:
- Cancellation checkpoints before/after every uncertainty action and before waiting on model futures.
- Model wait must be non-blocking with cancellable deadline.
- Cap uninterrupted action segments (e.g., no burst longer than 1 second without cancel check).

### [ELEPHANT] 6) Privacy and policy risk if clipboard context is sent to cloud
Concern:
- Clipboard content may include sensitive data and gets transmitted for confidence metadata.

Fix:
- Local deterministic mode as default.
- Explicit opt-in for cloud uncertainty with clear disclosure and redaction policy.
- Content classifier blocks cloud calls for likely sensitive text.

### [ELEPHANT] 7) "More realism" can become stealth feature pressure
Concern:
- Team incentives drift toward detector-evasion behavior over product safety and reliability.

Fix:
- Ship gates prioritize stability, fidelity, and user control first.
- Require risk review for any realism increase that raises abuse potential.

### [PAPER] "Any rewrite looks fake"
Assessment:
- Not always true. Rare, bounded, context-aware delete/retype can improve realism.
- The problem is unbounded frequency and semantic alteration, not rewrite itself.

## Edge Cases to Explicitly Test
- Very short text (<6 words): uncertainty should be off.
- Long uninterrupted token (hash, UUID, URL, base64): no rewrite.
- Code block / markdown with punctuation and symbols: pause-only or fully off.
- CJK or mixed-script text: no word-based rewrite.
- Emoji and multi-scalar graphemes: backspace unit correctness.
- High typo profile + uncertainty high: verify arbitration prevents cascades.
- Network jitter/timeouts in cloud mode: verify deterministic fallback and no stalls.

## Anti-Patterns (Do Not Ship)
- Per-chunk blocking RPC in main typing path.
- Unbounded rewrite probability tied only to "low confidence".
- Allowing generated alternative text in strict/exact contexts.
- Running uncertainty and typo corrections independently without shared budget.
- No telemetry for rewrite counts, fallback rate, or latency deltas.

## Guardrail Contract (Implementation)
- Deterministic fallback always available.
- Byte-identical output invariant in safe mode.
- Bounded action budgets (rewrites/backspaces/time overhead).
- Cooldown + mutual exclusion with typo subsystem.
- Cancellation responsiveness invariant.
- Telemetry per run:
  - uncertainty actions/100 words
  - rewrite bursts and max burst length
  - fallback rate
  - added latency vs baseline

## Minimal Safe Version (Ship This First)
1. Deterministic-only uncertainty (no cloud).
2. Pause-only + very rare delete/retype of exact same span (no semantic changes).
3. Dynamic chunk planner uses punctuation-aware boundaries, not strict 3-word slices.
4. Hard budgets:
   - max 2 rewrites per 100 words
   - max 6 backspaces per rewrite
   - max 10% throughput overhead
5. Mutual exclusion with typo corrections (never overlap in same local window).
6. Automatic disable contexts:
   - code-like text
   - URLs/emails/long numbers
   - short messages (<6 words)
7. Escape/cancel check between every uncertainty action.
8. Feature flag default OFF plus telemetry, then staged rollout.

If this minimal safe version hits realism gains without guardrail breaches, then add cloud metadata as a non-blocking optimization behind a second flag.
