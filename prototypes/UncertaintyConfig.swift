import Foundation

struct UncertaintyConfig: Codable {
    let enabled: Bool
    let mode: String
    let predictionProvider: String
    let openAIModel: String
    let openAITimeoutMs: Int
    let planWindowWords: Int
    let minWordsForSyntheticEdits: Int

    let falseStartTriggerMinWords: Int
    let falseStartTriggerMaxWords: Int
    let maxFalseStartsPerMessage: Int
    let falseStartPauseMinMs: Int
    let falseStartPauseMaxMs: Int

    let maxPredictionWords: Int
    let minPredictionWords: Int

    let cursorEditTriggerMinWords: Int
    let cursorEditTriggerMaxWords: Int
    let maxCursorEditsPerMessage: Int
    let cursorBacktrackMinChars: Int
    let cursorBacktrackMaxChars: Int
    let cursorPauseMinMs: Int
    let cursorPauseMaxMs: Int

    let cooldownWordsBetweenSyntheticEvents: Int
    let maxSyntheticLatencyBudgetMs: Int

    static let `default` = UncertaintyConfig(
        enabled: true,
        mode: "safe",
        predictionProvider: "deterministic",
        openAIModel: "gpt-4.1-nano",
        openAITimeoutMs: 900,
        planWindowWords: 3,
        minWordsForSyntheticEdits: 20,
        falseStartTriggerMinWords: 60,
        falseStartTriggerMaxWords: 120,
        maxFalseStartsPerMessage: 2,
        falseStartPauseMinMs: 220,
        falseStartPauseMaxMs: 620,
        maxPredictionWords: 4,
        minPredictionWords: 2,
        cursorEditTriggerMinWords: 80,
        cursorEditTriggerMaxWords: 140,
        maxCursorEditsPerMessage: 1,
        cursorBacktrackMinChars: 4,
        cursorBacktrackMaxChars: 12,
        cursorPauseMinMs: 150,
        cursorPauseMaxMs: 420,
        cooldownWordsBetweenSyntheticEvents: 20,
        maxSyntheticLatencyBudgetMs: 1800
    )

    static func load(from url: URL) -> UncertaintyConfig {
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(UncertaintyConfig.self, from: data)
        } catch {
            return .default
        }
    }
}
