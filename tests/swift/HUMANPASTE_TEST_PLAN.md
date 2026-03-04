# HumanPaste Swift Test Plan

Scope reviewed: all Swift files at repository root plus all files in `prototypes/`.

## Existing Test Coverage Snapshot
- `test_features.swift`: standalone checks for sentence-start logic, familiarity tiers, and word-position helper (replicated logic).
- `prototypes/UncertaintySelfTest.swift`: end-to-end canonical-integrity Monte Carlo for uncertainty actions.
- Gap: no XCTest/CI-integrated Swift test target; most functions are currently unverified by structured unit tests.

## 1) Unit Tests Needed For Every Function Without Tests

### ErrorModel.swift
- `rollForError(char:profile:speedMultiplier:)`
  - Non-letter chars always return `nil`.
  - Probability bins map to each `TypoType` under deterministic random seeding seam.
  - Speed multiplier scaling increases typo frequency.
- `noticeDelay()`
  - Always positive.
  - Mixture behavior produces two clusters (fast/slow) in distribution test.
- `backspaceDelay()`
  - Positive and bounded expected quantiles.
- `postCorrectionPause()`
  - Positive and expected median range.
- `charsBeforeOmissionNotice()`
  - Integer in `[1, 3]`.
- `lateNoticeDistance()`
  - Integer in `[2, 4]`.

### KeyboardLayout.swift
- `Finger.<`
  - Raw-value ordering works across all cases.
- `keyInfo(for:)`
  - Case-insensitive lookup.
  - Unknown symbols return `nil`.
- `isCrossHand(_:_:)`
  - True for opposite-hand pairs, false otherwise.
- `isSameFinger(_:_:)`
  - True only for same hand+finger.
- `nearbyWrongKey(for:)`
  - Returns neighbor from adjacency map.
  - Preserves uppercase when input is uppercase.
  - Returns `nil` for unsupported chars.
- `wordFamiliarityMultiplier(for:)`
  - Tier1/2/3 mappings exact.
  - Long rare fallback `1.12`.
  - Case-insensitive behavior.

### TimingModel.swift
- `logLogisticRandom(alpha:beta:)`
  - Positive samples; quantiles align with log-logistic theory.
- `clamp(_:min:max:)` (private; cover through public callers)
  - Implicitly validated via bounded outputs from downstream functions.
- `loadTypingCalibration()`
  - Uses defaults when files missing.
  - Prefers first valid candidate when multiple paths exist.
  - Invalid JSON falls back safely.
- `speedProfileForWPM(_:pausePct:typoPct:)`
  - Monotonicity vs WPM (higher WPM => lower scales).
  - Pause/typo overhead compensation impact.
  - Floor clamps for `flightScale` and `dwellScale`.
- `pauseConfigFromPercent(_:)`
  - 0/50/100 mapping and `lostThoughtEnabled` threshold.
- `typoMultiplierFromPercent(_:)`
  - 0/50/100 mapping.
- `computeFlightTime(...)`
  - Word-start, cross-hand, same-finger, row-change, number-row modifiers.
  - Unknown key fallback path.
  - Hard bounds `[18, 2500]`.
- `computeDwellTime(...)`
  - Finger multipliers + unknown-key fallback.
  - Hard bounds `[25, 550]`.
- `computeCognitivePause(...)`
  - Paragraph, sentence, clause, random-space, and default-zero branches.
- `shouldUseRollover(prev:cur:calibration:)`
  - Unknown-key false path.
  - Cross-hand vs same-hand probability path.
- `shiftHesitation(for:calibration:)`
  - Uppercase letter path and default-zero path.
- `boundedMsToSeconds(_:)`
  - Lower and upper bound clipping.

### HumanTyper.swift
- `init(calibration:)`
  - Uses passed calibration.
- `cancel()`
  - Sets cancel flag during typing.
- `typeText(_:)`
  - No-op while already typing.
  - Callback ordering `onTypingStarted` then `onTypingStopped`.
- `performTyping(_:)` (private)
  - Canonical output across ordinary text and special chars.
  - Newline/tab behavior.
  - Burst/slow phase timing modifiers.
  - Post-error slowdown decay.
  - Cancellation responsiveness.
- `executeError(_:chars:at:prevChar:)` (private)
  - Substitution/omission/insertion/transposition branches.
  - Edge guard paths (non-letter, end-of-text for transposition).
- `buildInjectionMap(for:)` (private)
  - Correct char-index mapping for synthetic actions.
  - Trailing pending synthetic actions flush.
- `executeSyntheticActions(_:atCharIndex:)` (private)
  - Each `TypingAction` branch incl. held-backspace path.
- `positionInCurrentWord(chars:at:)` (private)
  - Word index progression and non-letter zero path.
- `extractCurrentWord(chars:at:)` (private)
  - Word boundary extraction at start/mid/end.
- `isSentenceStart(chars:at:)` (private)
  - Start-of-text, punctuation+whitespace, comma-negative cases.
- `hpLog(_:_:)` and `correctionMultiplier` (private)
  - Callback/log formatting and correction-speed scaling.

### main.swift
- `SettingsWindow` methods
  - `init(del:)`, `buildUI()`, `addSectionHeader`, `addSliderRow`, `applyPreset`, `appendLog`,
    `controlTextDidEndEditing`, slider action methods, `sync`.
  - Needs AppKit host tests verifying slider-field sync, clamping, and callback routing.
- `AppDelegate` methods
  - `applicationDidFinishLaunching`, `applyAll`, `updateStatusTitle`, setters,
    `setupMenuBar`, `openSettings`, `setupGlobalHotkey`, `triggerPaste`.
  - Needs integration tests with pasteboard and event-tap seam/mocks.
- Free functions
  - `loadDotEnv()`: parsing, comments, quote stripping, no-overwrite env behavior.
  - `classifyEvent(actions:)`: event classification matrix.
  - `runVisualTest(...)`: canonical integrity and event capture output shape.
  - `*(lhs:rhs:)`: repeat helper correctness.

### prototypes/BoundaryTokenizer.swift
- `tokenize(_:)`
  - Empty input, punctuation boundaries, whitespace grouping, text preservation.
- `wordWindows(from:size:)`
  - Window chunking, terminal short window, invalid size handling.

### prototypes/FalseStartPlanner.swift
- `shouldInjectFalseStart(...)`
  - Max-count, min-word, cooldown gates.
  - Probability branch (with deterministic random seam).
- `predictionRequest(contextWords:upcomingWords:)`
  - Context truncation and upcoming-word cap.
- `buildFalseStartActions(prediction:)`
  - min/max word bounds, protected token rejection, action structure.

### prototypes/CursorEditPlanner.swift
- `shouldInjectEvent(...)`
  - Max-count/min-word/cooldown/probability gates.
- `pickEventType(word:recentTokens:)`
  - Clause/word/restart/rephrase branch selection.
- `buildMidWordRestart(word:)`
  - Length guard and action structure.
- `buildRephraseBacktrack(recentWords:actualRecentText:aiAlternative:)`
  - Protected-token guard, fallback path, AI alternative path.
- `buildForgottenWord(recentTokens:)`
  - Candidate selection, text-without build, action sequence.
- `buildForgottenClause(recentTokens:)`
  - Clause-boundary extraction and size sanity checks.

### prototypes/PredictionProvider.swift
- `PredictionProviderFactory.make(...)`
  - Env-key/provider selection and override behavior.
- `OpenAIPredictionProvider.predictFalseStart(...)`
  - Request build, decode/sanitize, error handling.
- `DeterministicPredictionProvider.predictFalseStart(...)`
  - Continuation-table path, generic fallback, overlap filtering.
- `CloudPredictionProvider.predictFalseStart(...)`
  - Request/response path and sanitize behavior.
- `sanitize(candidate:maxWords:)` (private)
  - Empty, protected, word-count, confidence-clamp paths.

### prototypes/UncertaintyConfig.swift
- `load(from:)`
  - Success decode path and default fallback path.

### prototypes/UncertaintyEngine.swift
- `init(config:predictor:)`
  - Planner wiring.
- `buildActions(for:)`
  - Disabled path, min-word bypass, canonical integrity, synthetic budget gate.
  - false-start + cognitive-event insertion points and state updates.
- `fetchRephraseAlternative(phrase:)` (private)
  - Predictor pass-through and nil path.
- `estimatePause(_:)` (private)
  - Sum of pause actions only.
- `actualTokenText(recentTokens:wordCount:)` (private)
  - Last-N-word slice preserving punctuation/spacing.
- `collectUpcomingWords(tokens:from:maxWords:)` (private)
  - Word-only extraction, cap, and bounds.

### prototypes/UncertaintyTypes.swift
- `TypingAction.description`
  - String formatting for each enum case.
- `String.wordCountApprox`
  - Whitespace splitting behavior.
- `String.looksProtectedToken`
  - URL/email/date/code-token detection and false-positive checks.

## 2) Integration Tests
Required matrix (all must assert final rendered text equals canonical):
- Short text: simple sentence.
- Long text: multi-paragraph input.
- Unicode text: accents + CJK + emoji.
- Empty text: `""`.
- Single-char text: `"a"`.

Additionally validate action-stream invariants:
- Canonical `.type` chunks concatenate to input.
- Synthetic actions can perturb intermediate state but must converge back.

## 3) Stress Tests
- 10K+ chars canonical corpus with uncertainty enabled.
- Repeated runs (>=3) to check:
  - Canonical integrity each run.
  - Action growth remains linear vs input size.
  - Timing drift ratio (`max runtime / min runtime`) below agreed threshold.
- Memory checks:
  - Track action list size and run resident-memory snapshots (Mach task info) across runs.
  - Fail on monotonic unbounded growth (leak signal).

## 4) Edge Cases
- Newlines-only text (`"\n\n\n"`).
- Spaces-only text (`"     "`).
- URLs (`https://...`) and emails.
- Code-like strings (`{ } < > ; $` etc).
- Emoji-only strings.

## 5) Timing Validation (Log-Logistic)
Statistical suite for `logLogisticRandom` and downstream timing functions:
- Quantile-fit checks vs theoretical `Q(p)` at p25/p50/p75.
- Confirm right-tail property (`mean > median`).
- Stability checks across sample batches (batch medians within tolerance).
- Optional KS test against reference distribution for stricter CI mode.

## 6) Regression Tests
- Rephrase double-char bug:
  - Backspace + alternative + revert sequence must restore exact original text with no duplicated suffix/punctuation.
- Caps fumble:
  - Trigger only when uppercase is at sentence start (after `. ! ?` + whitespace).
  - Must not trigger on mid-sentence proper nouns.

## Top 10 Tests Implemented In This Change
Implemented file: `tests/swift/HumanPasteTop10Tests.swift`

1. Boundary tokenizer unit validation.
2. False-start planner unit validation.
3. Integration canonical integrity: short text.
4. Integration canonical integrity: long text.
5. Integration canonical integrity: unicode text.
6. Integration canonical integrity: empty + single-char.
7. Edge-case corpus (newlines/spaces/URL/code/emoji).
8. Stress 10K+ with action-growth and timing-drift guards.
9. Log-logistic statistical quantile validation.
10. Regression bundle: rephrase double-char + caps-fumble gating.
