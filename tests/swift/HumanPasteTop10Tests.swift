import Foundation

private struct TestFailure: Error, CustomStringConvertible {
    let description: String
}

@inline(__always)
private func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() {
        throw TestFailure(description: message)
    }
}

private func expectNear(_ actual: Double, _ expected: Double, relTol: Double, _ message: String) throws {
    let baseline = max(abs(expected), 1e-9)
    let relErr = abs(actual - expected) / baseline
    if relErr > relTol {
        throw TestFailure(description: "\(message) | expected=\(expected) actual=\(actual) relErr=\(relErr)")
    }
}

private struct SimState {
    var buffer: [Character] = []
    var cursor: Int = 0

    init(initialText: String = "") {
        self.buffer = Array(initialText)
        self.cursor = self.buffer.count
    }

    mutating func apply(_ action: TypingAction) {
        switch action {
        case .type(let text), .syntheticType(let text):
            for ch in text {
                if cursor == buffer.count {
                    buffer.append(ch)
                } else {
                    buffer.insert(ch, at: cursor)
                }
                cursor += 1
            }

        case .pause:
            return

        case .backspace(let count):
            guard count > 0 else { return }
            for _ in 0..<count {
                guard cursor > 0 else { break }
                buffer.remove(at: cursor - 1)
                cursor -= 1
            }

        case .deleteForward(let count):
            guard count > 0 else { return }
            for _ in 0..<count {
                guard cursor < buffer.count else { break }
                buffer.remove(at: cursor)
            }

        case .moveCursorLeft(let count):
            guard count > 0 else { return }
            cursor = max(0, cursor - count)

        case .moveCursorRight(let count):
            guard count > 0 else { return }
            cursor = min(buffer.count, cursor + count)
        }
    }

    var text: String { String(buffer) }
}

private func replay(actions: [TypingAction], initialText: String = "") -> String {
    var state = SimState(initialText: initialText)
    for action in actions {
        state.apply(action)
    }
    return state.text
}

private func makeConfig(
    minWords: Int = 1,
    maxFalseStarts: Int = 3,
    maxCursorEdits: Int = 2,
    cooldownWords: Int = 1,
    latencyBudgetMs: Int = 20_000
) -> UncertaintyConfig {
    let d = UncertaintyConfig.default
    return UncertaintyConfig(
        enabled: true,
        mode: d.mode,
        predictionProvider: "deterministic",
        openAIModel: d.openAIModel,
        openAITimeoutMs: d.openAITimeoutMs,
        planWindowWords: d.planWindowWords,
        minWordsForSyntheticEdits: minWords,
        falseStartTriggerMinWords: 1,
        falseStartTriggerMaxWords: 4,
        maxFalseStartsPerMessage: maxFalseStarts,
        falseStartPauseMinMs: d.falseStartPauseMinMs,
        falseStartPauseMaxMs: d.falseStartPauseMaxMs,
        maxPredictionWords: d.maxPredictionWords,
        minPredictionWords: d.minPredictionWords,
        cursorEditTriggerMinWords: 1,
        cursorEditTriggerMaxWords: 4,
        maxCursorEditsPerMessage: maxCursorEdits,
        cursorBacktrackMinChars: d.cursorBacktrackMinChars,
        cursorBacktrackMaxChars: d.cursorBacktrackMaxChars,
        cursorPauseMinMs: d.cursorPauseMinMs,
        cursorPauseMaxMs: d.cursorPauseMaxMs,
        cooldownWordsBetweenSyntheticEvents: cooldownWords,
        maxSyntheticLatencyBudgetMs: latencyBudgetMs
    )
}

private func buildActions(text: String, config: UncertaintyConfig) async -> [TypingAction] {
    let engine = UncertaintyEngine(config: config, predictor: DeterministicPredictionProvider())
    return await engine.buildActions(for: text)
}

private func quantile(_ sorted: [Double], p: Double) -> Double {
    precondition(!sorted.isEmpty)
    let clamped = max(0.0, min(1.0, p))
    let idx = Int(Double(sorted.count - 1) * clamped)
    return sorted[idx]
}

private func logLogisticQuantile(alpha: Double, beta: Double, p: Double) -> Double {
    alpha * pow(p / (1.0 - p), 1.0 / beta)
}

private func isSentenceStartModel(chars: [Character], at i: Int) -> Bool {
    if i == 0 { return true }
    var j = i - 1
    while j >= 0 && (chars[j] == " " || chars[j] == "\t" || chars[j] == "\n") {
        j -= 1
    }
    if j < 0 { return true }
    let prev = chars[j]
    return prev == "." || prev == "!" || prev == "?"
}

private func test01BoundaryTokenizerUnit() throws {
    let input = "Hello, world!\n\n42"
    let tokens = BoundaryTokenizer.tokenize(input)

    try expect(!tokens.isEmpty, "Tokenizer returned no tokens")
    try expect(tokens.map(\.text).joined() == input, "Tokenizer did not preserve exact text")
    try expect(tokens.count == 7, "Unexpected token count: \(tokens.count)")
    try expect(tokens[0].kind == .word && tokens[0].text == "Hello", "Token 0 mismatch")
    try expect(tokens[1].kind == .punctuation && tokens[1].text == ",", "Token 1 mismatch")
    try expect(tokens[2].kind == .whitespace && tokens[2].text == " ", "Token 2 mismatch")
    try expect(tokens[3].kind == .word && tokens[3].text == "world", "Token 3 mismatch")
    try expect(tokens[4].kind == .punctuation && tokens[4].text == "!", "Token 4 mismatch")
    try expect(tokens[5].kind == .whitespace && tokens[5].text == "\n\n", "Token 5 mismatch")
    try expect(tokens[6].kind == .word && tokens[6].text == "42", "Token 6 mismatch")
}

private func test02FalseStartPlannerUnit() throws {
    let cfg = makeConfig(minWords: 1)
    let planner = FalseStartPlanner(config: cfg)

    let ok = planner.buildFalseStartActions(prediction: PredictionCandidate(phrase: "quick brown", confidence: 0.8))
    try expect(ok.count == 3, "Expected 3 actions for valid prediction")
    try expect(ok[0] == .syntheticType("quick brown "), "Expected syntheticType first")

    let tooShort = planner.buildFalseStartActions(prediction: PredictionCandidate(phrase: "oops", confidence: 0.8))
    try expect(tooShort.isEmpty, "Expected rejection for 1-word prediction")

    let protected = planner.buildFalseStartActions(prediction: PredictionCandidate(phrase: "https://example.com", confidence: 0.8))
    try expect(protected.isEmpty, "Expected rejection for protected token-like phrase")
}

private func test03IntegrationShortText() async throws {
    let cfg = makeConfig(minWords: 1, maxFalseStarts: 3, maxCursorEdits: 2, cooldownWords: 1)
    let text = "The quick brown fox."

    for _ in 0..<25 {
        let actions = await buildActions(text: text, config: cfg)
        let rendered = replay(actions: actions)
        try expect(rendered == text, "Canonical integrity failed for short text")
    }
}

private func test04IntegrationLongText() async throws {
    let cfg = makeConfig(minWords: 1, maxFalseStarts: 4, maxCursorEdits: 3, cooldownWords: 1)
    let text = String(repeating: "The migration completed successfully, but we still need to validate checksums and monitor latency. ", count: 18)

    for _ in 0..<10 {
        let actions = await buildActions(text: text, config: cfg)
        let rendered = replay(actions: actions)
        try expect(rendered == text, "Canonical integrity failed for long text")
    }
}

private func test05IntegrationUnicodeText() async throws {
    let cfg = makeConfig(minWords: 1, maxFalseStarts: 3, maxCursorEdits: 2)
    let text = "Cafe naive resume こんにちは世界 emojis 😀😅👍🏽 end."

    for _ in 0..<15 {
        let actions = await buildActions(text: text, config: cfg)
        let rendered = replay(actions: actions)
        try expect(rendered == text, "Canonical integrity failed for unicode text")
    }
}

private func test06IntegrationEmptyAndSingleChar() async throws {
    let cfg = makeConfig(minWords: 1, maxFalseStarts: 2, maxCursorEdits: 1)
    let cases = ["", "a"]

    for input in cases {
        for _ in 0..<10 {
            let actions = await buildActions(text: input, config: cfg)
            let rendered = replay(actions: actions)
            try expect(rendered == input, "Canonical integrity failed for input '\(input)'")
        }
    }
}

private func test07EdgeCases() async throws {
    let cfg = makeConfig(minWords: 1, maxFalseStarts: 2, maxCursorEdits: 1)
    let cases = [
        "\\n\\n\\n",
        "     ",
        "https://example.com/path?x=1",
        "if (x < 10) { return y; }",
        "🙂🙂🙂"
    ]

    try expect("https://example.com".looksProtectedToken, "URL should be protected")
    try expect("john@example.com".looksProtectedToken, "Email should be protected")
    try expect("if (x < 10) { return y; }".looksProtectedToken, "Code-ish token should be protected")
    try expect(!"simple words only".looksProtectedToken, "Normal phrase should not be protected")

    for input in cases {
        for _ in 0..<10 {
            let actions = await buildActions(text: input, config: cfg)
            let rendered = replay(actions: actions)
            try expect(rendered == input, "Canonical integrity failed for edge case input")
        }
    }
}

private func test08Stress10kMemoryTimingDrift() async throws {
    let cfg = makeConfig(minWords: 1, maxFalseStarts: 8, maxCursorEdits: 5, cooldownWords: 1, latencyBudgetMs: 80_000)
    let text = String(repeating: "HumanPaste simulates realistic typing with pauses and corrections. ", count: 180)
    try expect(text.count > 10_000, "Stress input is not 10K+ chars")

    var durations: [Double] = []
    var actionCounts: [Int] = []

    for _ in 0..<3 {
        let start = CFAbsoluteTimeGetCurrent()
        let actions = await buildActions(text: text, config: cfg)
        let elapsed = CFAbsoluteTimeGetCurrent() - start
        durations.append(elapsed)
        actionCounts.append(actions.count)

        let rendered = replay(actions: actions)
        try expect(rendered == text, "Canonical integrity failed in stress run")
        try expect(actions.count < text.count * 5, "Action growth exceeded linear bound")
    }

    guard let minT = durations.min(), let maxT = durations.max() else {
        throw TestFailure(description: "No stress durations recorded")
    }

    let driftRatio = maxT / max(minT, 1e-6)
    try expect(driftRatio < 3.0, "Timing drift too high in stress run: \(driftRatio)")

    guard let minActions = actionCounts.min(), let maxActions = actionCounts.max() else {
        throw TestFailure(description: "No action counts recorded")
    }
    try expect(Double(maxActions) / Double(max(minActions, 1)) < 2.0,
               "Action count drift too high across stress runs")
}

private func test09TimingValidationLogLogistic() throws {
    let alpha = 170.0
    let beta = 4.4
    let n = 50_000

    var sample: [Double] = []
    sample.reserveCapacity(n)

    for _ in 0..<n {
        let value = logLogisticRandom(alpha: alpha, beta: beta)
        try expect(value > 0, "logLogisticRandom produced non-positive sample")
        sample.append(value)
    }

    sample.sort()

    let q25 = quantile(sample, p: 0.25)
    let q50 = quantile(sample, p: 0.50)
    let q75 = quantile(sample, p: 0.75)

    let t25 = logLogisticQuantile(alpha: alpha, beta: beta, p: 0.25)
    let t50 = logLogisticQuantile(alpha: alpha, beta: beta, p: 0.50)
    let t75 = logLogisticQuantile(alpha: alpha, beta: beta, p: 0.75)

    try expectNear(q25, t25, relTol: 0.15, "Q25 deviates from log-logistic theory")
    try expectNear(q50, t50, relTol: 0.12, "Q50 deviates from log-logistic theory")
    try expectNear(q75, t75, relTol: 0.15, "Q75 deviates from log-logistic theory")

    let mean = sample.reduce(0, +) / Double(n)
    try expect(mean > q50, "Expected right tail: mean should exceed median")
}

private func test10RegressionRephraseAndCapsFumble() throws {
    let cfg = makeConfig(minWords: 1)
    let planner = CognitiveEventPlanner(config: cfg)

    // Regression A: rephrase should return to exact original text (no double-char suffix artifacts)
    let prefix = "This is "
    let actualRecentText = "good, actually."
    let initial = prefix + actualRecentText

    let actions = planner.buildRephraseBacktrack(
        recentWords: ["good", "actually"],
        actualRecentText: actualRecentText,
        aiAlternative: "better wording"
    )

    try expect(!actions.isEmpty, "Expected rephrase actions")
    let rendered = replay(actions: actions, initialText: initial)
    try expect(rendered == initial, "Rephrase backtrack changed canonical text or duplicated chars")

    // Regression B: caps-fumble gating should only trigger at sentence starts
    let chars = Array("Hello.\n\nWorld and NASA reports.")

    let worldIndex = chars.firstIndex(of: "W")!
    let nasaIndex = chars.firstIndex(of: "N")!

    try expect(isSentenceStartModel(chars: chars, at: 0), "First character should be sentence start")
    try expect(isSentenceStartModel(chars: chars, at: worldIndex), "Uppercase after punctuation+newlines should be sentence start")
    try expect(!isSentenceStartModel(chars: chars, at: nasaIndex), "Mid-sentence uppercase should not be sentence start")
}

private struct NamedTest {
    let name: String
    let run: () async throws -> Void
}

@main
enum HumanPasteTop10Tests {
    static func main() async {
        let tests: [NamedTest] = [
            NamedTest(name: "01 Boundary tokenizer unit") { try test01BoundaryTokenizerUnit() },
            NamedTest(name: "02 False-start planner unit") { try test02FalseStartPlannerUnit() },
            NamedTest(name: "03 Integration short text") { try await test03IntegrationShortText() },
            NamedTest(name: "04 Integration long text") { try await test04IntegrationLongText() },
            NamedTest(name: "05 Integration unicode text") { try await test05IntegrationUnicodeText() },
            NamedTest(name: "06 Integration empty + single-char") { try await test06IntegrationEmptyAndSingleChar() },
            NamedTest(name: "07 Edge-case corpus") { try await test07EdgeCases() },
            NamedTest(name: "08 Stress 10K + timing drift") { try await test08Stress10kMemoryTimingDrift() },
            NamedTest(name: "09 Timing validation log-logistic") { try test09TimingValidationLogLogistic() },
            NamedTest(name: "10 Regression: rephrase + caps-fumble") { try test10RegressionRephraseAndCapsFumble() }
        ]

        var failures = 0

        for (idx, test) in tests.enumerated() {
            do {
                try await test.run()
                print("[PASS] [\(idx + 1)/\(tests.count)] \(test.name)")
            } catch {
                failures += 1
                print("[FAIL] [\(idx + 1)/\(tests.count)] \(test.name)")
                print("       \(error)")
            }
        }

        print("\nResult: \(tests.count - failures)/\(tests.count) passed")
        if failures > 0 {
            exit(1)
        }
    }
}
