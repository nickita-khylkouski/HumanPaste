import Foundation

private struct SimState {
    var buffer: [Character] = []
    var cursor: Int = 0

    mutating func apply(_ action: TypingAction) {
        switch action {
        case .type(let text):
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

private func runSingle(canonical: String, config: UncertaintyConfig) async -> (ok: Bool, actions: Int, synthetic: Int) {
    let provider = PredictionProviderFactory.make(config: config)
    let engine = UncertaintyEngine(config: config, predictor: provider)
    let actions = await engine.buildActions(for: canonical)

    var sim = SimState()
    var synthetic = 0

    for action in actions {
        switch action {
        case .type(let t):
            if t != canonical { synthetic += 1 }
        case .pause, .backspace, .deleteForward, .moveCursorLeft, .moveCursorRight:
            synthetic += 1
        }
        sim.apply(action)
    }

    return (sim.text == canonical, actions.count, synthetic)
}

@main
struct UncertaintySelfTest {
    static func main() async {
        let defaultPath = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("config/default_uncertainty_config.json")

        var cfg = UncertaintyConfig.load(from: defaultPath)

        // Force deterministic provider for reproducible CI-ish checks.
        cfg = UncertaintyConfig(
            enabled: true,
            mode: cfg.mode,
            predictionProvider: "deterministic",
            openAIModel: cfg.openAIModel,
            openAITimeoutMs: cfg.openAITimeoutMs,
            planWindowWords: cfg.planWindowWords,
            minWordsForSyntheticEdits: 8,
            falseStartTriggerMinWords: 4,
            falseStartTriggerMaxWords: 8,
            maxFalseStartsPerMessage: 4,
            falseStartPauseMinMs: cfg.falseStartPauseMinMs,
            falseStartPauseMaxMs: cfg.falseStartPauseMaxMs,
            maxPredictionWords: 4,
            minPredictionWords: 2,
            cursorEditTriggerMinWords: 5,
            cursorEditTriggerMaxWords: 9,
            maxCursorEditsPerMessage: 3,
            cursorBacktrackMinChars: cfg.cursorBacktrackMinChars,
            cursorBacktrackMaxChars: cfg.cursorBacktrackMaxChars,
            cursorPauseMinMs: cfg.cursorPauseMinMs,
            cursorPauseMaxMs: cfg.cursorPauseMaxMs,
            cooldownWordsBetweenSyntheticEvents: 2,
            maxSyntheticLatencyBudgetMs: cfg.maxSyntheticLatencyBudgetMs
        )

        let canonical = """
        This is a realistic long-form typing sample with punctuation, line breaks, and mixed casing.
        We want to verify that false starts and cursor edits never alter the final canonical payload.
        If this fails, shipping would be unsafe because content integrity is the hard requirement.
        """

        var failures = 0
        var totalActions = 0
        var totalSynthetic = 0
        let runs = 200

        for _ in 0..<runs {
            let result = await runSingle(canonical: canonical, config: cfg)
            totalActions += result.actions
            totalSynthetic += result.synthetic
            if !result.ok { failures += 1 }
        }

        print("Uncertainty self-test")
        print("- runs: \(runs)")
        print("- failures: \(failures)")
        print("- avg actions: \(Double(totalActions) / Double(runs))")
        print("- avg synthetic actions: \(Double(totalSynthetic) / Double(runs))")
        print("- result: \(failures == 0 ? "PASS" : "FAIL")")

        if failures != 0 {
            exit(2)
        }
    }
}
