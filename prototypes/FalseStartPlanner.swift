import Foundation

struct FalseStartPlanner {
    let config: UncertaintyConfig

    func shouldInjectFalseStart(state: PlannerState, currentWordIndex: Int) -> Bool {
        if state.falseStartsUsed >= config.maxFalseStartsPerMessage { return false }
        if currentWordIndex < config.minWordsForSyntheticEdits { return false }
        if currentWordIndex - state.lastSyntheticEventWordIndex < config.cooldownWordsBetweenSyntheticEvents {
            return false
        }

        // Probability-based trigger: spread false starts evenly across the text
        // P(trigger) ≈ maxFalseStarts / (totalWords - minWords) per eligible word
        let eligibleWords = max(1, state.totalWords - config.minWordsForSyntheticEdits)
        let targetCount = Double(config.maxFalseStartsPerMessage)
        let probability = min(0.15, targetCount / Double(eligibleWords) * 1.5)

        return Double.random(in: 0...1) < probability
    }

    func predictionRequest(
        contextWords: [String],
        upcomingWords: [String]
    ) -> PredictionRequest {
        let context = contextWords.suffix(12).joined(separator: " ")
        let trimmedUpcoming = Array(upcomingWords.prefix(config.maxPredictionWords))
        return PredictionRequest(
            precedingContext: context,
            upcomingCanonicalWords: trimmedUpcoming,
            mode: config.mode,
            maxWords: config.maxPredictionWords
        )
    }

    func buildFalseStartActions(prediction: PredictionCandidate) -> [TypingAction] {
        let phrase = prediction.phrase
        let wordCount = phrase.wordCountApprox
        if wordCount < config.minPredictionWords || wordCount > config.maxPredictionWords { return [] }
        if phrase.looksProtectedToken { return [] }

        let pauseMs = Int.random(in: config.falseStartPauseMinMs...config.falseStartPauseMaxMs)
        return [
            .syntheticType(phrase + " "),
            .pause(milliseconds: pauseMs),
            .backspace(count: phrase.count + 1)
        ]
    }
}
