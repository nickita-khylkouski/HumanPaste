# HumanPaste Typing Engine v3 Architecture Proposal

## Scope
This document defines a production-ready architecture for a new `v3` typing engine that replaces the current monolithic `HumanTyper.performTyping` loop with a deterministic, testable pipeline.

Goals:
- Separate planning from execution.
- Support precise scheduling of `keyDown`/`keyUp` with dwell, flight, and rollover overlap.
- Keep existing app behavior (`Ctrl+Shift+V`, menu speed/typo profiles, cancel) while enabling deep tests.

Non-goals:
- UI redesign.
- New detector-evasion heuristics beyond current model inputs.

---

## Current Constraints (from codebase)
- `HumanTyper.swift` mixes planning, timing, sleeping, and event emission in one loop.
- `KeystrokeEmitter.swift` emits real CGEvents directly and sleeps internally for dwell.
- `main.swift` integrates via `HumanTyper.typeText(_:)`, profile fields, callbacks, and `cancel()`.
- Build is file-list based (`build.sh`), so adding engine modules requires explicit compile list updates.

---

## v3 Module Boundaries

### 1) Engine Facade (`TypingEngineV3`)
Single public API used by app layer.

Responsibilities:
- Accept text and runtime config.
- Start/cancel run.
- Publish lifecycle callbacks (`onStarted`, `onStopped`, `onProgress`, `onError`).
- Own worker queue and run state.

Public surface:
```swift
protocol TypingEngine {
    var isTyping: Bool { get }
    func typeText(_ text: String)
    func cancel()
}
```

### 2) Plan Builder (`TypingPlanBuilder`)
Converts input text into semantic typing actions, independent of real time.

Responsibilities:
- Text segmentation (`char`, word boundaries, sentence boundaries, paragraph boundaries).
- Error injection decisions (substitution/omission/insertion/transposition).
- Produces canonical action stream (e.g., `press(char)`, `backspace`, `pause(reason)`).

Input:
- Raw text
- `SpeedProfile`, `TypoProfile`, `TypingCalibration`
- RNG

Output:
- `TypingPlan` (ordered logical actions, no timestamps yet)

### 3) Timing Model (`TimingSampler`)
Pure timing policy.

Responsibilities:
- Sample dwell and flight per action pair.
- Sample cognitive pauses.
- Compute rollover decision and overlap duration.
- Enforce timing bounds.

Input:
- Logical actions + context (prev char, next char, key metadata, burst/fatigue state)

Output:
- `TimingDecision` per transition:
  - `dwellMs`
  - `flightMs`
  - `rollover: Bool`
  - `overlapMs`
  - `postPauseMs`

### 4) Schedule Compiler (`EventScheduleCompiler`)
Transforms logical actions + timing decisions into absolute timestamped key events.

Responsibilities:
- Generate `ScheduledEvent(time, keyEvent)` sequence using monotonic time origin.
- Guarantee invariants (ordering, non-negative intervals, legal overlap).
- Normalize to platform-independent event model.

Core output type:
```swift
enum KeyEvent {
    case keyDown(Character)
    case keyUp(Character)
    case backspaceDown, backspaceUp
    case returnDown, returnUp
    case tabDown, tabUp
}

struct ScheduledEvent {
    let tMonotonicMs: Double
    let event: KeyEvent
}
```

### 5) Runtime Scheduler (`EventScheduler`)
Real-time dispatcher.

Responsibilities:
- Dispatch `ScheduledEvent` at target times using monotonic clock.
- Support cancellation between events.
- Record drift metrics (`actual - scheduled`) for diagnostics.

Dependencies:
- `Clock` abstraction (real clock in app, fake in tests).
- `Sleeper` abstraction (real sleep, fake step in tests).
- `KeyEventSink` abstraction.

### 6) Event Sink (`CGEventSink`)
Platform adapter for macOS CGEvent emission.

Responsibilities:
- Convert `KeyEvent` to CGEvent and post.
- No timing logic.
- No randomization.

This replaces dwell sleeping in `emitKeystroke`; dwell is scheduler-owned.

### 7) Observability (`EngineMetrics`)
Optional but recommended.

Responsibilities:
- Track counts/rates: chars, typos by type, rollover %, pause distribution, scheduler drift.
- Export structured log lines for validation runs.

---

## Data Contracts

```swift
struct EngineConfig {
    let speedProfile: SpeedProfile
    let typoProfile: TypoProfile
    let calibration: TypingCalibration
}

struct TypingAction {
    enum Kind {
        case typeChar(Character)
        case backspace
        case `return`
        case tab
        case pause(reason: PauseReason)
    }
    let kind: Kind
    let sourceIndex: Int?
}

struct TimingDecision {
    let dwellMs: Double
    let flightMs: Double
    let rollover: Bool
    let overlapMs: Double
    let postPauseMs: Double
}
```

Rules:
- `TypingPlanBuilder` owns *what* to type.
- `TimingSampler` owns *when* each transition should happen.
- `EventScheduleCompiler` owns *exact event timestamps*.
- `EventScheduler` owns *runtime dispatch*.

---

## Event Scheduling Model (Dwell, Flight, Rollover)

Definitions for character `i`:
- `KD_i`: keyDown time
- `KU_i`: keyUp time
- `D_i`: dwell sampled for char `i`
- `F_i`: flight sampled between char `i` and `i+1`
- `R_i`: rollover flag for transition `i -> i+1`
- `O_i`: overlap duration for rollover transition

Base equations:
- `KU_i = KD_i + D_i`
- No rollover: `KD_{i+1} = KU_i + F_i`
- Rollover: `KD_{i+1} = KU_i + F_i - O_i`

Constraints:
- `0 <= O_i <= min(F_i + D_i - minGapMs, maxOverlapMs)`
- `KD_{i+1} >= KD_i + minInterDownMs`
- `KU_i >= KD_i + minDwellMs`
- `F_i, D_i, postPauseMs` are clamped by calibration bounds.

Practical interpretation:
- Flight is still modeled for every pair.
- Rollover only shifts next `keyDown` earlier by `overlapMs`; it never changes sampled dwell.
- Cognitive pauses are inserted as extra offset before next `KD` (after punctuation/word/sentence/paragraph/thinking pause actions).

---

## Reference Pseudocode

### A) Plan + Timing + Schedule Compile
```text
origin = clock.nowMonotonicMs()
currentDown = origin

for each logical action a_i in typingPlan:
  if a_i is pause:
    currentDown += samplePause(a_i)
    continue

  if a_i is key action for char c_i:
    dwell = sampleDwell(c_i, context)
    append event(currentDown, keyDown(c_i))

    keyUpAt = currentDown + dwell
    append event(keyUpAt, keyUp(c_i))

    transition = peek next key action
    if transition exists:
      flight = sampleFlight(c_i, c_next, context)
      rollover = sampleRollover(c_i, c_next, context)
      overlap = rollover ? sampleOverlap(context) : 0
      postPause = samplePostCharPause(c_i, context)

      nextDown = keyUpAt + flight - overlap + postPause
      currentDown = max(nextDown, currentDown + minInterDownMs)
```

### B) Runtime Scheduler Loop
```text
for event in scheduledEvents:
  if cancelled: break
  delta = event.tMonotonicMs - clock.nowMonotonicMs()
  if delta > 0: sleeper.sleepMs(delta)
  sink.emit(event)
  metrics.recordDrift(actual=clock.nowMonotonicMs(), scheduled=event.tMonotonicMs)
```

---

## Testing Strategy

### Unit Tests (pure, deterministic)
Use fake RNG with fixed sequence + fake clock.

1. `TimingSamplerTests`
- Dwell distribution bounds by finger.
- Flight differences for cross-hand vs same-finger.
- Rollover probability branch behavior and overlap bounds.

2. `EventScheduleCompilerTests`
- Invariant checks:
  - every `keyDown` has matching `keyUp`
  - monotonic schedule ordering
  - rollover cases have `KD_next < KU_current`
  - non-rollover cases have `KD_next >= KU_current`

3. `TypingPlanBuilderTests`
- Error-injection expansion correctness for each typo type.
- Boundary pause action insertion at punctuation/newlines.

4. `EventSchedulerTests`
- Cancellation mid-stream stops future events.
- Drift accounting for delayed clock.

### Statistical Tests (offline, seeded batch)
Run 10k+ characters across fixed seeds, assert envelope metrics:
- Mean/median dwell in expected profile range.
- Heavy-tailed flight (p95/p99 ratio > threshold).
- Rollover rate near calibration target (with tolerance).
- Error-type composition near configured rates.

### Integration Tests (macOS)
- `FakeEventSink` integration: verify exact emitted sequence and timing order.
- Optional gated test with `CGEventSink` in local/dev environment only.

### Regression Harness
Create a script target that prints JSON summary for seed sets:
- `totalChars`, `totalEvents`, `rolloverPct`, `avgDwellMs`, `avgFlightMs`, `typoBreakdown`, `schedulerDriftMs`
Use this as release gate for timing regressions.

---

## Integration Plan (Unambiguous, File-Level)

### Phase 1: Introduce v3 core alongside existing engine
Add new files (no behavior switch yet):
- `HumanPaste/engine/v3/Types.swift`
- `HumanPaste/engine/v3/TypingPlanBuilder.swift`
- `HumanPaste/engine/v3/TimingSampler.swift`
- `HumanPaste/engine/v3/EventScheduleCompiler.swift`
- `HumanPaste/engine/v3/EventScheduler.swift`
- `HumanPaste/engine/v3/TypingEngineV3.swift`
- `HumanPaste/engine/v3/CGEventSink.swift`

Update `build.sh` compile list to include new files.

Exit criteria:
- Project builds with old runtime path unchanged.

### Phase 2: Adapter bridge in `HumanTyper`
- Refactor `HumanTyper` into facade that delegates to `TypingEngineV3`.
- Preserve current public API:
  - `typeText(_:)`
  - `cancel()`
  - `typing` property
  - profile fields and callbacks.

Exit criteria:
- `main.swift` unchanged except initialization wiring if needed.
- Hotkey flow still works.

### Phase 3: Emitter split
- Move all sleeps out of `KeystrokeEmitter` path.
- Keep existing helper functions for backward compatibility if needed, but v3 uses `CGEventSink.emit(KeyEvent)` only.

Exit criteria:
- Dwell/flight controlled solely by scheduler.

### Phase 4: Test harness and fake dependencies
Add test-support files:
- `HumanPasteTests/FakeClock.swift`
- `HumanPasteTests/FakeSleeper.swift`
- `HumanPasteTests/FakeEventSink.swift`
- Unit tests for planner/sampler/compiler/scheduler.

Exit criteria:
- Deterministic tests pass on CI.

### Phase 5: Feature flag + migration
- Add runtime flag `engineVersion` defaulting to `v3` with fallback `v2`.
- Keep legacy path temporarily for rollback.
- Remove legacy path after two stable releases.

Exit criteria:
- v3 default on all builds.

---

## Compatibility and Risk Controls

Compatibility:
- Preserve existing profile structs (`SpeedProfile`, `TypoProfile`, `TypingCalibration`) to reduce migration risk.
- Preserve `main.swift` user-facing flow and menu controls.

Primary risks and mitigations:
- Timing drift under system load -> scheduler drift metrics + bounded correction.
- CGEvent edge cases for non-printable keys -> explicit key event enum + adapter tests.
- Statistical behavior drift after tuning -> seeded regression harness and envelope assertions.

---

## Implementation Checklist
- [ ] Add v3 engine modules and protocols.
- [ ] Introduce fakeable `Clock`, `Sleeper`, `KeyEventSink` abstractions.
- [ ] Implement plan builder independent of real-time.
- [ ] Implement timing sampler with rollover overlap policy.
- [ ] Implement schedule compiler with invariant checks.
- [ ] Implement runtime scheduler with cancellation/drift accounting.
- [ ] Bridge `HumanTyper` facade to v3.
- [ ] Add deterministic unit tests and seeded statistical tests.
- [ ] Add feature flag and rollout plan.

This architecture keeps behavior understandable, testable, and migration-safe while enabling precise dwell/flight/rollover scheduling without ambiguity.
